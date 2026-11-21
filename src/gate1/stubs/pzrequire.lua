-- pzrequire.lua — gate1 contract require module (Phase 3 mod loader core,
-- plan Task 1, provide seeding Task 3). Owns the in-engine require semantics
-- the mod loader (Task 2) installs in mod mode: normalized path-keyed
-- execute-once cache (the key is cache identity only — loadfile always
-- gets the first-seen real path, so POSIX absolute roots keep their
-- leading '/'; case folding stays Windows-only), ordered first-hit root
-- scan, soft-fail warn+nil on
-- miss, circular re-entry guard, provide-seeded stub entries, and the
-- testkit facade (resetLoaded / keep / provide / std_require).
--
-- Loadable standalone: dofile(...) defines _G.PzRequire at load time
-- (java_pack_spec loader precedent). Plain suite runs never activate it —
-- runner.lua's loader block installs it via PzRequire.install() in mod mode
-- only (Task 2 wiring; feature-off identity: _G.require stays std, no
-- _G.testkit). Gate1-only module: uses loadfile / io.popen per the
-- established Lua 5.1 gate1 precedent (never wired on gate2).
--
-- Engine contract (decompiled B42.22.2 base, re-verified 2026-11-14; nothing
-- copied — semantics only):
--   LuaManager.java:4966-4981  require(name): append ".lua" when missing ->
--     ordered paths scan -> first hit RunLua; miss = Lua-log warn + null.
--   LuaManager.java:1327-1402  RunLua(path): "\"->"/" normalization; in-flight
--     set -> recursion warn + null; loaded/loadedReturn path-keyed
--     execute-once cache (the done flag is set even when the chunk returns
--     nil — loaded.contains semantics).
--   runner.lua normalizeSpecKey / umbrella.lua libraryProbe: the house
--     normalization and directory-probe precedents reused below.
--
-- Documented deviations (plan Global Constraints, deliberate):
--   * a FOUND module that fails to compile or execute RAISES
--     "PZ_REQUIRE: load error in '<path>': <msg>" (level 0) and is NOT
--     cached — the engine logs-and-nulls, but silent nil is exactly the
--     false-green this project fights. Not-found and recursive stays soft
--     (warn + nil) so optional-dep checks (`local d = require("x") or nil`)
--     keep working, and soft-fail is strict-independent (strict targets
--     unknown globals/events, not require misses).
--   * keep()'s persistent tier covers the CACHE ONLY: a persistent module's
--     load-time-registered listeners are still cleared by reset_events —
--     register inside a function or re-register in before_each.
--
-- Rawget discipline: every _G read/write here goes through rawget/rawset so
-- the module behaves identically with the strict unknown-global guard armed
-- (PZ_STRICT=1) and without it.

local PzRequire = {}

PzRequire._roots = {}
PzRequire._done = {}
PzRequire._value = {}
PzRequire._inflight = {}
PzRequire._persistent = {}
PzRequire._paths = {}
PzRequire._std = nil

local installed = false
local WINDOWS = package.config:sub(1, 1) == "\\"

local function normalizeKey(p)
    local k = p:gsub("\\", "/")
    k = k:gsub("/+$", "")
    k = k:gsub("^%./", "")
    return k
end

