pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Bar visibility. One instance (not per monitor) so IPC is registered once.
//   qs ipc call bar toggle | show | hide | toggleAuto | get
Singleton {
    id: root

    property bool autoHide: false   // slide the top bar away until the pointer hits the top edge
    property bool hidden: false     // forced off; ignores hover until toggled back
    property bool winbarEnabled: true // WinBar title bars on/off (toggle in Settings)
    property int winbarSpace: 0      // extra top space reserved for WinBar title bars (set by WinBar)
    property bool ready: false

    readonly property string stateFile:
        (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell-bar"

    function persist() {
        if (!ready) return;
        store.setText((autoHide ? "1" : "0") + " " + (hidden ? "1" : "0") + " " + (winbarEnabled ? "1" : "0"));
    }
    function toggle() { hidden = !hidden; }
    function show() { hidden = false; }
    function hide() { hidden = true; }
    function toggleAuto() { autoHide = !autoHide; }

    FileView {
        id: store
        path: root.stateFile
        onLoaded: {
            const parts = text().trim().split(/\s+/);
            if (parts.length >= 2) {
                root.autoHide = parts[0] === "1";
                root.hidden = parts[1] === "1";
            }
            if (parts.length >= 3) root.winbarEnabled = parts[2] === "1";
            root.ready = true;
        }
        onLoadFailed: root.ready = true
    }
    onAutoHideChanged: persist()
    onHiddenChanged: persist()
    onWinbarEnabledChanged: persist()

    IpcHandler {
        target: "bar"
        function toggle(): void { root.toggle(); }
        function show(): void { root.show(); }
        function hide(): void { root.hide(); }
        function toggleAuto(): void { root.toggleAuto(); }
        function get(): string {
            return (root.hidden ? "hidden" : "shown") + (root.autoHide ? " auto" : "");
        }
    }
}
