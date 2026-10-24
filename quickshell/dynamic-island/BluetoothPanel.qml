import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// Bluetooth menu that drops out of the notch, macOS style: switch on top, "My Devices" (paired)
// and "Nearby Devices" (found while this menu is open). Click a paired device to connect or
// disconnect it, a nearby one to pair and connect. Uses BlueZ through Quickshell.Bluetooth.
//   qs -c dynamic-island ipc call bluetooth toggle   (also: show / hide)
NotchPanel {
    id: win
    ns: "bluetooth"
    panelW: 420
    panelH: 480

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter ? adapter.enabled : false
    readonly property bool scanning: adapter ? adapter.discovering : false
    property string busy: ""        // address being connected / paired

    readonly property var devices: adapter ? adapter.devices.values : []
    // paired = BlueZ "Paired" (or "Bonded", depending on the Quickshell version)
    function isPaired(d) { return d.paired === true || d.bonded === true; }
    property var pending: null      // unpaired device we just asked to pair; connected once it pairs
    property int pendingTicks: 0
    readonly property var mine: {
        const arr = devices.filter(d => isPaired(d));
        arr.sort((a, b) => (b.connected - a.connected) || String(a.name).localeCompare(String(b.name)));
        return arr;
    }
    readonly property var nearby: devices.filter(d => !isPaired(d) && d.name && d.name.length > 0)
    readonly property var entries: {
        const out = [];
        if (mine.length > 0) out.push({ header: "MY DEVICES" });
        for (const d of mine) out.push({ dev: d });
        out.push({ header: scanning ? "NEARBY DEVICES  \u00b7  scanning..." : "NEARBY DEVICES" });
        for (const d of nearby) out.push({ dev: d });
        return out;
    }

    function show() { open = true; }
    function hide() { open = false; }
    function setOn(v) {
        if (!adapter) return;
        adapter.enabled = v;
        if (v && open) Qt.callLater(() => { if (win.adapter) win.adapter.discovering = true; });
    }
    function click(d) {
        busy = d.address;
        busyClear.restart();
        if (isPaired(d)) {
            if (d.connected) d.disconnect(); else d.connect();
        } else {
            pending = d;
            pendingTicks = 0;
            pairWatch.restart();
            d.pair();    // pairWatch connects it as soon as it shows up as paired
        }
    }

    onOpenChanged: {
        if (!adapter) return;
        if (open) { busy = ""; if (adapter.enabled) adapter.discovering = true; Qt.callLater(() => keys.forceActiveFocus()); }
        else adapter.discovering = false;
    }

    Timer { id: busyClear; interval: 9000; onTriggered: win.busy = "" }
    Timer {
        id: pairWatch
        interval: 800
        repeat: true
        onTriggered: {
            win.pendingTicks++;
            if (win.pending && win.isPaired(win.pending)) {
                const d = win.pending;
                win.pending = null;
                stop();
                d.connect();
            } else if (win.pendingTicks > 20 || !win.pending) {
                win.pending = null;
                stop();
            }
        }
    }

    IpcHandler {
        target: "bluetooth"
        function toggle(): void { win.open ? win.hide() : win.show() }
        function show(): void   { win.show() }
        function hide(): void   { win.hide() }
    }

    Item {   // Esc closes
        id: keys
        anchors.fill: parent
        Keys.onEscapePressed: win.hide()
    }

    // ---- Header ----
    Item {
        id: header
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: 72
        Text {
            x: 28
            anchors.verticalCenter: parent.verticalCenter
            text: "Bluetooth"
            color: Theme.foreground
            font.pixelSize: 21
            font.weight: Font.DemiBold
        }
        ToggleSwitch {
            anchors.right: parent.right
            anchors.rightMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            enabledSwitch: win.adapter !== null
            checked: win.on
            onToggled: win.setOn(!win.on)
        }
    }
    Rectangle {
        id: divider
        anchors.top: header.bottom
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 24; anchors.rightMargin: 24
        height: 1
        color: Theme.border
    }

    // ---- Device list ----
    ListView {
        id: list
        anchors.top: divider.bottom
        anchors.topMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 20; anchors.rightMargin: 20
        visible: win.on
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel { values: win.entries }

        delegate: Item {
            id: row
            required property var modelData
            readonly property bool isHeader: modelData.header !== undefined
            readonly property var dev: modelData.dev
            width: ListView.view.width
            height: isHeader ? 34 : 56

            // section header
            Text {
                visible: row.isHeader
                x: 8
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                text: row.isHeader ? row.modelData.header : ""
                color: Qt.alpha(Theme.foreground, 0.45)
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
            }

            // device row
            Item {
                visible: !row.isHeader
                anchors.fill: parent

                Rectangle {
                    anchors.fill: parent
                    radius: 18
                    color: dma.containsMouse ? Theme.surface : "transparent"
                }
                Rectangle {   // round icon, filled when connected
                    id: dot
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38; height: 38; radius: 19
                    color: row.dev && row.dev.connected ? Theme.accent : Theme.surfaceAlt
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Canvas {
                        anchors.centerIn: parent
                        width: 18; height: 18
                        antialiasing: true
                        property color col: row.dev && row.dev.connected ? Theme.onAccent : Theme.foreground
                        onColChanged: requestPaint()
                        onPaint: {
                            const c = getContext("2d");
                            c.reset();
                            c.strokeStyle = col;
                            c.lineWidth = 1.7; c.lineCap = "round"; c.lineJoin = "round";
                            c.beginPath();
                            c.moveTo(4.5, 5.5); c.lineTo(13, 12.5); c.lineTo(9, 16.5);
                            c.lineTo(9, 1.5); c.lineTo(13, 5.5); c.lineTo(4.5, 12.5);
                            c.stroke();
                        }
                    }
                }
                Column {
                    anchors.left: dot.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 70
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: parent.width
                        text: row.dev ? row.dev.name : ""
                        color: Theme.foreground
                        font.pixelSize: 14
                        font.weight: row.dev && row.dev.connected ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: {
                            if (!row.dev) return "";
                            if (win.busy === row.dev.address && !row.dev.connected) return win.isPaired(row.dev) ? "Connecting..." : "Pairing...";
                            if (row.dev.connected) return "Connected" + (row.dev.batteryAvailable ? "  \u00b7  " + Math.round(row.dev.battery * 100) + "%" : "");
                            return win.isPaired(row.dev) ? "Not connected" : "Click to pair";
                        }
                        color: row.dev && row.dev.connected ? Theme.accent : Qt.alpha(Theme.foreground, 0.5)
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                Text {   // forget a paired, disconnected device
                    visible: !!row.dev && win.isPaired(row.dev) && !row.dev.connected && dma.containsMouse
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Forget"
                    color: Qt.alpha(Theme.foreground, 0.5)
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.dev.forget()
                    }
                }
                MouseArea {
                    id: dma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.click(row.dev)
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 20
        visible: !win.on
        text: win.adapter ? "Bluetooth is off" : "No Bluetooth adapter found"
        color: Theme.foregroundMuted
        font.pixelSize: 15
    }
}
