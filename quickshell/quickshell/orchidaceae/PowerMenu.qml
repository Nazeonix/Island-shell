import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Slides in from the right edge: power off, reboot, sleep, hibernate.
PanelWindow {
    id: win
    property bool triggerHovered: false
    property bool shown: false
    property bool ipcOpen: false
    readonly property bool wanted: triggerHovered || hover.hovered || ipcOpen
    // keyboard: Up/Down (or k/j) move, Enter runs, Esc closes. Active via the IPC/keybind
    // open, or while the pointer is over the menu.
    property int sel: 0
    property bool navActive: false
    readonly property var buttons: [bPoweroff, bReboot, bSleep, bHibernate]
    onIpcOpenChanged: if (ipcOpen) Qt.callLater(() => keys.forceActiveFocus())
    onShownChanged: { navActive = false; sel = 0; if (shown) Qt.callLater(() => keys.forceActiveFocus()); }
    WlrLayershell.keyboardFocus: (ipcOpen || hover.hovered) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IpcHandler {
        target: "powermenu"
        function toggle(): void { win.ipcOpen = !win.ipcOpen }
        function open(): void { win.ipcOpen = true }
        function close(): void { win.ipcOpen = false }
    }

    onWantedChanged: {
        if (wanted) { closeTimer.stop(); shown = true; }
        else closeTimer.restart();
    }
    Timer { id: closeTimer; interval: 300; onTriggered: win.shown = false }

    anchors { right: true }                       // vertically centered
    margins { right: Theme.frameThickness }
    exclusionMode: ExclusionMode.Ignore
    readonly property int pad: 0
    readonly property int fillet: 16      // room above/below the sheet for the edge fillets
    implicitWidth: 112
    implicitHeight: 370 + fillet * 2
    color: "transparent"
    visible: shown || sheet.x < win.implicitWidth - 1
    mask: Region { item: sheet }

    Item {
        id: sheet
        y: win.fillet
        width: 112
        height: 370
        x: win.shown ? win.pad : win.implicitWidth
        Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        HoverHandler { id: hover }
        Item {
            id: keys
            focus: true
            Keys.onPressed: event => {
                const n = win.buttons.length;
                if (event.key === Qt.Key_Escape) {
                    win.ipcOpen = false; event.accepted = true;
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                    if (!win.navActive) { win.navActive = true; win.sel = 0; }
                    else win.sel = (win.sel + 1) % n;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                    if (!win.navActive) { win.navActive = true; win.sel = n - 1; }
                    else win.sel = (win.sel + n - 1) % n;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    // only when a selection is visible, so a stray Enter can't power off
                    if (win.navActive) win.buttons[win.sel].activate();
                    event.accepted = true;
                }
            }
        }

        // surface: 2px outline; left corners convex, top/bottom flare into the screen edge
        Shape {
            id: surf
            x: 0; y: -win.fillet
            width: sheet.width + 40
            height: sheet.height + win.fillet * 2
            preferredRendererType: Shape.CurveRenderer
            readonly property real o: win.fillet   // y offset of the sheet inside the shape
            readonly property real sw: sheet.width
            readonly property real sh: sheet.height
            readonly property real cr: 16           // left corner radius
            readonly property real fr: win.fillet   // edge fillet radius

            ShapePath {
                fillColor: Theme.background
                strokeColor: Theme.foreground
                strokeWidth: 2
                joinStyle: ShapePath.RoundJoin
                startX: surf.sw; startY: 0
                PathArc  { x: surf.sw - surf.fr; y: surf.o
                           radiusX: surf.fr; radiusY: surf.fr; direction: PathArc.Clockwise }
                PathLine { x: surf.cr; y: surf.o }
                PathArc  { x: 0; y: surf.o + surf.cr
                           radiusX: surf.cr; radiusY: surf.cr; direction: PathArc.Counterclockwise }
                PathLine { x: 0; y: surf.o + surf.sh - surf.cr }
                PathArc  { x: surf.cr; y: surf.o + surf.sh
                           radiusX: surf.cr; radiusY: surf.cr; direction: PathArc.Counterclockwise }
                PathLine { x: surf.sw - surf.fr; y: surf.o + surf.sh }
                PathArc  { x: surf.sw; y: surf.o + surf.sh + surf.fr
                           radiusX: surf.fr; radiusY: surf.fr; direction: PathArc.Clockwise }
                PathLine { x: surf.sw + 40; y: surf.o + surf.sh + surf.fr }
                PathLine { x: surf.sw + 40; y: 0 }
                PathLine { x: surf.sw; y: 0 }
            }
        }

        ColumnLayout {
            anchors { fill: parent; margins: 14 }
            spacing: 10

            PowerMenuButton {
                id: bPoweroff
                selected: win.navActive && win.sel === 0
                navActive: win.navActive
                onMouseMoved: { win.navActive = false; win.sel = 0 }
                glyph: "\uf011"; label: "Power off"; tone: Theme.alert
                cmd: ["systemctl", "poweroff"]
            }
            PowerMenuButton {
                id: bReboot
                selected: win.navActive && win.sel === 1
                navActive: win.navActive
                onMouseMoved: { win.navActive = false; win.sel = 1 }
                glyph: "\uf021"; label: "Reboot"; tone: Theme.secondary
                cmd: ["systemctl", "reboot"]
            }

            PowerMenuButton {
                id: bSleep
                selected: win.navActive && win.sel === 2
                navActive: win.navActive
                onMouseMoved: { win.navActive = false; win.sel = 2 }
                glyph: "\uf186"; label: "Sleep"; tone: Theme.accent
                cmd: ["systemctl", "suspend"]
            }
            PowerMenuButton {
                id: bHibernate
                selected: win.navActive && win.sel === 3
                navActive: win.navActive
                onMouseMoved: { win.navActive = false; win.sel = 3 }
                glyph: "\uf2dc"; label: "Hibernate"; tone: Theme.accent
                cmd: ["systemctl", "hibernate"]
            }
        }
    }
}
