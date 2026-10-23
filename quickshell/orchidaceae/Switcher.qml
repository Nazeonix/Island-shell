import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Windows 98 / XP style Alt-Tab switcher: a retro dialog with a row of window icons.
//   qs -c orchidaceae ipc call switcher next | prev | commit | cancel | look 98|xp
// Hold the modifier, press Tab to cycle; releasing Alt/Super picks the window.
// Also: arrows, Enter, Esc, mouse click. Works on Hyprland and niri (foreign-toplevel).
Scope {
    id: root

    property string look: "98"          // "98" | "xp"
    property bool open: false
    property int sel: 0
    property var items: []              // snapshot of toplevels while open, most recent first
    property var history: []            // focus history, most recent first

    readonly property var w98: ({
        face: "#c0c0c0", hi: "#ffffff", hi2: "#dfdfdf", shadow: "#808080", dark: "#000000",
        text: "#000000", titleA: "#000080", titleB: "#1084d0", titleText: "#ffffff", sel: "#000080"
    })
    readonly property var xp: ({
        face: "#ece9d8", frame: "#0831d9", titleA: "#0058ee", titleB: "#3d95ff",
        titleText: "#ffffff", text: "#000000", sel: "#316ac5", edge: "#aca899"
    })
    readonly property var cur: look === "xp" ? xp : w98
    readonly property bool isXp: look === "xp"

    // ---- focus history (foreign-toplevel gives no MRU order itself) -------
    function touch(t) { history = [t].concat(history.filter(x => x !== t)) }

    Instantiator {
        model: ToplevelManager.toplevels
        delegate: QtObject {
            required property var modelData
            readonly property bool act: modelData.activated
            onActChanged: if (act) root.touch(modelData)
            Component.onCompleted: if (act) root.touch(modelData)
        }
    }

    function snapshot() {
        const v = ToplevelManager.toplevels.values;
        const live = [];
        for (let i = 0; i < v.length; i++) live.push({ t: v[i], rank: 0 });
        for (let i = 0; i < live.length; i++) {
            const r = history.indexOf(live[i].t);
            live[i].rank = r >= 0 ? r : 1000 + i;
        }
        live.sort((a, b) => a.rank - b.rank);
        return live.map(x => x.t);
    }

    function iconFor(t) {
        if (!t) return "";
        const id = t.appId || "";
        if (id === "") return "";
        const e = DesktopEntries.heuristicLookup(id);
        return Quickshell.iconPath(e && e.icon ? e.icon : id.toLowerCase(), true);
    }

    // ---- actions ---------------------------------------------------------
    function show(dir) {
        if (!open) {
            items = snapshot();
            if (items.length === 0) return;
            sel = items.length > 1 ? (dir > 0 ? 1 : items.length - 1) : 0;
            open = true;
        } else {
            sel = (sel + dir + items.length) % items.length;
        }
    }
    function commit() {
        if (!open) return;
        const t = items[sel];
        open = false;
        if (t) t.activate();
    }
    function cancel() { open = false }

    IpcHandler {
        target: "switcher"
        function next(): void { root.show(1) }
        function prev(): void { root.show(-1) }
        function commit(): void { root.commit() }
        function cancel(): void { root.cancel() }
        function look(name: string): void { if (name === "98" || name === "xp") root.look = name }
    }

    // ---- 98 bevel (decor only; content goes on top, inset 2px) -----------
    component Bevel: Rectangle {
        id: bv
        property bool sunken: false
        property var pal: root.w98
        color: sunken ? pal.hi : pal.dark
        Rectangle {
            anchors { fill: parent; rightMargin: 1; bottomMargin: 1 }
            color: bv.sunken ? bv.pal.shadow : bv.pal.hi
            Rectangle {
                anchors { fill: parent; leftMargin: 1; topMargin: 1 }
                color: bv.sunken ? bv.pal.hi2 : bv.pal.shadow
                Rectangle {
                    anchors { fill: parent; rightMargin: 1; bottomMargin: 1 }
                    color: bv.sunken ? bv.pal.dark : bv.pal.hi2
                    Rectangle {
                        anchors { fill: parent; leftMargin: 1; topMargin: 1 }
                        color: bv.pal.face
                    }
                }
            }
        }
    }

    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: root.open
        focusable: true
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-switcher"

        onVisibleChanged: if (visible) Qt.callLater(() => keys.forceActiveFocus())

        MouseArea { anchors.fill: parent; onClicked: root.cancel() }   // click outside = cancel

        Item {
            id: keys
            focus: true
            Keys.onPressed: event => {
                const k = event.key;
                if (k === Qt.Key_Tab)            root.show((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                else if (k === Qt.Key_Backtab)   root.show(-1);
                else if (k === Qt.Key_Right)     root.show(1);
                else if (k === Qt.Key_Left)      root.show(-1);
                else if (k === Qt.Key_Down)      root.sel = Math.min(root.items.length - 1, root.sel + frame.cols);
                else if (k === Qt.Key_Up)        root.sel = Math.max(0, root.sel - frame.cols);
                else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.commit();
                else if (k === Qt.Key_Escape)    root.cancel();
                else return;
                event.accepted = true;
            }
            Keys.onReleased: event => {
                // releasing the modifier that opened the switcher picks the window
                if ([Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R].indexOf(event.key) >= 0) {
                    root.commit();
                    event.accepted = true;
                }
            }
        }

        Item {
            id: frame
            readonly property int cell: 64
            readonly property int gap: 4
            readonly property int cols: Math.max(1, Math.min(8, root.items.length))
            readonly property int gridW: Math.max(cols, 4) * cell + (Math.max(cols, 4) - 1) * gap
            readonly property int titleH: root.isXp ? 26 : 20
            readonly property int m: 3
            readonly property string ui: "Tahoma"

            anchors.centerIn: parent
            width: col.implicitWidth + m * 2
            height: col.implicitHeight + m * 2

            // ---- window frame ----
            Bevel { anchors.fill: parent; visible: !root.isXp }
            Rectangle {
                anchors.fill: parent
                visible: root.isXp
                radius: 8
                color: root.xp.frame
                Rectangle {
                    anchors { fill: parent; leftMargin: 3; rightMargin: 3; bottomMargin: 3; topMargin: frame.titleH }
                    color: root.xp.face
                }
            }

            ColumnLayout {
                id: col
                anchors { fill: parent; margins: frame.m }
                spacing: 0

                // ---- title bar ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.isXp ? frame.titleH - frame.m : 18
                    radius: root.isXp ? 6 : 0
                    gradient: Gradient {
                        orientation: root.isXp ? Gradient.Vertical : Gradient.Horizontal
                        GradientStop { position: 0; color: root.cur.titleA }
                        GradientStop { position: 1; color: root.cur.titleB }
                    }

                    Text {
                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                        text: "Switch Windows"
                        color: root.cur.titleText
                        renderType: Text.NativeRendering
                        font { family: frame.ui; pixelSize: 12; bold: true }
                    }

                    // close button (decor + cancel)
                    Item {
                        anchors { right: parent.right; rightMargin: 2; verticalCenter: parent.verticalCenter }
                        width: root.isXp ? 21 : 16
                        height: root.isXp ? 21 : 14
                        Bevel { anchors.fill: parent; visible: !root.isXp }
                        Rectangle {
                            anchors.fill: parent
                            visible: root.isXp
                            radius: 3
                            color: "#d6482f"
                            border { width: 1; color: "#ffffff" }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: root.isXp ? "#ffffff" : root.w98.text
                            renderType: Text.NativeRendering
                            font { family: frame.ui; pixelSize: 13; bold: true }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.cancel() }
                    }
                }

                // ---- body ----
                ColumnLayout {
                    Layout.margins: 10
                    spacing: 8

                    GridLayout {
                        Layout.alignment: Qt.AlignHCenter
                        columns: frame.cols
                        rowSpacing: frame.gap
                        columnSpacing: frame.gap

                        Repeater {
                            model: root.items
                            delegate: Item {
                                id: cellItem
                                required property var modelData
                                required property int index
                                readonly property bool current: index === root.sel
                                readonly property string iconSrc: root.iconFor(modelData)
                                implicitWidth: frame.cell
                                implicitHeight: frame.cell

                                // selection frame
                                Rectangle {
                                    anchors { fill: parent; margins: 2 }
                                    visible: cellItem.current
                                    color: root.isXp ? Qt.rgba(0.19, 0.42, 0.77, 0.18) : "transparent"
                                    radius: root.isXp ? 4 : 0
                                    border { width: root.isXp ? 2 : 2; color: root.cur.sel }
                                }
                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: 32
                                    source: cellItem.iconSrc
                                    visible: cellItem.iconSrc !== ""
                                }
                                Text {   // no icon found: first letter
                                    anchors.centerIn: parent
                                    visible: cellItem.iconSrc === ""
                                    text: (cellItem.modelData.appId || "?").charAt(0).toUpperCase()
                                    color: root.cur.text
                                    renderType: Text.NativeRendering
                                    font { family: frame.ui; pixelSize: 22; bold: true }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onPositionChanged: root.sel = cellItem.index
                                    onClicked: { root.sel = cellItem.index; root.commit() }
                                }
                            }
                        }
                    }

                    // title of the selected window
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredWidth: frame.gridW
                        Layout.preferredHeight: 22
                        Bevel { anchors.fill: parent; sunken: true; visible: !root.isXp; pal: root.w98 }
                        Rectangle {
                            anchors.fill: parent
                            visible: root.isXp
                            color: "#ffffff"
                            border { width: 1; color: root.xp.edge }
                        }
                        Text {
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: root.items[root.sel] ? root.items[root.sel].title : ""
                            color: root.cur.text
                            renderType: Text.NativeRendering
                            font { family: frame.ui; pixelSize: 12 }
                        }
                    }
                }
            }
        }
    }
}
