import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Numbered cells; chosen = rounded square, has windows = accent bold number, empty = dim. Hyprland native, niri via `niri msg`.
Row {
    id: root
    property string screenName: ""
    property int count: 5   // Hyprland: fixed 1..count

    readonly property bool isHypr: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    readonly property bool isNiri: !!Quickshell.env("NIRI_SOCKET")
    property var niriWs: []

    // true when the workspace really has a window (not just "the workspace exists")
    function hyprOcc(id, ws) {
        try {
            const t = Hyprland.toplevels.values;
            for (let j = 0; j < t.length; j++) {
                const w = t[j].workspace;
                if (w && w.id === id) return true;
            }
            return false;
        } catch (e) {}
        try {
            if (ws && ws.lastIpcObject && ws.lastIpcObject.windows !== undefined) return ws.lastIpcObject.windows > 0;
        } catch (e) {}
        return !!ws;
    }
    function hyprItems() {
        const out = [];
        const vals = Hyprland.workspaces.values;
        const fw = Hyprland.focusedWorkspace;
        for (let i = 1; i <= count; i++) {
            let ws = null;
            for (let j = 0; j < vals.length; j++) if (vals[j].id === i) ws = vals[j];
            out.push({ key: i, active: !!fw && fw.id === i, occupied: hyprOcc(i, ws) });
        }
        return out;
    }
    function niriItems() {
        return niriWs
            .filter(w => w.output === screenName)
            .sort((a, b) => a.idx - b.idx)
            .map(w => ({ key: w.idx, active: w.is_active, occupied: w.active_window_id !== null }));
    }
    function go(key) {
        if (isHypr) Hyprland.dispatch("hl.dsp.focus({ workspace = " + key + " })");   // Lua config (Hyprland 0.55+). Old hyprlang: "workspace " + key
        else if (isNiri) Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(key)]);
    }

    readonly property var items: isHypr ? hyprItems() : (isNiri ? niriItems() : [])

    visible: items.length > 0
    spacing: 0

    Repeater {
        model: root.items
        delegate: Item {
            required property var modelData
            width: 24
            height: 22

            Rectangle {     // chosen workspace: rounded square
                anchors.centerIn: parent
                width: 22; height: 20
                radius: 7
                color: modelData.active ? Theme.accent : "transparent"
            }
            Text {
                anchors.centerIn: parent
                text: modelData.key
                color: modelData.active ? Theme.background
                     : modelData.occupied ? Theme.accent : Theme.muted   // accent = has windows open
                font { family: Theme.fontFamily; pixelSize: 13; bold: modelData.active || modelData.occupied }
            }
            MouseArea { anchors.fill: parent; onClicked: root.go(modelData.key) }
        }
    }

    Process {
        id: query
        command: ["niri", "msg", "--json", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.niriWs = JSON.parse(text); } catch (e) {} }
        }
    }
    Process {
        running: root.isNiri
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser { onRead: line => { if (!query.running) query.running = true; } }
    }
    Component.onCompleted: {
        if (isNiri) query.running = true;
        try { Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); } catch (e) {}
    }
}
