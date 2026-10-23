import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property bool compact: false    // notch style: ascending signal bars, no circle/ring
    width: compact ? 19 : 35
    height: compact ? 15 : 35

    property bool connected: false
    property int signal: 0          // 0–100
    property string ssid: ""
    readonly property int level: !connected ? 0 : signal >= 67 ? 3 : signal >= 34 ? 2 : 1

    onConnectedChanged: canvas.requestPaint()
    onSignalChanged: canvas.requestPaint()
    onCompactChanged: canvas.requestPaint()

    // Poll NetworkManager
    Process {
        id: proc
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL,SSID", "dev", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector {
            onStreamFinished: {
                let found = false;
                for (const line of text.split("\n")) {
                    const m = line.match(/^\*:(\d+):(.*)$/);
                    if (m) {
                        root.signal = parseInt(m[1]);
                        root.ssid = m[2];
                        found = true;
                        break;
                    }
                }
                if (!found) { root.signal = 0; root.ssid = ""; }
                root.connected = found;
            }
        }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    // Circle
    Rectangle {
        visible: !root.compact
        anchors.fill: parent
        radius: width / 2
        color: Theme.notch
    }

    // Signal ring + wifi glyph
    Canvas {
        id: canvas
        Connections { target: Theme; function onCurrentChanged() { canvas.requestPaint() } }
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2;
            const lit = Theme.accent, dim = Qt.alpha(Theme.accent, 0.22), accent = Theme.primary;

            if (root.compact) {   // 4 ascending bars
                const bars = !root.connected ? 0 : Math.max(1, Math.min(4, Math.ceil(root.signal / 25)));
                for (let i = 0; i < 4; i++) {
                    const h = 4 + i * 3.6;
                    ctx.fillStyle = i < bars ? lit : dim;
                    ctx.beginPath();
                    ctx.roundedRect(i * 5, height - h, 3.2, h, 1.2, 1.2);
                    ctx.fill();
                }
                return;
            }

            // Ring track + signal progress
            ctx.lineWidth = 2;
            ctx.lineCap = "round";
            if (root.connected) {
                ctx.strokeStyle = accent;
                ctx.beginPath();
                ctx.arc(cx, cy, 16, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * root.signal / 100);
                ctx.stroke();
            }

            // Wifi arcs
            const gy = cy + 5;
            for (let i = 1; i <= 3; i++) {
                ctx.strokeStyle = (root.connected && i <= root.level) ? lit : dim;
                ctx.beginPath();
                ctx.arc(cx, gy, i * 4.2, -3 * Math.PI / 4, -Math.PI / 4);
                ctx.stroke();
            }
            ctx.fillStyle = root.connected ? lit : dim;
            ctx.beginPath(); ctx.arc(cx, gy, 1.6, 0, 2 * Math.PI); ctx.fill();

            // Disconnected slash
            if (!root.connected) {
                ctx.strokeStyle = Theme.error;
                ctx.beginPath();
                ctx.moveTo(cx - 7, cy - 7);
                ctx.lineTo(cx + 7, cy + 7);
                ctx.stroke();
            }
        }
    }
}
