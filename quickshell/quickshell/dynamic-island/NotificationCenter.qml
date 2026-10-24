import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Persistent list of every live notification. Toggle with:
//   qs -c dynamic-island ipc call notifications toggle
//   qs -c dynamic-island ipc call notifications clear
PanelWindow {
    id: win

    required property var service
    property bool open: false

    screen: service.activeScreen
    visible: open || panel.opacity > 0

    anchors { top: true; right: true; bottom: true }
    margins { top: Theme.toastTop; right: Theme.margin; bottom: Theme.margin + (Theme.barAtTop ? 0 : Theme.barHeight) }

    implicitWidth: Theme.cardWidth + Theme.padding * 2
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "dynamic-island-notifications"
    WlrLayershell.layer: WlrLayer.Overlay   // above the click-away backdrop below
    mask: Region { item: panel }

    IpcHandler {
        target: "notifications"
        function toggle(): void { win.open = !win.open; }
        function clear(): void { win.service.dismissAll(); }
    }

    // Close on click outside: transparent full-screen surface one layer below the center
    PanelWindow {
        screen: win.screen
        visible: win.open
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "dynamic-island-notifications-backdrop"
        WlrLayershell.layer: WlrLayer.Top
        MouseArea { anchors.fill: parent; onClicked: win.open = false }
    }

    Rectangle {
        id: panel
        width: parent.width
        height: parent.height
        radius: Theme.radius + 4
        color: Theme.bg
        border.width: 1
        border.color: Theme.border

        opacity: win.open ? 1 : 0
        x: win.open ? 0 : 40
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.padding
            spacing: Theme.spacing

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Notifications"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitle
                    font.weight: Font.Medium
                }
                Rectangle {   // Clear all
                    visible: list.count > 0
                    Layout.preferredWidth: clearLabel.implicitWidth + 24
                    Layout.preferredHeight: 28
                    radius: Theme.innerRadius
                    color: clearArea.containsMouse ? Theme.accentSoft : Theme.bgRaised
                    Text {
                        id: clearLabel
                        anchors.centerIn: parent
                        text: "Clear all"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: clearArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: win.service.dismissAll()
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: "No notifications"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBody
                }

                ListView {
                    id: list
                    anchors.fill: parent
                    clip: true
                    spacing: Theme.spacing
                    boundsBehavior: Flickable.StopAtBounds

                    // Newest first
                    model: ScriptModel { values: win.service.list.values.slice().reverse() }

                    delegate: NotificationCard {
                        required property var modelData
                        notif: modelData
                        width: list.width
                        onDismissed: modelData.dismiss()
                    }

                    remove: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 0; duration: 160 }
                            NumberAnimation { property: "x"; to: 60; duration: 200; easing.type: Easing.InCubic }
                        }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}
