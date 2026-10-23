-- Windows that must ALWAYS float, even when floating mode is off.
-- Shared by rules.lua (static rules) and floatmode.lua (so toggling back to
-- tiling doesn't tile these).
local M = {
    classes = { "com.gabm.satty" },

    -- thunar secondary windows, matched by title prefix
    thunar_titles = {
        "Rename", "Properties", "File Operation Progress", "Confirm",
        "Open", "Save", "New Folder", "Bulk Rename",
    },
}

function M.is_always_float(w)
    local class, title = w.class or "", w.title or ""
    for _, c in ipairs(M.classes) do
        if class == c then return true end
    end
    if class == "thunar" then
        for _, t in ipairs(M.thunar_titles) do
            if title:find("^" .. t) then return true end
        end
    end
    return false
end

return M
