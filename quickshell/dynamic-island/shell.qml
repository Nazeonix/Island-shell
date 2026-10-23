import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick.Shapes

ShellRoot {
    id: shellRoot
    property int cornerRadius: 24   // rounded screen corners; 0 disables

    PanelWindow {
        id: win
        // First screen; swap for a specific monitor if needed (also update Island.wsScreen)
        screen: Quickshell.screens[0]
        visible: true

        // Anchoring only to top => compositor centers it horizontally
        anchors.top: true
        implicitWidth: 760   // wide enough for the widest state (middle, 560) plus the flared corners
        implicitHeight: island.fullH + 24   // tall enough for the fully open control center
        color: "transparent"
        // Reserve only the collapsed pill (margin + height); expanded state overlays windows.
        // (Default Auto reserved the whole 220px window -> empty gap.)
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: island.y + island.barH
        WlrLayershell.namespace: "dynamic-island"
        // Grab the keyboard only while the island is keyboard-opened (Esc releases it)
        WlrLayershell.keyboardFocus: island.pinned ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // Only the island and badge capture input; rest of the window is click-through
        mask: Region {
            regions: [
        //        Region { item: vol },
        //        Region { item: wall },
                Region { item: island }
        //        Region { item: wifi }
            ]
        }
       
        Island {
            id: island
            notifService: notifs
            onOsdShow: (kind) => osd.show(kind)
            x: (win.width - width) / 2
            y: 0   // notch: flush with the top edge
        }
    }
    // Compositor-agnostic control: `qs ipc call island <fn>` (bind these in Hyprland: binds.lua)
    IpcHandler {
        target: "island"
        function toggle(): void    { island.toggle() }
        function wall(): void      { Wallpaper.pickerOpen = !Wallpaper.pickerOpen }   // same as `wallpaper picker`
        function playpause(): void { island.mediaToggle() }
        function next(): void      { island.mediaNext() }
        function prev(): void      { island.mediaPrev() }
        function volup(): void     { island.volStep(0.05) }
        function voldown(): void   { island.volStep(-0.05) }
        function mute(): void      { island.toggleMute() }
        function brup(): void      { island.brStep(5) }
        function brdown(): void    { island.brStep(-5) }
    }

    // ---- Wallpaper: state + IPC in the Wallpaper singleton, one layer per monitor; the picker is its own panel (WallpaperPicker) ----
    Variants {
        model: Quickshell.screens
        WallpaperLayer {}
    }

    // ---- Rounded screen corners: click-through overlay per monitor ----
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: shellRoot.cornerRadius > 0
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "island-corners"
            color: "transparent"
            mask: Region {}   // empty region: all input passes through

            // One corner shape, rotated into the four corners (TL=0, TR=90, BR=180, BL=270)
            Repeater {
                model: [
                    { rot: 0,   ax: "left",  ay: "top"    },
                    { rot: 90,  ax: "right", ay: "top"    },
                    { rot: 180, ax: "right", ay: "bottom" },
                    { rot: 270, ax: "left",  ay: "bottom" }
                ]
                Shape {
                    id: corner
                    required property var modelData
                    width: shellRoot.cornerRadius; height: width
                    rotation: modelData.rot
                    x: modelData.ax === "left" ? 0 : parent.width - width
                    y: modelData.ay === "top" ? 0 : parent.height - height
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "black"
                        strokeWidth: -1
                        startX: 0; startY: 0
                        PathLine { x: corner.width; y: 0 }
                        PathArc {
                            x: 0; y: corner.height
                            radiusX: corner.width; radiusY: corner.height
                            direction: PathArc.Counterclockwise
                        }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }
        }
    }

    Osd { id: osd; source: island }
    Switcher {}

    NotificationService { id: notifs }
    NotificationToasts { service: notifs }
    NotificationCenter { service: notifs }
    Launcher { id: launcher }
    ThemePanel {}
    WallpaperPicker {}
    Clipboard {}
    Powermenu {}
}
