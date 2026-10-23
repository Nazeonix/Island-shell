import QtQuick
import Quickshell
import Quickshell.Io

// Theme chooser that grows out of the notch: search + a centered carousel of palette cards.
//   qs -c dynamic-island ipc call theme toggle   (also: show / hide / select <key> / next / prev)
// Keys: type to filter | Left/Right (Tab, Ctrl+N/P) move | Enter apply | Esc close
NotchPanel {
    id: win
    ns: "theme"
    panelW: 820
    panelH: 232

    property string query: ""
    property int index: 0

    readonly property var results: {
        const q = query.trim().toLowerCase();
        return Theme.options.filter(o => q === "" || o.label.toLowerCase().includes(q) || o.key.toLowerCase().includes(q));
    }

    function show() { open = true; }
    function hide() { open = false; }
    function move(d) {
        if (results.length === 0) return;
        index = Math.max(0, Math.min(results.length - 1, index + d));
    }
    function apply(i) {
        const o = results[i];
        if (o) Theme.select(o.key);
    }

    onOpenChanged: if (open) {
        field.text = "";
        query = "";
        index = Math.max(0, Theme.options.findIndex(o => o.key === Theme.current));
        Qt.callLater(() => field.forceActiveFocus());
    }
    onResultsChanged: index = Math.min(index, Math.max(0, results.length - 1))

    IpcHandler {
        target: "theme"
        function toggle(): void { win.open ? win.hide() : win.show() }
        function show(): void   { win.show() }
        function hide(): void   { win.hide() }
        function select(key: string): void { Theme.select(key) }
        function next(): void   { Theme.cycle(1) }
        function prev(): void   { Theme.cycle(-1) }
        function apply(): void  { Theme.exportTheme() }   // re-push the current theme to GTK / browsers
    }

    // ---- Search row ----
    Item {
        id: searchRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 60

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
            anchors.right: count.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.foreground
            selectionColor: Theme.accent
            selectedTextColor: Theme.background
            font.pixelSize: 17
            clip: true
            onTextChanged: win.query = text

            Text {
                visible: field.text.length === 0
                text: "Search themes..."
                color: Qt.alpha(Theme.foreground, 0.4)
                font.pixelSize: 17
                anchors.verticalCenter: parent.verticalCenter
            }

            Keys.onPressed: (e) => {
                const ctrl = e.modifiers & Qt.ControlModifier;
                let ok = true;
                if (e.key === Qt.Key_Escape) win.hide();
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.apply(win.index);
                else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down || e.key === Qt.Key_Tab
                         || (ctrl && (e.key === Qt.Key_N || e.key === Qt.Key_J))) win.move(1);
                else if (e.key === Qt.Key_Left || e.key === Qt.Key_Up || e.key === Qt.Key_Backtab
                         || (ctrl && (e.key === Qt.Key_P || e.key === Qt.Key_K))) win.move(-1);
                else ok = false;
                e.accepted = ok;
            }
        }

        Text {
            id: count
            anchors.right: parent.right
            anchors.rightMargin: 26
            anchors.verticalCenter: parent.verticalCenter
            text: win.results.length > 0 ? (win.index + 1) + "/" + win.results.length : "0/0"
            color: Qt.alpha(Theme.foreground, 0.5)
            font.pixelSize: 12
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

    // ---- Card carousel (focused card stays centered) ----
    ListView {
        id: carousel
        anchors.top: divider.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        height: 108
        orientation: ListView.Horizontal
        spacing: 12
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: win.index
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width - 190) / 2
        preferredHighlightEnd: (width + 190) / 2
        highlightMoveDuration: 280
        interactive: false
        model: ScriptModel { values: win.results }

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool foc: index === win.index
            readonly property bool cur: modelData.key === Theme.current
            width: 190
            height: ListView.view.height

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: cell.foc ? 190 : 174
                height: cell.foc ? 100 : 88
                radius: 18
                color: cell.modelData.background
                border.width: cell.foc ? 1.5 : 1
                border.color: cell.foc ? Theme.foreground : Qt.alpha(Theme.foreground, 0.12)
                Behavior on width  { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Row {   // the palette's own colors
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.34 - height / 2
                    spacing: 9
                    Repeater {
                        model: [cell.modelData.red, cell.modelData.green, cell.modelData.yellow,
                                cell.modelData.blue, cell.modelData.purple, cell.modelData.cyan]
                        Rectangle {
                            required property color modelData
                            width: 13; height: 13; radius: 6.5
                            color: modelData
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    width: parent.width - 24
                    horizontalAlignment: Text.AlignHCenter
                    text: cell.modelData.label.toLowerCase()
                    color: cell.foc ? cell.modelData.foreground : cell.modelData.foregroundMuted
                    font.pixelSize: 12
                    font.weight: cell.foc ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                }
                Rectangle {   // marks the active theme
                    visible: cell.cur
                    x: parent.width - 18; y: 10
                    width: 6; height: 6; radius: 3
                    color: Theme.accent
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { win.index = cell.index; win.apply(cell.index); }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: win.results.length === 0
            text: "No themes"
            color: Theme.foregroundMuted
            font.pixelSize: 14
        }
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 26
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        text: "Enter to apply"
        color: Qt.alpha(Theme.foreground, 0.45)
        font.pixelSize: 11
    }
}
