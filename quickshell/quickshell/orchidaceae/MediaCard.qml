import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

Rectangle {
    id: root
    color: "transparent"

    // Prefer the playing player; otherwise the first available one
    readonly property var player: {
        const ps = Mpris.players.values
        let first = null
        for (let i = 0; i < ps.length; i++) {
            if (ps[i].isPlaying) return ps[i]
            if (!first) first = ps[i]
        }
        return first
    }

    readonly property bool hasPlayer: player !== null
    readonly property bool playing: hasPlayer && player.isPlaying
    readonly property real len: hasPlayer ? player.length : 0
    readonly property string title: hasPlayer ? (player.trackTitle || "Unknown title") : ""
    readonly property string artist: hasPlayer ? (player.trackArtist || "") : ""
    readonly property string album: hasPlayer ? (player.trackAlbum || "") : ""
    readonly property string art: hasPlayer ? player.trackArtUrl : ""
    readonly property string playerName: hasPlayer ? (player.identity || "") : ""

    // Position does not update reactively — poll while playing (Quickshell docs pattern)
    property real pos: 0
    function syncPos() {
        if (hasPlayer) pos = player.position
        else pos = 0
    }
    Timer {
        interval: 500
        running: root.playing
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.player) root.player.positionChanged()
            root.syncPos()
        }
    }
    Connections {
        target: root.player
        function onPositionChanged() { root.syncPos() }
        function onTrackChanged() { root.syncPos() }
        function onPostTrackChanged() { root.syncPos() }
        function onLengthChanged() { root.syncPos() }
        function onIsPlayingChanged() { root.syncPos() }
    }
    onPlayerChanged: syncPos()

    function fmt(s) {
        s = Math.max(0, Math.floor(s))
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        const sec = s % 60
        const mm = ("0" + m).slice(-2)
        const ss = ("0" + sec).slice(-2)
        return h > 0 ? h + ":" + mm + ":" + ss : m + ":" + ss
    }

    function seekTo(ratio) {
        if (!hasPlayer || !player.canSeek || len <= 0) return
        player.position = Math.max(0, Math.min(len, ratio * len))
        syncPos()
    }

    // ---- empty state ----
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.hasPlayer
        spacing: 10
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "\uf001"
            color: Theme.muted
            font { family: Theme.iconFont; pixelSize: 40 }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Nothing playing"
            color: Theme.muted
            font { family: Theme.fontFamily; pixelSize: 15 }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Open a player that supports MPRIS"
            color: Qt.alpha(Theme.muted, 0.7)
            font { family: Theme.fontFamily; pixelSize: 12 }
        }
    }

    // ---- active player ----
    RowLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 18
        visible: root.hasPlayer

        // cover art
        Rectangle {
            Layout.preferredWidth: 200
            Layout.preferredHeight: 200
            Layout.alignment: Qt.AlignVCenter
            color: Theme.surface
            clip: true

            Image {
                id: cover
                anchors.fill: parent
                source: root.art
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }
            // placeholder when no art / still loading
            Column {
                anchors.centerIn: parent
                spacing: 6
                visible: cover.status !== Image.Ready
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\uf001"
                    color: Theme.muted
                    font { family: Theme.iconFont; pixelSize: 36 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.playerName !== ""
                    text: root.playerName
                    color: Theme.muted
                    font { family: Theme.fontFamily; pixelSize: 11 }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4

            Item { Layout.fillHeight: true }

            // player name (Spotify, Firefox, …)
            Text {
                Layout.fillWidth: true
                visible: root.playerName !== ""
                text: root.playerName
                elide: Text.ElideRight
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 11; bold: true; capitalization: Font.AllUppercase }
            }

            Text {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                color: Theme.foreground
                font { family: Theme.fontFamily; pixelSize: 18; bold: true }
            }
            Text {
                Layout.fillWidth: true
                visible: root.artist !== ""
                text: root.artist
                elide: Text.ElideRight
                color: Theme.secondary
                font { family: Theme.fontFamily; pixelSize: 14 }
            }
            Text {
                Layout.fillWidth: true
                visible: root.album !== ""
                text: root.album
                elide: Text.ElideRight
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: 12 }
            }

            Item { Layout.preferredHeight: 8 }

            // progress bar
            Item {
                id: bar
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                readonly property real ratio: root.len > 0 ? Math.min(1, root.pos / root.len) : 0

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    color: Qt.alpha(Theme.foreground, 0.12)
                    Rectangle {
                        width: parent.width * bar.ratio
                        height: parent.height
                        color: Theme.accent
                    }
                }
                // scrub handle
                Rectangle {
                    x: parent.width * bar.ratio - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 10
                    color: Theme.foreground
                    visible: root.len > 0
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.hasPlayer && root.player.canSeek && root.len > 0
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    // drag to seek
                    property bool dragging: false
                    onPressed: m => { dragging = true; root.seekTo(m.x / width) }
                    onPositionChanged: m => { if (dragging) root.seekTo(m.x / width) }
                    onReleased: dragging = false
                    onCanceled: dragging = false
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.fmt(root.pos)
                    color: Theme.muted
                    font { family: Theme.fontFamily; pixelSize: 12 }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.len > 0 ? root.fmt(root.len) : "--:--"
                    color: Theme.muted
                    font { family: Theme.fontFamily; pixelSize: 12 }
                }
            }

            // transport controls
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                spacing: 12

                // previous
                Rectangle {
                    implicitWidth: 44
                    implicitHeight: 44
                    color: prevMa.containsMouse && prevMa.enabled
                           ? Qt.alpha(Theme.foreground, 0.12) : "transparent"
                    opacity: root.hasPlayer && root.player.canGoPrevious ? 1 : 0.35
                    Text {
                        anchors.centerIn: parent
                        text: "\uf048"
                        color: Theme.foreground
                        font { family: Theme.iconFont; pixelSize: 15 }
                    }
                    MouseArea {
                        id: prevMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.hasPlayer && root.player.canGoPrevious
                        onClicked: root.player.previous()
                    }
                }

                // play / pause
                Rectangle {
                    implicitWidth: 52
                    implicitHeight: 52
                    color: Theme.accent
                    opacity: root.hasPlayer && root.player.canTogglePlaying ? 1 : 0.4
                    Text {
                        anchors.centerIn: parent
                        text: root.playing ? "\uf04c" : "\uf04b"
                        color: Theme.background
                        font { family: Theme.iconFont; pixelSize: 18 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.hasPlayer && root.player.canTogglePlaying
                        onClicked: root.player.togglePlaying()
                    }
                }

                // next
                Rectangle {
                    implicitWidth: 44
                    implicitHeight: 44
                    color: nextMa.containsMouse && nextMa.enabled
                           ? Qt.alpha(Theme.foreground, 0.12) : "transparent"
                    opacity: root.hasPlayer && root.player.canGoNext ? 1 : 0.35
                    Text {
                        anchors.centerIn: parent
                        text: "\uf051"
                        color: Theme.foreground
                        font { family: Theme.iconFont; pixelSize: 15 }
                    }
                    MouseArea {
                        id: nextMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.hasPlayer && root.player.canGoNext
                        onClicked: root.player.next()
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
