import QtQuick
import Quickshell

// Month grid (6 x 7, fixed height). Pure view + month/year state; no popup logic.
// Use: CalendarGrid { id: grid; width: 288 }   grid.step(1)   grid.reset()   grid.title
Item {
    id: root

    property int weekStart: 1                       // 0 = Sunday, 1 = Monday
    property int year: new Date().getFullYear()
    property int month: new Date().getMonth()       // 0..11
    property int cellH: 36

    readonly property real cellW: width / 7
    readonly property int offset: (new Date(year, month, 1).getDay() - weekStart + 7) % 7
    readonly property string todayKey: Qt.formatDate(clock.date, "yyyyMMdd")
    readonly property string title: Qt.formatDate(new Date(year, month, 1), "MMMM yyyy")

    implicitHeight: 24 + 6 * cellH

    function step(d) {          // months
        const t = new Date(year, month + d, 1);
        year = t.getFullYear();
        month = t.getMonth();
    }
    function stepYear(d) { year = year + d; }
    function reset() {
        const t = new Date();
        year = t.getFullYear();
        month = t.getMonth();
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    MouseArea {   // wheel = change month
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: (w) => root.step(w.angleDelta.y > 0 ? -1 : 1)
    }

    // Weekday labels
    Row {
        Repeater {
            model: 7
            Text {
                required property int index
                width: root.cellW
                height: 24
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: Qt.locale().dayName((root.weekStart + index) % 7, Locale.ShortFormat).slice(0, 2)
                color: Theme.foregroundMuted
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }
    }

    // Days
    Grid {
        y: 24
        columns: 7
        Repeater {
            model: 42
            Item {
                id: cell
                required property int index
                readonly property var d: new Date(root.year, root.month, index - root.offset + 1)
                readonly property bool inMonth: d.getMonth() === root.month
                readonly property bool isToday: Qt.formatDate(d, "yyyyMMdd") === root.todayKey
                width: root.cellW
                height: root.cellH

                Rectangle {
                    visible: cell.isToday
                    anchors.centerIn: parent
                    width: 30; height: 30; radius: 15
                    color: Theme.accent
                }
                Text {
                    anchors.centerIn: parent
                    text: cell.d.getDate()
                    font.pixelSize: 13
                    font.weight: cell.isToday ? Font.Bold : Font.Normal
                    color: cell.isToday ? Theme.background
                                        : (cell.inMonth ? Theme.foreground : Qt.alpha(Theme.foreground, 0.3))
                }
            }
        }
    }
}
