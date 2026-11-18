local names = {
    "OnClientCommand",
    "OnContainerUpdate",
    "OnFillWorldObjectContextMenu",
    "OnGameBoot",
    "OnGameStart",
    "OnInitGlobalModData",
    "OnInitWorld",
    "OnLoadedTileDefinitions",
    "OnPlayerUpdate",
    "OnRefreshInventoryWindowContainers",
    "OnSave",
    "OnServerCommand",
    "OnServerStarted",
    "OnTick",
    "OnTickEvenPaused",
}

local seen = {}
local out = {}
for _, n in ipairs(names) do
    if type(n) == "string" and n ~= "" and not seen[n] then
        seen[n] = true
        out[#out + 1] = n
    end
end
table.sort(out)

return { names = out }
