import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// App launcher. Control with:
//   qs -c dynamic-island ipc call launcher toggle   (also: show / hide)
// Keys: type to filter | Up/Down, Ctrl+J/K, Ctrl+N/P, Tab/Shift+Tab move | Enter launch | Esc close
NotchPanel {
    id: win
    ns: "launcher"
    panelW: 640
    panelH: 450

    property string query: ""
    property int index: 0
    // Used for Terminal=true entries
    property var terminal: ["alacritty", "-e"]

    // Palette (pure-black panel, teal selection bar)
    readonly property color cBg: Theme.notch
    readonly property color cRow: Theme.surface
    readonly property color cRowHover: Theme.hover
    readonly property color cTile: Theme.surfaceAlt
    readonly property color cText: Theme.foreground
    readonly property color cDim: Theme.foregroundMuted
    readonly property color cAccent: Theme.accent

    readonly property var results: {
        const q = query.trim().toLowerCase();
        const all = DesktopEntries.applications.values.filter(e => !e.noDisplay);
        if (q === "")
            return all.slice().sort((a, b) => a.name.localeCompare(b.name));
        const scored = [];
        for (const e of all) {
            const n = e.name.toLowerCase();
            let s = -1;
            if (n.startsWith(q)) s = 0;
            else if (n.split(/[\s\-_.]+/).some(w => w.startsWith(q))) s = 1;
            else if (n.includes(q)) s = 2;
            else if ((e.genericName || "").toLowerCase().includes(q)
                  || (e.comment || "").toLowerCase().includes(q)
                  || Array.from(e.keywords || []).join(" ").toLowerCase().includes(q)) s = 3;
            if (s >= 0) scored.push({ e: e, s: s });
        }
        scored.sort((a, b) => a.s - b.s || a.e.name.localeCompare(b.e.name));
        return scored.map(x => x.e);
    }

    function show() { open = true; }
    function hide() { open = false; }
    function move(d) {
        if (results.length === 0) return;
        index = Math.max(0, Math.min(results.length - 1, index + d));
        list.positionViewAtIndex(index, ListView.Contain);
    }
    function launch(e) {
        if (!e) return;
        hide();
        if (e.runInTerminal) Quickshell.execDetached(terminal.concat([...e.command]));
        else e.execute();
    }

    onOpenChanged: if (open) {
        field.text = "";
        query = "";
        index = 0;
        Qt.callLater(() => field.forceActiveFocus());
    }
    onResultsChanged: index = 0

    IpcHandler {
        target: "launcher"
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
            height: 70

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
                    c.strokeStyle = win.cDim;
                    c.lineWidth = 1.8;
                    c.lineCap = "round";
                    c.beginPath(); c.arc(9.5, 9.5, 6.5, 0, 2 * Math.PI); c.stroke();
                    c.beginPath(); c.moveTo(14.5, 14.5); c.lineTo(19.5, 19.5); c.stroke();
                }
            }

            TextInput {
                id: field
                anchors.left: glass.right
                anchors.leftMargin: 18
                anchors.right: parent.right
                anchors.rightMargin: 26
                anchors.verticalCenter: parent.verticalCenter
                color: win.cText
                selectionColor: win.cAccent
                selectedTextColor: Theme.background
                font.pixelSize: 20
                clip: true
                onTextChanged: win.query = text

                Text {
                    visible: field.text.length === 0
                    text: "Search..."
                    color: Qt.alpha(Theme.foreground, 0.4)
                    font.pixelSize: 20
                    anchors.verticalCenter: parent.verticalCenter
                }

                Keys.onPressed: (e) => {
                    const ctrl = e.modifiers & Qt.ControlModifier;
                    let ok = true;
                    if (e.key === Qt.Key_Escape) win.hide();
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.launch(win.results[win.index]);
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

        // ---- Results ----
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
                readonly property string iconSrc: {
                    const ic = modelData.icon || "";
                    if (ic.startsWith("/")) return "file://" + ic;
                    return Quickshell.iconPath(ic, true)
                        || Quickshell.iconPath("application-x-executable", true);
                }
                width: ListView.view.width
                height: 58

                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: row.sel ? win.cRow : (rma.containsMouse ? win.cRowHover : "transparent")
                }
                Rectangle {   // teal selection bar
                    visible: row.sel
                    x: 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3; height: 26; radius: 2
                    color: win.cAccent
                }
                Rectangle {   // icon tile
                    id: tile
                    x: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 44; radius: 12
                    color: win.cTile
                    Image {
                        anchors.centerIn: parent
                        width: 28; height: 28
                        source: row.iconSrc
                        sourceSize: Qt.size(56, 56)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                    }
                }
                ColumnLayout {
                    anchors.left: tile.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        color: win.cText
                        font.pixelSize: 16
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: row.modelData.comment || row.modelData.genericName || ""
                        color: win.cDim
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }
                MouseArea {
                    id: rma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: win.index = row.index
                    onClicked: win.launch(row.modelData)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: win.results.length === 0
                text: "No results"
                color: win.cDim
                font.pixelSize: 14
            }
        }
}
