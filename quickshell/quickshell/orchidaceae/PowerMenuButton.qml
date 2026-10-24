import QtQuick
import Quickshell

// button: fills with its tone color on hover / keyboard selection (no outline)
Rectangle {
    id: btn
    property string glyph
    property string label
    property color tone: Theme.foreground
    property var cmd: []
    property bool selected: false      // keyboard selection
    property bool navActive: false     // keyboard navigation in use (mouse hover then doesn't highlight)
    signal mouseMoved()
    readonly property bool lit: selected || (ma.containsMouse && !navActive)
    function activate() { Quickshell.execDetached(btn.cmd) }
    implicitWidth: 80
    implicitHeight: 74
    radius: 12
    color: lit ? tone : "transparent"
    Column {
        anchors.centerIn: parent
        spacing: 6
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.glyph
            color: btn.lit ? Theme.background : btn.tone
            font { family: Theme.iconFont; pixelSize: 22 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.label
            color: btn.lit ? Theme.background : Theme.foreground
            font { family: Theme.fontFamily; pixelSize: 11; bold: true; capitalization: Font.AllUppercase }
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: btn.mouseMoved()
        onClicked: btn.activate()
    }
}
