import QtQuick
import Quickshell
import Quickshell.Io

// Wi-Fi menu that drops out of the notch, macOS style: switch on top, list of networks below.
// Click a saved/open network to join, the connected one to disconnect; a new secured network
// asks for its password inline. Uses NetworkManager (nmcli).
//   qs -c dynamic-island ipc call wifi toggle   (also: show / hide)
NotchPanel {
    id: win
    ns: "wifi"
    panelW: 420
    panelH: 470

    property bool enabled: true
    property var raw: []            // [{ ssid, signal, security, inUse }]
    property var saved: []          // names of saved Wi-Fi connections
    property string pwFor: ""       // ssid whose password field is open
    property string busy: ""        // ssid being connected
    property string message: ""

    readonly property var networks: {
        const arr = raw.map(n => ({ ssid: n.ssid, signal: n.signal, security: n.security, inUse: n.inUse,
                                    saved: saved.indexOf(n.ssid) >= 0 }));
        arr.sort((a, b) => (b.inUse - a.inUse) || (b.saved - a.saved) || (b.signal - a.signal));
        return arr;
    }

    function show() { open = true; }
    function hide() { open = false; }
    function refresh() {
        statusProc.running = true;
        savedProc.running = true;
        listProc.running = true;
    }
    function setEnabled(on) {
        enabled = on;
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
        refreshLater.restart();
    }
    function connectTo(n, pw) {
        busy = n.ssid;
        message = "Connecting to " + n.ssid + "...";
        pwFor = "";
        if (pw) connProc.command = ["nmcli", "device", "wifi", "connect", n.ssid, "password", pw];
        else if (n.saved) connProc.command = ["nmcli", "connection", "up", "id", n.ssid];
        else connProc.command = ["nmcli", "device", "wifi", "connect", n.ssid];
        connProc.running = true;
    }
    function disconnectFrom(n) {
        Quickshell.execDetached(["nmcli", "connection", "down", "id", n.ssid]);
        refreshLater.restart();
    }
    function forget(n) {
        Quickshell.execDetached(["nmcli", "connection", "delete", "id", n.ssid]);
        refreshLater.restart();
    }
    function clickNetwork(n) {
        if (n.inUse) disconnectFrom(n);
        else if (!n.saved && n.security !== "") {
            pwFor = pwFor === n.ssid ? "" : n.ssid;
        } else connectTo(n, "");
    }

    // split an nmcli -t line on unescaped colons
    function fields(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (ch === "\\" && i + 1 < line.length) { cur += line[i + 1]; i++; }
            else if (ch === ":") { out.push(cur); cur = ""; }
            else cur += ch;
        }
        out.push(cur);
        return out;
    }

    onOpenChanged: if (open) {
        pwFor = "";
        message = "";
        refresh();
        poll.start();
        Qt.callLater(() => keys.forceActiveFocus());
    } else poll.stop()

    Timer { id: poll; interval: 6000; repeat: true; onTriggered: win.refresh() }
    Timer { id: refreshLater; interval: 1500; onTriggered: win.refresh() }

    IpcHandler {
        target: "wifi"
        function toggle(): void { win.open ? win.hide() : win.show() }
        function show(): void   { win.show() }
        function hide(): void   { win.hide() }
    }

    Process {
        id: statusProc
        command: ["nmcli", "-t", "-f", "WIFI", "radio"]
        stdout: StdioCollector { onStreamFinished: win.enabled = text.trim() === "enabled" }
    }
    Process {
        id: savedProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = [];
                for (const line of text.split("\n")) {
                    const f = win.fields(line);
                    if (f.length >= 2 && f[1] === "802-11-wireless") names.push(f[0]);
                }
                win.saved = names;
            }
        }
    }
    Process {
        id: listProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "auto"]
        stdout: StdioCollector {
            onStreamFinished: {
                const best = {};
                for (const line of text.split("\n")) {
                    const f = win.fields(line);
                    if (f.length < 4 || f[1] === "") continue;
                    const n = { ssid: f[1], signal: parseInt(f[2]) || 0, security: f[3], inUse: f[0] === "*" };
                    const prev = best[n.ssid];
                    if (!prev || n.inUse || (!prev.inUse && n.signal > prev.signal)) best[n.ssid] = n;
                }
                win.raw = Object.values(best);
            }
        }
    }
    Process {
        id: connProc
        stderr: StdioCollector { id: connErr }
        onExited: (code) => {
            win.busy = "";
            if (code === 0) win.message = "";
            else {
                const t = connErr.text.trim();
                win.message = t.indexOf("Secrets were required") >= 0 || t.indexOf("password") >= 0 ? "Wrong password" : "Could not connect";
            }
            win.refresh();
        }
    }

    Item {   // Esc closes (the password field handles its own Esc)
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
            text: "Wi-Fi"
            color: Theme.foreground
            font.pixelSize: 21
            font.weight: Font.DemiBold
        }
        ToggleSwitch {
            anchors.right: parent.right
            anchors.rightMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            checked: win.enabled
            onToggled: win.setEnabled(!win.enabled)
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

    Text {
        id: sectionLabel
        anchors.top: divider.bottom
        anchors.topMargin: 14
        x: 28
        visible: win.enabled
        text: "NETWORKS"
        color: Qt.alpha(Theme.foreground, 0.45)
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
    }

    // ---- Network list ----
    ListView {
        id: list
        anchors.top: sectionLabel.bottom
        anchors.topMargin: 8
        anchors.bottom: footer.top
        anchors.bottomMargin: 6
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 20; anchors.rightMargin: 20
        visible: win.enabled
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel { values: win.networks }

        delegate: Item {
            id: row
            required property var modelData
            readonly property bool askPw: win.pwFor === modelData.ssid
            readonly property bool isBusy: win.busy === modelData.ssid
            width: ListView.view.width
            height: askPw ? 110 : 52
            onAskPwChanged: if (askPw) Qt.callLater(() => pwField.forceActiveFocus())
            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent
                radius: 18
                color: rma.containsMouse || askPw ? Theme.surface : "transparent"
            }

            // signal bars
            Canvas {
                id: bars
                x: 14; y: 14
                width: 22; height: 22
                antialiasing: true
                property int level: row.modelData.signal > 75 ? 4 : row.modelData.signal > 50 ? 3 : row.modelData.signal > 25 ? 2 : 1
                property color col: row.modelData.inUse ? Theme.accent : Theme.foreground
                onLevelChanged: requestPaint()
                onColChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d");
                    c.reset();
                    for (let i = 0; i < 4; i++) {
                        const h = 5 + i * 4.2;
                        c.fillStyle = i < level ? col : Qt.alpha(col, 0.25);
                        c.beginPath();
                        c.roundedRect(i * 5.5, 22 - h, 3.4, h, 1.2, 1.2);
                        c.fill();
                    }
                }
            }

            Column {
                x: 50
                y: 8
                width: parent.width - 50 - 90
                spacing: 1
                Text {
                    width: parent.width
                    text: row.modelData.ssid
                    color: row.modelData.inUse ? Theme.accent : Theme.foreground
                    font.pixelSize: 14
                    font.weight: row.modelData.inUse ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: row.isBusy ? "Connecting..." : row.modelData.inUse ? "Connected"
                          : row.modelData.saved ? "Saved" : (row.modelData.security !== "" ? row.modelData.security : "Open")
                    color: Qt.alpha(Theme.foreground, 0.5)
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            // forget (saved networks, on hover) + lock / check
            Text {
                visible: row.modelData.saved && !row.modelData.inUse && rma.containsMouse
                anchors.right: parent.right
                anchors.rightMargin: 44
                y: 17
                text: "Forget"
                color: Qt.alpha(Theme.foreground, 0.5)
                font.pixelSize: 11
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.forget(row.modelData)
                }
            }
            Canvas {   // lock for secured networks, check for the connected one
                x: row.width - 34; y: 17
                width: 18; height: 18
                antialiasing: true
                property bool inUse: row.modelData.inUse
                property bool secured: row.modelData.security !== ""
                property color col: inUse ? Theme.accent : Qt.alpha(Theme.foreground, 0.5)
                onInUseChanged: requestPaint()
                onSecuredChanged: requestPaint()
                onColChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d");
                    c.reset();
                    c.strokeStyle = col; c.fillStyle = col;
                    c.lineWidth = 1.8; c.lineCap = "round"; c.lineJoin = "round";
                    if (inUse) {
                        c.beginPath(); c.moveTo(3, 9.5); c.lineTo(7.5, 14); c.lineTo(15, 4.5); c.stroke();
                    } else if (secured) {
                        c.fillRect(4, 8, 10, 8);
                        c.beginPath(); c.arc(9, 8, 3.4, Math.PI, 0); c.stroke();
                    }
                }
            }

            MouseArea {
                id: rma
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                height: 52
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: win.clickNetwork(row.modelData)
            }

            // password prompt
            Item {
                visible: row.askPw
                x: 14; y: 54
                width: parent.width - 28
                height: 44
                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: Theme.surfaceAlt
                }
                TextInput {
                    id: pwField
                    anchors.left: parent.left; anchors.leftMargin: 14
                    anchors.right: joinBtn.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.foreground
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.onAccent
                    echoMode: TextInput.Password
                    font.pixelSize: 14
                    clip: true
                    onAccepted: win.connectTo(row.modelData, text)
                    Keys.onEscapePressed: win.pwFor = ""
                    Text {
                        visible: pwField.text.length === 0
                        text: "Password"
                        color: Qt.alpha(Theme.foreground, 0.4)
                        font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Rectangle {
                    id: joinBtn
                    anchors.right: parent.right; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 58; height: 32; radius: 16
                    color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "Join"
                        color: Theme.onAccent
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.connectTo(row.modelData, pwField.text)
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: win.networks.length === 0
            text: "Searching for networks..."
            color: Theme.foregroundMuted
            font.pixelSize: 13
        }
    }

    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 20
        visible: !win.enabled
        text: "Wi-Fi is off"
        color: Theme.foregroundMuted
        font.pixelSize: 15
    }

    // ---- Footer: status message ----
    Item {
        id: footer
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: 28; anchors.rightMargin: 28
        height: 34
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            text: win.message
            color: win.message === "Wrong password" || win.message === "Could not connect" ? Theme.error : Qt.alpha(Theme.foreground, 0.55)
            font.pixelSize: 12
            elide: Text.ElideRight
        }
    }
}
