import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

// One notification. Used by both the toast window and the center.
//   toast: true  -> shows a progress bar and emits expired() when it runs out;
//                   the timer pauses while the pointer is over the card.
Rectangle {
    id: card

    required property var notif
    property bool toast: false

    signal expired()     // toast timer ran out (hide the popup, keep in center)
    signal dismissed()   // user closed it or invoked an action

    // ---- Snapshot of the notification ----
    // Quickshell destroys a Notification once it is closed, which would
    // spam binding errors while the exit animation still runs. So the card
    // copies the fields and refreshes them only while the object is alive.
    property string summary: ""
    property string body: ""
    property string appName: ""
    property string appIcon: ""
    property string image: ""
    property int urgency: NotificationUrgency.Normal
    property real expireTimeout: -1
    property var actions: []
    readonly property var buttons: actions.filter(a => a.identifier !== "default")

    function sync() {
        if (!notif) return;
        summary = notif.summary;
        body = notif.body;
        appName = notif.appName;
        appIcon = notif.appIcon;
        image = notif.image;
        urgency = notif.urgency;
        expireTimeout = notif.expireTimeout;
        actions = notif.actions;
    }

    property bool ready: false
    Component.onCompleted: { sync(); ready = true; }

    Connections {
        target: card.notif
        ignoreUnknownSignals: true
        function onSummaryChanged() { card.sync(); }
        function onBodyChanged() { card.sync(); }
        function onAppIconChanged() { card.sync(); }
        function onImageChanged() { card.sync(); }
        function onUrgencyChanged() { card.sync(); }
        function onActionsChanged() { card.sync(); }
    }

    // ---- Auto-dismiss: 0 = never (critical, or not a toast) ----
    readonly property real durationMs:
        (!toast || urgency === NotificationUrgency.Critical) ? 0
        : (expireTimeout > 0 ? expireTimeout * 1000 : Theme.toastTimeout)
    property real remaining: 1

    NumberAnimation {
        target: card
        property: "remaining"
        from: 1; to: 0
        duration: card.durationMs
        running: card.ready && card.durationMs > 0
        paused: hover.hovered            // pause on hover
        onFinished: card.expired()
    }

    HoverHandler { id: hover }

    // ---- Look ----
    implicitHeight: content.implicitHeight + Theme.padding * 2
    radius: Theme.radius
    color: Theme.bg
    border.width: 1
    border.color: urgency === NotificationUrgency.Critical ? Theme.urgent : Theme.border

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.padding
        spacing: Theme.spacing

        Image {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            sourceSize: Qt.size(80, 80)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: source != ""
            source: card.image !== "" ? card.image
                  : card.appIcon.startsWith("/") ? "file://" + card.appIcon
                  : card.appIcon !== "" ? Quickshell.iconPath(card.appIcon, "dialog-information")
                  : ""
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: card.appName
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSmall
                    elide: Text.ElideRight
                }
                Text {   // close button
                    text: "✕"
                    color: closeArea.containsMouse ? Theme.text : Theme.textDim
                    font.pixelSize: 12
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        onClicked: card.dismissed()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: card.summary
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitle
                font.weight: Font.Medium
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: card.body !== ""
                text: card.body
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
                textFormat: Text.StyledText      // body markup (<b>, <i>, <a>)
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            RowLayout {
                visible: card.buttons.length > 0
                Layout.topMargin: 6
                spacing: 6

                Repeater {
                    model: card.buttons
                    delegate: Rectangle {
                        id: btn
                        required property var modelData
                        Layout.preferredWidth: label.implicitWidth + 24
                        Layout.preferredHeight: 28
                        radius: Theme.innerRadius
                        color: btnArea.containsMouse ? Theme.accentSoft : Theme.bgRaised

                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: btn.modelData.text
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: btnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { btn.modelData.invoke(); card.dismissed(); }
                        }
                    }
                }
            }
        }
    }

    // Auto-dismiss progress (toasts only)
    Rectangle {
        visible: card.durationMs > 0
        x: card.radius
        y: card.height - 5
        height: 2
        radius: 1
        width: Math.max(0, (card.width - card.radius * 2) * card.remaining)
        color: Theme.accent
        opacity: 0.5
    }
}
