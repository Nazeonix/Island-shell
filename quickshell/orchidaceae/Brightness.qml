import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Brightness OSD: half-hidden sun on the right edge, 5 rays = 5 x 20%, each grows with the level. Needs `brightnessctl`.
//   qs -c orchidaceae ipc call brightness up | down | set <percent> | get
// Bind your brightness keys to these calls so the OSD shows.
Scope {
    id: root

    property real level: 0          // 0..1
    property bool shown: false
    property bool seeded: false     // first read at startup must not pop the OSD
    property bool wantPop: false
    property int step: 5            // percent per up/down

    function pop() {
        shown = true;
        hideTimer.restart();
    }
    function apply(arg) {
        Quickshell.execDetached(["brightnessctl", "-e4", "-n2", "set", arg]);   // same curve/min as before
        wantPop = true;
        refreshTimer.restart();
    }
    function refresh() { if (!reader.running) reader.running = true }

    Timer { id: hideTimer; interval: 1500; onTriggered: root.shown = false }
    Timer { id: refreshTimer; interval: 80; onTriggered: root.refresh() }
    Component.onCompleted: refresh()

    Process {
        id: reader
        command: ["brightnessctl", "-e4", "-m"]     // device,class,current,percent%,max
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(",");
                if (p.length < 5) return;
                const v = Math.max(0, Math.min(1, parseFloat(p[3]) / 100));
                const changed = v !== root.level;
                root.level = v;
                if (root.seeded && (changed || root.wantPop)) root.pop();
                root.seeded = true;
                root.wantPop = false;
            }
        }
    }

    IpcHandler {
        target: "brightness"
        function up(): void { root.apply(root.step + "%+") }
        function down(): void { root.apply(root.step + "%-") }
        function set(percent: int): void { root.apply(Math.max(1, Math.min(100, percent)) + "%") }
        function get(): string { return Math.round(root.level * 100) + "%" }
    }

    PanelWindow {
        anchors { right: true }                     // centered vertically
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        implicitWidth: 96
        implicitHeight: 160
        visible: root.shown || sun.opacity > 0.01
        mask: Region {}                             // never steals input
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-brightness"

        // sun centre sits on the screen edge, so the right half is cropped away
        Item {
            id: sun
            readonly property real cx: width
            readonly property real cy: height / 2
            readonly property real r: 27
            width: parent.width
            height: parent.height
            x: root.shown ? 0 : 84                  // slides in from the right edge
            opacity: root.shown ? 1 : 0
            Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

            Rectangle {
                x: sun.cx - sun.r
                y: sun.cy - sun.r
                width: sun.r * 2
                height: sun.r * 2
                radius: sun.r
                color: "transparent"
                border { width: 4; color: Theme.foreground }
            }

            // each ray owns 20%: ray 0 = bottom (0-20%) ... ray 4 = top (80-100%).
            // It grows outward from the sun as brightness rises and shrinks as it falls.
            Repeater {
                model: [135, 157.5, 180, 202.5, 225]
                delegate: Rectangle {
                    id: ray
                    required property real modelData
                    required property int index
                    readonly property real rad: modelData * Math.PI / 180
                    readonly property real fill: Math.max(0, Math.min(1, (root.level - index * 0.2) / 0.2))
                    readonly property real inner: sun.r * 1.34          // gap between sun and ray
                    property real smoothFill: fill
                    Behavior on smoothFill { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                    readonly property real len: (7 + 17 * smoothFill) * reveal   // 7px stub .. 24px full

                    // appear: sun first, then rays pop out one by one, bottom to top
                    property real reveal: 0
                    readonly property bool active: root.shown
                    onActiveChanged: {
                        showAnim.stop(); hideAnim.stop();
                        if (active) { reveal = 0; showAnim.start() }
                        else hideAnim.start()
                    }
                    SequentialAnimation {
                        id: showAnim
                        PauseAnimation { duration: 260 + ray.index * 100 }
                        NumberAnimation { target: ray; property: "reveal"; to: 1; duration: 280; easing.type: Easing.OutBack }
                    }
                    NumberAnimation { id: hideAnim; target: ray; property: "reveal"; to: 0; duration: 200 }

                    width: len
                    height: 4.5
                    radius: height / 2
                    x: sun.cx + (inner + len / 2) * Math.cos(rad) - width / 2
                    y: sun.cy + (inner + len / 2) * Math.sin(rad) - height / 2
                    rotation: modelData
                    color: Theme.foreground
                    opacity: Math.min(1, reveal * 1.5) * (0.3 + 0.7 * smoothFill)
                }
            }
        }
    }
}
