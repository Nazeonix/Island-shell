import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Click the wifi icon: enable / disable, nearby networks. Needs NetworkManager (`nmcli`).
PanelWindow {
    id: win

    property Item anchorItem: null
    property bool open: false
    property real cardX: 0

    property bool wifiEnabled: true
    property bool pendingRadio: false
    property bool requery: false
    property var networks: []
    property string askSsid: ""
    property string password: ""
    property string pendingSsid: ""
    property string message: ""
    property bool messageBad: false
    property bool busy: false
    property string connectErrText: ""
    property string connectOut: ""

    readonly property bool scanning: scanProc.running
    readonly property var currentNet: {
        for (let i = 0; i < networks.length; i++) if (networks[i].used) return networks[i];
        return null;
    }
    readonly property var otherNets: {
        const out = [];
        for (let i = 0; i < networks.length; i++) if (!networks[i].used) out.push(networks[i]);
        return out;
    }

    signal updated()

    function nm(args) { return ["env", "LC_ALL=C.UTF-8", "LANG=C.UTF-8", "nmcli"].concat(args); }
    function splitNm(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line.charAt(i);
            if (c === "\\" && i + 1 < line.length) { cur += line.charAt(i + 1); i++; continue; }
            if (c === ":") { out.push(cur); cur = ""; continue; }
            cur += c;
        }
        out.push(cur);
        return out;
    }

    function place() {
        if (!anchorItem) return;
        const host = anchorItem.Window.window;
        if (!host || !host.contentItem) return;
        const p = anchorItem.mapToItem(host.contentItem, 0, 0);
        const right = p.x + Math.max(1, anchorItem.width);
        const bound = host.width > 0 ? host.width : width;
        cardX = Math.max(8, Math.min(right - card.width, Math.max(8, bound - card.width - 8)));
    }
    function toggle() {
        if (!open) place();
        open = !open;
    }
    function queryRadio() {
        if (radioQuery.running) requery = true;
        else radioQuery.running = true;
    }
    function setRadio(on) {
        if (radioSet.running) return;
        pendingRadio = true;
        wifiEnabled = on;
        if (!on) { networks = []; askSsid = ""; password = ""; message = ""; }
        radioSet.command = nm(["radio", "wifi", on ? "on" : "off"]);
        radioSet.running = true;
    }
    function scan(force) {
        if (!wifiEnabled || scanProc.running || !open) return;
        scanProc.command = nm(["-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "device", "wifi", "list", "--rescan", force ? "yes" : "auto"]);
        scanProc.running = true;
    }
    function parseNetworks(raw) {
        const map = ({});
        const lines = raw.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line === "") continue;
            const parts = splitNm(line);
            if (parts.length < 4) continue;
            const used = parts[0] === "*";
            const signal = parseInt(parts[1], 10) || 0;
            const security = parts[2];
            const ssid = parts.slice(3).join(":");
            if (ssid === "" || ssid === "--") continue;
            const secure = security !== "" && security !== "--";
            const prev = map[ssid];
            if (!prev) map[ssid] = { ssid: ssid, signal: signal, secure: secure, used: used };
            else {
                prev.used = prev.used || used;
                if (signal > prev.signal) { prev.signal = signal; prev.secure = secure; }
            }
        }
        const out = [];
        for (const k in map) out.push(map[k]);
        out.sort((a, b) => (b.used ? 1 : 0) - (a.used ? 1 : 0) || b.signal - a.signal);
        return out;
    }
    function needsSecret(err) {
        const t = (err || "").toLowerCase();
        return t.indexOf("secret") >= 0 || t.indexOf("password") >= 0 || t.indexOf("psk") >= 0
            || t.indexOf("key-mgmt") >= 0 || t.indexOf("802-11-wireless-security") >= 0;
    }
    function connectTo(ssid, psk) {
        if (connectProc.running || downProc.running || !ssid) return;
        busy = true;
        pendingSsid = ssid;
        message = "Connecting…";
        messageBad = false;
        connectErrText = "";
        connectOut = "";
        const args = ["device", "wifi", "connect", ssid];
        if (psk) args.push("password", psk);
        connectProc.command = nm(args);
        connectProc.running = true;
        connectWatch.restart();
    }
    function submitPassword() {
        if (askSsid === "" || password === "") return;
        connectTo(askSsid, password);
    }
    function disconnectFrom(ssid) {
        if (connectProc.running || downProc.running || !ssid) return;
        busy = true;
        pendingSsid = ssid;
        message = "Disconnecting…";
        messageBad = false;
        downProc.command = nm(["connection", "down", "id", ssid]);
        downProc.running = true;
    }
    function finishConnect(code) {
        connectWatch.stop();
        busy = false;
        const err = (connectErrText || "") + "\n" + (connectOut || "");
        if (code === 0) {
            askSsid = "";
            password = "";
            message = "";
            scan(true);
            updated();
            return;
        }
        if (needsSecret(err)) {
            const hadPw = password !== "";
            askSsid = pendingSsid;
            password = "";
            message = hadPw ? "Wrong password" : "Password required";
            messageBad = hadPw;
            Qt.callLater(() => pw.forceActiveFocus());
        } else {
            message = "Couldn't connect";
            messageBad = true;
        }
    }

    onOpenChanged: {
        if (open) {
            place();
            queryRadio();
            Qt.callLater(() => { place(); keys.forceActiveFocus(); });
        } else if (!busy) {
            askSsid = "";
            password = "";
            message = "";
        }
    }

    Timer {
        interval: 8000; repeat: true; running: win.open && win.wifiEnabled
        onTriggered: win.scan(false)
    }
    Timer { id: scanKick; interval: 700; onTriggered: if (win.open && win.wifiEnabled) win.scan(true) }
    Timer {
        id: connectWatch
        interval: 20000
        onTriggered: {
            if (connectProc.running) connectProc.running = false;
            win.busy = false;
            win.message = "Timed out";
            win.messageBad = true;
        }
    }

    Process {
        id: radioQuery
        command: ["env", "LC_ALL=C.UTF-8", "LANG=C.UTF-8", "nmcli", "-t", "-f", "WIFI", "radio"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (win.pendingRadio) return;
                const t = text.trim().toLowerCase();
                if (t !== "enabled" && t !== "disabled") return;
                win.wifiEnabled = t === "enabled";
                if (!win.wifiEnabled) win.networks = [];
                else if (win.open) win.scan(win.networks.length === 0);
            }
        }
        onExited: if (win.requery) { win.requery = false; running = true; }
    }
    Process {
        id: radioSet
        onExited: {
            win.pendingRadio = false;
            win.queryRadio();
            win.updated();
            if (win.wifiEnabled) scanKick.start();
        }
    }
    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: if (win.wifiEnabled) win.networks = win.parseNetworks(text);
        }
    }
    Process {
        id: connectProc
        stdout: StdioCollector { onStreamFinished: win.connectOut = text }
        stderr: StdioCollector { onStreamFinished: win.connectErrText = text }
        onExited: code => Qt.callLater(() => win.finishConnect(code))
    }
    Process {
        id: downProc
        onExited: code => {
            win.busy = false;
            if (code === 0) { win.message = ""; win.scan(true); win.updated(); }
            else { win.message = "Couldn't disconnect"; win.messageBad = true; }
        }
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || card.opacity > 0.01
    focusable: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-wifi"

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

    component NetRow: Rectangle {
        id: nr
        property string ssid
        property int strength: 0
        property bool secure: false
        property bool active: false
        property string idleTail: ""
        property string hoverTail: ""
        signal picked()

        implicitHeight: 34
        height: 34
        radius: 8
        color: active ? Theme.accent : (ma.containsMouse ? Theme.foreground : "transparent")
        readonly property color ink: (active || ma.containsMouse) ? Theme.background : Theme.foreground
        readonly property string tail: (ma.containsMouse && hoverTail !== "") ? hoverTail : idleTail

        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: nr.ssid
                elide: Text.ElideRight
                color: nr.ink
                font { family: Theme.fontFamily; pixelSize: 13 }
            }
            Text {
                visible: nr.secure
                text: "\uf023"
                color: nr.ink
                font { family: Theme.iconFont; pixelSize: 11 }
            }
            Text {
                text: nr.tail !== "" ? nr.tail : String(nr.strength)
                color: nr.ink
                font {
                    family: Theme.fontFamily; pixelSize: 12; bold: nr.tail !== ""
                    capitalization: nr.tail !== "" ? Font.AllUppercase : Font.MixedCase
                }
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
                    text: "\uf1eb"
                    color: win.wifiEnabled ? Theme.accent : Theme.muted
                    font { family: Theme.iconFont; pixelSize: 16 }
                }
                Text {
                    Layout.fillWidth: true
                    text: "Wi-Fi"
                    color: Theme.foreground
                    font { family: Theme.fontFamily; pixelSize: 14; bold: true; capitalization: Font.AllUppercase }
                }
                Act {
                    label: win.wifiEnabled ? "Disable" : "Enable"
                    on: win.wifiEnabled
                    onClicked: win.setRadio(!win.wifiEnabled)
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
                visible: !win.wifiEnabled
                text: "Wi-Fi is off"
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 13 }
            }

            NetRow {
                Layout.fillWidth: true
                visible: win.wifiEnabled && win.currentNet !== null
                ssid: win.currentNet ? win.currentNet.ssid : ""
                strength: win.currentNet ? win.currentNet.signal : 0
                secure: !!(win.currentNet && win.currentNet.secure)
                active: true
                idleTail: "Connected"
                hoverTail: "Disconnect"
                onPicked: if (win.currentNet) win.disconnectFrom(win.currentNet.ssid)
            }

            Text {
                visible: win.wifiEnabled
                text: "Other networks"
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 11; bold: true; capitalization: Font.AllUppercase; letterSpacing: 0.4 }
            }

            Text {
                visible: win.wifiEnabled && win.scanning && win.otherNets.length > 0
                text: "Scanning…"
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 11 }
            }

            Text {
                visible: win.wifiEnabled && win.otherNets.length === 0
                text: win.scanning ? "Scanning…" : (win.currentNet ? "No other networks" : "No networks in range")
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 12 }
            }

            Flickable {
                id: flick
                visible: win.wifiEnabled && win.otherNets.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(netCol.implicitHeight, 260)
                contentHeight: netCol.implicitHeight
                contentWidth: width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                interactive: contentHeight > height

                Column {
                    id: netCol
                    width: flick.width
                    spacing: 2
                    Repeater {
                        model: win.otherNets
                        delegate: NetRow {
                            width: netCol.width
                            ssid: modelData.ssid
                            strength: modelData.signal
                            secure: !!modelData.secure
                            active: win.askSsid === modelData.ssid
                            onPicked: win.connectTo(modelData.ssid)
                        }
                    }
                }
            }

            ColumnLayout {
                visible: win.askSsid !== ""
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: win.askSsid
                    elide: Text.ElideRight
                    color: Theme.muted
                    font { family: Theme.fontFamily; pixelSize: 11 }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 8
                        color: "transparent"
                        border { width: 2; color: Theme.foreground }
                        TextInput {
                            id: pw
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            verticalAlignment: Text.AlignVCenter
                            color: Theme.foreground
                            echoMode: TextInput.Password
                            clip: true
                            selectByMouse: true
                            font { family: Theme.fontFamily; pixelSize: 13 }
                            onTextChanged: win.password = text
                            onAccepted: win.submitPassword()
                            Keys.onEscapePressed: win.open = false
                        }
                    }
                    Act { label: "Join"; onClicked: win.submitPassword() }
                }
            }
        }
    }

    onPasswordChanged: if (pw.text !== password) pw.text = password

    Connections {
        target: win.anchorItem
        function onWidthChanged() { if (win.open) win.place(); }
        function onXChanged() { if (win.open) win.place(); }
    }
}
