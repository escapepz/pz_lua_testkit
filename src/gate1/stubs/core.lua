local ctx = _G.overlords_ctx or "sp"
_G.isServer      = function() return ctx == "server" end
_G.isClient      = function() return ctx == "client" end
_G.isMultiplayer = function() return ctx ~= "sp" end
_G.isSinglePlayer = function() return ctx == "sp" end
local dispatchers = setmetatable({}, { __mode = "k" })
local function newEvent()
    local cbs = {}
    local ev = {
        Add = function(fn) table.insert(cbs, fn) end,
        Remove = function(fn)
            for i, f in ipairs(cbs) do
                if f == fn then table.remove(cbs, i) return end
            end
        end,
        Clear = function() cbs = {} end,
        _fire = function(...)
            for _, f in ipairs(cbs) do f(...) end
        end,
        _count = function() return #cbs end,
    }
    dispatchers[ev] = true
    return ev
end
_G.__pz_is_dispatcher = function(v)
    return type(v) == "table" and dispatchers[v] == true
end
if rawget(_G, "__pz_events_list") == nil then
    _G.__pz_events_list = require("events_list")
end
local function allowlistHas(list, name)
    if type(list) ~= "table" then return false end
    for _, n in ipairs(list) do
        if n == name then return true end
    end
    return false
end
local function makeEventIndex(opts)
    return function(t, k)
        if type(k) == "string" and k ~= "" then
            if _G.pz_strict then
                local known = allowlistHas(opts.allowlist, k)
                if not known and opts.umbrella then
                    local lookup = rawget(_G, "__umbrella_event_lookup")
                    if type(lookup) == "function" and lookup(k) then
                        known = true
                    end
                end
                if not known then
                    error("PZ_STRICT: unknown PZ event '"
                        .. opts.name .. "." .. tostring(k) .. "'", 2)
                end
            end
            local e = newEvent()
            rawset(t, k, e)
            return e
        end
        return nil
    end
end
local lists = _G.__pz_events_list
_G.Events = setmetatable({}, {
    __index = makeEventIndex({ name = "Events", allowlist = lists.events, umbrella = true }),
})
_G.Hook = setmetatable({}, {
    __index = makeEventIndex({ name = "Hook", allowlist = lists.hooks, umbrella = false }),
})
_G.LuaEventManager = {
    AddEvent = function(name)
        if type(name) ~= "string" or name == "" then
            error("LuaEventManager.AddEvent: event name must be a non-empty string", 2)
        end
        local list = _G.__pz_events_list
        if not (type(list) == "table" and type(list.events) == "table") then
            error("LuaEventManager.AddEvent: event allowlist not loaded", 2)
        end
        local events = list.events
        local known = false
        for _, n in ipairs(events) do
            if n == name then known = true break end
        end
        if not known then
            local pos = #events + 1
            for i, n in ipairs(events) do
                if n > name then pos = i break end
            end
            table.insert(events, pos, name)
        end
        if rawget(_G.Events, name) == nil then
            rawset(_G.Events, name, newEvent())
        end
        return _G.Events[name]
    end,
}
_G._pz_logs = _G._pz_logs or {}
_G.writeLog = function(category, message)
    table.insert(_G._pz_logs, { category = category, message = message })
end
_G.getTimestamp = function() return os.time() end
_G.getTimestampMs = function() return os.time() * 1000 end
local multiplier = 1
local gameTime = {}
gameTime.getHours = function() return 7 end
gameTime.getMinutes = function() return 30 end
gameTime.getSeconds = function() return 0 end
gameTime.getDay = function() return 1 end
gameTime.getHour = function() return 7 end
gameTime.getMonth = function() return 7 end
gameTime.getNightsSurvived = function() return 0 end
gameTime.getWorldAgeHours = function() return 0 end
gameTime.getMultiplier = function() return multiplier end
gameTime.getTrueMultiplier = function() return multiplier end
gameTime.setMultiplier = function(v) multiplier = tonumber(v) or 1 end
gameTime.getTimeOfDay = function() return 7.5 end
gameTime.getMinutesPerDay = function() return 60 end
gameTime.daysInMonth = function() return 31 end
gameTime.getModData = function()
    gameTime.__mod_data = gameTime.__mod_data or {}
    return gameTime.__mod_data
end
_G.getGameTime = function() return gameTime end
_G.instanceof = function(obj, className)
    if obj == nil then return false end
    if type(obj) ~= "table" and type(obj) ~= "userdata" then return false end
    if type(className) ~= "string" then return false end
    local c = type(obj) == "table" and rawget(obj, "__class") or nil
    while c do
        if c.__name == className then return true end
        c = rawget(c, "__super")
    end
    return false
end
_G.ISTimedActionQueue = _G.ISTimedActionQueue or {
    add = function() end,
    getTimedActionQueue = function() return {} end,
}
_G.ISBaseTimedAction = { new = function() return {} end }
print("[pzspec] gate1 stubs loaded (ctx=" .. ctx .. ")")
