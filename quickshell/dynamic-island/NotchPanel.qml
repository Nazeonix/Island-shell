import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// Base for Launcher / ThemePanel / Clipboard: a full-screen overlay (click outside closes) whose
// panel starts at the notch's size and grows out of it, flat on top, round at the bottom.
// Children go into `body`, a fixed panelW x panelH item (revealed as the panel grows).
PanelWindow {
    id: win

    property bool open: false
    property int panelW: 640
    property int panelH: 450
    property string ns: "panel"
    // Keep in sync with the collapsed notch in Island.qml (width 270, barH)
    property int notchW: 270
    property int notchH: 38

    default property alias content: body.data

    screen: Quickshell.screens[0]
    visible: open || panelRect.height > notchH + 1
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "dynamic-island-" + ns
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: win.open = false
    }

    // "Water drop" top corners, same as the island (10 collapsed, 18 open)
    property real earR: open ? 18 : 10
    Behavior on earR { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
    Shape {
        id: earL
        x: panelRect.x - width + 1; y: 0
        width: win.earR; height: win.earR
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: Theme.notch
            strokeWidth: -1
            startX: 0; startY: 0
            PathLine { x: earL.width; y: 0 }
            PathLine { x: earL.width; y: earL.height }
            PathArc { x: 0; y: 0; radiusX: earL.width; radiusY: earL.height; direction: PathArc.Counterclockwise }
        }
    }
    Shape {
        id: earRt
        x: panelRect.x + panelRect.width - 1; y: 0
        width: win.earR; height: win.earR
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: Theme.notch
            strokeWidth: -1
            startX: earRt.width; startY: 0
            PathLine { x: 0; y: 0 }
            PathLine { x: 0; y: earRt.height }
            PathArc { x: earRt.width; y: 0; radiusX: earRt.width; radiusY: earRt.height; direction: PathArc.Clockwise }
        }
    }

    Rectangle {
        id: panelRect
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: win.open ? win.panelW : win.notchW
        height: win.open ? win.panelH : win.notchH
        topLeftRadius: 0     // flared ears below replace top rounding
        topRightRadius: 0
        bottomLeftRadius: win.open ? 30 : 14
        bottomRightRadius: bottomLeftRadius
        color: Theme.notch
        clip: true

        Behavior on width  { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        Behavior on bottomLeftRadius { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }   // swallow clicks on the panel itself

        Item {
            id: body
            width: win.panelW
            height: win.panelH
            anchors.horizontalCenter: parent.horizontalCenter
            // content fades in once the notch has started growing
            opacity: win.open ? 1 : 0
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: win.open ? 140 : 0 }
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
