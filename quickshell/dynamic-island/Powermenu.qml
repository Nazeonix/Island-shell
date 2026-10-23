import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Power menu. Control with:
//   qs -c dynamic-island ipc call powermenu toggle   (also: show / hide)
// Keys: Left/Right or Tab/Shift+Tab move | Enter/Space select | L S R P direct | Esc cancel/close
// Reboot and Power off need a second press to confirm.
PanelWindow {
    id: win

    property bool open: false
    property int index: 0
    property int armed: -1   // index of a destructive action waiting for confirmation

    // Palette (matches Launcher.qml)
    readonly property color cBg: Theme.background
    readonly property color cRow: Theme.surface
    readonly property color cText: Theme.foreground
    readonly property color cDim: Theme.foregroundMuted
    readonly property color cAccent: Theme.accent
    readonly property color cUrgent: Theme.error

    // Commands are argv arrays (no shell, nothing to inject into)
    readonly property var actions: [
        { key: "lock",     label: "Lock",      cmd: ["swaylock"],              confirm: false, detached: true,  hot: Qt.Key_L },
        { key: "suspend",  label: "Sleep",     cmd: ["systemctl", "suspend"],  confirm: false, detached: false, hot: Qt.Key_S },
        { key: "reboot",   label: "Reboot",    cmd: ["systemctl", "reboot"],   confirm: true,  detached: false, hot: Qt.Key_R },
        { key: "poweroff", label: "Power off", cmd: ["systemctl", "poweroff"], confirm: true,  detached: false, hot: Qt.Key_P }
    ]

    // One Process for the systemctl actions
    Process {
        id: proc
        onExited: (code, status) => {
            if (code !== 0) console.warn("powermenu: " + proc.command.join(" ") + " exited with " + code);
        }
    }

    function show() { open = true; }
    function hide() { open = false; }

    function run(a) {
        hide();
        if (a.detached) {
            // swaylock must outlive this shell: a reload/crash of quickshell must never kill the locker
            Quickshell.execDetached(a.cmd);
            return;
        }
        if (proc.running) return;
        proc.command = a.cmd;
        proc.running = true;
    }
    function activate(i) {
        const a = actions[i];
        if (!a) return;
        if (a.confirm && armed !== i) {
            armed = i;
            return;
        }
        run(a);
    }
    function move(d) {
        index = Math.max(0, Math.min(actions.length - 1, index + d));
    }

    onIndexChanged: armed = -1
    onOpenChanged: if (open) {
        index = 0;
        armed = -1;
        Qt.callLater(() => keys.forceActiveFocus());
    }

    screen: Quickshell.screens[0]
    visible: open || panel.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "dynamic-island-powermenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IpcHandler {
        target: "powermenu"
        function toggle(): void { win.open ? win.hide() : win.show() }
        function show(): void   { win.show() }
        function hide(): void   { win.hide() }
    }

    // Dim backdrop; click anywhere outside the panel to close
    Rectangle {
        anchors.fill: parent
        color: "#73000000"
        opacity: win.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        MouseArea {
            anchors.fill: parent
            onClicked: win.hide()
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: (e) => {
            let ok = true;
            if (e.key === Qt.Key_Escape) {
                if (win.armed >= 0) win.armed = -1;
                else win.hide();
            } else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) win.move(1);
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) win.move(-1);
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) win.activate(win.index);
            else {
                ok = false;
                for (let i = 0; i < win.actions.length; i++) {
                    if (win.actions[i].hot === e.key) {
                        win.index = i;
                        win.activate(i);
                        ok = true;
                        break;
                    }
                }
            }
            e.accepted = ok;
        }
    }

    Rectangle {
        id: panel
        width: 538
        height: 176
        anchors.centerIn: parent
        radius: 28
        color: win.cBg
        border.width: 1
        border.color: Theme.border

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }   // swallow clicks on the panel itself

        Row {
            anchors.centerIn: parent
            spacing: 14

            Repeater {
                model: win.actions

                Item {
                    id: btn
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === win.index
                    readonly property bool isArmed: win.armed === index
                    readonly property color fg: isArmed ? win.cUrgent : (sel ? win.cText : win.cDim)
                    width: 112
                    height: 128

                    Rectangle {
                        anchors.fill: parent
                        radius: 20
                        color: btn.sel ? win.cRow : "transparent"
                        border.width: btn.isArmed ? 2 : 0
                        border.color: win.cUrgent
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    Canvas {
                        id: cv
                        width: 36; height: 36
                        x: (btn.width - width) / 2
                        y: 26
                        antialiasing: true
                        property string kind: btn.modelData.key
                        property color col: btn.fg
                        onColChanged: requestPaint()
                        onPaint: {
                            const c = getContext("2d");
                            c.reset();
                            c.strokeStyle = col;
                            c.fillStyle = col;
                            c.lineWidth = 2.4;
                            c.lineCap = "round";
                            c.lineJoin = "round";
                            const rad = d => d * Math.PI / 180;
                            if (kind === "poweroff") {
                                c.beginPath(); c.arc(18, 19, 11, rad(-60), rad(240)); c.stroke();
                                c.beginPath(); c.moveTo(18, 4); c.lineTo(18, 16); c.stroke();
                            } else if (kind === "reboot") {
                                c.beginPath(); c.arc(18, 18, 11, rad(-40), rad(270)); c.stroke();
                                c.beginPath(); c.moveTo(24, 7); c.lineTo(18, 3); c.lineTo(18, 11); c.closePath(); c.fill();
                            } else if (kind === "suspend") {
                                // crescent moon: outer circle minus an offset inner circle
                                c.beginPath();
                                c.arc(17, 19, 11, rad(16.2), rad(266.5), false);
                                c.arc(22, 15, 9, rad(230.9), rad(51.9), true);
                                c.closePath();
                                c.fill();
                            } else {   // lock
                                c.beginPath(); c.roundedRect(8, 16, 20, 15, 3, 3); c.stroke();
                                c.beginPath(); c.arc(18, 16, 6, Math.PI, 2 * Math.PI, false); c.stroke();
                                c.beginPath(); c.arc(18, 23.5, 1.8, 0, 2 * Math.PI); c.fill();
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 82
                        text: btn.isArmed ? "Press again" : btn.modelData.label
                        color: btn.fg
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: win.index = btn.index
                        onClicked: {
                            win.index = btn.index;
                            win.activate(btn.index);
                        }
                    }
                }
            }
        }
    }
}
