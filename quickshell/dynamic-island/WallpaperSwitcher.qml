import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland

// Wallpaper picker card: thumbnail grid. Toggle: bar image icon or `qs ipc call wallpaper picker`.
PanelWindow {
    id: win
    property int sel: 0
    readonly property bool shown: Wallpaper.pickerOpen

    function close() { Wallpaper.pickerOpen = false }
    function thumb(path) { return "file://" + path.split("/").map(encodeURIComponent).join("/") }
    function baseName(path) { return path.split("/").pop().replace(/\.[^.]+$/, "") }
    function move(d) {
        const n = Wallpaper.files.length
        if (n === 0) return
        sel = Math.max(0, Math.min(n - 1, sel + d))
        grid.positionViewAtIndex(sel, GridView.Contain)
    }
    function apply() {
        if (Wallpaper.files.length > 0) Wallpaper.set(Wallpaper.files[sel])
    }

    onShownChanged: {
        if (shown) {
            sel = Math.max(0, Wallpaper.index)
            Qt.callLater(() => { keys.forceActiveFocus(); grid.positionViewAtIndex(win.sel, GridView.Center) })
        }
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: shown || card.opacity > 0.01
    focusable: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-wallpaper-picker"

    // transparent click-catcher: click outside to dismiss (the desktop stays visible)
    MouseArea { anchors.fill: parent; onClicked: win.close() }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(860, parent.width - 80)
        height: Math.min(col.implicitHeight + 44, parent.height - 80)
        color: Theme.background
        border { width: 2; color: Theme.foreground }
        opacity: win.shown ? 1 : 0
        scale: win.shown ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }   // block clicks from reaching the backdrop

        Item {
            id: keys
            focus: true
            Keys.onPressed: event => {
                event.accepted = true
                if (event.key === Qt.Key_Escape) win.close()
                else if (event.key === Qt.Key_Right) win.move(1)
                else if (event.key === Qt.Key_Left) win.move(-1)
                else if (event.key === Qt.Key_Down) win.move(grid.cols)
                else if (event.key === Qt.Key_Up) win.move(-grid.cols)
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) win.apply()
                else if (event.key === Qt.Key_R) { Wallpaper.random(); win.sel = Math.max(0, Wallpaper.index) }
                else if (event.key === Qt.Key_S) Wallpaper.slideshow = !Wallpaper.slideshow
                else event.accepted = false
            }
        }

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: 22 }
            spacing: 14

            // header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Wallpapers"
                    color: Theme.foreground
                    font { family: Theme.fontFamily; pixelSize: 18; bold: true; capitalization: Font.AllUppercase }
                }
                Text {
                    text: Wallpaper.files.length + (Wallpaper.files.length === 1 ? " image" : " images")
                    color: Theme.muted
                    font { family: Theme.fontFamily; pixelSize: 12 }
                }
                Rectangle {
                    implicitWidth: rnd.implicitWidth + 24; implicitHeight: 30
                    color: rndMa.containsMouse ? Theme.foreground : "transparent"
                    border { width: 2; color: Theme.foreground }
                    Text {
                        id: rnd
                        anchors.centerIn: parent
                        text: "Random"
                        color: rndMa.containsMouse ? Theme.background : Theme.foreground
                        font { family: Theme.fontFamily; pixelSize: 11; bold: true; capitalization: Font.AllUppercase }
                    }
                    MouseArea {
                        id: rndMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { Wallpaper.random(); win.sel = Math.max(0, Wallpaper.index) }
                    }
                }
                Rectangle {
                    implicitWidth: ss.implicitWidth + 24; implicitHeight: 30
                    color: Wallpaper.slideshow ? Theme.accent : (ssMa.containsMouse ? Theme.foreground : "transparent")
                    border { width: 2; color: Theme.foreground }
                    Text {
                        id: ss
                        anchors.centerIn: parent
                        text: Wallpaper.slideshow ? "Slideshow on" : "Slideshow off"
                        color: (Wallpaper.slideshow || ssMa.containsMouse) ? Theme.background : Theme.foreground
                        font { family: Theme.fontFamily; pixelSize: 11; bold: true; capitalization: Font.AllUppercase }
                    }
                    MouseArea {
                        id: ssMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Wallpaper.slideshow = !Wallpaper.slideshow
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            // thumbnails
            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.preferredHeight: cellHeight * 3     // 3 rows visible, scroll for more
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: Wallpaper.files

                readonly property int cols: Math.max(1, Math.floor(width / 200))
                cellWidth: Math.floor(width / cols)
                cellHeight: (cellWidth - 28) * 0.6 + 52

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

                    readonly property bool sel: index === win.sel
                    readonly property bool isCurrent: modelData === Wallpaper.current

                    Rectangle {
                        anchors { fill: parent; margins: 4 }
                        color: cell.sel ? Theme.surface : "transparent"
                        border { width: 2; color: cell.sel ? Theme.foreground : "transparent" }
                    }

                    Column {
                        anchors { fill: parent; margins: 10 }
                        spacing: 6

                        Rectangle {
                            width: parent.width
                            height: parent.height - 24
                            color: Theme.surface
                            border { width: 2; color: cell.isCurrent ? Theme.accent : Theme.border }
                            Image {
                                anchors { fill: parent; margins: 2 }
                                source: win.thumb(cell.modelData)
                                sourceSize: Qt.size(480, 300)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            // marks the active wallpaper
                            Rectangle {
                                visible: cell.isCurrent
                                anchors { top: parent.top; left: parent.left; margins: 6 }
                                width: 10; height: 10
                                color: Theme.accent
                                border { width: 2; color: Theme.background }
                            }
                        }
                        Text {
                            width: parent.width
                            height: 18
                            text: win.baseName(cell.modelData)
                            elide: Text.ElideMiddle
                            horizontalAlignment: Text.AlignHCenter
                            color: cell.sel ? Theme.foreground : Qt.alpha(Theme.foreground, 0.75)
                            font { family: Theme.fontFamily; pixelSize: 11 }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: win.sel = cell.index
                        onClicked: { win.sel = cell.index; Wallpaper.set(cell.modelData) }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: Wallpaper.files.length === 0
                    text: "No images in " + Wallpaper.dir + "\ndrop one on the desktop to add it"
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.muted
                    font { family: Theme.fontFamily; pixelSize: 13 }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            Text {
                text: "←↑↓→ navigate  ·  ↵ set  ·  r random  ·  s slideshow  ·  esc close"
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 12 }
            }
        }
    }
}
