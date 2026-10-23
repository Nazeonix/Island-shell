import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

// Pixel-art title bar drawn above every visible window (Hyprland), in your Theme colours:
// app icon + title + minimise / maximise / close. Hard 2px outline, notched corners, no AA.
//   qs -c orchidaceae ipc call winbar toggle | restore
// The bar sits directly ABOVE the window, so keep >= bar height of gap there.
// Geometry is polled, so it can lag a little while windows animate.
Scope {
    id: root

    readonly property bool enabled: BarCtl.winbarEnabled   // toggled from Settings / IPC
    property int pollMs: 150
    // no title bar for windows whose class starts with one of these (case-insensitive)
    property var ignoreClasses: [ "steam" ]                                   // also covers steam_app_* games and steamwebhelper
    //     "firefox", "org.mozilla.firefox", "librewolf", "floorp", "zen", "helium",
    //     "chromium", "google-chrome", "brave", "vivaldi",
    //     "vesktop", "equibop", "goofcord", "discord"
    
    property string fontName: Theme.fontFamily           // set a pixel font here (e.g. "Terminus", "Silkscreen")
    readonly property int h: 26
    readonly property string minWs: "minimized"      // special workspace used for "minimise"

    // a title bar is currently drawn (visible, non-fullscreen, non-ignored window on an active workspace)
    readonly property bool needSpace: {
        const list = Hyprland.toplevels.values;
        for (let i = 0; i < list.length; i++) {
            const o = list[i], oi = o.lastIpcObject;
            if (!oi || !oi.at || !oi.size || oi.mapped === false || oi.hidden || oi.fullscreen) continue;
            if (!o.workspace || !o.workspace.active || ignored(oi.class)) continue;
            return true;
        }
        return false;
    }

    // reserve room under the shell bar so title bars never overlap it (none when only ignored apps are shown)
    Binding { target: BarCtl; property: "winbarSpace"; value: root.enabled && root.needSpace ? root.h : 0 }

    // 7x7 pixel glyphs, drawn 2px per cell
    readonly property var gMin:   [".......", ".......", ".......", ".......", ".......", ".......", "#######"]
    readonly property var gMax:   ["#######", "#######", "#.....#", "#.....#", "#.....#", "#.....#", "#######"]
    readonly property var gClose: ["##...##", ".##.##.", "..###..", "...#...", "..###..", ".##.##.", "##...##"]

    // ---- actions (change the dispatcher strings here to remap buttons) ----
    function focusWin(t) { if (t.wayland) t.wayland.activate() }
    function later(fn) { pending = fn; actTimer.restart() }       // let activation land first
    property var pending: null
    Timer { id: actTimer; interval: 70; onTriggered: if (root.pending) { root.pending(); root.pending = null } }

    function close(t)    { if (t.wayland) t.wayland.close() }
    function maximize(t) { focusWin(t); later(() => Hyprland.dispatch('hl.dsp.window.fullscreen({ action = "toggle" })')) }
    function minimize(t) {
        focusWin(t);
        const inMin = t.workspace && t.workspace.name === "special:" + minWs;
        if (inMin) {
            const id = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1;
            later(() => {
                Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + id + ' })');
                Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + minWs + '")');
            });
        } else {
            later(() => Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:' + minWs + '" })'));
        }
    }
    function restore() { Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + minWs + '")') }

    function ignored(cls) {
        const c = (cls || "").toLowerCase();
        return ignoreClasses.some(p => c.startsWith(p.toLowerCase()));
    }

    // is window a drawn above window b? floating beats tiled; among floating, most recently focused wins
    function higher(a, b) {
        if (!!a.floating !== !!b.floating) return !!a.floating;
        if (!a.floating) return false;
        return a.focusHistoryID < b.focusHistoryID;
    }

    // Largest part of [x0, x1] (global x) of `self`'s bar that is not covered by a window (or the
    // bar of a window) stacked above it. Layer-shell bars can't interleave with windows, so
    // covered parts are cut off instead. Returns [a, b] or null.
    function freeSpan(self, x0, x1, gy) {
        const list = Hyprland.toplevels.values;
        const si = self.lastIpcObject;
        let segs = [[x0, x1]];
        for (let i = 0; i < list.length; i++) {
            const o = list[i];
            if (o === self) continue;
            const oi = o.lastIpcObject;
            if (!oi || !oi.at || !oi.size || oi.mapped === false || oi.hidden) continue;
            if (!o.workspace || !self.workspace || o.workspace.id !== self.workspace.id) continue;
            if (!higher(oi, si)) continue;
            const oy = oi.at[1];
            const top = oy - (ignored(oi.class) ? 0 : h);       // its bar sits above it
            const bottom = oy + oi.size[1];
            if (!(top < gy && bottom > gy - h)) continue;       // no vertical overlap with our bar
            const ox0 = oi.at[0], ox1 = oi.at[0] + oi.size[0];
            const next = [];
            for (const sg of segs) {
                if (ox1 <= sg[0] || ox0 >= sg[1]) { next.push(sg); continue; }
                if (ox0 - sg[0] > 0) next.push([sg[0], ox0]);
                if (sg[1] - ox1 > 0) next.push([ox1, sg[1]]);
            }
            segs = next;
        }
        let best = null;
        for (const sg of segs) if (!best || sg[1] - sg[0] > best[1] - best[0]) best = sg;
        return best;
    }

    function iconFor(cls) {
        if (!cls) return "";
        const e = DesktopEntries.heuristicLookup(cls);
        return Quickshell.iconPath(e && e.icon ? e.icon : cls.toLowerCase(), true);
    }
    function screenFor(name) {
        const s = Quickshell.screens;
        for (let i = 0; i < s.length; i++) if (s[i].name === name) return s[i];
        return null;
    }

    IpcHandler {
        target: "winbar"
        function toggle(): void { BarCtl.winbarEnabled = !BarCtl.winbarEnabled }
        function restore(): void { root.restore() }
    }

    // window geometry is not pushed on every layout change, so poll it
    Timer { interval: root.pollMs; repeat: true; running: root.enabled; onTriggered: Hyprland.refreshToplevels() }

    // box with 2px outline and notched (stepped) corners
    component PixelBox: Item {
        id: pb
        property color line: Theme.foreground
        property color fill: Theme.background
        property bool squareBottom: false
        readonly property int t: 2          // outline thickness
        readonly property int n: 2          // corner notch
        Rectangle { x: pb.n; y: 0; width: pb.width - pb.n * 2; height: pb.height; color: pb.line }
        Rectangle { x: 0; y: pb.n; width: pb.width; height: pb.squareBottom ? pb.height - pb.n : pb.height - pb.n * 2; color: pb.line }
        Rectangle { x: pb.n + pb.t; y: pb.t; width: pb.width - (pb.n + pb.t) * 2; height: pb.height - pb.t * 2; color: pb.fill }
        Rectangle {
            x: pb.t; y: pb.n + pb.t; width: pb.width - pb.t * 2
            height: pb.squareBottom ? pb.height - pb.n - pb.t * 2 : pb.height - pb.n * 2 - pb.t * 2
            color: pb.fill
        }
    }

    // caption button with a pixel glyph
    component CapBtn: Item {
        id: cb
        property var glyph
        property bool danger: false
        signal clicked()
        width: 20
        height: 20
        readonly property color ink: (ma.pressed || danger) ? Theme.background : Theme.foreground

        PixelBox {
            anchors.fill: parent
            fill: ma.pressed ? Theme.accent : (cb.danger ? Theme.alert : Theme.background)
        }
        Item {
            anchors.centerIn: parent
            width: 14
            height: 14
            Repeater {
                model: 49
                delegate: Rectangle {
                    required property int index
                    x: (index % 7) * 2
                    y: Math.floor(index / 7) * 2
                    width: 2
                    height: 2
                    color: cb.ink
                    visible: cb.glyph[Math.floor(index / 7)].charAt(index % 7) === "#"
                }
            }
        }
        MouseArea { id: ma; anchors.fill: parent; onClicked: cb.clicked() }
    }

    Instantiator {
        model: Hyprland.toplevels

        delegate: PanelWindow {
            id: bar
            required property var modelData
            readonly property var t: modelData
            readonly property var ipc: t.lastIpcObject
            readonly property var mon: t.monitor
            readonly property var monIpc: mon ? mon.lastIpcObject : null
            readonly property bool live: !!ipc && !!ipc.at && !!ipc.size && ipc.mapped !== false && !ipc.hidden
            readonly property bool focused: t.activated

            // visible part of the window on its monitor: columns scrolled partly/fully off-screen
            // must not keep a full-width bar clamped to the edge (that is what stacked them)
            readonly property real monW: monIpc && monIpc.scale ? monIpc.width / monIpc.scale : 100000
            readonly property real wx: live ? ipc.at[0] - (monIpc ? monIpc.x : 0) : 0
            readonly property real ww: live ? ipc.size[0] : 0
            readonly property real vx0: Math.max(0, wx)
            readonly property real vx1: Math.min(monW, wx + ww)
            readonly property real monX: monIpc ? monIpc.x : 0
            readonly property var span: live ? root.freeSpan(t, vx0 + monX, vx1 + monX, ipc.at[1]) : null
            readonly property real fx0: span ? span[0] - monX : 0
            readonly property real vw: span ? span[1] - span[0] : 0
            readonly property color fillColor: focused ? Theme.accent : Theme.mix(Theme.background, Theme.foreground, 0.14)
            readonly property color stripeColor: focused ? Theme.mix(Theme.accent, Theme.background, 0.3)
                                                         : Theme.mix(fillColor, Theme.foreground, 0.1)
            readonly property color inkColor: focused ? Theme.background : Theme.foreground

            screen: root.screenFor(mon ? mon.name : "")
            visible: root.enabled && live && !ipc.fullscreen && !!mon
                     && !!t.workspace && t.workspace.active && !!span && vw >= 90
                     && !root.ignored(ipc.class)
            anchors { top: true; left: true }
            margins {
                left: live ? Math.round(fx0) : 0
                top: live ? Math.max(0, Math.round(ipc.at[1] - (monIpc ? monIpc.y : 0)) - root.h) : 0
            }
            implicitWidth: live ? Math.max(1, Math.round(vw)) : 80
            implicitHeight: root.h
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-winbar"

            PixelBox { anchors.fill: parent; fill: bar.fillColor; squareBottom: true }

            Item {
                anchors { fill: parent; leftMargin: 8; rightMargin: 4; topMargin: 2; bottomMargin: 2 }

                IconImage {
                    id: icon
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    implicitSize: 16
                    source: root.iconFor(bar.ipc ? bar.ipc.class : "")
                }

                // Mac-OS-8-style pinstripes behind the title
                Item {
                    id: stripes
                    anchors {
                        left: icon.right; leftMargin: 6
                        right: btns.left; rightMargin: 6
                        top: parent.top; bottom: parent.bottom
                    }
                    clip: true
                    Repeater {
                        model: 5
                        delegate: Rectangle {
                            required property int index
                            y: 2 + index * 4
                            width: stripes.width
                            height: 2
                            color: bar.stripeColor
                        }
                    }
                    Rectangle {                     // plate keeps the title readable
                        width: Math.min(titleText.implicitWidth + 12, stripes.width)
                        height: parent.height
                        color: bar.fillColor
                        Text {
                            id: titleText
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: bar.t.title
                            color: bar.inkColor
                            renderType: Text.NativeRendering
                            font { family: root.fontName; pixelSize: 12; bold: true; hintingPreference: Font.PreferFullHinting }
                        }
                    }
                }
                MouseArea {                         // click = focus, double click = maximise
                    anchors { left: parent.left; right: btns.left; top: parent.top; bottom: parent.bottom }
                    onPressed: root.focusWin(bar.t)
                    onDoubleClicked: root.maximize(bar.t)
                }
                Row {
                    id: btns
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    CapBtn { glyph: root.gMin; onClicked: root.minimize(bar.t) }
                    CapBtn { glyph: root.gMax; onClicked: root.maximize(bar.t) }
                    CapBtn { glyph: root.gClose; danger: true; onClicked: root.close(bar.t) }
                }
            }
        }
    }
}
