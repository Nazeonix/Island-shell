import QtQuick

// Base type for every palette. A palette only has to set the core colors;
// the derived tokens below follow automatically and can be overridden per theme.
QtObject {
    // Identity
    property string key: ""        // stable id, persisted ("tokyonight")
    property string label: ""      // display name ("Tokyo Night")

    // Surfaces
    property color background: "#1e1e1e"
    property color backgroundAlt: "#171717"   // darker than background (bars, wells)
    property color surface: "#2b2b2b"         // raised cards / rows
    property color surfaceAlt: "#383838"      // higher elevation / tiles

    // Text
    property color foreground: "#e3e3e3"
    property color foregroundMuted: "#a0a0a0"

    // Brand
    property color primary: "#a8c7fa"
    property color secondary: "#0a84ff"
    property color accent: primary

    // Hues
    property color red: "#ff453a"
    property color orange: "#ff9f0a"
    property color yellow: "#ffd60a"
    property color green: "#30d158"
    property color cyan: "#64d2ff"
    property color blue: "#0a84ff"
    property color purple: "#bf5af2"
    property color pink: "#ff375f"

    // Status (default to the matching hue)
    property color success: green
    property color warning: yellow
    property color error: red
    property color info: blue

    // Light or dark theme (drives GTK color-scheme and the browser color scheme)
    readonly property bool dark: background.hslLightness < 0.5

    // Interaction states (derived from the palette, so every theme gets them for free)
    property color border: Qt.alpha(foreground, 0.15)
    property color borderSubtle: Qt.alpha(foreground, 0.08)
    property color hover: Qt.alpha(foreground, 0.08)
    property color active: Qt.alpha(primary, 0.22)
    property color selected: Qt.alpha(primary, 0.16)
}
