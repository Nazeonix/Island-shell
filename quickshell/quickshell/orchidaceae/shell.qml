//@ pragma UseQApplication
import Quickshell

Scope {
    // app launcher (IPC: qs ipc call launcher toggle)
    AppLauncher {}

    // notification daemon: toasts + center (IPC: qs ipc call notifs toggle)
    NotificationUI {}

    // volume OSD (IPC: qs ipc call volume up|down|mute)
    Volume {}

    // brightness OSD (IPC: qs ipc call brightness up|down|set <percent>)
    Brightness {}

    // Win98/XP style alt-tab (IPC: qs ipc call switcher next|prev|commit|cancel|look)
    Switcher {}

    // Win98/XP title bars above windows (IPC: qs ipc call winbar toggle|look|restore)
    WinBar {}

    // wallpaper picker card (IPC: qs ipc call wallpaper picker)
    WallpaperSwitcher {}

    // wallpaper daemon (IPC: qs ipc call wallpaper next|prev|random|set <path>)
    Variants {
        model: Quickshell.screens
        WallpaperLayer {}
    }

    Variants {
        // one bar per monitor; use [Quickshell.screens[0]] for a single bar
        model: Quickshell.screens
        Bar {}
    }
}
