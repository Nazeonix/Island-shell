import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Owns org.freedesktop.Notifications.
//   list   : every notification still alive (feeds the center)
//   toasts : subset currently shown as popups (feeds the toast window)
// Only one daemon can own the DBus name: stop mako/dunst/swaync first.
Scope {
    id: root

    property alias list: server.trackedNotifications
    property var toasts: []

    // Monitor for popups (compositor-agnostic: the first screen)
    readonly property var activeScreen: Quickshell.screens[0]

    function hideToast(n) { toasts = toasts.filter(t => t !== n); }
    function dismissAll() { list.values.slice().forEach(n => n.dismiss()); }

    NotificationServer {
        id: server
        keepOnReload: true            // survive `qs` reloads
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;         // without this it is destroyed after this handler
            root.toasts = [...root.toasts.filter(t => t !== n), n];
            // Closed by the app, a dismiss, or the center: drop its toast too
            n.closed.connect(() => root.hideToast(n));
        }
    }
}
