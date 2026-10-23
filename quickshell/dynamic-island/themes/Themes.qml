import QtQuick

// Registry of available palettes (display order = list order).
// To add a theme: create themes/MyTheme.qml (a `ThemePalette {}`) and add `MyTheme {}` below.
QtObject {
    readonly property list<ThemePalette> all: [
        Ayu {},
        Gruvbox {},
        GruvboxMaterial {},
        Kanagawa {},
        RosePine {},
        TokyoNight {},
        ASW {},
        Alpenglow {},
        Osaka {},
        Noir {},
        Industrial {},
        Horizon {},
        Nightfox {},
        Nord {},
        Catppuccin {},
        Dracula {},
        Everforest {},
        Solarized {},
    ]

    function byKey(key) {
        for (let i = 0; i < all.length; i++)
            if (all[i].key === key) return all[i];
        return null;
    }
}
