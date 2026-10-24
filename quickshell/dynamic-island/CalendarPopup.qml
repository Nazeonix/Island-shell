import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Calendar popup (same pattern as Launcher/Powermenu: overlay PanelWindow + backdrop click-away + IPC).
//   toggleAt(x) opens it centered under screen-x `x` (clamped to the screen); IPC reuses the last x.
//   qs -p <shell.qml> ipc call calendar toggle     (also: show / hide)
// Keys: Left/Right month | Up/Down year | T today | Esc close
PanelWindow {
    id: win

    property bool open: false
    property real anchorX: -1        // < 0 = center of the screen

    function toggleAt(x) {
        if (x !== undefined && x >= 0) anchorX = x;
        open = !open;
    }
    function show() { open = true; }
    function hide() { open = false; }

    onOpenChanged: if (open) {
        grid.reset();
        Qt.callLater(() => keys.forceActiveFocus());
    }

    visible: open || panel.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "dynamic-island-calendar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IpcHandler {
        target: "calendar"
        function toggle(): void { win.toggleAt(win.anchorX) }
        function show(): void   { win.show() }
        function hide(): void   { win.hide() }
    }

    MouseArea {   // click anywhere outside to close
        anchors.fill: parent
        onClicked: win.hide()
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: (e) => {
            let ok = true;
            if (e.key === Qt.Key_Escape) win.hide();
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) grid.step(-1);
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) grid.step(1);
            else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) grid.stepYear(-1);
            else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) grid.stepYear(1);
            else if (e.key === Qt.Key_T) grid.reset();
            else ok = false;
            e.accepted = ok;
        }
    }

    Rectangle {
        id: panel
        width: 320
        height: footer.y + footer.height + 14
        // Under (or above) the bar, centered on the clock
        x: {
            const cx = win.anchorX >= 0 ? win.anchorX : parent.width / 2;
            return Math.max(Theme.margin, Math.min(parent.width - width - Theme.margin, cx - width / 2));
        }
        y: Theme.barAtTop ? Theme.barHeight + 8 : parent.height - Theme.barHeight - height - 8
        radius: 24
        color: Theme.background
        border.width: 1
        border.color: Theme.border

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        transformOrigin: Theme.barAtTop ? Item.Top : Item.Bottom
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }   // swallow clicks on the panel itself

        // Header: < Month Year >
        Item {
            id: head
            x: 16; y: 16
            width: parent.width - 32
            height: 36

            Rectangle {
                id: prev
                width: 32; height: 32; radius: 16
                anchors.verticalCenter: parent.verticalCenter
                color: prevMouse.containsMouse ? Theme.hover : "transparent"
                Text { anchors.centerIn: parent; text: "\u2039"; color: Theme.foreground; font.pixelSize: 20 }
                MouseArea { id: prevMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: grid.step(-1) }
            }
            Text {
                anchors.centerIn: parent
                text: grid.title
                color: Theme.foreground
                font.pixelSize: 16
                font.weight: Font.DemiBold
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: grid.reset() }
            }
            Rectangle {
                width: 32; height: 32; radius: 16
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: nextMouse.containsMouse ? Theme.hover : "transparent"
                Text { anchors.centerIn: parent; text: "\u203a"; color: Theme.foreground; font.pixelSize: 20 }
                MouseArea { id: nextMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: grid.step(1) }
            }
        }

        CalendarGrid {
            id: grid
            x: 16
            y: head.y + head.height + 10
            width: parent.width - 32
        }

        // Footer: today's date; click = jump back to the current month
        Rectangle {
            id: footer
            x: 16
            y: grid.y + grid.implicitHeight + 8
            width: parent.width - 32
            height: 34
            radius: 12
            color: footMouse.containsMouse ? Theme.surface : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            Text {
                anchors.centerIn: parent
                text: Qt.formatDate(new Date(), "dddd, d MMMM")
                color: Theme.foregroundMuted
                font.pixelSize: 13
            }
            MouseArea { id: footMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: grid.reset() }
        }
    }
}