local function cacheKey(p)
    local k = normalizeKey(p)
    local parts = {}
    for seg in k:gmatch("[^/]+") do
        if seg ~= "." then
            parts[#parts + 1] = WINDOWS and seg:lower() or seg
        end
    end
    return table.concat(parts, "/")
end

local function normalizedName(name)
    local n = normalizeKey(name)
    if n:match("%.lua$") == nil then
        n = n .. ".lua"
    end
    return n
end

local function isTraversal(name)
    for seg in normalizeKey(name):gmatch("[^/]+") do
        if seg == ".." then return true end
    end
    return false
end

local quoteShellPath = dofile(
    (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".")
        .. "/../shellpath.lua").quote

local function dirHasEntries(dir)
    local q = quoteShellPath(dir)
    if not q then return false end
    local cmd
    if package.config:sub(1, 1) == "\\" then
        cmd = "dir /b " .. q .. " 2>nul"
    else
        cmd = "ls -1 " .. q .. " 2>/dev/null"
    end
    local p = io.popen(cmd)
    if not p then return false end
    local n = 0
    for _ in p:lines() do n = n + 1 end
    p:close()
    return n > 0
end

function PzRequire.init(roots)
    PzRequire._roots = {}
    PzRequire._done = {}
    PzRequire._value = {}
    PzRequire._inflight = {}
    PzRequire._persistent = {}
    PzRequire._paths = {}
    for _, r in ipairs(roots or {}) do
        local dir = normalizeKey(r)
        if dirHasEntries(dir) then
            table.insert(PzRequire._roots, dir)
        else
            print("PZ_REQUIRE: root dir missing '" .. dir .. "'")
        end
    end
    return true
end

function PzRequire.resolve(name)
    if isTraversal(name) then
        print("PZ_REQUIRE: rejected '..' traversal in '" .. normalizeKey(name) .. "'")
        return nil
    end
    local n = normalizedName(name)
    for _, root in ipairs(PzRequire._roots) do
        local cand = root .. "/" .. n
        local f = io.open(cand, "r")
        if f then
            local _, rerr = f:read(1)
            f:close()
            if rerr == nil then
                local key = cacheKey(cand)
                if PzRequire._paths[key] == nil then
                    PzRequire._paths[key] = normalizeKey(cand)
                end
                return key
            end
        end
    end
    return nil
end

function PzRequire.require_file(abs_path)
    local real = normalizeKey(abs_path)
    local key = cacheKey(real)
    if PzRequire._done[key] then
        return PzRequire._value[key]
    end
    if PzRequire._inflight[key] then
        print("PZ_REQUIRE: circular require of '" .. key .. "' skipped")
        return nil
    end
    local load_path = PzRequire._paths[key] or real
    PzRequire._paths[key] = load_path
    local chunk, err = loadfile(load_path)
    if not chunk then
        error("PZ_REQUIRE: load error in '" .. key .. "': " .. tostring(err), 0)
    end
    PzRequire._inflight[key] = true
    local ok, ret = pcall(chunk)
    PzRequire._inflight[key] = nil
    if not ok then
        error("PZ_REQUIRE: load error in '" .. key .. "': " .. tostring(ret), 0)
    end
    PzRequire._done[key] = true
    PzRequire._value[key] = ret
    return ret
end

function PzRequire.require(name)
    if type(name) == "string" and isTraversal(name) then
        print("PZ_REQUIRE: rejected '..' traversal in '" .. normalizeKey(name) .. "'")
        return nil
    end
    if type(name) == "string" then
        local pkey = "provided:" .. cacheKey(name)
        if PzRequire._done[pkey] then
            return PzRequire._value[pkey]
        end
    end
    local path = type(name) == "string" and PzRequire.resolve(name) or nil
    if not path then
        if type(name) == "string" and isTraversal(name) then
            return nil
        end
        print("PZ_REQUIRE: module not found '" .. tostring(name) .. "'")
        return nil
    end
    return PzRequire.require_file(path)
end

function PzRequire.provide(name, value)
    local key = "provided:" .. cacheKey(tostring(name))
    PzRequire._done[key] = true
    PzRequire._value[key] = value
    PzRequire._persistent[key] = true
end

function PzRequire.install()
    if installed then return end
    installed = true
    PzRequire._std = rawget(_G, "require")
    rawset(_G, "require", PzRequire.require)
    rawset(_G, "testkit", {
        resetLoaded = function()
            PzRequire.reset()
            PzRequire.reset_events()
        end,
        keep = PzRequire.keep,
        provide = PzRequire.provide,
        std_require = PzRequire._std,
    })
end

function PzRequire.keep(name)
    local path = type(name) == "string" and PzRequire.resolve(name) or nil
    if not path or not PzRequire._done[path] then
        print("PZ_REQUIRE: keep('" .. tostring(name) .. "') — not loaded")
        return
    end
    PzRequire._persistent[path] = true
end

function PzRequire.reset()
    for k in pairs(PzRequire._done) do
        if not PzRequire._persistent[k] then
            PzRequire._done[k] = nil
            PzRequire._value[k] = nil
        end
    end
    PzRequire._inflight = {}
end

function PzRequire.reset_events()
    rawset(_G, "_pz_logs", {})
    local is_dispatcher = rawget(_G, "__pz_is_dispatcher")
    if type(is_dispatcher) ~= "function" then
        print("PZ_REQUIRE: __pz_is_dispatcher missing — reset_events falling back to duck-typed clearing")
        for _, reg_name in ipairs({ "Events", "Hook" }) do
            local reg = rawget(_G, reg_name)
            if type(reg) == "table" then
                for k, v in pairs(reg) do
                    if type(k) == "string" and k:match("^On")
                        and type(v) == "table" and type(v.Clear) == "function" then
                        v.Clear()
                    end
                end
            end
        end
        return
    end
    for _, reg_name in ipairs({ "Events", "Hook" }) do
        local reg = rawget(_G, reg_name)
        if type(reg) == "table" then
            for _, v in pairs(reg) do
                if is_dispatcher(v) then
                    v:Clear()
                end
            end
        end
    end
end

_G.PzRequire = PzRequire
return PzRequire
