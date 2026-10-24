pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Notification daemon (org.freedesktop.Notifications). Kill mako/dunst/swaync first.
//   qs ipc call notifs toggle | toggleDnd | clear
Singleton {
    id: root

    property bool dnd: false
    property bool centerOpen: false
    property var popups: []                       // notifications currently shown as toasts
    readonly property var tracked: server.trackedNotifications
    readonly property int count: server.trackedNotifications.values.length

    function toggleCenter() { centerOpen = !centerOpen }
    function drop(n) { popups = popups.filter(p => p !== n) }
    function clearAll() {
        popups = []
        const all = server.trackedNotifications.values.slice()
        for (let i = 0; i < all.length; i++) all[i].dismiss()
    }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true
            n.closed.connect(() => root.drop(n))
            if (n.lastGeneration) return          // re-emitted after reload: history only
            if (root.dnd && n.urgency !== NotificationUrgency.Critical) return
            root.popups = [...root.popups, n]
        }
    }

    IpcHandler {
        target: "notifs"
        function toggle(): void { root.toggleCenter() }
        function toggleDnd(): void { root.dnd = !root.dnd }
        function clear(): void { root.clearAll() }
    }
}
