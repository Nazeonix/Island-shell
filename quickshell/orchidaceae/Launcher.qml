pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared launcher controller — bar logo and IPC both call this.
Singleton {
    id: root
    property bool open: false

    function toggle() { open = !open }
    function show() { open = true }
    function hide() { open = false }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggle() }
        function open(): void { root.show() }
        function close(): void { root.hide() }
    }
}
