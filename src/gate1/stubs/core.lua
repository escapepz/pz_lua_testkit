local ctx = _G.overlords_ctx or "sp"

_G.isServer      = function() return ctx == "server" end
_G.isClient      = function() return ctx == "client" end
_G.isMultiplayer = function() return ctx ~= "sp" end
_G.isSinglePlayer = function() return ctx == "sp" end

local function newEvent(name)
    local cbs = {}
    return {
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
end

if rawget(_G, "__pz_events_list") == nil then
    _G.__pz_events_list = require("events_list")
end

local function isKnownEvent(name)
    local list = _G.__pz_events_list
    if not (type(list) == "table" and type(list.names) == "table") then
        return false
    end
    for _, n in ipairs(list.names) do
        if n == name then return true end
    end
    return false
end

local function makeEventIndex(kind, consult_umbrella)
    return function(t, k)
        if type(k) == "string" and k:match("^On") then
            if _G.pz_strict and not isKnownEvent(k) then
                local lookup = consult_umbrella
                    and rawget(_G, "__umbrella_event_lookup")
                    or nil
                if not (lookup and lookup(k)) then
                    error("PZ_STRICT: unknown PZ event '"
                        .. kind .. "." .. tostring(k) .. "'", 2)
                end
            end
            local e = newEvent(k)
            rawset(t, k, e)
            return e
        end
    end
end

_G.Events = setmetatable({}, { __index = makeEventIndex("Events", true) })
_G.Hook = setmetatable({}, { __index = makeEventIndex("Hook") })

_G.LuaEventManager = {
    AddEvent = function(name)
        if type(name) ~= "string" or name == "" then
            error("LuaEventManager.AddEvent: event name must be a non-empty string", 2)
        end
        local list = _G.__pz_events_list
        if not (type(list) == "table" and type(list.names) == "table") then
            error("LuaEventManager.AddEvent: event allowlist not loaded", 2)
        end
        local names = list.names
        local known = false
        for _, n in ipairs(names) do
            if n == name then known = true break end
        end
        if not known then
            local pos = #names + 1
            for i, n in ipairs(names) do
                if n > name then pos = i break end
            end
            table.insert(names, pos, name)
        end
        if rawget(_G.Events, name) == nil then
            rawset(_G.Events, name, newEvent(name))
        end
        return _G.Events[name]
    end,
}

_G._pz_logs = _G._pz_logs or {}
_G.writeLog = function(category, message)
    table.insert(_G._pz_logs, { category = category, message = message })
end
_G.getTimestamp = function() return os.time() * 1000 end
_G.getTimestampMs = function() return os.clock() * 1000 end
_G.getGameTime = function() return 0 end

-- instanceof helper. REAL PZ signature: instanceof(obj, className) —
-- decompiled zombie.Lua.LuaManager$GlobalObject.instof(Object obj,
-- String name) at pz_vanilla_code_base/java/zombie/Lua/LuaManager.java:2919
-- (@LuaMethod(name = "instanceof", global = true)); vanilla Lua usage agrees
-- (e.g. pz_vanilla_code_base/lua/client/BuildingObjects/TimedActions/
-- ISBuildAction.lua:12: instanceof(object, "IsoWindow")).
-- RESOLVES SURFACE.md DISAGREEMENTS D1 — this file previously had the
-- arguments reversed. gate1 protocol: stub classes mark instances with
-- __class = class table; classes carry __name (string) and __super (parent
-- class table), so the walk resolves subclass chains (game.lua's classes
-- follow it; CAF's metatable-identity cases IsoPlayer/IsoObject/IsoDeadBody
-- all resolve). Miss-tolerant: nil / non-object obj and non-string className
-- return false (the real VM would throw on type mismatches; stubs prefer
-- false so mod code paths degrade instead of crashing the test run).
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
