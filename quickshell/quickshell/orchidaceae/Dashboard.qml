import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// Drops down under the bar while the pointer is on the top-center of the bar
// (triggerHovered) or on the panel itself.
PanelWindow {
    id: win
    property bool triggerHovered: false
    property bool shown: false
    property bool ipcOpen: false
    readonly property bool wanted: triggerHovered || hover.hovered || ipcOpen
    onIpcOpenChanged: if (ipcOpen) Qt.callLater(() => keys.forceActiveFocus())
    WlrLayershell.keyboardFocus: ipcOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IpcHandler {
        target: "dashboard"
        function toggle(): void { win.ipcOpen = !win.ipcOpen }
        function open(): void { win.ipcOpen = true }
        function close(): void { win.ipcOpen = false }
    }

    onWantedChanged: {
        if (wanted) { closeTimer.stop(); shown = true; }
        else closeTimer.restart();
    }
    Timer { id: closeTimer; interval: 300; onTriggered: win.shown = false }

    // ---- volume ----
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    PwObjectTracker { objects: [win.sink] }
    function setVol(v) {
        if (!sink || !sink.audio) return
        sink.audio.muted = false
        sink.audio.volume = Math.max(0, Math.min(1, v))
    }
    function toggleMute() { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted }

    // ---- brightness (brightnessctl, same curve as Brightness.qml) ----
    property real bright: 0
    property real pendingBright: 0
    property bool hasBacklight: false
    function setBright(v) {
        bright = Math.max(0, Math.min(1, v))
        pendingBright = bright
        if (!briSet.running) briSet.start()     // throttle while dragging
    }
    Timer {
        id: briSet
        interval: 60
        onTriggered: Quickshell.execDetached(["brightnessctl", "-e4", "-n2", "set",
            Math.max(1, Math.round(win.pendingBright * 100)) + "%"])
    }
    Process {
        id: briRead
        command: ["brightnessctl", "-e4", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(",");
                if (p.length < 5) return;
                win.hasBacklight = true;
                if (!briSet.running) win.bright = Math.max(0, Math.min(1, parseFloat(p[3]) / 100));
            }
        }
    }
    onShownChanged: if (shown) briRead.running = true
    Component.onCompleted: briRead.running = true

    anchors { top: true }
    margins { top: Theme.barHeight }
    exclusionMode: ExclusionMode.Ignore
    readonly property int pad: 16        // room for the top fillets left/right of the sheet
    implicitWidth: 900 + pad * 2
    implicitHeight: 400
    color: "transparent"
    visible: shown || sheet.y > -sheet.height - pad + 1
    mask: Region { item: sheet }

    Item {
        id: sheet
        x: win.pad
        width: 900
        height: 400
        y: win.shown ? 0 : -height - win.pad
        Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        HoverHandler { id: hover }
        Item { id: keys; focus: true; Keys.onEscapePressed: win.ipcOpen = false }

        // surface: 2px outline; bottom corners convex, top joins the bar with concave fillets
        Shape {
            id: surf
            x: -win.pad; y: -40
            width: sheet.width + win.pad * 2
            height: sheet.height + 40
            preferredRendererType: Shape.CurveRenderer
            readonly property real a: win.pad      // x offset of the sheet inside the shape
            readonly property real b: 40           // y offset
            readonly property real sw: sheet.width
            readonly property real sh: sheet.height
            readonly property real cr: 16           // bottom corner radius
            readonly property real fr: win.pad      // top fillet radius

            ShapePath {
                fillColor: Theme.background
                strokeColor: Theme.foreground
                strokeWidth: 2
                joinStyle: ShapePath.RoundJoin
                startX: surf.a - surf.fr; startY: surf.b
                PathArc  { x: surf.a; y: surf.b + surf.fr
                           radiusX: surf.fr; radiusY: surf.fr; direction: PathArc.Clockwise }
                PathLine { x: surf.a; y: surf.b + surf.sh - surf.cr }
                PathArc  { x: surf.a + surf.cr; y: surf.b + surf.sh
                           radiusX: surf.cr; radiusY: surf.cr; direction: PathArc.Counterclockwise }
                PathLine { x: surf.a + surf.sw - surf.cr; y: surf.b + surf.sh }
                PathArc  { x: surf.a + surf.sw; y: surf.b + surf.sh - surf.cr
                           radiusX: surf.cr; radiusY: surf.cr; direction: PathArc.Counterclockwise }
                PathLine { x: surf.a + surf.sw; y: surf.b + surf.fr }
                PathArc  { x: surf.a + surf.sw + surf.fr; y: surf.b
                           radiusX: surf.fr; radiusY: surf.fr; direction: PathArc.Clockwise }
                PathLine { x: surf.a + surf.sw + surf.fr; y: 0 }
                PathLine { x: surf.a - surf.fr; y: 0 }
                PathLine { x: surf.a - surf.fr; y: surf.b }
            }
        }

        ColumnLayout {
            anchors { fill: parent; margins: 18 }
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14
                Calendar { Layout.preferredWidth: 320; Layout.fillHeight: true }
                MediaCard { Layout.fillWidth: true; Layout.fillHeight: true }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            RowLayout {
                Layout.fillWidth: true
                spacing: 28

                // volume + brightness: icon, thin line with a vertical tick, percent
                Repeater {
                    model: [{ kind: "vol" }, { kind: "bri" }]
                    delegate: RowLayout {
                        id: row
                        required property var modelData
                        readonly property bool isVol: modelData.kind === "vol"
                        readonly property real val: isVol ? (win.muted ? 0 : win.vol) : win.bright
                        readonly property bool dimmed: isVol && win.muted
                        readonly property real pos: Math.max(0, Math.min(1, val))
                        function setVal(v) { if (isVol) win.setVol(v); else win.setBright(v); }

                        Layout.fillWidth: true
                        visible: isVol || win.hasBacklight
                        spacing: 12

                        Text {
                            Layout.preferredWidth: 22
                            horizontalAlignment: Text.AlignHCenter
                            text: row.isVol ? (win.muted || win.vol === 0 ? "\uf026" : win.vol < 0.5 ? "\uf027" : "\uf028") : "\uf185"
                            color: row.dimmed ? Theme.alert : Theme.foreground
                            font { family: Theme.iconFont; pixelSize: 16 }
                            MouseArea {
                                anchors { fill: parent; margins: -4 }
                                onClicked: if (row.isVol) win.toggleMute()
                            }
                        }

                        Item {
                            id: track
                            Layout.fillWidth: true
                            implicitHeight: 28
                            readonly property real hx: Math.max(2, Math.min(width - 2, width * row.pos))
                            readonly property int thick: 8    // line thickness (same for volume + brightness)

                            Rectangle {     // remaining track
                                x: track.hx
                                width: track.width - track.hx
                                height: track.thick; radius: 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.alpha(Theme.foreground, 0.25)
                            }
                            Rectangle {     // filled part
                                width: track.hx
                                height: track.thick; radius: 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: row.dimmed ? Theme.muted : Theme.foreground
                            }
                            Rectangle {     // tick
                                x: track.hx - 2
                                width: 4; height: 20; radius: 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.foreground
                            }
                            MouseArea {
                                anchors { fill: parent; topMargin: -4; bottomMargin: -4 }
                                cursorShape: Qt.PointingHandCursor
                                onPressed: m => row.setVal(Math.max(0, Math.min(1, m.x / width)))
                                onPositionChanged: m => { if (pressed) row.setVal(Math.max(0, Math.min(1, m.x / width))); }
                                onWheel: w => row.setVal(Math.max(0, Math.min(1, row.pos + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
                            }
                        }

                        Text {
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(row.val * 100) + "%"
                            color: row.dimmed ? Theme.muted : Theme.foreground
                            font { family: Theme.fontFamily; pixelSize: 13 }
                        }
                    }
                }
            }
        }
    }
}
