import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell

// Neo-brutalist frame: solid border on all sides (thick top = the bar), sharp inner
// corners, 2px hard-outlined boxes, no shadows. The middle is click-through.
Scope {
    id: scope
    required property var modelData

    property bool peek: false
    property bool bandHot: false
    property bool edgeHot: false
    readonly property bool hot: bandHot || edgeHot
    readonly property bool barOpen: !BarCtl.hidden && (!BarCtl.autoHide || peek)
    // module chips (squircle-ish rounded boxes) + bar bottom-corner radius
    readonly property color chip: Qt.tint(Theme.background, Qt.alpha(Theme.foreground, 0.09))
    readonly property int chipR: 9
    readonly property int slabR: 16
    property real topInset: barOpen ? Theme.barHeight : 0
    Behavior on topInset { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    // left/right/bottom outline follows the bar: gone when the bar is hidden / auto-hidden
    // (visual animates; the layout reserve below only changes when pinned, so peeking never reflows)
    property real frameT: barOpen ? Theme.frameThickness : 0
    Behavior on frameT { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    onHotChanged: {
        if (hot) { hideTimer.stop(); peek = true; }
        else hideTimer.restart();
    }
    Timer { id: hideTimer; interval: 350; onTriggered: scope.peek = false }

    PanelWindow {
        screen: scope.modelData
        anchors { top: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: ((BarCtl.hidden || BarCtl.autoHide) ? 0 : Theme.barHeight) + BarCtl.winbarSpace   // peek overlays, never reflows; + room for WinBar
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
    }
    PanelWindow {
        screen: scope.modelData
        anchors { bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: (BarCtl.hidden || BarCtl.autoHide) ? 0 : Theme.frameThickness
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
    }
    PanelWindow {
        screen: scope.modelData
        anchors { left: true; top: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: (BarCtl.hidden || BarCtl.autoHide) ? 0 : Theme.frameThickness
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
    }
    PanelWindow {
        screen: scope.modelData
        anchors { right: true; top: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: (BarCtl.hidden || BarCtl.autoHide) ? 0 : Theme.frameThickness
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
    }

    Dashboard { screen: scope.modelData; triggerHovered: topHover.hovered }
    PowerMenu { screen: scope.modelData; triggerHovered: rightHover.hovered }
    WifiMenu {
        id: wifiMenu
        screen: scope.modelData
        anchorItem: statusIcons.netAnchor
        onUpdated: statusIcons.refreshNet()
    }
    BtMenu {
        id: btMenu
        screen: scope.modelData
        anchorItem: statusIcons.btAnchor
    }

    PanelWindow {
        id: win
        screen: scope.modelData
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        mask: Region {
            x: scope.frameT
            y: scope.topInset
            width: win.width - scope.frameT * 2
            height: win.height - scope.topInset - scope.frameT
            intersection: Intersection.Xor
        }

        Item {
            id: root
            anchors.fill: parent

            readonly property real fl: scope.frameT
            readonly property real ft: scope.topInset
            readonly property real fr: scope.frameT
            readonly property real fb: scope.frameT
            readonly property real r: Theme.frameRadius

            // bar slab: hugs the top/left/right edges, rounded bottom corners
            Shape {
                anchors.fill: parent
                visible: root.ft > 0.5
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    id: slab
                    readonly property real rr: Math.min(scope.slabR, root.ft)
                    fillColor: Theme.background
                    strokeWidth: -1
                    startX: 0; startY: 0
                    PathLine { x: root.width; y: 0 }
                    PathLine { x: root.width; y: root.ft - slab.rr }
                    PathArc  { x: root.width - slab.rr; y: root.ft
                               radiusX: slab.rr; radiusY: slab.rr; direction: PathArc.Clockwise }
                    PathLine { x: slab.rr; y: root.ft }
                    PathArc  { x: 0; y: root.ft - slab.rr
                               radiusX: slab.rr; radiusY: slab.rr; direction: PathArc.Clockwise }
                    PathLine { x: 0; y: 0 }
                }
            }

            // optional full frame (only when Theme.frameThickness > 0)
            Shape {
                anchors.fill: parent
                visible: scope.frameT > 0.5
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: Theme.background
                    strokeWidth: -1
                    fillRule: ShapePath.OddEvenFill

                    startX: 0; startY: 0
                    PathLine { x: root.width; y: 0 }
                    PathLine { x: root.width; y: root.height }
                    PathLine { x: 0; y: root.height }
                    PathLine { x: 0; y: 0 }

                    PathMove { x: root.fl + root.r; y: root.ft }
                    PathLine { x: root.width - root.fr - root.r; y: root.ft }
                    PathArc  { x: root.width - root.fr; y: root.ft + root.r
                               radiusX: root.r; radiusY: root.r; direction: PathArc.Clockwise }
                    PathLine { x: root.width - root.fr; y: root.height - root.fb - root.r }
                    PathArc  { x: root.width - root.fr - root.r; y: root.height - root.fb
                               radiusX: root.r; radiusY: root.r; direction: PathArc.Clockwise }
                    PathLine { x: root.fl + root.r; y: root.height - root.fb }
                    PathArc  { x: root.fl; y: root.height - root.fb - root.r
                               radiusX: root.r; radiusY: root.r; direction: PathArc.Clockwise }
                    PathLine { x: root.fl; y: root.ft + root.r }
                    PathArc  { x: root.fl + root.r; y: root.ft
                               radiusX: root.r; radiusY: root.r; direction: PathArc.Clockwise }
                }
            }

            Item {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: scope.frameT + 2
                height: 360
                HoverHandler { id: rightHover }
            }

            Item {
                anchors { left: parent.left; right: parent.right }
                y: scope.topInset - Theme.barHeight
                height: Theme.barHeight
                HoverHandler { onHoveredChanged: scope.bandHot = hovered }

                RowLayout {
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 8

                    Rectangle {     // logo: 3-leaf clover, pixel art (1 char = 1 px; bump `pix` to scale up)
                        radius: scope.chipR; color: scope.chip
                        Layout.preferredWidth: logo.width + 14
                        Layout.preferredHeight: 28
                        Canvas {
                            id: logo
                            anchors.centerIn: parent
                            readonly property int pix: 1
                            readonly property var bits: [
                                ".......####.###.......",
                                "......##########......",
                                ".....############.....",
                                ".....############.....",
                                "......###########.....",
                                ".......#########......",
                                ".......#########......",
                                ".####...#######..####.",
                                ".#####...#####..#####.",
                                "######...#####..######",
                                "########.#############",
                                "######################",
                                "######################",
                                "######################",
                                "######################",
                                "######################",
                                "#######...###...######",
                                ".#####....##.....####.",
                                "..###.....##......##..",
                                "...........#..........",
                                "...........#..........",
                                "..........##..........",
                                "..........###.........",
                                "..........###........."
                            ]
                            width: bits[0].length * pix
                            height: bits.length * pix
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                ctx.fillStyle = Theme.foreground;
                                for (let y = 0; y < bits.length; y++)
                                    for (let x = 0; x < bits[y].length; x++)
                                        if (bits[y][x] === "#") ctx.fillRect(x * pix, y * pix, pix, pix);
                            }
                            Connections {
                                target: Theme
                                function onForegroundChanged() { logo.requestPaint(); }
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: Launcher.toggle() }
                    }
                    Rectangle {
                        visible: ws.items.length > 0
                        radius: scope.chipR; color: scope.chip
                        Layout.preferredWidth: ws.implicitWidth + 12
                        Layout.preferredHeight: 28
                        Workspaces {
                            id: ws
                            anchors.centerIn: parent
                            screenName: scope.modelData ? scope.modelData.name : ""
                        }
                    }
                }

                Item {
                    anchors.centerIn: parent
                    width: 560
                    height: parent.height
                    HoverHandler { id: topHover }
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Rectangle {
                        radius: scope.chipR; color: scope.chip
                        Layout.preferredWidth: aw.implicitWidth + 24
                        Layout.preferredHeight: 28
                        ActiveWindow { id: aw; anchors.centerIn: parent }
                    }
                    Rectangle {
                        radius: scope.chipR; color: scope.chip
                        Layout.preferredWidth: clk.implicitWidth + 24
                        Layout.preferredHeight: 28
                        Clock { id: clk; anchors.centerIn: parent }
                    }
                }

                RowLayout {
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Rectangle {
                        visible: tray.implicitWidth > 0
                        radius: scope.chipR; color: scope.chip
                        Layout.preferredWidth: tray.implicitWidth + 20
                        Layout.preferredHeight: 28
                        Tray { id: tray; anchors.centerIn: parent }
                    }
                    Rectangle {
                        radius: scope.chipR; color: scope.chip
                        Layout.preferredWidth: statusIcons.implicitWidth + 24
                        Layout.preferredHeight: 28
                        StatusIcons {
                            id: statusIcons
                            anchors.centerIn: parent
                            wifiOpen: wifiMenu.open
                            btOpen: btMenu.open
                            onWifiClicked: { btMenu.open = false; wifiMenu.toggle(); }
                            onBtClicked: { wifiMenu.open = false; btMenu.toggle(); }
                        }
                    }
                    Rectangle {
                        radius: scope.chipR; color: scope.chip
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        Text {
                            anchors.centerIn: parent
                            text: "\uf013"
                            color: SettingsPanel.open ? Theme.accent : Theme.foreground
                            font { family: Theme.iconFont; pixelSize: 15 }
                        }
                        MouseArea { anchors.fill: parent; onClicked: SettingsPanel.toggle() }
                    }
                }
            }
        }
    }

    PanelWindow {
        screen: scope.modelData
        anchors { top: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        implicitHeight: 3
        color: "transparent"
        visible: BarCtl.autoHide && !BarCtl.hidden && scope.topInset < 8
        HoverHandler { onHoveredChanged: scope.edgeHot = hovered }
    }
}
