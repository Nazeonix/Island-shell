-- Add/remove commands here; each runs once at compositor start.
local cmds = {
    "gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'",
    "qs -c dynamic-island",
    "systemctl --user start hyprpolkitagent",
    "wl-paste --type text --watch cliphist store",
    "wl-paste --type image --watch cliphist store",
    "gsettings set org.gnome.desktop.wm.preferences button-layout ':'",
}

hl.on("hyprland.start", function()
    for _, cmd in ipairs(cmds) do
        hl.exec_cmd(cmd)
    end
end)
