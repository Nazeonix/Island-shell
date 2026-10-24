import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets

RowLayout {
    id: root
    spacing: 8

    readonly property bool isHypr: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    readonly property bool isNiri: !!Quickshell.env("NIRI_SOCKET")
    property string niriTitle: ""
    property string niriApp: ""

    readonly property var toplevel: isHypr ? Hyprland.activeToplevel : null
    readonly property string title: isHypr ? (toplevel ? toplevel.title : "") : niriTitle
    readonly property string appId: isHypr
        ? (toplevel && toplevel.lastIpcObject ? (toplevel.lastIpcObject["class"] || "") : "")
        : niriApp
    readonly property var desktopEntry: appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
    readonly property string iconSrc: {
        if (appId === "") return ""
        const name = desktopEntry && desktopEntry.icon ? desktopEntry.icon : appId.toLowerCase()
        return Quickshell.iconPath(name, true)
    }
    property bool requery: false   // event arrived while a query was running

    Process {
        id: query
        command: ["niri", "msg", "--json", "focused-window"]
        onExited: if (root.requery) { root.requery = false; running = true }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const w = JSON.parse(text);
                    root.niriTitle = w ? (w.title || "") : "";
                    root.niriApp = w ? (w.app_id || "") : "";
                } catch (e) { root.niriTitle = ""; root.niriApp = ""; }
            }
        }
    }
    Process {
        running: root.isNiri
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser { onRead: line => { if (query.running) root.requery = true; else query.running = true; } }
    }
    Component.onCompleted: if (isNiri) query.running = true

    IconImage {
        visible: root.iconSrc !== ""
        source: root.iconSrc
        implicitSize: 20
    }
    Text {
        visible: root.iconSrc === ""
        text: "\uf108"
        color: Theme.muted
        font { family: Theme.iconFont; pixelSize: 18 }
    }
    Text {
        Layout.maximumWidth: 480
        text: root.title !== "" ? root.title : "Desktop"
        elide: Text.ElideRight
        color: Theme.foreground
        font { family: Theme.fontFamily; pixelSize: 13; bold: true; capitalization: Font.AllUppercase; letterSpacing: 0.5 }
    }
}
