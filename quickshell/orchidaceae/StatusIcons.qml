import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// order: layout, mic, volume+%, network+ssid (click = wifi), bluetooth (click = devices), battery+%, bell
RowLayout {
    id: root
    spacing: 12

    property alias netAnchor: netSlot
    property alias btAnchor: btSlot
    property bool wifiOpen: false
    property bool btOpen: false
    signal wifiClicked()
    signal btClicked()
    function refreshNet() { if (!nm.running) nm.running = true }

    readonly property bool isNiri: !!Quickshell.env("NIRI_SOCKET")

    // ---- keyboard layout ----
    property string layout: ""
    function abbr(n) {
        const m = n.match(/\(([^)]+)\)/);
        return (m ? m[1] : n).slice(0, 2).toLowerCase();
    }
    Process {
        id: kb
        command: root.isNiri ? ["niri", "msg", "--json", "keyboard-layouts"] : ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (d.names) root.layout = root.abbr(d.names[d.current_idx]);
                    else if (d.keyboards) {
                        let k = d.keyboards[0];
                        for (const x of d.keyboards) if (x.main) k = x;
                        root.layout = root.abbr(k.active_keymap);
                    }
                } catch (e) {}
            }
        }
    }
    // Hyprland: refresh on the activelayout event; niri has no event hook here, so poll
    Connections {
        target: Hyprland
        enabled: !root.isNiri
        function onRawEvent(e) { if (e.name === "activelayout" && !kb.running) kb.running = true }
    }
    Timer {
        interval: 1500; running: root.isNiri; repeat: true; triggeredOnStart: true
        onTriggered: if (!kb.running) kb.running = true
    }
    Component.onCompleted: kb.running = true
    Text {
        visible: root.layout !== ""
        text: root.layout
        color: Theme.foreground
        font { family: Theme.fontFamily; pixelSize: 14 }
    }

    // ---- audio ----
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property bool micMuted: source && source.audio ? source.audio.muted : false
    PwObjectTracker { objects: [root.sink, root.source] }

    Text {
        text: root.micMuted ? "\uf131" : "\uf130"
        color: root.micMuted ? Theme.alert : Theme.foreground
        font { family: Theme.iconFont; pixelSize: 15 }
        MouseArea {
            anchors { fill: parent; margins: -4 }
            onClicked: if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
        }
    }
    Item {
        implicitWidth: volRow.implicitWidth
        implicitHeight: volRow.implicitHeight
        RowLayout {
            id: volRow
            spacing: 4
            Text {
                text: root.muted || root.vol === 0 ? "\uf026" : root.vol < 0.5 ? "\uf027" : "\uf028"
                color: root.muted ? Theme.alert : Theme.foreground
                font { family: Theme.iconFont; pixelSize: 15 }
            }
            Text {
                text: root.muted ? "mute" : Math.round(root.vol * 100) + "%"
                color: root.muted ? Theme.alert : Theme.foreground
                font { family: Theme.fontFamily; pixelSize: 13 }
            }
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
            onWheel: w => {
                if (!root.sink || !root.sink.audio) return;
                root.sink.audio.volume = Math.max(0, Math.min(1.0,
                    root.sink.audio.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05)));
            }
        }
    }

    // ---- network (nmcli: type + SSID when wifi) ----
    property string net: "none"
    property string netName: ""
    Process {
        id: nm
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = "none";
                let name = "";
                text.split("\n").forEach(l => {
                    const parts = l.split(":");
                    if (parts.length < 2) return;
                    const type = parts[0], state = parts[1], conn = parts.slice(2).join(":") || "";
                    if (type === "wifi" && state === "connected") {
                        r = "wifi";
                        name = conn;
                    } else if (type === "ethernet" && state === "connected" && r !== "wifi") {
                        r = "ethernet";
                        name = conn || "eth";
                    }
                });
                root.net = r;
                root.netName = name;
            }
        }
    }
    Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!nm.running) nm.running = true
    }
    Item {
        id: netSlot
        implicitWidth: netRow.implicitWidth
        implicitHeight: netRow.implicitHeight

        RowLayout {
            id: netRow
            spacing: 4
            Text {
                text: root.net === "ethernet" ? "\uf0e8" : "\uf1eb"
                color: root.wifiOpen ? Theme.accent
                     : root.net === "none" ? Theme.muted : Theme.foreground
                font { family: Theme.iconFont; pixelSize: 15 }
            }
            Text {
                visible: root.net !== "none" && root.netName !== ""
                text: root.netName.length > 12 ? root.netName.slice(0, 11) + "…" : root.netName
                color: root.wifiOpen ? Theme.accent : Theme.foreground
                font { family: Theme.fontFamily; pixelSize: 13 }
            }
            Text {
                visible: root.net === "none"
                text: "off"
                color: root.wifiOpen ? Theme.accent : Theme.muted
                font { family: Theme.fontFamily; pixelSize: 13 }
            }
        }
        MouseArea {
            anchors.fill: netRow
            anchors.margins: -6
            onClicked: root.wifiClicked()
        }
    }

    // ---- bluetooth ----
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: adapter ? adapter.enabled : false
    readonly property bool btConnected: {
        if (!adapter) return false;
        const d = adapter.devices.values;
        for (let i = 0; i < d.length; i++) if (d[i].connected) return true;
        return false;
    }
    Item {
        id: btSlot
        implicitWidth: btIcon.implicitWidth
        implicitHeight: btIcon.implicitHeight
        Text {
            id: btIcon
            text: "\uf293"
            color: root.btOpen || root.btConnected ? Theme.accent
                 : root.btOn ? Theme.foreground : Theme.muted
            font { family: Theme.iconFont; pixelSize: 15 }
        }
        MouseArea {
            anchors.fill: btIcon
            anchors.margins: -6
            onClicked: root.btClicked()
        }
    }

    // ---- battery (icon + %) ----
    readonly property var bat: UPower.displayDevice
    readonly property real pct: bat.percentage
    readonly property bool charging: bat.state === UPowerDeviceState.Charging
                                  || bat.state === UPowerDeviceState.FullyCharged
    RowLayout {
        spacing: 4
        visible: root.bat.isPresent
        Text {
            text: root.charging ? "\uf0e7"
                : root.pct > 0.875 ? "\uf240"
                : root.pct > 0.625 ? "\uf241"
                : root.pct > 0.375 ? "\uf242"
                : root.pct > 0.125 ? "\uf243" : "\uf244"
            color: root.charging ? Theme.accent : root.pct <= 0.15 ? Theme.alert : Theme.foreground
            font { family: Theme.iconFont; pixelSize: 15 }
        }
        Text {
            text: Math.round(root.pct * 100) + "%"
            color: root.charging ? Theme.accent : root.pct <= 0.15 ? Theme.alert : Theme.foreground
            font { family: Theme.fontFamily; pixelSize: 13 }
        }
    }

    // ---- notifications bell: click = center, right-click = do-not-disturb ----
    Text {
        text: Notifs.dnd ? "\uf1f6" : "\uf0f3"
        color: Notifs.dnd ? Theme.muted : Notifs.centerOpen ? Theme.accent : Theme.foreground
        font { family: Theme.iconFont; pixelSize: 15 }
        Rectangle {
            visible: Notifs.count > 0 && !Notifs.dnd
            anchors { top: parent.top; right: parent.right; topMargin: -2; rightMargin: -3 }
            width: 7; height: 7
            color: Theme.alert
        }
        MouseArea {
            anchors { fill: parent; margins: -4 }
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => { if (m.button === Qt.RightButton) Notifs.dnd = !Notifs.dnd; else Notifs.toggleCenter(); }
        }
    }
}
