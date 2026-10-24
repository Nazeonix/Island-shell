import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications

// Toasts (top-right) + notification center (bell in StatusIcons toggles it).
Scope {
    id: root
    readonly property int pad: 0
    readonly property int cardW: 360

    // inline components don't see outer ids: only Theme / Notifs here
    component NotifCard: Rectangle {
        id: card
        required property var n
        property bool toast: false

        readonly property bool critical: !!n && n.urgency === NotificationUrgency.Critical
        readonly property int life: n && n.expireTimeout > 0 ? n.expireTimeout * 1000 : 6000
        readonly property string imgSrc: {
            if (!n) return "";
            if (n.image !== "") return n.image;
            if (n.appIcon === "") return "";
            return n.appIcon.startsWith("/") ? n.appIcon : Quickshell.iconPath(n.appIcon, true);
        }
        readonly property var buttons: {
            const out = [];
            if (!n) return out;
            const a = n.actions;
            for (let i = 0; i < a.length; i++) if (a[i].identifier !== "default") out.push(a[i]);
            return out;
        }

        implicitWidth: 360
        implicitHeight: col.implicitHeight + 28
        color: Theme.background
        border { width: 2; color: card.critical ? Theme.alert : Theme.foreground }

        // accent strip (alert color for critical)
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 2 }
            width: 6
            color: card.critical ? Theme.alert : Theme.accent
        }

        HoverHandler { id: hv }

        // left click: default action (+ close toast) · right click: dismiss
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => {
                if (!card.n) return;
                if (m.button === Qt.RightButton) { Notifs.drop(card.n); card.n.dismiss(); return; }
                const a = card.n.actions;
                for (let i = 0; i < a.length; i++) if (a[i].identifier === "default") { a[i].invoke(); break; }
                if (card.toast) Notifs.drop(card.n);
            }
        }

        ColumnLayout {
            id: col
            x: 22; y: 14
            width: card.width - 38
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 44; implicitHeight: 44
                    color: "transparent"
                    border { width: 2; color: Theme.foreground }
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 28
                        visible: card.imgSrc !== ""
                        source: card.imgSrc
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: card.imgSrc === ""
                        text: "\uf0f3"
                        color: card.critical ? Theme.alert : Theme.accent
                        font { family: Theme.iconFont; pixelSize: 20 }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: card.n ? card.n.appName : ""
                            elide: Text.ElideRight
                            color: card.critical ? Theme.alert : Theme.muted
                            font { family: Theme.fontFamily; pixelSize: 11; bold: true; capitalization: Font.AllUppercase }
                        }
                        Text {
                            text: "\uf00d"
                            color: Theme.muted
                            font { family: Theme.iconFont; pixelSize: 12 }
                            MouseArea {
                                anchors { fill: parent; margins: -6 }
                                onClicked: if (card.n) { Notifs.drop(card.n); card.n.dismiss(); }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.n ? card.n.summary : ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Theme.foreground
                        font { family: Theme.fontFamily; pixelSize: 14; bold: true }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: card.n ? card.n.body.replace(/<img[^>]*>/gi, "") : ""   // StyledText <img> would fetch remote URLs
                        textFormat: Text.StyledText
                        wrapMode: Text.Wrap
                        maximumLineCount: card.toast ? 4 : 6
                        elide: Text.ElideRight
                        color: Qt.alpha(Theme.foreground, 0.8)
                        font { family: Theme.fontFamily; pixelSize: 12 }
                    }
                }
            }

            // action buttons
            Flow {
                Layout.fillWidth: true
                visible: card.buttons.length > 0
                spacing: 10
                Repeater {
                    model: card.buttons
                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: lbl.implicitWidth + 26
                        implicitHeight: 30
                        color: am.containsMouse ? Theme.accent : "transparent"
                        border { width: 2; color: Theme.foreground }
                        Text {
                            id: lbl
                            anchors.centerIn: parent
                            text: modelData.text
                            color: am.containsMouse ? Theme.background : Theme.foreground
                            font { family: Theme.fontFamily; pixelSize: 11; bold: true; capitalization: Font.AllUppercase }
                        }
                        MouseArea {
                            id: am
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                modelData.invoke();
                                if (card.toast) Notifs.drop(card.n);
                            }
                        }
                    }
                }
            }

            // timeout well (toasts only, pauses on hover)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                visible: card.toast && !card.critical
                color: Qt.alpha(Theme.foreground, 0.15)
                Rectangle {
                    id: bar
                    height: parent.height
                    width: parent.width
                    color: Theme.accent
                    NumberAnimation on width {
                        running: card.toast && !card.critical
                        paused: hv.hovered
                        from: bar.parent.width
                        to: 0
                        duration: card.life
                        onFinished: if (card.toast) Notifs.drop(card.n)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- toasts
    PanelWindow {
        id: toasts
        visible: Notifs.popups.length > 0 || stack.implicitHeight > 0
        anchors { top: true; right: true }
        margins { top: Theme.barHeight + 12; right: Theme.frameThickness + 12 }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        implicitWidth: root.cardW + root.pad * 2
        implicitHeight: stack.implicitHeight + root.pad * 2
        mask: Region { item: stack }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-notifications"

        Column {
            id: stack
            x: root.pad
            y: root.pad
            spacing: 22

            Repeater {
                model: Notifs.tracked
                delegate: Item {
                    id: slot
                    required property var modelData
                    readonly property bool active: Notifs.popups.indexOf(modelData) >= 0
                    property bool appeared: false
                    Component.onCompleted: appeared = true

                    visible: active || opacity > 0.01
                    opacity: appeared && active ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                    width: root.cardW
                    height: visible ? c.implicitHeight : 0

                    NotifCard {
                        id: c
                        n: slot.modelData
                        toast: slot.active
                        transform: Translate {
                            x: slot.appeared && slot.active ? 0 : 40
                            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- center
    PanelWindow {
        id: center
        readonly property int panelW: root.cardW + 40
        readonly property int panelH: Math.min(600, (screen ? screen.height : 800) - Theme.barHeight - 70)

        visible: Notifs.centerOpen || panel.x < center.implicitWidth - 1
        anchors { top: true; right: true }
        margins { top: Theme.barHeight + 12; right: Theme.frameThickness + 12 }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        implicitWidth: panelW + root.pad * 2
        implicitHeight: panelH + root.pad * 2
        mask: Region { item: panel }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-notification-center"

        Rectangle {
            id: panel
            x: Notifs.centerOpen ? root.pad : center.implicitWidth
            y: root.pad
            width: center.panelW
            height: center.panelH
            color: Theme.background
            border { width: 2; color: Theme.foreground }
            Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

            ColumnLayout {
                anchors { fill: parent; margins: 16 }
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        Layout.fillWidth: true
                        text: "Notifications"
                        color: Theme.foreground
                        font { family: Theme.fontFamily; pixelSize: 15; bold: true; capitalization: Font.AllUppercase }
                    }
                    // do-not-disturb
                    Rectangle {
                        implicitWidth: 34; implicitHeight: 34
                        color: Notifs.dnd ? Theme.accent : "transparent"
                        border { width: 2; color: Theme.foreground }
                        Text {
                            anchors.centerIn: parent
                            text: "\uf1f6"
                            color: Notifs.dnd ? Theme.background : Theme.foreground
                            font { family: Theme.iconFont; pixelSize: 14 }
                        }
                        MouseArea { anchors.fill: parent; onClicked: Notifs.dnd = !Notifs.dnd }
                    }
                    // clear all
                    Rectangle {
                        implicitWidth: clr.implicitWidth + 24; implicitHeight: 34
                        color: clrMa.containsMouse ? Theme.alert : "transparent"
                        border { width: 2; color: Theme.foreground }
                        Text {
                            id: clr
                            anchors.centerIn: parent
                            text: "Clear"
                            color: clrMa.containsMouse ? Theme.background : Theme.foreground
                            font { family: Theme.fontFamily; pixelSize: 11; bold: true; capitalization: Font.AllUppercase }
                        }
                        MouseArea { id: clrMa; anchors.fill: parent; hoverEnabled: true; onClicked: Notifs.clearAll() }
                    }
                }

                ListView {
                    id: hist
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 12
                    topMargin: 0
                    bottomMargin: 0
                    model: Notifs.tracked

                    delegate: Item {
                        id: row
                        required property var modelData
                        width: hist.width
                        height: hc.implicitHeight
                        NotifCard {
                            id: hc
                            n: row.modelData
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: hist.width
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: Notifs.count === 0
                        text: Notifs.dnd ? "Do not disturb" : "All caught up"
                        color: Theme.muted
                        font { family: Theme.fontFamily; pixelSize: 14 }
                    }
                }
            }
        }
    }
}
