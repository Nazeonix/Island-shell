import QtQuick
import Quickshell
import Quickshell.Wayland

// Transient popups, top-right under the island. Hidden when nothing to show.
PanelWindow {
    id: win

    required property var service

    screen: service.activeScreen
    visible: service.toasts.length > 0 || linger.running

    // Anchor top + left + right instead to center the stack under the island
    anchors { top: true; right: true }
    margins { top: Theme.toastTop; right: Theme.margin }

    implicitWidth: Theme.cardWidth
    // Fixed tall window; the mask below keeps everything outside the cards click-through
    implicitHeight: screen ? screen.height - Theme.toastTop - Theme.margin : 600
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "dynamic-island-toasts"
    mask: Region { item: list }

    // Keep the window mapped while the last card plays its exit animation
    Timer { id: linger; interval: 400 }
    Connections {
        target: win.service
        function onToastsChanged() {
            if (win.service.toasts.length === 0) linger.restart();
        }
    }

    ListView {
        id: list
        width: parent.width
        height: contentHeight
        interactive: false
        spacing: Theme.spacing

        // ScriptModel diffs the array, which is what lets add/remove animate
        model: ScriptModel { values: win.service.toasts }

        delegate: NotificationCard {
            required property var modelData
            notif: modelData
            toast: true
            width: list.width
            onExpired: win.service.hideToast(modelData)   // popup only; stays in the center
            onDismissed: modelData.dismiss()              // closes it everywhere
        }

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
                NumberAnimation { property: "x"; from: 60; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
            }
        }
        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: 180 }
                NumberAnimation { property: "x"; to: 60; duration: 220; easing.type: Easing.InCubic }
            }
        }
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic }
        }
    }
}
