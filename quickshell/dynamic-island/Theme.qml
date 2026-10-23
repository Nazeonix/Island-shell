pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "themes"

// Single source of truth for the shell's look.
//  - themes/       palette definitions (Palette base + one file per theme + registry)
//  - this file     selection state, persistence, and the semantic tokens components bind to
//  - panels/theme  the theme picker UI
// Components use `Theme.background`, `Theme.primary`, ... and update live when `current` changes.
Singleton {
    id: root

    // ---- Selection ----
    readonly property string defaultKey: "asw"
    property string current: defaultKey                    // palette key, persisted
    readonly property var options: {                       // every palette, in display order (plain array)
        const out = [];
        for (let i = 0; i < registry.all.length; i++) out.push(registry.all[i]);
        out.sort((a, b) => a.key.localeCompare(b.key));    // alphabetical in the picker
        return out;
    }
    readonly property var palette: registry.byKey(current) ?? registry.byKey(defaultKey)

    function select(key) {
        if (!registry.byKey(key)) return;                  // ignore unknown names
        current = key;
        store.setText(key + "\n");
        exportTimer.restart();                             // push the palette to GTK / browsers
    }
    function cycle(step) {                                 // +1 / -1
        const n = options.length;
        let i = 0;
        for (let j = 0; j < n; j++) if (options[j].key === current) i = j;
        select(options[(i + step + n) % n].key);
    }

    Themes { id: registry }

    // ---- Persistence: $XDG_STATE_HOME/dynamic-island/theme (one line: the palette key) ----
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/dynamic-island"
    Process { command: ["mkdir", "-p", root.stateDir]; running: true }
    FileView {
        id: store
        path: root.stateDir + "/theme"
        // Missing file (first launch) or unreadable -> keep the default; unknown key -> ignored
        onLoaded: {
            const k = text().trim();
            if (registry.byKey(k)) root.current = k;
        }
    }


    // ---- Apply the palette to the rest of the desktop: GTK 3 + 4 colors, Chromium-family browsers ----
    // Runs a moment after every select()/cycle(); also on demand: qs -c dynamic-island ipc call theme apply
    //  - GTK:     writes ~/.config/gtk-3.0/gtk.css and ~/.config/gtk-4.0/gtk.css (libadwaita + classic color
    //             names) and re-sets color-scheme so open GTK apps reload. adw-gtk3 gives the best GTK 3 result.
    //  - Browsers: Brave/Chromium in "GTK" appearance follow the GTK colors by themselves. Optionally a
    //             managed policy (BrowserThemeColor) is written to any policy dir you made writable.
    property bool exportGtk: true
    Timer { id: exportTimer; interval: 300; onTriggered: root.exportTheme() }

    function hex(c) { return "" + c }                      // "#rrggbb"

    function gtkCss(p) {
        const dark = p.dark;
        const shade = dark ? "rgba(0, 0, 0, 0.36)" : "rgba(0, 0, 0, 0.07)";
        const rows = [
            // accents + status
            ["accent_bg_color", p.accent], ["accent_fg_color", p.background], ["accent_color", p.accent],
            ["destructive_bg_color", p.error], ["destructive_fg_color", p.background], ["destructive_color", p.error],
            ["success_bg_color", p.success], ["success_fg_color", p.background], ["success_color", p.success],
            ["warning_bg_color", p.warning], ["warning_fg_color", p.background], ["warning_color", p.warning],
            ["error_bg_color", p.error], ["error_fg_color", p.background], ["error_color", p.error],
            // window / content
            ["window_bg_color", p.background], ["window_fg_color", p.foreground],
            ["view_bg_color", p.backgroundAlt], ["view_fg_color", p.foreground],
            ["headerbar_bg_color", p.surface], ["headerbar_fg_color", p.foreground],
            ["headerbar_border_color", p.surfaceAlt], ["headerbar_backdrop_color", p.background],
            ["headerbar_shade_color", shade], ["headerbar_darker_shade_color", "rgba(0, 0, 0, 0.9)"],
            ["sidebar_bg_color", p.surface], ["sidebar_fg_color", p.foreground],
            ["sidebar_backdrop_color", p.background], ["sidebar_shade_color", shade], ["sidebar_border_color", p.surfaceAlt],
            ["secondary_sidebar_bg_color", p.background], ["secondary_sidebar_fg_color", p.foreground],
            ["secondary_sidebar_backdrop_color", p.background], ["secondary_sidebar_shade_color", shade],
            ["secondary_sidebar_border_color", p.surfaceAlt],
            ["card_bg_color", p.surface], ["card_fg_color", p.foreground], ["card_shade_color", shade],
            ["dialog_bg_color", p.surface], ["dialog_fg_color", p.foreground],
            ["popover_bg_color", p.surface], ["popover_fg_color", p.foreground], ["popover_shade_color", shade],
            ["thumbnail_bg_color", p.surface], ["thumbnail_fg_color", p.foreground],
            ["shade_color", shade], ["scrollbar_outline_color", "rgba(0, 0, 0, 0.5)"],
            // classic GTK 3 / Adwaita names
            ["theme_bg_color", p.background], ["theme_fg_color", p.foreground],
            ["theme_base_color", p.backgroundAlt], ["theme_text_color", p.foreground],
            ["theme_selected_bg_color", p.accent], ["theme_selected_fg_color", p.background],
            ["theme_unfocused_bg_color", p.background], ["theme_unfocused_fg_color", p.foregroundMuted],
            ["theme_unfocused_base_color", p.backgroundAlt], ["theme_unfocused_text_color", p.foreground],
            ["theme_unfocused_selected_bg_color", p.surfaceAlt], ["theme_unfocused_selected_fg_color", p.foreground],
            ["insensitive_bg_color", p.surface], ["insensitive_fg_color", p.foregroundMuted],
            ["insensitive_base_color", p.backgroundAlt],
            ["borders", p.surfaceAlt], ["unfocused_borders", p.surface],
            ["content_view_bg", p.backgroundAlt],
        ];
        let out = "/* generated by dynamic-island (" + p.key + ") - overwritten on every theme change */\n";
        for (const r of rows)
            out += "@define-color " + r[0] + " " + (typeof r[1] === "string" ? r[1] : hex(r[1])) + ";\n";
        return out;
    }

    readonly property string exportScript: `
css="$1"; bg="$2"; scheme="$3"
for d in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
    mkdir -p "$d" && printf '%s\n' "$css" > "$d/gtk.css"
done
for d in /etc/brave/policies/managed /etc/chromium/policies/managed /etc/opt/chrome/policies/managed /etc/opt/edge/policies/managed; do
    if [ -d "$d" ] && [ -w "$d" ]; then
        printf '{"BrowserThemeColor":"%s","BrowserColorScheme":"%s"}\n' "$bg" "$scheme" > "$d/dynamic-island-theme.json"
    fi
done
if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme default
    sleep 0.15
    gsettings set org.gnome.desktop.interface color-scheme "prefer-$scheme"
fi
`

    function exportTheme() {
        if (!exportGtk) return;
        const p = palette;
        Quickshell.execDetached(["sh", "-c", exportScript, "_", gtkCss(p), hex(p.background), p.dark ? "dark" : "light"]);
    }

    // ---- Layout mode: "island" (floating pill) or "panel" (full-width bar). Persisted next to the theme. ----
    property string mode: "island"
    readonly property bool islandMode: mode === "island"
    readonly property bool panelMode: mode === "panel"
    function setMode(m) {
        if (m !== "island" && m !== "panel") return;
        mode = m;
        modeStore.setText(m + "\n");
    }
    function toggleMode() { setMode(islandMode ? "panel" : "island"); }
    FileView {
        id: modeStore
        path: root.stateDir + "/mode"
        onLoaded: {
            const m = text().trim();
            if (m === "island" || m === "panel") root.mode = m;
        }
    }

    // ---- Semantic colors ----
    readonly property color background: palette.background
    readonly property color notch: "#000000"   // notch / panel surface: pure black; applets use the accent
    readonly property color backgroundAlt: palette.backgroundAlt
    readonly property color surface: palette.surface
    readonly property color surfaceAlt: palette.surfaceAlt
    readonly property color foreground: palette.foreground
    readonly property color foregroundMuted: palette.foregroundMuted
    readonly property color primary: palette.primary
    readonly property color secondary: palette.secondary
    readonly property color accent: palette.accent
    readonly property color border: palette.border
    readonly property color borderSubtle: palette.borderSubtle
    readonly property color hover: palette.hover
    readonly property color active: palette.active
    readonly property color selected: palette.selected
    readonly property color success: palette.success
    readonly property color warning: palette.warning
    readonly property color error: palette.error
    readonly property color info: palette.info
    readonly property color red: palette.red
    readonly property color orange: palette.orange
    readonly property color yellow: palette.yellow
    readonly property color green: palette.green
    readonly property color cyan: palette.cyan
    readonly property color blue: palette.blue
    readonly property color purple: palette.purple
    readonly property color pink: palette.pink

    // ---- Names used by the notification UI (kept so those files need no changes) ----
    readonly property color bg: background
    readonly property color bgRaised: surface
    readonly property color text: foreground
    readonly property color textDim: foregroundMuted
    readonly property color accentSoft: Qt.alpha(accent, 0.15)
    readonly property color urgent: error

    // Shape
    readonly property int radius: 20
    readonly property int innerRadius: 12
    readonly property int padding: 14
    readonly property int spacing: 10

    // Fonts
    readonly property string fontFamily: Qt.application.font.family
    readonly property int fontTitle: 14
    readonly property int fontBody: 13
    readonly property int fontSmall: 11

    // Layout
    readonly property int cardWidth: 360
    readonly property int margin: 12
    readonly property int toastTop: 60        // below the island
    readonly property real toastTimeout: 5000 // ms, used when the app gives none
    readonly property real barScale: 1.35     // Bar.qml size multiplier (1.0 = original)
    function s(px) { return Math.round(px * barScale) }   // scale a bar dimension
    readonly property int barHeight: s(40)    // Bar.qml
    readonly property bool barAtTop: true     // Bar.qml edge (panel mode; the island is hidden then)
}
