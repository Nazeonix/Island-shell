import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray

// Modular status bar: separate solid (fully opaque) capsules floating over the wallpaper.
//   left:   launcher button, now-playing
//   center: clock, Hyprland workspaces
//   right:  tray, volume, wifi, battery, settings (opens the theme panel)
// Edge is Theme.barAtTop / Theme.barHeight. Default is the bottom, since the island sits top-center.
PanelWindow {
    id: win

    signal logoClicked()
    signal settingsClicked()

    screen: Quickshell.screens[0]
    visible: Theme.panelMode   // island mode shows the island instead
    anchors { left: true; right: true; top: Theme.barAtTop; bottom: !Theme.barAtTop }
    implicitHeight: Theme.barHeight
    color: "transparent"      // gaps between modules show the wallpaper
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Theme.barHeight
    WlrLayershell.namespace: "dynamic-island-bar"

    // ================= Data =================

    // Media (same pick rule as the island: first playing, else first)
    readonly property var player: {
        const list = Mpris.players.values;
        for (const p of list)
            if (p.playbackState === MprisPlaybackState.Playing) return p;
        return list.length > 0 ? list[0] : null;
    }
    readonly property bool playing: player !== null && player.playbackState === MprisPlaybackState.Playing
    readonly property string mediaText: {
        if (!player) return "";
        const t = player.trackTitle || "";
        const a = player.trackArtist || "";
        return a.length > 0 && t.length > 0 ? a + " \u2014 " + t : (t.length > 0 ? t : a);
    }

    // Volume
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: win.sink ? [win.sink] : [] }
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property int volPct: sink && sink.audio ? Math.round(sink.audio.volume * 100) : 0

    // Wifi (NetworkManager, polled)
    property bool wifiUp: false
    property string ssid: ""
    Process {
        id: wifiProc
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL,SSID", "dev", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector {
            onStreamFinished: {
                let found = false;
                for (const line of text.split("\n")) {
                    const m = line.match(/^\*:(\d+):(.*)$/);
                    if (m) { win.ssid = m[2]; found = true; break; }
                }
                if (!found) win.ssid = "";
                win.wifiUp = found;
            }
        }
    }
    Timer {
        interval: 5000; running: win.visible; repeat: true; triggeredOnStart: true
        onTriggered: wifiProc.running = true
    }

    // Battery
    readonly property var bat: UPower.displayDevice
    readonly property int batPct: Math.round(bat.percentage * 100)
    readonly property bool charging: bat.state === UPowerDeviceState.Charging
                                  || bat.state === UPowerDeviceState.FullyCharged
    readonly property color batColor: charging ? Theme.success : (batPct <= 20 ? Theme.error : Theme.green)

    // Workspaces (Hyprland, native IPC): sorted, only this screen's, no polling needed
    readonly property var workspaces: Hyprland.workspaces.values
        .filter(w => w.id > 0 && (!win.screen || !w.monitor || w.monitor.name === win.screen.name))
        .sort((a, b) => a.id - b.id)
    onVisibleChanged: { if (!visible) calendar.hide(); }

    // ================= Building blocks =================
    // Small vector icons (no icon font). Repaints itself when kind/col/alt/level change.
    component Glyph: Canvas {
        property string kind: ""
        property color col: Theme.foreground
        property bool alt: false        // muted / paused / offline / charging
        property real level: 1          // battery fill 0..1
        width: Theme.s(14); height: Theme.s(14)
        antialiasing: true
        onKindChanged: requestPaint()
        onColChanged: requestPaint()
        onAltChanged: requestPaint()
        onLevelChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            c.scale(width / 14, height / 14);
            c.strokeStyle = col;
            c.fillStyle = col;
            c.lineWidth = 1.4;
            c.lineCap = "round";
            c.lineJoin = "round";
            const rad = d => d * Math.PI / 180;
            if (kind === "clock") {
                c.beginPath(); c.arc(7, 7, 5.5, 0, 2 * Math.PI); c.stroke();
                c.beginPath(); c.moveTo(7, 7); c.lineTo(7, 3.8); c.moveTo(7, 7); c.lineTo(9.4, 8.4); c.stroke();
            } else if (kind === "volume") {
                c.beginPath();
                c.moveTo(1, 5); c.lineTo(3.5, 5); c.lineTo(6.5, 2.2); c.lineTo(6.5, 11.8); c.lineTo(3.5, 9); c.lineTo(1, 9);
                c.closePath(); c.fill();
                if (alt) {
                    c.beginPath(); c.moveTo(9, 5); c.lineTo(13, 9); c.moveTo(13, 5); c.lineTo(9, 9); c.stroke();
                } else {
                    c.beginPath(); c.arc(7, 7, 3.4, rad(-50), rad(50)); c.stroke();
                    c.beginPath(); c.arc(7, 7, 6, rad(-50), rad(50)); c.stroke();
                }
            } else if (kind === "wifi") {
                c.globalAlpha = alt ? 0.45 : 1;
                for (let i = 1; i <= 3; i++) {
                    c.beginPath(); c.arc(7, 11.5, i * 3, rad(-135), rad(-45)); c.stroke();
                }
                c.beginPath(); c.arc(7, 11.5, 1, 0, 2 * Math.PI); c.fill();
                c.globalAlpha = 1;
                if (alt) { c.beginPath(); c.moveTo(2, 2); c.lineTo(12, 12); c.stroke(); }
            } else if (kind === "battery") {
                c.beginPath(); c.roundedRect(0.8, 3.2, 10.4, 7.6, 2, 2); c.stroke();
                c.fillRect(12, 5.8, 1.4, 2.4);
                c.fillRect(2.4, 4.8, Math.max(0, 7.2 * level), 4.4);
                if (alt) {   // charging bolt, punched out in the bar's dark color
                    c.fillStyle = Theme.background;
                    c.beginPath();
                    c.moveTo(7, 4); c.lineTo(4.6, 7.4); c.lineTo(6.4, 7.4); c.lineTo(5.6, 10); c.lineTo(8.4, 6.4); c.lineTo(6.6, 6.4);
                    c.closePath(); c.fill();
                }
            } else if (kind === "sliders") {
                const ys = [3, 7, 11], xs = [4.5, 9.5, 5.5];
                for (let i = 0; i < 3; i++) {
                    c.beginPath(); c.moveTo(1.5, ys[i]); c.lineTo(12.5, ys[i]); c.stroke();
                    c.beginPath(); c.arc(xs[i], ys[i], 1.7, 0, 2 * Math.PI); c.fill();
                }
            } else if (kind === "media") {
                if (alt) {   // paused -> show play
                    c.beginPath(); c.moveTo(4, 2.5); c.lineTo(11.5, 7); c.lineTo(4, 11.5); c.closePath(); c.fill();
                } else {     // playing -> show pause
                    c.fillRect(3.5, 2.5, 2.6, 9);
                    c.fillRect(7.9, 2.5, 2.6, 9);
                }
            } else if (kind === "logo") {
                c.lineWidth = 1.8;
                c.beginPath(); c.moveTo(2, 12); c.lineTo(7, 2); c.lineTo(12, 12); c.stroke();
                c.beginPath(); c.moveTo(4.6, 8.6); c.lineTo(9.4, 8.6); c.stroke();
            }
        }
    }

    // Circular tinted badge holding a glyph
    component Badge: Rectangle {
        property string kind: ""
        property color tint: Theme.primary
        property bool alt: false
        property real level: 1
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.s(20); height: width; radius: width / 2
        color: Qt.alpha(tint, 0.18)
        Glyph { anchors.centerIn: parent; kind: parent.kind; col: parent.tint; alt: parent.alt; level: parent.level }
    }

    // Dark translucent capsule; children are laid out in a row
    component Pill: Rectangle {
        default property alias content: row.data
        property int padL: Theme.s(4)
        property int padR: Theme.s(12)
        property bool interactive: false
        signal clicked()
        signal scrolled(int dir)
        implicitWidth: row.implicitWidth + padL + padR
        implicitHeight: Theme.s(28)
        radius: height / 2
        readonly property bool hot: interactive && pillMouse.containsMouse
        color: hot ? Theme.surface : Theme.background   // solid, no transparency
        border.width: 1
        border.color: Theme.borderSubtle
        Behavior on color { ColorAnimation { duration: 120 } }
        Row {
            id: row
            x: parent.padL
            height: parent.height
            spacing: Theme.s(8)
        }
        MouseArea {
            id: pillMouse
            anchors.fill: parent
            enabled: parent.interactive
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
            onWheel: (w) => parent.scrolled(w.angleDelta.y > 0 ? 1 : -1)
        }
    }

    // Round icon-only button
    component RoundBtn: Rectangle {
        property string kind: ""
        property color tint: Theme.primary
        signal clicked()
        width: Theme.s(28); height: width; radius: width / 2
        color: btnMouse.containsMouse ? Theme.surface : Theme.background   // solid, no transparency
        border.width: 1
        border.color: Theme.borderSubtle
        Behavior on color { ColorAnimation { duration: 120 } }
        Glyph { anchors.centerIn: parent; kind: parent.kind; col: parent.tint }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component BarText: Text {
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.foreground
        font.pixelSize: Theme.s(13)
        font.weight: Font.Medium
        elide: Text.ElideRight
    }

    CalendarPopup { id: calendar; screen: win.screen }

    // ================= Layout =================
    // ---- Left ----
    Row {
        anchors.left: parent.left
        anchors.leftMargin: Theme.s(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.s(6)

        RoundBtn { kind: "logo"; tint: Theme.primary; onClicked: win.logoClicked() }

        Pill {
            visible: win.player !== null
            interactive: true
            onClicked: if (win.player && win.player.canTogglePlaying) win.player.togglePlaying()
            Badge { kind: "media"; tint: Theme.primary; alt: !win.playing }
            BarText { width: Math.min(implicitWidth, Theme.s(260)); text: win.mediaText }
        }
    }

    // ---- Center ----
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.s(8)

        ClockApplet {
            format: "hh:mm"
            active: calendar.open
            onClicked: (x) => calendar.toggleAt(x)
        }

        Pill {
            padL: Theme.s(12)
            visible: win.workspaces.length > 0
            Repeater {
                model: win.workspaces
                Item {
                    id: ws
                    required property var modelData
                    readonly property bool act: modelData.active
                    readonly property bool occ: modelData.toplevels && modelData.toplevels.values ? modelData.toplevels.values.length > 0 : false
                    width: Theme.s(14); height: Theme.s(28)
                    Rectangle {
                        anchors.centerIn: parent
                        width: ws.act ? Theme.s(10) : Theme.s(6); height: width; radius: width / 2
                        color: ws.act ? Theme.primary : (ws.occ ? Theme.foreground : Qt.alpha(Theme.foreground, 0.25))
                        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Hyprland.dispatch("workspace " + ws.modelData.id)
                    }
                }
            }
        }
    }

    // ---- Right ----
    Row {
        anchors.right: parent.right
        anchors.rightMargin: Theme.s(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.s(8)

        Pill {   // system tray: click = activate, middle = secondary, right = menu, scroll = scroll
            visible: SystemTray.items.values.length > 0
            padL: Theme.s(10)
            padR: Theme.s(10)
            Repeater {
                model: SystemTray.items
                Item {
                    id: tray
                    required property var modelData
                    width: Theme.s(20)
                    height: Theme.s(28)

                    function openMenu() {
                        const p = tray.mapToItem(win.contentItem, 0, 0);
                        trayMenu.anchor.rect = Qt.rect(p.x, p.y, tray.width, tray.height);
                        trayMenu.open();
                    }

                    Image {
                        anchors.centerIn: parent
                        width: Theme.s(18); height: width
                        source: tray.modelData.icon
                        sourceSize: Qt.size(Theme.s(36), Theme.s(36))
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        opacity: trayMouse.containsMouse ? 1 : 0.85
                    }
                    QsMenuAnchor {
                        id: trayMenu
                        menu: tray.modelData.menu
                        anchor.window: win
                        anchor.edges: Theme.barAtTop ? (Edges.Bottom | Edges.Left) : (Edges.Top | Edges.Left)
                        anchor.gravity: Theme.barAtTop ? (Edges.Bottom | Edges.Right) : (Edges.Top | Edges.Right)
                    }
                    MouseArea {
                        id: trayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (m) => {
                            const it = tray.modelData;
                            if (m.button === Qt.LeftButton) {
                                if (it.onlyMenu && it.hasMenu) tray.openMenu();
                                else it.activate();
                            } else if (m.button === Qt.MiddleButton) it.secondaryActivate();
                            else if (it.hasMenu) tray.openMenu();
                        }
                        onWheel: (w) => tray.modelData.scroll(w.angleDelta.y, false)
                    }
                }
            }
        }

        Pill {   // click = mute, scroll = volume
            interactive: true
            onClicked: if (win.sink && win.sink.audio) win.sink.audio.muted = !win.sink.audio.muted
            onScrolled: (dir) => {
                if (!win.sink || !win.sink.audio) return;
                win.sink.audio.volume = Math.max(0, Math.min(1, win.sink.audio.volume + dir * 0.05));
            }
            Badge { kind: "volume"; tint: win.muted ? Theme.error : Theme.cyan; alt: win.muted }
            BarText { text: win.muted ? "Muted" : win.volPct + "%" }
        }

        Pill {
            Badge { kind: "wifi"; tint: win.wifiUp ? Theme.pink : Theme.foregroundMuted; alt: !win.wifiUp }
            BarText { width: Math.min(implicitWidth, Theme.s(140)); text: win.wifiUp ? win.ssid : "Offline" }
        }

        Pill {
            visible: win.bat.isPresent
            Badge { kind: "battery"; tint: win.batColor; alt: win.charging; level: win.batPct / 100 }
            BarText { text: win.batPct + "%" }
        }

        WallpaperApplet {}

        RoundBtn { kind: "sliders"; tint: Theme.yellow; onClicked: win.settingsClicked() }
    }
}
