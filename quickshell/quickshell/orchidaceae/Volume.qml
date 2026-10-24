import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// Minimal volume OSD (iOS style vertical bar, left edge): pops up on any volume/mute change, click-through.
//   qs -c orchidaceae ipc call volume up | down | mute | get
Scope {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property real ratio: muted ? 0 : Math.max(0, Math.min(1, vol))

    property bool shown: false
    property real last: 0              // previous volume, to tell up from down
    property int dir: 1                // +1 last change was up, -1 down
    property real nudge: 0             // vertical bounce offset of the pill (px)
    property bool armed: false          // ignore the values pipewire reports at startup / device switch

    PwObjectTracker { objects: [root.sink] }

    function bounce() { bounceAnim.restart() }

    function pop() {
        if (!armed) return;
        shown = true;
        hideTimer.restart();
    }
    function step(d) {
        if (!sink || !sink.audio) return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + d));
        pop();
    }
    function toggleMute() {
        if (!sink || !sink.audio) return;
        sink.audio.muted = !sink.audio.muted;
        pop();
    }

    // the pill hops in the direction of the change, then springs back
    SequentialAnimation {
        id: bounceAnim
        NumberAnimation { target: root; property: "nudge"; to: -root.dir * 10; duration: 80; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "nudge"; to: 0; duration: 650; easing.type: Easing.OutElastic; easing.amplitude: 1.0; easing.period: 0.35 }
    }
    Timer { id: hideTimer; interval: 1500; onTriggered: root.shown = false }
    Timer { id: armTimer; interval: 1000; running: true; onTriggered: root.armed = true }
    onSinkChanged: { armed = false; armTimer.restart() }

    Connections {
        target: root.sink ? root.sink.audio : null
        function onVolumeChanged() {
            const v = root.vol;
            if (root.armed && v !== root.last) { root.dir = v > root.last ? 1 : -1; root.bounce(); }
            root.last = v;
            root.pop();
        }
        function onMutedChanged() { root.pop() }
    }

    IpcHandler {
        target: "volume"
        function up(): void { root.step(0.05) }
        function down(): void { root.step(-0.05) }
        function mute(): void { root.toggleMute() }
        function get(): string { return Math.round(root.vol * 100) + (root.muted ? " muted" : "") }
    }

    PanelWindow {
        anchors { left: true }                  // centered vertically
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        implicitWidth: 130                      // gap from the screen edge + pill + percentage
        implicitHeight: 300
        visible: root.shown || pill.opacity > 0.01
        mask: Region {}                         // never steals input
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-volume"

        // iOS-style: thin vertical pill on the left edge, fills from the bottom
        Rectangle {
            id: pill
            readonly property int gap: Theme.frameThickness + 8   // distance from the screen edge (just inside the frame)
            x: root.shown ? gap : -width - 4
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.nudge
            width: 6
            height: 260
            radius: width / 2
            color: Qt.alpha(Theme.foreground, 0.3)
            opacity: root.shown ? 1 : 0
            clip: true
            Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: parent.height * root.ratio
                radius: parent.radius
                color: Theme.foreground
                Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
            }
        }
    }
}
