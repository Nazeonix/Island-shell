import QtQuick
import QtQuick.Effects
import Quickshell

// Wallpaper picker that grows out of the notch: search + a centered carousel of large thumbnails,
// random and slideshow buttons. Data and actions come from the Wallpaper singleton.
//   qs -c dynamic-island ipc call wallpaper picker      toggle (also: show / hide)
// Keys: type to filter | Left/Right, Tab, Ctrl+N/P move | Enter set | Ctrl+R random |
//       Ctrl+S slideshow on/off | Esc close | mouse wheel scrolls, click sets
NotchPanel {
    id: win
    ns: "wallpapers"
    panelW: 900
    panelH: 350

    property string query: ""
    property int index: 0

    function baseName(path) { return path.split("/").pop().replace(/\.[^.]+$/, ""); }

    readonly property var results: {
        const q = query.trim().toLowerCase();
        return q === "" ? Wallpaper.files : Wallpaper.files.filter(f => baseName(f).toLowerCase().includes(q));
    }

    function show() { Wallpaper.pickerOpen = true; }
    function hide() { Wallpaper.pickerOpen = false; }
    function move(d) {
        if (results.length === 0) return;
        index = Math.max(0, Math.min(results.length - 1, index + d));
    }
    function apply(i) {
        const f = results[i];
        if (f) Wallpaper.set(f);
    }
    function random() {
        Wallpaper.random();
        index = Math.max(0, results.indexOf(Wallpaper.current));
    }

    // The singleton owns the open flag so the `wallpaper picker` IPC works from anywhere
    Connections {
        target: Wallpaper
        function onPickerOpenChanged() { win.open = Wallpaper.pickerOpen; }
        function onFilesChanged() { if (win.open) win.index = Math.max(0, win.results.indexOf(Wallpaper.current)); }
    }
    onOpenChanged: {
        Wallpaper.pickerOpen = open;
        if (open) {
            field.text = "";
            query = "";
            Wallpaper.reload();                    // pick up new files every time it opens
            index = Math.max(0, results.indexOf(Wallpaper.current));
            Qt.callLater(() => field.forceActiveFocus());
        }
    }
    onResultsChanged: index = Math.min(index, Math.max(0, results.length - 1))

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
            x: 28
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
            selectedTextColor: Theme.onAccent
            font.pixelSize: 17
            clip: true
            onTextChanged: win.query = text

            Text {
                visible: field.text.length === 0
                text: "Search wallpapers..."
                color: Qt.alpha(Theme.foreground, 0.4)
                font.pixelSize: 17
                anchors.verticalCenter: parent.verticalCenter
            }

            Keys.onPressed: (e) => {
                const ctrl = e.modifiers & Qt.ControlModifier;
                let ok = true;
                if (e.key === Qt.Key_Escape) win.hide();
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.apply(win.index);
                else if (ctrl && e.key === Qt.Key_R) win.random();
                else if (ctrl && e.key === Qt.Key_S) Wallpaper.slideshow = !Wallpaper.slideshow;
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
            anchors.rightMargin: 28
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

    // ---- Thumbnails (focused one stays centered) ----
    ListView {
        id: carousel
        anchors.top: divider.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        height: 200
        orientation: ListView.Horizontal
        spacing: 16
        clip: true
        interactive: false
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: win.index
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width - 270) / 2
        preferredHighlightEnd: (width + 270) / 2
        highlightMoveDuration: 300
        model: ScriptModel { values: win.results }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (e) => win.move((e.angleDelta.y !== 0 ? e.angleDelta.y : e.angleDelta.x) > 0 ? -1 : 1)
        }

        delegate: Item {
            id: cell
            required property string modelData
            required property int index
            readonly property bool foc: index === win.index
            readonly property bool cur: Wallpaper.current === modelData
            width: 270
            height: ListView.view.height

            Item {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                width: 270
                height: 152
                scale: cell.foc ? 1.04 : 0.94
                opacity: cell.foc ? 1 : 0.7
                Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Rectangle { anchors.fill: parent; radius: 18; color: Theme.surface }
                Image {
                    id: thumb
                    anchors.fill: parent
                    source: Wallpaper.url(cell.modelData)
                    sourceSize: Qt.size(540, 304)       // downscaled decode keeps memory low
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                    layer.enabled: true
                }
                Rectangle {
                    id: thumbMask
                    anchors.fill: parent
                    radius: 18
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    source: thumb
                    maskEnabled: true
                    maskSource: thumbMask
                    visible: thumb.status === Image.Ready
                }
                Rectangle {   // focus ring
                    anchors.fill: parent
                    radius: 18
                    color: "transparent"
                    border.width: cell.foc ? 3 : 0
                    border.color: Theme.accent
                }
                Rectangle {   // marks the wallpaper that is set now
                    visible: cell.cur
                    x: parent.width - 26; y: 12
                    width: 14; height: 14; radius: 7
                    color: Theme.accent
                    border.width: 2
                    border.color: Theme.notch
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { win.index = cell.index; win.apply(cell.index); }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: card.y + card.height + 8
                width: parent.width - 20
                horizontalAlignment: Text.AlignHCenter
                text: win.baseName(cell.modelData)
                color: cell.foc ? Theme.foreground : Theme.foregroundMuted
                font.pixelSize: 12
                font.weight: cell.foc ? Font.Medium : Font.Normal
                elide: Text.ElideMiddle
            }
        }

        Text {
            anchors.centerIn: parent
            visible: win.results.length === 0
            horizontalAlignment: Text.AlignHCenter
            text: win.query !== "" ? "No matches" : "No images in " + Wallpaper.dir
            color: Theme.foregroundMuted
            font.pixelSize: 13
        }
    }

    // ---- Bottom bar: hints + actions ----
    Item {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 28; anchors.rightMargin: 28
        anchors.bottomMargin: 16
        height: 32

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Enter set   ·   Ctrl+R random   ·   Ctrl+S slideshow   ·   Esc close"
            color: Qt.alpha(Theme.foreground, 0.4)
            font.pixelSize: 11
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Rectangle {   // random
                width: rndText.implicitWidth + 28
                height: 32
                radius: 16
                color: rndArea.containsMouse ? Qt.lighter(Theme.surface, 1.2) : Theme.surface
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    id: rndText
                    anchors.centerIn: parent
                    text: "Random"
                    color: Theme.accent
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
                MouseArea {
                    id: rndArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.random()
                }
            }
            Rectangle {   // slideshow toggle
                width: ssText.implicitWidth + 28
                height: 32
                radius: 16
                color: Wallpaper.slideshow ? Theme.accent : (ssArea.containsMouse ? Qt.lighter(Theme.surface, 1.2) : Theme.surface)
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    id: ssText
                    anchors.centerIn: parent
                    text: Wallpaper.slideshow ? "Slideshow on" : "Slideshow off"
                    color: Wallpaper.slideshow ? Theme.onAccent : Theme.foregroundMuted
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
                MouseArea {
                    id: ssArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Wallpaper.slideshow = !Wallpaper.slideshow
                }
            }
        }
    }
}
