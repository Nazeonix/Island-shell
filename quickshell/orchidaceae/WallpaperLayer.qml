import QtQuick
import Quickshell
import Quickshell.Wayland

// One per monitor: background-layer window with a crossfade between wallpapers.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.background
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-wallpaper"

    function urlOf(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }
    function show(path) {
        if (!path) return;
        const url = urlOf(path);
        if (top.source.toString() === url) return;
        fade.stop();
        base.source = top.source;      // previous wallpaper becomes the backdrop
        top.opacity = 0;
        top.source = url;              // fades in once decoded
    }

    Item {
        anchors.fill: parent

        Image {
            id: base
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: false        // cached copy of the previous wallpaper: no flash
        }
        Image {
            id: top
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: 0
            onStatusChanged: if (status === Image.Ready) fade.restart()
        }
        NumberAnimation {
            id: fade
            target: top
            property: "opacity"
            from: 0; to: 1
            duration: 700
            easing.type: Easing.InOutQuad
        }

        // drop an image on empty desktop space to set it as the wallpaper
        DropArea {
            id: drop
            anchors.fill: parent
            keys: ["text/uri-list"]
            onDropped: d => {
                const paths = [];
                for (let i = 0; i < d.urls.length; i++) {
                    const u = d.urls[i].toString();
                    if (u.startsWith("file://")) paths.push(decodeURIComponent(u.slice(7)));
                }
                Wallpaper.importFiles(paths);
            }
        }
        Rectangle {
            anchors { fill: parent; margins: 20 }
            visible: drop.containsDrag
            color: "transparent"
            border { width: 2; color: Theme.foreground }
            Rectangle {
                anchors.centerIn: parent
                width: label.implicitWidth + 40
                height: 48
                color: Theme.background
                border { width: 2; color: Theme.foreground }
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: "Drop image to set wallpaper"
                    color: Theme.foreground
                    font { family: Theme.fontFamily; pixelSize: 14; bold: true; capitalization: Font.AllUppercase }
                }
            }
        }

        Connections {
            target: Wallpaper
            function onCurrentChanged() { win.show(Wallpaper.current) }
        }
        Component.onCompleted: win.show(Wallpaper.current)
    }
}
