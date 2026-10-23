import QtQuick

// Control-center slider card: label on top, then a flat track with a taller rectangular handle
// that sticks out above and below it (a fader), with a small gap between the fill and the handle.
Rectangle {
    id: ps

    property string label: ""
    property real value: 0            // 0..1
    property bool available: true
    property bool dragging: false
    property real dragValue: 0
    readonly property real shown: dragging ? dragValue : value
    signal moved(real v)

    // Proportions of the drawing: handle ~1.6x the track height, ~0.65x as wide
    readonly property int trackH: 22
    readonly property int handleW: 14
    readonly property int handleH: 36
    readonly property int gap: 4

    radius: 24
    color: Theme.surface
    opacity: available ? 1 : 0.4

    Text {
        x: 18; y: 8
        text: ps.label
        color: Theme.foreground
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }

    Item {
        id: pbar
        x: 14; y: 28
        width: parent.width - 28
        height: ps.handleH

        Rectangle {   // track
            id: track
            y: (parent.height - ps.trackH) / 2
            width: parent.width
            height: ps.trackH
            radius: 6
            color: Qt.alpha(Theme.foreground, 0.08)
        }
        Rectangle {   // fill, stops a gap before the handle
            y: track.y
            width: Math.max(0, handle.x - ps.gap)
            height: ps.trackH
            radius: 6
            color: Theme.accent
            visible: width > 0
            Text {
                visible: parent.width > 38
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(ps.shown * 100)
                color: Theme.notch
                font.pixelSize: 11
                font.weight: Font.Bold
            }
        }
        Rectangle {   // handle
            id: handle
            x: ps.shown * (pbar.width - width)
            width: ps.handleW
            height: ps.handleH
            radius: 5
            color: Theme.accent
        }

        MouseArea {
            anchors.fill: parent
            enabled: ps.available
            cursorShape: Qt.PointingHandCursor
            function setFrom(mx) {
                ps.dragValue = Math.max(0, Math.min(1, (mx - ps.handleW / 2) / (width - ps.handleW)));
                ps.moved(ps.dragValue);
            }
            onPressed: (e) => { ps.dragging = true; setFrom(e.x); }
            onPositionChanged: (e) => { if (pressed) setFrom(e.x); }
            onReleased: ps.dragging = false
            onCanceled: ps.dragging = false
            onWheel: (w) => {
                ps.dragValue = Math.max(0, Math.min(1, ps.shown + (w.angleDelta.y > 0 ? 0.05 : -0.05)));
                ps.moved(ps.dragValue);
            }
        }
    }
}
