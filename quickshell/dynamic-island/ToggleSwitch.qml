import QtQuick

// macOS-style on/off switch: accent pill with a round knob.
Rectangle {
    id: sw

    property bool checked: false
    property bool enabledSwitch: true
    signal toggled()

    width: 52
    height: 30
    radius: height / 2
    color: checked ? Theme.accent : Theme.surfaceAlt
    opacity: enabledSwitch ? 1 : 0.4
    Behavior on color { ColorAnimation { duration: 140 } }

    Rectangle {
        y: 3
        x: sw.checked ? sw.width - width - 3 : 3
        width: sw.height - 6
        height: width
        radius: width / 2
        color: sw.checked ? Theme.onAccent : Theme.foreground
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: sw.enabledSwitch
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled()
    }
}
