import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

// Simple search-based application launcher.
// Toggle via: qs ipc call launcher toggle
// Or click the logo on the left of the bar.
PanelWindow {
    id: win
    property string query: ""
    property int selected: 0
    property var menuEntry: null
    property real menuX: 0
    property real menuY: 0

    readonly property bool shown: Launcher.open

    onShownChanged: {
        searchField.text = ""   // also clears query/selected via onTextChanged
        query = ""
        selected = 0
        if (shown) Qt.callLater(() => searchField.forceActiveFocus())
    }

    function close() { menuEntry = null; Launcher.hide() }

    function matches(entry, q) {
        if (!q) return true
        const n = (entry.name || "").toLowerCase()
        const g = (entry.genericName || "").toLowerCase()
        const c = (entry.comment || "").toLowerCase()
        if (n.includes(q) || g.includes(q) || c.includes(q)) return true
        const kws = entry.keywords || []
        for (let i = 0; i < kws.length; i++)
            if (String(kws[i]).toLowerCase().includes(q)) return true
        return false
    }

    readonly property var filtered: {
        const all = DesktopEntries.applications.values
        const q = query.trim().toLowerCase()
        const out = []
        for (let i = 0; i < all.length; i++) {
            const e = all[i]
            if (!e || !e.name || e.noDisplay) continue
            if (matches(e, q)) out.push(e)
        }
        out.sort((a, b) => {
            if (!q) return a.name.localeCompare(b.name)
            const an = a.name.toLowerCase(), bn = b.name.toLowerCase()
            const aStarts = an.startsWith(q), bStarts = bn.startsWith(q)
            if (aStarts && !bStarts) return -1
            if (!aStarts && bStarts) return 1
            return an.localeCompare(bn)
        })
        return out
    }

    onFilteredChanged: {
        if (selected >= filtered.length)
            selected = Math.max(0, filtered.length - 1)
    }

    function launch(entry) {
        if (!entry) return
        entry.execute()
        close()
    }

    function moveSel(delta) {
        const n = filtered.length
        if (n === 0) { selected = 0; return }
        selected = Math.max(0, Math.min(n - 1, selected + delta))
        grid.positionViewAtIndex(selected, GridView.Contain)
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: shown || card.y < win.height
    focusable: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-launcher"

    // transparent click-catcher (no screen dimming) — click outside to dismiss
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            onClicked: win.close()
        }
    }

    // centered card: search + application grid; jumps up from the bottom edge (overshoots, settles)
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.shown ? Math.round((parent.height - height) / 2) : parent.height
        width: Math.min(960, parent.width - 40)
        height: Math.min(col.implicitHeight + 44, parent.height - 80)
        radius: 8
        color: Theme.background
        border { width: 2; color: Theme.foreground }
        Behavior on y {
            NumberAnimation {
                duration: win.shown ? 480 : 220
                easing.type: win.shown ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 1.4
            }
        }

        // block clicks from reaching backdrop
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: 22 }
            spacing: 14

            // search
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 38

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchField.text.length === 0
                        text: "Search apps…"
                        color: Theme.muted
                        font { family: Theme.fontFamily; pixelSize: 22 }
                    }
                    TextInput {
                        id: searchField
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        color: Theme.foreground
                        font { family: Theme.fontFamily; pixelSize: 22 }
                        clip: true
                        focus: true
                        selectByMouse: true
                        onTextChanged: {
                            win.query = text
                            win.selected = 0
                        }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                event.accepted = true
                                if (win.menuEntry) win.menuEntry = null
                                else win.close()
                            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
                                event.accepted = true
                                win.moveSel(1)
                            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
                                event.accepted = true
                                win.moveSel(-1)
                            } else if (event.key === Qt.Key_Down) {
                                event.accepted = true
                                win.moveSel(grid.cols)
                            } else if (event.key === Qt.Key_Up) {
                                event.accepted = true
                                win.moveSel(-grid.cols)
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                event.accepted = true
                                if (win.filtered.length > 0)
                                    win.launch(win.filtered[win.selected])
                            }
                        }
                    }
                }

                Text {
                    text: win.filtered.length + (win.filtered.length === 1 ? " app" : " apps")
                    color: Theme.muted
                    font { family: Theme.fontFamily; pixelSize: 15 }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            Text {
                text: win.query.trim() === "" ? "All apps" : "Results"
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 14 }
            }

            // application grid
            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.preferredHeight: cellHeight * 4     // 4 rows visible, scroll for more
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: win.filtered

                readonly property int cols: 9               // 9 apps per row
                cellWidth: Math.floor(width / cols)   // fractional width can drop a column
                cellHeight: 92

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle { implicitWidth: 4; color: Theme.muted }
                    background: Item {}
                }

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight

                    readonly property bool sel: index === win.selected
                    readonly property string iconSrc: modelData.icon
                        ? Quickshell.iconPath(modelData.icon, true) : ""
                    readonly property string abbr: {
                        const n = (modelData.name || "?").replace(/[^A-Za-z0-9]/g, "")
                        return n.charAt(0).toUpperCase() + n.charAt(1).toLowerCase()
                    }

                    Rectangle {
                        anchors { fill: parent; margins: 4 }
                        radius: 6
                        color: cell.sel ? Theme.surface : "transparent"
                        border { width: 2; color: cell.sel ? Theme.foreground : "transparent" }
                    }

                    Column {
                        anchors { top: parent.top; topMargin: 10; horizontalCenter: parent.horizontalCenter }
                        width: parent.width - 12
                        spacing: 6

                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 31; height: 31

                            IconImage {
                                anchors.fill: parent
                                visible: cell.iconSrc !== ""
                                source: cell.iconSrc
                            }
                            // no icon: bordered letter tile
                            Rectangle {
                                anchors.fill: parent
                                visible: cell.iconSrc === ""
                                radius: 6
                                color: "transparent"
                                border { width: 2; color: Theme.border }
                                Text {
                                    anchors.centerIn: parent
                                    text: cell.abbr
                                    color: Theme.muted
                                    font { family: Theme.fontFamily; pixelSize: 12 }
                                }
                            }
                        }
                        Text {
                            width: parent.width
                            height: 34
                            text: cell.modelData.name || ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignTop
                            color: cell.sel ? Theme.foreground : Qt.alpha(Theme.foreground, 0.8)
                            font { family: Theme.fontFamily; pixelSize: 13 }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onPositionChanged: win.selected = cell.index
                        onClicked: m => {
                            if (m.button === Qt.RightButton) {
                                const acts = cell.modelData.actions
                                if (acts && acts.length > 0) {
                                    win.selected = cell.index
                                    const p = mapToItem(card, m.x, m.y)
                                    win.menuX = p.x
                                    win.menuY = p.y
                                    win.menuEntry = cell.modelData
                                }
                            } else win.launch(cell.modelData)
                        }
                    }
                }

                // empty state
                Text {
                    anchors.centerIn: parent
                    visible: win.filtered.length === 0
                    text: win.query.trim() === "" ? "No applications found" : "No matches"
                    color: Theme.muted
                    font { family: Theme.fontFamily; pixelSize: 14 }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            // tips
            Text {
                text: "type to search  ·  ↵ launch  ·  right-click for actions  ·  esc close"
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 12 }
            }
        }

        // right-click actions menu
        MouseArea {
            anchors.fill: parent
            visible: win.menuEntry !== null
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: win.menuEntry = null
        }
        Rectangle {
            visible: win.menuEntry !== null
            width: 230
            height: actionsCol.implicitHeight + 12
            x: Math.max(8, Math.min(win.menuX, card.width - width - 8))
            y: Math.max(8, Math.min(win.menuY, card.height - height - 8))
            radius: 6
            color: Theme.background
            border { width: 2; color: Theme.foreground }

            Column {
                id: actionsCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                Repeater {
                    model: win.menuEntry ? win.menuEntry.actions : []
                    delegate: Rectangle {
                        required property var modelData
                        width: actionsCol.width
                        height: 30
                        radius: 4
                        color: am.containsMouse ? Theme.surface : "transparent"
                        Text {
                            anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: modelData.name
                            elide: Text.ElideRight
                            color: Theme.foreground
                            font { family: Theme.fontFamily; pixelSize: 13 }
                        }
                        MouseArea {
                            id: am
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { modelData.execute(); win.close() }
                        }
                    }
                }
            }
        }
    }
}
