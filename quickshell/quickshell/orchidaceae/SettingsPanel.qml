pragma Singleton
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Settings card. Open: gear icon in the bar, or `qs ipc call settings toggle | open | close`.
// Theme, bar visibility and DND persist already; wallpaper slideshow settings reset on reload.
Singleton {
    id: root
    property bool open: false
    function toggle() { open = !open }
    function close() { open = false }

    IpcHandler {
        target: "settings"
        function toggle(): void { root.toggle() }
        function open(): void { root.open = true }
        function close(): void { root.close() }
    }

    // ---- building blocks (hard 2px outline, no shadows/gradients) ----------
    component Btn: Rectangle {
        id: b
        property string text
        property bool on: false
        property bool danger: false
        signal clicked()
        implicitWidth: lbl.implicitWidth + 24
        implicitHeight: 30
        radius: 8
        color: on ? Theme.accent
             : ma.containsMouse ? (danger ? Theme.alert : Theme.foreground) : "transparent"
        border { width: 2; color: Theme.foreground }
        Text {
            id: lbl
            anchors.centerIn: parent
            text: b.text
            color: (b.on || ma.containsMouse) ? Theme.background : Theme.foreground
            font { family: Theme.fontFamily; pixelSize: 11; bold: true; capitalization: Font.AllUppercase }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }

    component Heading: Text {
        color: Theme.muted
        font { family: Theme.fontFamily; pixelSize: 11; bold: true; capitalization: Font.AllUppercase; letterSpacing: 0.5 }
    }

    // label on the left, controls (children) on the right
    component Setting: RowLayout {
        id: s
        property string label
        default property alias content: slot.data
        Layout.fillWidth: true
        spacing: 12
        Text {
            Layout.preferredWidth: 150
            text: s.label
            color: Theme.foreground
            font { family: Theme.fontFamily; pixelSize: 13 }
        }
        Row { id: slot; spacing: 8 }
        Item { Layout.fillWidth: true }
    }

    component Rule: Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

    // ---- window ------------------------------------------------------------
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: root.open || card.opacity > 0.01
        focusable: true
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-settings"

        onVisibleChanged: if (visible) Qt.callLater(() => keys.forceActiveFocus())

        // click outside to dismiss (no dimming)
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(700, parent.width - 80)
            height: Math.min(col.implicitHeight + 44, parent.height - 80)
            radius: 16
            color: Theme.background
            border { width: 2; color: Theme.foreground }
            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.97
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }   // block clicks to the backdrop

            Item {
                id: keys
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) { event.accepted = true; root.close() }
                }
            }

            ColumnLayout {
                id: col
                anchors { fill: parent; margins: 22 }
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: "Settings"
                        color: Theme.foreground
                        font { family: Theme.fontFamily; pixelSize: 18; bold: true; capitalization: Font.AllUppercase }
                    }
                    Btn { text: "Close"; onClicked: root.close() }
                }
                Rule {}

                // ---- appearance ----
                Heading { text: "Appearance" }
                Setting {
                    label: "Theme"
                    Repeater {
                        model: Theme.families.slice(0, 4)
                        delegate: Btn {
                            required property string modelData
                            text: modelData
                            on: Theme.family === modelData
                            onClicked: Theme.setTheme(modelData, Theme.variant)
                        }
                    }
                }
                Setting {
                    label: ""
                    Repeater {
                        model: Theme.families.slice(4, 8)
                        delegate: Btn {
                            required property string modelData
                            text: modelData
                            on: Theme.family === modelData
                            onClicked: Theme.setTheme(modelData, Theme.variant)
                        }
                    }
                }
                Setting {
                    label: "Variant"
                    Repeater {
                        model: Theme.variants
                        delegate: Btn {
                            required property string modelData
                            text: modelData
                            on: Theme.variant === modelData
                            onClicked: Theme.setTheme(Theme.family, modelData)
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.variantLabel
                        color: Theme.muted
                        font { family: Theme.fontFamily; pixelSize: 12 }
                    }
                }
                Rule {}

                // ---- bar ----
                Heading { text: "Bar" }
                Setting {
                    label: "Auto-hide"
                    Btn { text: BarCtl.autoHide ? "On" : "Off"; on: BarCtl.autoHide; onClicked: BarCtl.toggleAuto() }
                }
                Setting {
                    label: "Hidden"
                    Btn { text: BarCtl.hidden ? "On" : "Off"; on: BarCtl.hidden; onClicked: BarCtl.toggle() }
                }
                Setting {
                    label: "Window title bars"
                    Btn { text: BarCtl.winbarEnabled ? "On" : "Off"; on: BarCtl.winbarEnabled; onClicked: BarCtl.winbarEnabled = !BarCtl.winbarEnabled }
                }
                Rule {}

                // ---- wallpaper ----
                Heading { text: "Wallpaper" }
                Setting {
                    label: "Slideshow"
                    Btn { text: Wallpaper.slideshow ? "On" : "Off"; on: Wallpaper.slideshow; onClicked: Wallpaper.slideshow = !Wallpaper.slideshow }
                }
                Setting {
                    label: "Interval"
                    Btn {
                        text: "−"
                        onClicked: { const m = Wallpaper.slideshowMinutes; Wallpaper.slideshowMinutes = m > 5 ? m - 5 : Math.max(1, m - 1) }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Wallpaper.slideshowMinutes + " min"
                        color: Theme.foreground
                        font { family: Theme.fontFamily; pixelSize: 13 }
                    }
                    Btn {
                        text: "+"
                        onClicked: { const m = Wallpaper.slideshowMinutes; Wallpaper.slideshowMinutes = Math.min(240, m >= 5 ? m + 5 : m + 1) }
                    }
                }
                Setting {
                    label: "Actions"
                    Btn { text: "Picker"; onClicked: { root.close(); Wallpaper.pickerOpen = true } }
                    Btn { text: "Random"; onClicked: Wallpaper.random() }
                    Btn { text: "Next"; onClicked: Wallpaper.next() }
                    Btn { text: "Rescan"; onClicked: Wallpaper.reload() }
                }
                Setting {
                    label: "Folder"
                    Text {
                        text: Wallpaper.dir + "  ·  " + Wallpaper.files.length + " images"
                        color: Theme.muted
                        font { family: Theme.fontFamily; pixelSize: 12 }
                    }
                }
                Rule {}

                // ---- notifications ----
                Heading { text: "Notifications" }
                Setting {
                    label: "Do not disturb"
                    Btn { text: Notifs.dnd ? "On" : "Off"; on: Notifs.dnd; onClicked: Notifs.dnd = !Notifs.dnd }
                }
                Setting {
                    label: "History"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Notifs.count + " stored"
                        color: Theme.muted
                        font { family: Theme.fontFamily; pixelSize: 12 }
                    }
                    Btn { text: "Clear"; danger: true; onClicked: Notifs.clearAll() }
                }
                Rule {}

                // ---- shell ----
                Heading { text: "Shell" }
                Setting {
                    label: "Quickshell"
                    Btn { text: "Reload"; onClicked: Quickshell.reload(true) }
                }

                Text {
                    text: "esc close"
                    color: Theme.muted
                    font { family: Theme.fontFamily; pixelSize: 12 }
                }
            }
        }
    }
}
