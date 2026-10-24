import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Clipboard history that grows out of the notch. Needs cliphist + wl-clipboard, and a watcher
// started with the session, e.g. in Hyprland autostart:
//   wl-paste --type text  --watch cliphist store
//   wl-paste --type image --watch cliphist store
// Control:  qs -c dynamic-island ipc call clipboard toggle   (also: show / hide)
// Keys: type to filter | Up/Down, Tab, Ctrl+N/P/J/K move | Enter copy | Delete remove entry | Esc close
NotchPanel {
    id: win
    ns: "clipboard"
    panelW: 600
    panelH: 430

    property string query: ""
    property int index: 0
    property var all: []        // [{ line, text }] newest first
    property var buf: []
    property bool loaded: false

    readonly property var results: {
        const q = query.trim().toLowerCase();
        return q === "" ? all : all.filter(e => e.text.toLowerCase().includes(q));
    }

    function show() { open = true; }
    function hide() { open = false; }
    function reload() { if (!listProc.running) listProc.running = true; }
    function move(d) {
        if (results.length === 0) return;
        index = Math.max(0, Math.min(results.length - 1, index + d));
        list.positionViewAtIndex(index, ListView.Contain);
    }
    function copy(e) {
        if (!e) return;
        hide();
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "_", e.line]);
    }
    function remove(e) {
        if (!e) return;
        delProc.command = ["sh", "-c", 'printf "%s\\n" "$1" | cliphist delete', "_", e.line];
        delProc.running = true;
    }

    onOpenChanged: if (open) {
        field.text = "";
        query = "";
        index = 0;
        loaded = false;
        reload();
        Qt.callLater(() => field.forceActiveFocus());
    }
    onResultsChanged: index = Math.min(index, Math.max(0, results.length - 1))

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/^(\d+)\t(.*)$/);
                if (m) win.buf.push({ line: line, text: m[2] });
            }
        }
        onStarted: win.buf = []
        onExited: { win.all = win.buf.slice(0, 300); win.loaded = true; }
    }
    Process {
        id: delProc
        onExited: win.reload()
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { win.open ? win.hide() : win.show() }
        function show(): void   { win.show() }
        function hide(): void   { win.hide() }
    }

    // ---- Search row ----
    Item {
        id: searchRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 64

        Canvas {
            id: glass
            Connections { target: Theme; function onCurrentChanged() { glass.requestPaint() } }
            width: 22; height: 22
            x: 26
            anchors.verticalCenter: parent.verticalCenter
            antialiasing: true
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.strokeStyle = Theme.foregroundMuted;
                c.lineWidth = 1.8;
                c.lineCap = "round";
                c.beginPath(); c.arc(9.5, 9.5, 6.5, 0, 2 * Math.PI); c.stroke();
                c.beginPath(); c.moveTo(14.5, 14.5); c.lineTo(19.5, 19.5); c.stroke();
            }
        }

        TextInput {
            id: field
            anchors.left: glass.right
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 26
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.foreground
            selectionColor: Theme.accent
            selectedTextColor: Theme.background
            font.pixelSize: 18
            clip: true
            onTextChanged: win.query = text

            Text {
                visible: field.text.length === 0
                text: "Search clipboard..."
                color: Qt.alpha(Theme.foreground, 0.4)
                font.pixelSize: 18
                anchors.verticalCenter: parent.verticalCenter
            }

            Keys.onPressed: (e) => {
                const ctrl = e.modifiers & Qt.ControlModifier;
                let ok = true;
                if (e.key === Qt.Key_Escape) win.hide();
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.copy(win.results[win.index]);
                else if (e.key === Qt.Key_Delete) win.remove(win.results[win.index]);
                else if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab
                         || (ctrl && (e.key === Qt.Key_N || e.key === Qt.Key_J))) win.move(1);
                else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab
                         || (ctrl && (e.key === Qt.Key_P || e.key === Qt.Key_K))) win.move(-1);
                else if (e.key === Qt.Key_PageDown) win.move(6);
                else if (e.key === Qt.Key_PageUp) win.move(-6);
                else ok = false;
                e.accepted = ok;
            }
        }
    }

    Rectangle {
        id: divider
        anchors.top: searchRow.bottom
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 24; anchors.rightMargin: 24
        height: 1
        color: Theme.border
    }

    // ---- Entries ----
    ListView {
        id: list
        anchors.top: divider.bottom
        anchors.topMargin: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 24; anchors.rightMargin: 24
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel { values: win.results }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool sel: index === win.index
            readonly property bool isImage: modelData.text.startsWith("[[ binary data")
            width: ListView.view.width
            height: 46

            Rectangle {
                anchors.fill: parent
                radius: 14
                color: row.sel ? Theme.surface : (rma.containsMouse ? Theme.hover : "transparent")
            }
            Rectangle {   // selection bar
                visible: row.sel
                x: 5
                anchors.verticalCenter: parent.verticalCenter
                width: 3; height: 22; radius: 2
                color: Theme.accent
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.right: tag.visible ? tag.left : parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: row.isImage ? row.modelData.text.replace(/^\[\[ binary data /, "").replace(/ \]\]$/, "") : row.modelData.text
                color: Theme.foreground
                font.pixelSize: 14
                elide: Text.ElideRight
            }
            Text {
                id: tag
                visible: row.isImage
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "Image"
                color: Theme.accent
                font.pixelSize: 11
                font.weight: Font.Medium
            }
            MouseArea {
                id: rma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: win.index = row.index
                onClicked: win.copy(row.modelData)
            }
        }

        Text {
            anchors.centerIn: parent
            visible: win.results.length === 0
            horizontalAlignment: Text.AlignHCenter
            text: !win.loaded ? "" : (win.query !== "" ? "No matches"
                  : "Clipboard history is empty\n(needs cliphist + wl-clipboard running)")
            color: Theme.foregroundMuted
            font.pixelSize: 13
        }
    }
}
