import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland

// Click the bluetooth icon: enable / disable, paired and nearby devices.
PanelWindow {
    id: win

    property Item anchorItem: null
    property bool open: false
    property real cardX: 0
    property var deviceList: []
    property var watch: null
    property bool watchPairing: false
    property string message: ""
    property bool messageBad: false

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: !!(adapter && adapter.enabled)
    readonly property bool scanning: !!(adapter && adapter.discovering)
    readonly property var connectedDevs: {
        const out = [];
        for (let i = 0; i < deviceList.length; i++) if (deviceList[i].connected) out.push(deviceList[i]);
        return out;
    }
    readonly property var otherDevs: {
        const out = [];
        for (let i = 0; i < deviceList.length; i++) if (!deviceList[i].connected) out.push(deviceList[i]);
        return out;
    }

    function place() {
        if (!anchorItem) return;
        const host = anchorItem.Window.window;
        if (!host || !host.contentItem) {
            cardX = Math.max(8, width - 300 - 24);
            return;
        }
        const p = anchorItem.mapToItem(host.contentItem, 0, 0);
        const right = p.x + Math.max(1, anchorItem.width);
        const bound = host.width > 0 ? host.width : width;
        cardX = Math.max(8, Math.min(right - card.width, Math.max(8, bound - card.width - 8)));
    }
    function toggle() {
        if (!open) place();
        open = !open;
    }
    function reloadDevices() {
        if (!adapter) { deviceList = []; return; }
        const vals = adapter.devices.values.slice();
        vals.sort((a, b) => (b.connected ? 1 : 0) - (a.connected ? 1 : 0)
            || (b.paired ? 1 : 0) - (a.paired ? 1 : 0)
            || String(a.name || a.address || "").localeCompare(String(b.name || b.address || "")));
        deviceList = vals;
    }
    function setRadio(on) {
        if (!adapter) return;
        adapter.enabled = on;
        if (!on) adapter.discovering = false;
        else scanKick.start();
        message = "";
        reloadDevices();
    }
    function startScan() {
        if (open && adapter && adapter.enabled) adapter.discovering = true;
    }
    function activate(dev) {
        if (!dev || !adapter || !adapter.enabled) return;
        messageBad = false;
        watch = dev;
        watchPairing = false;
        try { if (!dev.trusted) dev.trusted = true; } catch (e) {}
        if (dev.connected) {
            message = "Disconnecting…";
            dev.disconnect();
            return;
        }
        if (!dev.paired) {
            message = "Pairing… confirm on the device";
            dev.pair();
            return;
        }
        message = "Connecting…";
        dev.connect();
    }
    function poll() {
        reloadDevices();
        const dev = watch;
        if (!dev) return;
        if (dev.pairing) { watchPairing = true; return; }
        if (dev.connected) { message = ""; watch = null; watchPairing = false; return; }
        if (watchPairing && dev.paired) {
            watchPairing = false;
            message = "Connecting…";
            dev.connect();
            return;
        }
        if (watchPairing && !dev.paired) {
            message = "Couldn't pair";
            messageBad = true;
            watch = null;
            watchPairing = false;
        }
    }

    onOpenChanged: {
        if (open) {
            place();
            startScan();
            poll();
            Qt.callLater(() => { place(); keys.forceActiveFocus(); });
        } else {
            if (adapter) adapter.discovering = false;
            message = "";
            watch = null;
            watchPairing = false;
        }
    }

    Timer { interval: 1000; repeat: true; running: win.open; onTriggered: win.poll() }
    Timer { id: scanKick; interval: 400; onTriggered: win.startScan() }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || card.opacity > 0.01
    focusable: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-bluetooth"

    MouseArea { anchors.fill: parent; onClicked: win.open = false }

    component Act: Rectangle {
        id: b
        property string label
        property bool on: false
        signal clicked()
        implicitWidth: t.implicitWidth + 22
        implicitHeight: 28
        radius: 8
        color: on ? Theme.accent : (ma.containsMouse ? Theme.foreground : "transparent")
        border { width: 2; color: Theme.foreground }
        Text {
            id: t
            anchors.centerIn: parent
            text: b.label
            color: (b.on || ma.containsMouse) ? Theme.background : Theme.foreground
            font { family: Theme.fontFamily; pixelSize: 11; bold: true; capitalization: Font.AllUppercase }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }

    component DevRow: Rectangle {
        id: nr
        property var dev
        signal picked()
        readonly property bool hot: ma.containsMouse
        readonly property bool on: !!(dev && dev.connected)
        readonly property string label: dev ? (dev.name || dev.address || "Device") : ""
        readonly property string tail: {
            if (!dev) return "";
            if (dev.connected) return hot ? "Disconnect" : "Connected";
            if (dev.pairing) return "Pairing";
            if (hot) return dev.paired ? "Connect" : "Pair";
            return dev.paired ? "Paired" : "";
        }
        readonly property color ink: (on || hot) ? Theme.background : Theme.foreground

        implicitHeight: 34
        height: 34
        radius: 8
        color: on ? Theme.accent : (hot ? Theme.foreground : "transparent")

        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: nr.label
                elide: Text.ElideRight
                color: nr.ink
                font { family: Theme.fontFamily; pixelSize: 13 }
            }
            Text {
                visible: !!(nr.dev && nr.dev.batteryAvailable && nr.dev.connected)
                text: (nr.dev && nr.dev.batteryAvailable) ? Math.round(nr.dev.battery * 100) + "%" : ""
                color: nr.ink
                font { family: Theme.fontFamily; pixelSize: 12 }
            }
            Text {
                visible: nr.tail !== ""
                text: nr.tail
                color: nr.ink
                font { family: Theme.fontFamily; pixelSize: 11; bold: true; capitalization: Font.AllUppercase }
            }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: nr.picked() }
    }

    Rectangle {
        id: card
        x: win.cardX
        y: win.open ? Theme.barHeight + 6 : Theme.barHeight - 6
        width: 300
        height: {
            const want = inner.implicitHeight + 28;
            const room = win.height - y - 12;
            return room > 48 ? Math.min(want, room) : want;
        }
        radius: 14
        color: Theme.background
        border { width: 2; color: Theme.foreground }
        clip: true
        opacity: win.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        Item {
            id: keys
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Escape) { e.accepted = true; win.open = false; }
            }
        }

        ColumnLayout {
            id: inner
            x: 14; y: 14
            width: parent.width - 28
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "\uf293"
                    color: win.btOn ? Theme.accent : Theme.muted
                    font { family: Theme.iconFont; pixelSize: 16 }
                }
                Text {
                    Layout.fillWidth: true
                    text: "Bluetooth"
                    color: Theme.foreground
                    font { family: Theme.fontFamily; pixelSize: 14; bold: true; capitalization: Font.AllUppercase }
                }
                Act {
                    visible: !!win.adapter
                    label: win.btOn ? "Disable" : "Enable"
                    on: win.btOn
                    onClicked: win.setRadio(!win.btOn)
                }
            }

            Text {
                visible: win.message !== ""
                Layout.fillWidth: true
                text: win.message
                elide: Text.ElideRight
                color: win.messageBad ? Theme.alert : Theme.muted
                font { family: Theme.fontFamily; pixelSize: 12 }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            Text {
                visible: !win.adapter
                text: "No adapter"
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 13 }
            }
            Text {
                visible: !!win.adapter && !win.btOn
                text: "Bluetooth is off"
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 13 }
            }

            Column {
                visible: win.btOn && win.connectedDevs.length > 0
                Layout.fillWidth: true
                spacing: 2
                Repeater {
                    model: win.connectedDevs
                    delegate: DevRow {
                        width: inner.width
                        dev: modelData
                        onPicked: win.activate(modelData)
                    }
                }
            }

            Text {
                visible: win.btOn
                text: "Other devices"
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 11; bold: true; capitalization: Font.AllUppercase; letterSpacing: 0.4 }
            }
            Text {
                visible: win.btOn && win.scanning && win.otherDevs.length > 0
                text: "Scanning…"
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 11 }
            }
            Text {
                visible: win.btOn && win.otherDevs.length === 0
                text: win.scanning ? "Scanning…" : "No other devices"
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 12 }
            }

            Flickable {
                id: flick
                visible: win.btOn && win.otherDevs.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(devCol.implicitHeight, 260)
                contentHeight: devCol.implicitHeight
                contentWidth: width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                interactive: contentHeight > height

                Column {
                    id: devCol
                    width: flick.width
                    spacing: 2
                    Repeater {
                        model: win.otherDevs
                        delegate: DevRow {
                            width: devCol.width
                            dev: modelData
                            onPicked: win.activate(modelData)
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: win.anchorItem
        function onWidthChanged() { if (win.open) win.place(); }
        function onXChanged() { if (win.open) win.place(); }
    }
}
