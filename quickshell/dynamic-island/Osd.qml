import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Volume / brightness OSD: drops out of the notch (flat top, flared corners), shows a title,
// a percent badge and a ruler-style slider (ticks + needle) with icons at both ends.
// Shown by Island.osdShow(kind) when volume or brightness change from a shortcut.
PanelWindow {
    id: win

    required property var source          // the Island (reads volume / brightness)
    property string kind: "volume"        // volume | brightness
    property bool open: false

    readonly property bool isVolume: kind === "volume"
    readonly property bool muted: isVolume && source && source.sink && source.sink.audio ? source.sink.audio.muted : false
    readonly property real value: {
        if (!source) return 0;
        if (isVolume) return source.sink && source.sink.audio ? source.sink.audio.volume : 0;
        return source.brMax > 0 ? source.brVal / source.brMax : 0;
    }
    readonly property real shown: muted ? 0 : Math.max(0, Math.min(1, value))

    // Keep in sync with the collapsed notch in Island.qml
    readonly property int notchW: 270
    readonly property int notchH: 38
    readonly property int panelW: 380
    readonly property int panelH: 106

    function show(k) {
        kind = k;
        open = true;
        hideTimer.restart();
    }
    Timer { id: hideTimer; interval: 1600; onTriggered: win.open = false }

    // Show the OSD for the current value without changing it:
    //   qs -c dynamic-island ipc call osd volume | brightness | hide
    IpcHandler {
        target: "osd"
        function volume(): void     { win.show("volume") }
        function brightness(): void { win.show("brightness") }
        function hide(): void       { win.open = false }
    }

    screen: Quickshell.screens[0]
    visible: open || panelRect.height > notchH + 1
    anchors { top: true; left: true; right: true }
    implicitHeight: panelH + 30
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}   // never takes input
    WlrLayershell.namespace: "dynamic-island-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Icons (drawn, no icon font needed)
    function drawIcon(c, k, big, col, muted) {
        c.reset();
        c.strokeStyle = col; c.fillStyle = col;
        c.lineWidth = 1.7; c.lineCap = "round"; c.lineJoin = "round";
        if (k === "brightness") {
            const r = big ? 5 : 3.4;
            c.beginPath(); c.arc(11, 11, r, 0, 2 * Math.PI); c.stroke();
            const a = r + (big ? 3 : 2.4), b = r + (big ? 6 : 4.4);
            for (let i = 0; i < 8; i++) {
                const t = i * Math.PI / 4;
                c.beginPath();
                c.moveTo(11 + Math.cos(t) * a, 11 + Math.sin(t) * a);
                c.lineTo(11 + Math.cos(t) * b, 11 + Math.sin(t) * b);
                c.stroke();
            }
        } else {
            c.beginPath();
            c.moveTo(3, 8); c.lineTo(7, 8); c.lineTo(12, 4); c.lineTo(12, 18); c.lineTo(7, 14); c.lineTo(3, 14);
            c.closePath(); c.fill();
            if (muted) {
                c.beginPath(); c.moveTo(15, 8); c.lineTo(20, 14); c.moveTo(20, 8); c.lineTo(15, 14); c.stroke();
            } else {
                c.beginPath(); c.arc(12.5, 11, 3.6, -0.9, 0.9); c.stroke();
                if (big) { c.beginPath(); c.arc(12.5, 11, 7.2, -0.9, 0.9); c.stroke(); }
            }
        }
    }

    // "Water drop" top corners, same as the island and the panels
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
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: win.open ? 30 : 14
        bottomRightRadius: bottomLeftRadius
        color: Theme.notch
        clip: true

        Behavior on width  { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
        Behavior on bottomLeftRadius { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }

        Item {
            id: body
            width: win.panelW
            height: win.panelH
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: win.open ? 1 : 0
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: win.open ? 110 : 0 }
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }

            // Title + percent badge
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 46 - 30
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.isVolume ? "Volume" : "Display"
                    color: Theme.foreground
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: badge.implicitWidth + 18
                    height: 22
                    radius: 11
                    color: Theme.surface
                    Text {
                        id: badge
                        anchors.centerIn: parent
                        text: win.muted ? "Muted" : Math.round(win.value * 100) + "%"
                        color: win.muted ? Theme.foregroundMuted : Theme.accent
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                }
            }

            // Left icon (small)
            Canvas {
                id: iconL
                x: 24; y: 62
                width: 22; height: 22
                antialiasing: true
                property color col: Qt.alpha(Theme.accent, 0.6)
                property string k: win.kind
                onColChanged: requestPaint()
                onKChanged: requestPaint()
                onPaint: win.drawIcon(getContext("2d"), win.kind, false, col, false)
            }
            // Right icon (big)
            Canvas {
                id: iconR
                x: win.panelW - 24 - width; y: 62
                width: 22; height: 22
                antialiasing: true
                property color col: Theme.accent
                property string k: win.kind
                property bool m: win.muted
                onColChanged: requestPaint()
                onKChanged: requestPaint()
                onMChanged: requestPaint()
                onPaint: win.drawIcon(getContext("2d"), win.kind, true, col, win.muted)
            }

            // Ruler: ticks every 2% (major every 10%), lit up to the value, needle at the value
            Item {
                id: ruler
                x: 58
                y: 52
                width: win.panelW - 116
                height: 42
                readonly property int n: 51

                Repeater {
                    model: ruler.n
                    Rectangle {
                        required property int index
                        readonly property bool major: index % 5 === 0
                        readonly property bool lit: index / (ruler.n - 1) <= win.shown + 0.001
                        x: index * (ruler.width - width) / (ruler.n - 1)
                        width: 2
                        height: major ? 20 : 11
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 1
                        color: lit ? Theme.accent : Qt.alpha(Theme.foreground, 0.22)
                        Behavior on color { ColorAnimation { duration: 90 } }
                    }
                }
                Rectangle {   // needle
                    x: win.shown * (ruler.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 4
                    height: 34
                    radius: 2
                    color: Theme.accent
                    Behavior on x { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
}
