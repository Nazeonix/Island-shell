import QtQuick
import Quickshell
import Quickshell.Wayland

// One per monitor: background-layer window with a crossfade between wallpapers.
// Styled like the notch: rounded shapes, Theme colors, no hard borders.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.background
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "island-wallpaper"

    function show(path) {
        if (!path) return;
        const url = Wallpaper.url(path);
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
            duration: Wallpaper.fadeMs
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
        Rectangle {   // soft rounded drop target, accent tinted
            anchors { fill: parent; margins: 16 }
            radius: 28
            opacity: drop.containsDrag ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            color: Qt.alpha(Theme.accent, 0.12)
            border { width: 2; color: Qt.alpha(Theme.accent, 0.7) }
            Rectangle {   // pill label, same look as the notch
                anchors.centerIn: parent
                width: label.implicitWidth + 36
                height: 40
                radius: height / 2
                color: Theme.background
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: "Drop image to set wallpaper"
                    color: Theme.foreground
                    font { family: Theme.fontFamily; pixelSize: 14 }
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
