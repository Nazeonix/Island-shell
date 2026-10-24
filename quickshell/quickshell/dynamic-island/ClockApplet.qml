import QtQuick
import Quickshell

// Clock capsule for Bar.qml. Clicking emits clicked(centerX) (x in window coordinates)
// so a popup can open centered under it.
//   ClockApplet { format: "hh:mm"; active: calendar.open; onClicked: (x) => calendar.toggleAt(x) }
Rectangle {
    id: root

    property string format: "hh:mm"
    property bool active: false          // highlight while its popup is open
    property color tint: Theme.orange
    signal clicked(real centerX)

    implicitWidth: row.implicitWidth + Theme.s(4) + Theme.s(12)
    implicitHeight: Theme.s(28)
    radius: height / 2
    color: (mouse.containsMouse || root.active) ? Theme.surface : Theme.background   // solid
    border.width: 1
    border.color: root.active ? Theme.accent : Theme.borderSubtle
    Behavior on color { ColorAnimation { duration: 120 } }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Row {
        id: row
        x: Theme.s(4)
        height: parent.height
        spacing: Theme.s(8)

        Rectangle {   // tinted badge with a clock glyph
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.s(20); height: width; radius: width / 2
            color: Qt.alpha(root.tint, 0.18)

            Canvas {
                id: glyph
                anchors.centerIn: parent
                width: Theme.s(14); height: Theme.s(14)
                antialiasing: true
                property color col: root.tint
                onColChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d");
                    c.reset();
                    c.scale(width / 14, height / 14);
                    c.strokeStyle = col;
                    c.lineWidth = 1.4;
                    c.lineCap = "round";
                    c.beginPath(); c.arc(7, 7, 5.5, 0, 2 * Math.PI); c.stroke();
                    c.beginPath(); c.moveTo(7, 7); c.lineTo(7, 3.8); c.moveTo(7, 7); c.lineTo(9.4, 8.4); c.stroke();
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, root.format)
            color: Theme.foreground
            font.pixelSize: Theme.s(13)
            font.weight: Font.Medium
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked(root.mapToItem(null, root.width / 2, 0).x)
    }
}
