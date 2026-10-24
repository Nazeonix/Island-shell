import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Alt+Tab window switcher: a centered black panel with one card per window (app icon, title,
// live preview); the selected card gets an accent outline. Most recently used window first.
//   qs -c dynamic-island ipc call switcher next | prev | commit | cancel
// Keys while open: Alt release = switch | Tab / arrows / H L = move | Enter = switch | Esc = cancel
// Needs live previews: Hyprland's toplevel export (on by default with xdg-desktop-portal-hyprland).
PanelWindow {
    id: win

    property bool open: false
    property var windows: []     // Toplevels, most recently used first (built when the switcher opens)
    property int index: 0
    property var mru: []         // focus history we keep ourselves

    // ---- focus history ----
    readonly property var active: ToplevelManager.activeToplevel
    onActiveChanged: {
        if (!active) return;
        const m = mru.filter(t => t !== active);
        m.unshift(active);
        mru = m.slice(0, 50);
    }
    Component.onCompleted: if (active) mru = [active]

    function build() {
        const all = ToplevelManager.toplevels.values.slice();
        const rank = t => { const i = mru.indexOf(t); return i < 0 ? 1000 : i; };
        all.sort((a, b) => rank(a) - rank(b));
        windows = all;
    }
    function step(d) {
        if (!open) {
            build();
            if (windows.length === 0) return;
            index = d > 0 ? Math.min(1, windows.length - 1) : windows.length - 1;
            open = true;
            Qt.callLater(() => keys.forceActiveFocus());
            return;
        }
        const n = windows.length;
        index = (index + d + n) % n;
    }
    function commit() {
        const t = windows[index];
        open = false;
        if (t) t.activate();
    }
    function cancel() { open = false; }

    onIndexChanged: Qt.callLater(() => { if (open) list.positionViewAtIndex(index, ListView.Contain); })

    IpcHandler {
        target: "switcher"
        function next(): void   { win.step(1) }
        function prev(): void   { win.step(-1) }
        function commit(): void { if (win.open) win.commit() }
        function cancel(): void { win.cancel() }
    }

    screen: Quickshell.screens[0]
    visible: open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "dynamic-island-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: win.cancel()
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: win.open
        Keys.onPressed: (e) => {
            let ok = true;
            if (e.key === Qt.Key_Escape) win.cancel();
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.commit();
            else if (e.key === Qt.Key_Tab) win.step((e.modifiers & Qt.ShiftModifier) ? -1 : 1);
            else if (e.key === Qt.Key_Backtab) win.step(-1);
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) win.step(1);
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) win.step(-1);
            else ok = false;
            e.accepted = ok;
        }
        Keys.onReleased: (e) => {
            if (!e.isAutoRepeat && e.key === Qt.Key_Alt) win.commit();
        }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(list.contentWidth + 36, parent.width - 80)
        height: 250
        radius: 36
        color: Qt.alpha(Theme.notch, 0.94)
        border.width: 1
        border.color: Qt.alpha(Theme.foreground, 0.08)
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale   { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 18
            orientation: ListView.Horizontal
            spacing: 14
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            model: ScriptModel { values: win.windows }

            delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property bool sel: index === win.index
                readonly property var entry: modelData.appId ? DesktopEntries.heuristicLookup(modelData.appId) : null
                readonly property string iconPath: Quickshell.iconPath(entry ? entry.icon : (modelData.appId || "").toLowerCase(), true)
                width: 280
                height: list.height

                Rectangle {
                    anchors.fill: parent
                    radius: 22
                    color: card.sel ? Theme.surface : Qt.alpha(Theme.surface, 0.5)
                    border.width: card.sel ? 3 : 0
                    border.color: Theme.accent
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                Row {
                    x: 16; y: 13
                    width: parent.width - 32
                    spacing: 9
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22
                        visible: card.iconPath !== ""
                        source: card.iconPath
                        sourceSize: Qt.size(44, 44)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 31
                        text: card.modelData.title || card.modelData.appId || "Window"
                        color: Theme.foreground
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }

                Item {   // live preview, kept in the window's aspect ratio
                    x: 16; y: 46
                    width: parent.width - 32
                    height: parent.height - 46 - 18
                    clip: true
                    ScreencopyView {
                        id: sc
                        captureSource: card.modelData
                        live: true
                        readonly property real ratio: implicitHeight > 0 ? implicitWidth / implicitHeight : 1.6
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height * ratio)
                        height: width / ratio
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { win.index = card.index; win.commit(); }
                }
            }
        }
    }
}
