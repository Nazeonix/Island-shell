import QtQuick
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: root
    color: "transparent"

    SystemClock { id: clk; precision: SystemClock.Minutes }

    property int vy: new Date().getFullYear()
    property int vm: new Date().getMonth()
    readonly property int offset: (new Date(vy, vm, 1).getDay() + 6) % 7   // Monday first

    function shift(n) {
        const d = new Date(vy, vm + n, 1);
        vy = d.getFullYear(); vm = d.getMonth();
    }
    function today() { vy = clk.date.getFullYear(); vm = clk.date.getMonth(); }

    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 8

        // header
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: Qt.locale().monthName(root.vm) + " " + root.vy
                color: Theme.foreground
                font { family: Theme.fontFamily; pixelSize: 16; bold: true; capitalization: Font.AllUppercase }
                MouseArea { anchors.fill: parent; onClicked: root.today() }
            }
            Repeater {
                model: [{ g: "\uf053", n: -1 }, { g: "\uf054", n: 1 }]
                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: 30; implicitHeight: 30
                    color: nav.containsMouse ? Theme.surface : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: modelData.g
                        color: Theme.foreground
                        font { family: Theme.iconFont; pixelSize: 12 }
                    }
                    MouseArea { id: nav; anchors.fill: parent; hoverEnabled: true; onClicked: root.shift(modelData.n) }
                }
            }
        }

        // weekday names
        Row {
            Layout.alignment: Qt.AlignHCenter
            Repeater {
                model: 7
                delegate: Text {
                    required property int index
                    width: 40; horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale().dayName((index + 1) % 7, Locale.ShortFormat).slice(0, 2)
                    color: Theme.secondary
                    font { family: Theme.fontFamily; pixelSize: 13 }
                }
            }
        }

        // days
        Grid {
            Layout.alignment: Qt.AlignHCenter
            columns: 7
            Repeater {
                model: 42
                delegate: Item {
                    required property int index
                    width: 40; height: 36
                    readonly property var d: new Date(root.vy, root.vm, 1 - root.offset + index)
                    readonly property bool inMonth: d.getMonth() === root.vm
                    readonly property bool isToday: d.getFullYear() === clk.date.getFullYear()
                        && d.getMonth() === clk.date.getMonth() && d.getDate() === clk.date.getDate()
                    Rectangle {
                        anchors.centerIn: parent
                        visible: parent.isToday
                        width: 34; height: 32
                        color: Theme.accent
                    }
                    Text {
                        anchors.centerIn: parent
                        text: parent.d.getDate()
                        color: parent.isToday ? Theme.background
                             : parent.inMonth ? Theme.foreground : Qt.alpha(Theme.foreground, 0.3)
                        font { family: Theme.fontFamily; pixelSize: 13; bold: parent.isToday }
                    }
                }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
