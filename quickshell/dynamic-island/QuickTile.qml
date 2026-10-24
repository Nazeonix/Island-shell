import QtQuick

// Control-center tile: round icon + title + subtitle (Wi-Fi, Bluetooth).
Rectangle {
    id: tile
    property string kind: "wifi"      // wifi | bluetooth
    property string title: ""
    property string subtitle: ""
    property bool active: false
    property bool chevron: false      // show a > that opens the tile's menu
    signal clicked()
    signal menuRequested()
    radius: height / 2
    color: tma.containsMouse ? Qt.lighter(Theme.surface, 1.15) : Theme.surface
    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
        id: tdot
        x: 9
        anchors.verticalCenter: parent.verticalCenter
        width: 40; height: 40; radius: 20
        color: tile.active ? Theme.accent : Theme.surfaceAlt
        Behavior on color { ColorAnimation { duration: 140 } }
        Canvas {
            anchors.centerIn: parent
            width: 20; height: 20
            antialiasing: true
            property color col: tile.active ? Theme.onAccent : Theme.foreground
            onColChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.strokeStyle = col; c.fillStyle = col;
                c.lineWidth = 1.8; c.lineCap = "round"; c.lineJoin = "round";
                if (tile.kind === "wifi") {
                    for (const r of [5, 9, 13]) {
                        c.beginPath(); c.arc(10, 16, r, -Math.PI * 0.77, -Math.PI * 0.23); c.stroke();
                    }
                    c.beginPath(); c.arc(10, 16.5, 1.6, 0, 2 * Math.PI); c.fill();
                } else {
                    c.beginPath();
                    c.moveTo(5.5, 6.5); c.lineTo(14.5, 13.5); c.lineTo(10, 17.5);
                    c.lineTo(10, 2.5); c.lineTo(14.5, 6.5); c.lineTo(5.5, 13.5);
                    c.stroke();
                }
            }
        }
    }
    Column {
        anchors.left: tdot.right
        anchors.leftMargin: 11
        anchors.right: parent.right
        anchors.rightMargin: tile.chevron ? 40 : 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text {
            width: parent.width
            text: tile.title
            color: Theme.foreground
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: tile.subtitle
            color: Theme.foregroundMuted
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }
    MouseArea {
        id: tma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.clicked()
    }

    // > button on the right: opens the menu (Wi-Fi networks, Bluetooth devices)
    Canvas {
        visible: tile.chevron
        x: tile.width - 28
        anchors.verticalCenter: parent.verticalCenter
        width: 10; height: 16
        antialiasing: true
        property color col: cma.containsMouse ? Theme.foreground : Theme.foregroundMuted
        onColChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            c.strokeStyle = col;
            c.lineWidth = 1.8; c.lineCap = "round"; c.lineJoin = "round";
            c.beginPath(); c.moveTo(2, 2); c.lineTo(8, 8); c.lineTo(2, 14); c.stroke();
        }
    }
    MouseArea {
        id: cma
        visible: tile.chevron
        anchors.right: parent.right
        width: 46
        height: parent.height
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.menuRequested()
    }
}
