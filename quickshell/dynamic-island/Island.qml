import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

Item {
    id: root

    // States: collapsed | expanded (hover, pinned or peek)
    property bool pinned: false   // keyboard-opened: stays expanded + grabs keyboard focus
    property bool peek: false     // brief expand after a volume/brightness shortcut
    property int trayMenus: 0     // open tray menus (they steal hover, so they pin the island open)
    property var notifService: null    // NotificationService, injected from shell.qml
    property bool full: false          // latched once the pointer reaches the bottom of the middle state

    // Levels: 0 collapsed | 1 middle (pointer on the notch) | 2 full (pointer at the bottom of the
    // middle state, or pinned / peeking / a tray menu open)
    readonly property int level: (pinned || peek || trayMenus > 0 || full) ? 2 : (hover.hovered ? 1 : 0)
    readonly property bool mediaOpen: level === 2
    readonly property bool midOpen: level === 1
    readonly property bool expanded: mediaOpen
    // Animated 0..1 progress of each state; the strip layout is interpolated from these
    property real midT: midOpen ? 1 : 0
    property real fullT: expanded ? 1 : 0
    Behavior on midT  { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
    Behavior on fullT { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    readonly property int midH: barH + 26
    readonly property int midRow2: 47    // vertical center of the pills / wifi / battery row in the middle state

    // Active window + notification summary for the middle state
    readonly property var activeTop: ToplevelManager.activeToplevel
    readonly property string activeId: activeTop ? (activeTop.appId || "") : ""
    readonly property var activeEntry: activeId !== "" ? DesktopEntries.heuristicLookup(activeId) : null
    readonly property string activeName: activeEntry ? activeEntry.name : (activeId !== "" ? activeId : "Desktop")
    readonly property string activeIcon: {
        if (activeId === "") return "";
        const ic = activeEntry ? activeEntry.icon : activeId.toLowerCase();
        return Quickshell.iconPath(ic, true) || Quickshell.iconPath("application-x-executable", true);
    }
    readonly property int notifCount: notifService ? notifService.list.values.length : 0
    readonly property var player: {
        const list = Mpris.players.values;
        for (const p of list)
            if (p.playbackState === MprisPlaybackState.Playing) return p;
        return list.length > 0 ? list[0] : null;
    }
    readonly property bool playing: player && player.playbackState === MprisPlaybackState.Playing

    // Material-ish palette
    readonly property color accent: Theme.accent
    readonly property color onSurface: Theme.foreground
    readonly property color onSurfaceDim: Theme.foregroundMuted

    function fmt(s) {
        s = Math.max(0, Math.floor(s));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    // ---- Workspaces (Hyprland) ----
    readonly property var wsScreen: Quickshell.screens[0]   // keep in sync with shell.qml
    readonly property var wsList: {
        const l = Hyprland.workspaces.values.filter(w => w.id > 0
            && (!wsScreen || !w.monitor || w.monitor.name === wsScreen.name));
        return l.sort((a, b) => a.id - b.id);
    }

    readonly property int barW: 260
    // Fully open: control-center layout (tiles + media, two sliders, notifications)
    readonly property int fullW: 460
    readonly property int fullH: barH + 8 + 412 + 14
    readonly property int barH: 38   // notch height
    readonly property int ctrlH: 64   // extra height for volume/brightness sliders
    readonly property int leftW: 384  // media pane width (art + controls + sliders)
    readonly property int calW: 232   // calendar pane width
    readonly property int calGap: 20  // space between media pane and calendar

    // ---- Calendar ----
    property int weekStart: 1                              // 0 = Sunday, 1 = Monday
    property int calYear: new Date().getFullYear()
    property int calMonth: new Date().getMonth()           // 0..11
    readonly property string todayKey: Qt.formatDate(clock.date, "yyyyMMdd")
    function calStep(d) {
        const t = new Date(calYear, calMonth + d, 1);
        calYear = t.getFullYear();
        calMonth = t.getMonth();
    }
    function calReset() {
        const t = new Date();
        calYear = t.getFullYear();
        calMonth = t.getMonth();
    }

    // ---- Bluetooth (BlueZ) ----
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btOn: btAdapter ? btAdapter.enabled : false
    readonly property var btConnected: btAdapter ? btAdapter.devices.values.filter(d => d.connected) : []
    readonly property string btSub: !btAdapter ? "Unavailable" : !btOn ? "Off"
        : btConnected.length === 0 ? "On" : (btConnected.length === 1 ? btConnected[0].name : btConnected.length + " devices")

    // ---- Volume (PipeWire) ----
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    // ---- Brightness (brightnessctl, internal eDP backlight) ----
    property int brVal: 0
    property int brMax: 100
    property bool brAvail: false
    property int brPending: -1

    function setBrightness(v) {
        v = Math.max(Math.max(1, Math.round(brMax * 0.01)), Math.min(brMax, v));   // never fully black
        brVal = v;
        brPending = v;
        if (!brSet.running) brFlush();
    }
    function brFlush() {
        brSet.command = ["brightnessctl", "-q", "-c", "backlight", "set", String(brPending)];
        brPending = -1;
        brSet.running = true;
    }
    // Coalesce drags into the latest value while a write is in flight
    Process {
        id: brSet
        onExited: if (root.brPending >= 0) root.brFlush()
    }
    Process {
        id: brGet
        command: ["brightnessctl", "-m", "-c", "backlight"]   // -> "name,class,cur,pct%,max"
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\n")[0].split(",");
                if (f.length >= 5) {
                    root.brVal = parseInt(f[2]);
                    root.brMax = Math.max(1, parseInt(f[4]));
                    root.brAvail = true;
                }
            }
        }
    }
    onMediaOpenChanged: {
        if (!mediaOpen) return;
        calReset();
        if (!brSet.running) brGet.running = true;
    }

    // ---- Keyboard / shortcut API (called from shell.qml GlobalShortcuts and Keys below) ----
    function peekNow() {
        if (pinned) return;
        peek = true;
        peekTimer.restart();
    }
    Timer { id: peekTimer; interval: 1500; onTriggered: root.peek = false }

    function toggle()     { pinned = !pinned; }
    function close()      { pinned = false; peek = false; }

    function mediaToggle() { if (player && player.canTogglePlaying) player.togglePlaying(); }
    function mediaNext()   { if (player && player.canGoNext) player.next(); }
    function mediaPrev()   { if (player && player.canGoPrevious) player.previous(); }
    function seek(d) {
        if (player && player.canSeek && player.length > 0)
            player.position = Math.max(0, Math.min(player.length, player.position + d));
    }

    // Volume / brightness changes show the OSD (Osd.qml) unless the island is already open
    signal osdShow(string kind)
    function notifyOsd(kind) { if (pinned || mediaOpen) return; osdShow(kind); }

    function volStep(d) {   // d in 0..1 units
        if (!sink || !sink.audio) return;
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + d));
        notifyOsd("volume");
    }
    function toggleMute() {
        if (!sink || !sink.audio) return;
        sink.audio.muted = !sink.audio.muted;
        notifyOsd("volume");
    }
    function brStep(pct) {  // pct in percentage points
        if (!brAvail) { brGet.running = true; return; }
        setBrightness(Math.max(0, Math.min(brMax, brVal + Math.round(pct * brMax / 100))));
        notifyOsd("brightness");
    }

    // Keys (only receives input while pinned, when shell.qml grants keyboard focus)
    focus: true
    onPinnedChanged: if (pinned) forceActiveFocus()
    Keys.onPressed: (e) => {
        const shift = e.modifiers & Qt.ShiftModifier;
        let ok = true;
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_Q) close();
        else {
            if (e.key === Qt.Key_Space || e.key === Qt.Key_K) mediaToggle();
            else if (e.key === Qt.Key_Left)  shift ? seek(-5) : mediaPrev();
            else if (e.key === Qt.Key_Right) shift ? seek(5)  : mediaNext();
            else if (e.key === Qt.Key_Up)    shift ? brStep(5)  : volStep(0.05);
            else if (e.key === Qt.Key_Down)  shift ? brStep(-5) : volStep(-0.05);
            else if (e.key === Qt.Key_M) toggleMute();
            else if (e.key === Qt.Key_BracketLeft) calStep(-1);
            else if (e.key === Qt.Key_BracketRight) calStep(1);
            else if (e.key === Qt.Key_T) calReset();
            else ok = false;
        }
        e.accepted = ok;
    }
    Component.onCompleted: brGet.running = true

    width: mediaOpen ? fullW : (midOpen ? 560 : 270)
    height: mediaOpen ? fullH : (midOpen ? midH : barH)

    Behavior on width  { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
    Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    // MPRIS position isn't pushed; poll while visible and playing
    Timer {
        interval: 500
        repeat: true
        running: root.mediaOpen && root.playing && root.player.positionSupported
        onTriggered: root.player.positionChanged()
    }

    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (!hovered) root.full = false;
        }
        // Pointer reached the lower part of the middle state -> expand fully
        onPointChanged: if (hovered && root.level === 1 && point.position.y > root.barH + 6) root.full = true
    }

    // Notch: flush with the top screen edge (square top corners), rounded bottom corners
    Rectangle {
        id: bg
        anchors.fill: parent
        topLeftRadius: 0     // top corners are flared outward instead (see the ears below)
        topRightRadius: 0
        bottomLeftRadius: root.expanded ? 28 : (root.midOpen ? 22 : 14)
        bottomRightRadius: bottomLeftRadius
        color: Theme.notch
        Behavior on bottomLeftRadius { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    }

    // "Water drop" top corners: concave fillets outside the notch that melt it into the top edge
    property real earR: expanded ? 18 : (midOpen ? 14 : 10)
    Behavior on earR { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    Shape {
        id: earL
        x: -width + 1; y: 0
        width: root.earR; height: root.earR
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: Theme.notch
            strokeWidth: -1
            startX: 0; startY: 0
            PathLine { x: earL.width; y: 0 }
            PathLine { x: earL.width; y: earL.height }
            PathArc { x: 0; y: 0; radiusX: earL.width; radiusY: earL.height; direction: PathArc.Counterclockwise }
        }
    }
    Shape {
        id: earRt
        x: root.width - 1; y: 0
        width: root.earR; height: root.earR
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: Theme.notch
            strokeWidth: -1
            startX: earRt.width; startY: 0
            PathLine { x: 0; y: 0 }
            PathLine { x: 0; y: earRt.height }
            PathArc { x: earRt.width; y: 0; radiusX: earRt.width; radiusY: earRt.height; direction: PathArc.Clockwise }
        }
    }

    // ===== Top strip (always visible): workspace pills left | clock | wifi + battery right =====
    RowLayout {
        anchors.left: parent.left
        anchors.leftMargin: 29 - 7 * root.midT - 15 * root.fullT
        y: (barH - height) / 2 * (1 - root.midT) + (root.midRow2 - height / 2) * root.midT
        spacing: 8

        // Vertical workspace pills; the active one is taller + accent colored
        Row {
            spacing: 5
            Layout.alignment: Qt.AlignVCenter
            Repeater {
                model: root.wsList
                Item {
                    id: ws
                    required property var modelData
                    readonly property bool act: modelData.active
                    readonly property bool occ: modelData.toplevels && modelData.toplevels.values
                                                ? modelData.toplevels.values.length > 0 : false
                    width: act ? 9 : 7
                    height: 24
                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: ws.act ? 19 : 13
                        radius: width / 2
                        color: ws.act ? root.accent
                             : ws.occ ? Qt.alpha(root.accent, 0.6)
                             : Qt.alpha(root.accent, 0.22)
                        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on color  { ColorAnimation  { duration: 160 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -2
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Hyprland.dispatch("workspace " + ws.modelData.id)
                    }
                }
            }
        }
    }

    Text {
        id: clockText
        // In the middle state the clock grows and shifts left to make room for the date
        x: (parent.width - width - root.midT * (dateText.width + 10)) / 2
        y: (barH - height) / 2 * (1 - root.midT) + (32 - height / 2) * root.midT
        text: Qt.formatDateTime(clock.date, "hh:mm")
        color: Qt.alpha(Theme.foreground, 0.9)
        font.pixelSize: Math.round(16 + 8 * root.midT)   // collapsed clock size: change the 16
        font.weight: Font.Medium
    }
    Text {
        id: dateText
        x: clockText.x + clockText.width + 10
        anchors.baseline: clockText.baseline
        text: Qt.formatDate(clock.date, "ddd, MMM d")
        color: Qt.alpha(Theme.foreground, 0.55)
        font.pixelSize: 13
        font.weight: Font.Medium
        opacity: root.midT
        visible: opacity > 0
    }
    Rectangle {   // playing dot, left of the clock
        visible: root.playing && !root.expanded && !root.midOpen
        width: 6; height: 6; radius: 3
        color: Theme.success
        anchors.right: clockText.left
        anchors.rightMargin: 8
        anchors.verticalCenter: clockText.verticalCenter
    }

    // ---- Middle state extras: active app (top left), notification status (top right) ----
    Row {
        x: 22
        y: 14 - height / 2
        spacing: 7
        opacity: root.midT
        visible: opacity > 0
        Image {
            width: 16; height: 16
            anchors.verticalCenter: parent.verticalCenter
            visible: root.activeIcon !== ""
            source: root.activeIcon
            sourceSize: Qt.size(32, 32)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 110)
            text: root.activeName
            color: Qt.alpha(Theme.foreground, 0.9)
            font.pixelSize: 13
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
    }
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 22
        y: 14 - height / 2
        spacing: 7
        opacity: root.midT
        visible: opacity > 0
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.notifCount > 0 ? root.notifCount + (root.notifCount === 1 ? " notification" : " notifications") : "All caught up"
            color: root.notifCount > 0 ? root.accent : Qt.alpha(Theme.foreground, 0.65)
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        Canvas {   // bell
            id: bell
            width: 14; height: 15
            anchors.verticalCenter: parent.verticalCenter
            antialiasing: true
            property color col: root.notifCount > 0 ? root.accent : Qt.alpha(Theme.foreground, 0.65)
            onColChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.strokeStyle = col;
                c.lineWidth = 1.4;
                c.lineJoin = "round";
                c.lineCap = "round";
                c.beginPath();
                c.moveTo(2.5, 11); c.lineTo(11.5, 11);
                c.bezierCurveTo(10.5, 10, 10.2, 8.5, 10.2, 6.5);
                c.bezierCurveTo(10.2, 4.3, 8.8, 2.8, 7, 2.8);
                c.bezierCurveTo(5.2, 2.8, 3.8, 4.3, 3.8, 6.5);
                c.bezierCurveTo(3.8, 8.5, 3.5, 10, 2.5, 11);
                c.stroke();
                c.beginPath(); c.arc(7, 12.6, 1.3, 0, Math.PI); c.stroke();
            }
        }
    }

    // Right group, anchored to the right edge exactly like the left group, so it rides the
    // width animation (no separate slide). Tray icons appear only once the island is wide.
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 29 - 7 * root.midT - 15 * root.fullT
        y: (barH - height) / 2 * (1 - root.midT) + (root.midRow2 - height / 2) * root.midT
        spacing: 10

        Row {   // system tray: click = activate, middle = secondary, right = menu, scroll = scroll
            id: trayRow
            opacity: root.expanded && root.width > 380 ? 1 : 0
            visible: opacity > 0 && SystemTray.items.values.length > 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: SystemTray.items
                Item {
                    id: tray
                    required property var modelData
                    readonly property var hostWin: QsWindow.window
                    width: 24; height: 24

                    function openMenu() {
                        const p = tray.mapToItem(tray.hostWin.contentItem, 0, 0);
                        trayMenu.anchor.rect = Qt.rect(p.x, p.y, tray.width, tray.height);
                        trayMenu.open();
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 20; height: 20
                        source: tray.modelData.icon
                        sourceSize: Qt.size(40, 40)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        opacity: trayMouse.containsMouse ? 1 : 0.85
                    }
                    QsMenuAnchor {
                        id: trayMenu
                        menu: tray.modelData.menu
                        anchor.window: tray.hostWin
                        anchor.edges: Edges.Bottom | Edges.Left
                        anchor.gravity: Edges.Bottom | Edges.Right
                        // keep the island expanded while a tray menu is open
                        onVisibleChanged: root.trayMenus = Math.max(0, root.trayMenus + (visible ? 1 : -1))
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

        WifiBadge { id: wifiBadge; compact: true; anchors.verticalCenter: parent.verticalCenter }
        Item {   // battery, drawn 18% larger (scale doesn't affect layout, so size the wrapper)
            visible: UPower.displayDevice.isPresent
            width: 33 * 1.18; height: 15 * 1.18
            anchors.verticalCenter: parent.verticalCenter
            Battery { id: batt; scale: 1.18; transformOrigin: Item.TopLeft }
        }
    }

    // Icon button drawn with Canvas (no icon font dependency)
    component IconBtn: Item {
        id: btn
        property string kind: "play"   // play | pause | prev | next
        property bool filled: false    // Material filled-tonal style
        property bool enabledBtn: true
        signal clicked()
        width: filled ? 44 : 36
        height: width
        opacity: enabledBtn ? 1 : 0.35

        onKindChanged: cv.requestPaint()

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: btn.filled ? root.accent : (ma.containsMouse ? Theme.hover : "transparent")
            Behavior on color { ColorAnimation { duration: 120 } }
            scale: ma.pressed ? 0.92 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
        }
        Canvas {
            id: cv
            Connections { target: Theme; function onCurrentChanged() { cv.requestPaint() } }
            anchors.centerIn: parent
            width: 20; height: 20
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.fillStyle = btn.filled ? Theme.onAccent : root.onSurface;
                if (btn.kind === "play") {
                    c.beginPath(); c.moveTo(5, 3); c.lineTo(17, 10); c.lineTo(5, 17); c.closePath(); c.fill();
                } else if (btn.kind === "pause") {
                    c.fillRect(4, 3, 4, 14); c.fillRect(12, 3, 4, 14);
                } else if (btn.kind === "prev") {
                    c.fillRect(3, 3, 2.5, 14);
                    c.beginPath(); c.moveTo(17, 3); c.lineTo(7, 10); c.lineTo(17, 17); c.closePath(); c.fill();
                } else {
                    c.fillRect(14.5, 3, 2.5, 14);
                    c.beginPath(); c.moveTo(3, 3); c.lineTo(13, 10); c.lineTo(3, 17); c.closePath(); c.fill();
                }
            }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.enabledBtn
            onClicked: btn.clicked()
        }
    }

    // Compact slider row: icon | track | percent
    component SliderRow: Item {
        id: sr
        property string kind: "volume"   // volume | brightness
        property real value: 0           // 0..1
        property bool available: true
        property bool dragging: false
        property real dragValue: 0
        readonly property real shown: dragging ? dragValue : value
        signal moved(real v)
        implicitHeight: 20
        opacity: available ? 1 : 0.35

        Canvas {
            id: ic
            Connections { target: Theme; function onCurrentChanged() { ic.requestPaint() } }
            width: 16; height: 16
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            antialiasing: true
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.fillStyle = root.onSurface;
                c.strokeStyle = root.onSurface;
                c.lineWidth = 1.5;
                c.lineCap = "round";
                if (sr.kind === "volume") {
                    c.beginPath();
                    c.moveTo(1, 6); c.lineTo(4, 6); c.lineTo(8, 2);
                    c.lineTo(8, 14); c.lineTo(4, 10); c.lineTo(1, 10);
                    c.closePath(); c.fill();
                    c.beginPath(); c.arc(8, 8, 4, -Math.PI / 3, Math.PI / 3); c.stroke();
                    c.beginPath(); c.arc(8, 8, 7, -Math.PI / 3, Math.PI / 3); c.stroke();
                } else {
                    c.beginPath(); c.arc(8, 8, 3, 0, 2 * Math.PI); c.fill();
                    for (let i = 0; i < 8; i++) {
                        const a = i * Math.PI / 4;
                        c.beginPath();
                        c.moveTo(8 + Math.cos(a) * 5.2, 8 + Math.sin(a) * 5.2);
                        c.lineTo(8 + Math.cos(a) * 7.2, 8 + Math.sin(a) * 7.2);
                        c.stroke();
                    }
                }
            }
        }

        Item {
            id: area
            anchors.left: ic.right; anchors.leftMargin: 10
            anchors.right: pct.left; anchors.rightMargin: 10
            height: parent.height

            Rectangle {
                id: strack
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 4; radius: 2
                color: Qt.alpha(Theme.foreground, 0.2)
                Rectangle {
                    width: parent.width * sr.shown
                    height: parent.height; radius: 2
                    color: root.accent
                }
            }
            Rectangle {
                x: strack.width * sr.shown - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: sma2.pressed ? 14 : 10; height: width; radius: width / 2
                color: root.accent
                Behavior on width { NumberAnimation { duration: 100 } }
            }
            MouseArea {
                id: sma2
                anchors.fill: parent
                enabled: sr.available
                function setFrom(mx) {
                    sr.dragValue = Math.max(0, Math.min(1, mx / width));
                    sr.moved(sr.dragValue);
                }
                onPressed: (e) => { sr.dragging = true; setFrom(e.x); }
                onPositionChanged: (e) => { if (pressed) setFrom(e.x); }
                onReleased: sr.dragging = false
                onCanceled: sr.dragging = false
                onWheel: (w) => {
                    sr.dragValue = Math.max(0, Math.min(1, sr.shown + (w.angleDelta.y > 0 ? 0.05 : -0.05)));
                    sr.moved(sr.dragValue);
                }
            }
        }

        Text {
            id: pct
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            horizontalAlignment: Text.AlignRight
            text: Math.round(sr.shown * 100)
            color: root.onSurfaceDim
            font.pixelSize: 10
        }
    }

    // macOS-style battery with percentage centered inside
    component Battery: Item {
        id: bat
        readonly property var dev: UPower.displayDevice
        readonly property int pct: Math.round(dev.percentage * 100)
        readonly property bool charging: dev.state === UPowerDeviceState.Charging
                                      || dev.state === UPowerDeviceState.FullyCharged
        readonly property color fillColor: charging ? Theme.success : pct <= 20 ? Theme.error : Theme.accent

        visible: dev.isPresent
        width: 33; height: 15

        // Body outline
        Rectangle {
            id: body
            width: 30; height: parent.height
            radius: 4
            color: Qt.alpha(Theme.accent, 0.22)   // faint empty-track instead of a stroke

            // White number, visible over the empty part
            Text {
                anchors.centerIn: parent
                text: bat.pct
                color: Theme.foreground
                font.pixelSize: 10
                font.weight: Font.Bold
            }

            // Fill
            Item {
                x: 0; y: 0
                width: Math.max(0, body.width * bat.pct / 100)
                height: body.height
                clip: true

                Rectangle {
                    width: body.width
                    height: body.height
                    radius: body.radius
                    color: bat.fillColor
                }
                // Dark number, visible only over the fill
                Text {
                    x: (body.width - width) / 2
                    y: (parent.height - height) / 2
                    text: bat.pct
                    color: Theme.onAccent
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
            }
        }

        // Terminal nub
        Rectangle {
            x: 31; anchors.verticalCenter: parent.verticalCenter
            width: 2.5; height: 6
            radius: 1
            color: Qt.alpha(Theme.foreground, 0.4)
        }
    }

    // ===== Fully open: control-center layout =====
    Item {
        id: ctrl
        anchors.fill: parent
        anchors.margins: 16
        anchors.topMargin: barH + 8
        opacity: root.mediaOpen ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220 } }

        // Wi-Fi + Bluetooth tiles
        QuickTile {
            x: 0; y: 0
            width: 196; height: 58
            kind: "wifi"
            title: "Wi-Fi"
            subtitle: wifiBadge.connected ? (wifiBadge.ssid || "Connected") : "Not connected"
            active: wifiBadge.connected
            onClicked: Quickshell.execDetached(["nmcli", "radio", "wifi", wifiBadge.connected ? "off" : "on"])
        }
        QuickTile {
            x: 0; y: 66
            width: 196; height: 58
            kind: "bluetooth"
            title: "Bluetooth"
            subtitle: root.btSub
            active: root.btOn
            onClicked: { if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled; }
        }

        // Media card: darkened, blurred cover as backdrop
        Rectangle {
            id: mediaCard
            x: 206; y: 0
            width: parent.width - 206
            height: 124
            radius: 24
            color: Theme.surface

            Image {
                id: coverBg
                anchors.fill: parent
                source: root.player ? root.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
                layer.enabled: true
            }
            Rectangle {
                id: coverMask
                anchors.fill: parent
                radius: 24
                visible: false
                layer.enabled: true
            }
            MultiEffect {
                anchors.fill: parent
                source: coverBg
                maskEnabled: true
                maskSource: coverMask
                blurEnabled: true
                blur: 0.7
                blurMax: 32
                brightness: -0.4
                visible: coverBg.status === Image.Ready
            }
            Text {
                x: 16; y: 13
                width: parent.width - 32
                text: root.player && root.player.trackTitle ? root.player.trackTitle : "Nothing playing"
                color: coverBg.status === Image.Ready ? "#ffffff" : root.onSurface
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                x: 16; y: 33
                width: parent.width - 32
                text: root.player ? (root.player.trackArtist || "") : ""
                color: coverBg.status === Image.Ready ? Qt.alpha("#ffffff", 0.75) : root.onSurfaceDim
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - height - 10
                spacing: 8
                IconBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "prev"
                    enabledBtn: root.player && root.player.canGoPrevious
                    onClicked: root.player.previous()
                }
                IconBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    filled: true
                    kind: root.playing ? "pause" : "play"
                    enabledBtn: root.player && root.player.canTogglePlaying
                    onClicked: root.player.togglePlaying()
                }
                IconBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "next"
                    enabledBtn: root.player && root.player.canGoNext
                    onClicked: root.player.next()
                }
            }
        }

        // Display (brightness) and Sound (volume)
        PillSlider {
            x: 0; y: 132
            width: parent.width; height: 72
            label: "Display"
            available: root.brAvail
            value: root.brMax > 0 ? root.brVal / root.brMax : 0
            onMoved: (v) => root.setBrightness(Math.round(v * root.brMax))
        }
        PillSlider {
            x: 0; y: 212
            width: parent.width; height: 72
            label: "Sound"
            available: root.sink && root.sink.audio
            value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
            onMoved: (v) => { if (root.sink && root.sink.audio) root.sink.audio.volume = v; }
        }

        // Notifications
        Rectangle {
            x: 0; y: 292
            width: parent.width; height: 120
            radius: 24
            color: Theme.surface

            Text {
                x: 18; y: 11
                text: "Notifications"
                color: root.onSurfaceDim
                font.pixelSize: 12
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 18
                y: 11
                visible: root.notifCount > 0
                text: "Clear all"
                color: root.accent
                font.pixelSize: 12
                font.weight: Font.Medium
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.notifService.dismissAll()
                }
            }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 8
                visible: root.notifCount === 0
                text: "No new notifications"
                color: Qt.alpha(Theme.foreground, 0.4)
                font.pixelSize: 12
            }
            ListView {
                x: 8; y: 34
                width: parent.width - 16
                height: parent.height - 42
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel { values: root.notifService ? root.notifService.list.values.slice().reverse() : [] }

                delegate: Rectangle {
                    id: nrow
                    required property var modelData
                    readonly property string iconSrc: modelData.appIcon
                        ? (modelData.appIcon.startsWith("/") ? "file://" + modelData.appIcon : Quickshell.iconPath(modelData.appIcon, true))
                        : ""
                    width: ListView.view.width
                    height: 60
                    radius: 18
                    color: Theme.surfaceAlt

                    Item {
                        id: nicon
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26; height: 26
                        Rectangle {
                            anchors.centerIn: parent
                            visible: nrow.iconSrc === ""
                            width: 12; height: 12; radius: 6
                            color: root.accent
                        }
                        Image {
                            anchors.fill: parent
                            visible: nrow.iconSrc !== ""
                            source: nrow.iconSrc
                            sourceSize: Qt.size(52, 52)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                    }
                    Column {
                        anchors.left: nicon.right
                        anchors.leftMargin: 11
                        anchors.right: parent.right
                        anchors.rightMargin: 36
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Text {
                            width: parent.width
                            text: nrow.modelData.appName
                            color: root.onSurfaceDim
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: nrow.modelData.summary
                            color: root.onSurface
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: text.length > 0
                            text: nrow.modelData.body.replace(/<[^>]*>/g, "").replace(/\n/g, " ")
                            color: root.onSurfaceDim
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                    Text {   // dismiss
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "×"
                        color: root.onSurfaceDim
                        font.pixelSize: 16
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: nrow.modelData.dismiss()
                    }
                }
            }
        }
    }
}
