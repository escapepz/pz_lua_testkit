local function runnerPath()
    for entry in package.path:gmatch("[^;]+") do
        local cand = entry:gsub("%?", "gate1/runner")

        if cand:match("[/\\]gate1[/\\]runner%.lua$") then return cand end
    end
    return nil
end

local function pzrequirePath()
    for entry in package.path:gmatch("[^;]+") do
        local cand = entry:gsub("%?", "pzrequire")
        if cand:match("stubs[/\\]pzrequire%.lua$") then return cand end
    end
    return nil
end

local runner = nil
local rp = runnerPath()
if rp then runner = dofile(rp) end

local pzspec = rawget(_G, "__pzspec")

local BASE_GLOBALS_N = (type(pzspec) == "table"
    and type(pzspec._global_befores) == "table")
    and #pzspec._global_befores or 0

local function truncateGlobalBefores()
    if type(pzspec) ~= "table" or type(pzspec._global_befores) ~= "table" then
        return
    end
    while #pzspec._global_befores > BASE_GLOBALS_N do
        table.remove(pzspec._global_befores)
    end
end

local function removeGlobalBefore(fn)
    if type(pzspec) ~= "table" or type(pzspec._global_befores) ~= "table" then
        return
    end
    local list = pzspec._global_befores
    for i = #list, 1, -1 do
        if list[i] == fn then table.remove(list, i) end
    end
end

local function withEnv(name, value, fn)
    local orig = os.getenv
    os.getenv = function(q)
        if q == name then return value end
        return orig(q)
    end
    local ok, err = pcall(fn)
    os.getenv = orig
    if not ok then error(err, 0) end
end

local function fixtureDir()
    local dir = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
    local stripped = dir:gsub("[/\\]src[/\\]gate1$", "")
    if stripped == dir or stripped == "" then stripped = dir .. "/../.." end
    return stripped .. "/.tmp/pzrequire_fixture"
end

local function buildFixture(fx)
    local WINDOWS = (package.config:sub(1, 1) == "\\")
    local function mkdirp(d)
        if WINDOWS then
            os.execute('mkdir "' .. (d:gsub("/", "\\")) .. '" 2>nul')
        else
            os.execute('mkdir -p "' .. d .. '" 2>/dev/null')
        end
    end
    local U = fx .. "/mod_a/media/lua"
    local dirs = {
        U .. "/shared",
        U .. "/client",
        U .. "/server",
        fx .. "/root_b/shared",
    }
    for _, d in ipairs(dirs) do mkdirp(d) end
    local files = {
        [U .. "/shared/util.lua"] =
            '__FIX_UTIL_N = (rawget(_G, "__FIX_UTIL_N") or 0) + 1\nreturn { marker = "util" }\n',
        [U .. "/shared/nilret.lua"] = "",
        [U .. "/client/cli_only.lua"] = "__FIX_CLI = true\n",
        [U .. "/server/srv_only.lua"] = "__FIX_SRV = true\n",
        [U .. "/shared/greeter.lua"] =
            "__FIX_GREETER = true\nEvents.OnFixtureTick.Add(function() end)\n",
        [U .. "/shared/circular_a.lua"] = 'require("shared/circular_b")\n',
        [U .. "/shared/circular_b.lua"] = 'require("shared/circular_a")\n',
        [U .. "/shared/broken.lua"] = "this is not = valid lua\n",
        [fx .. "/root_b/shared/util.lua"] = 'return { marker = "shadow" }\n',
    }
    for path, content in pairs(files) do
        local f = io.open(path, "wb")
        if f then
            f:write(content)
            f:close()
        end
    end
end

local FIX = fixtureDir()
local U = FIX .. "/mod_a/media/lua"

local PzRequire
local hookFn
local m_b1, m_b2, m_c1

describe("resetLoaded per-test: pzspec global tier + runner.wire_reset", function()
    before_all(function()
        local pp = pzrequirePath()
        if pp then PzRequire = dofile(pp) end
        buildFixture(FIX)
        local f = io.open(U .. "/shared/util.lua", "r")
        expect(f ~= nil).toBeTruthy()
        if f then f:close() end

        LuaEventManager.AddEvent("OnFixtureTick")

        __FIX_UTIL_N = 0
        if PzRequire then PzRequire.install() end
    end)

    after_all(function()
        truncateGlobalBefores()
    end)

    it("(a) tier: global_before_each appends to pzspec._global_befores; _run_global_befores invokes in order", function()
        expect(type(pzspec)).toBe("table")
        expect(type(pzspec.global_before_each)).toBe("function")
        expect(type(pzspec._global_befores)).toBe("table")
        expect(type(pzspec._run_global_befores)).toBe("function")
        local calls = {}
        local fn1 = function() calls[#calls + 1] = "one" end
        local fn2 = function() calls[#calls + 1] = "two" end
        local n0 = #pzspec._global_befores
        pzspec.global_before_each(fn1)
        pzspec.global_before_each(fn2)
        expect(#pzspec._global_befores).toBe(n0 + 2)
        expect(pzspec._global_befores[n0 + 1]).toBe(fn1)
        expect(pzspec._global_befores[n0 + 2]).toBe(fn2)
        pzspec._run_global_befores()
        expect(calls).toEqual({ "one", "two" })

        truncateGlobalBefores()
        expect(#pzspec._global_befores).toBe(n0)
    end)

    it("(b) wire_reset three-state matrix: explicit config wins, then env PZ_RESET_PER_TEST, then mod-set default", function()
        expect(type(runner)).toBe("table")
        expect(type(runner.wire_reset)).toBe("function")
        local n0 = #pzspec._global_befores
        local function wiredDelta(r)

            expect(#pzspec._global_befores).toBe(n0 + (r and 1 or 0))
            truncateGlobalBefores()
        end

        wiredDelta(runner.wire_reset({ mod = FIX, reset_per_test = true }, true))

        wiredDelta(runner.wire_reset({ mod = FIX, reset_per_test = false }, true))

        wiredDelta(runner.wire_reset({}, true))

        wiredDelta(runner.wire_reset({ mod = FIX }, true))

        wiredDelta(runner.wire_reset({ mod = FIX, reset_per_test = true }, false))

        withEnv("PZ_RESET_PER_TEST", "1", function()
            wiredDelta(runner.wire_reset({}, true))
        end)
        withEnv("PZ_RESET_PER_TEST", "0", function()
            wiredDelta(runner.wire_reset({ mod = FIX }, true))
        end)

        withEnv("PZ_RESET_PER_TEST", nil, function()
            wiredDelta(runner.wire_reset({}, true))
        end)
    end)

    it("(c) the registered hook is TOTAL and strict-safe: no raise with testkit missing/bogus, and it drives resetLoaded when present", function()

        local ok = runner.wire_reset({ mod = FIX, reset_per_test = true }, true)
        expect(ok).toBeTruthy()
        local hook = pzspec._global_befores[#pzspec._global_befores]
        expect(type(hook)).toBe("function")
        local tkRef = rawget(_G, "testkit")
        expect(type(tkRef)).toBe("table")

        rawset(_G, "testkit", nil)

        rawset(_G, "testkit", {})
        local savedStrict = _G.pz_strict
        local ok2 = pcall(function()
            _G.pz_strict = true
            hook()
        end)
        _G.pz_strict = savedStrict
        expect(ok2).toBeTruthy()

        rawset(_G, "testkit", tkRef)
        PzRequire.init({ U })
        local abs = PzRequire.resolve("shared/nilret")
        PzRequire.require_file(abs)
        expect(PzRequire._done[abs]).toBe(true)
        hook()
        expect(PzRequire._done[abs]).toBeNil()
        truncateGlobalBefores()
    end)

    it("(d) resetLoaded semantics: cache re-executes exactly once more, listeners cleared then re-registered exactly once", function()
        PzRequire.init({ U })
        local m1 = require("shared/util")
        expect(type(m1)).toBe("table")
        expect(__FIX_UTIL_N).toBe(1)
        require("shared/greeter")
        expect(Events.OnFixtureTick._count()).toBe(1)
        rawget(_G, "testkit").resetLoaded()
        local m2 = require("shared/util")
        expect(m2 ~= m1).toBeTruthy()
        expect(__FIX_UTIL_N).toBe(2)
        require("shared/greeter")
        expect(Events.OnFixtureTick._count()).toBe(1)

    end)

    it("(e) keep() entries survive resetLoaded; kept module's listeners still clear (cache-only tier)", function()
        local m1 = require("shared/util")
        expect(__FIX_UTIL_N).toBe(2)
        PzRequire.keep("shared/util")
        rawget(_G, "testkit").resetLoaded()
        local m2 = require("shared/util")
        expect(m2).toBe(m1)
        expect(__FIX_UTIL_N).toBe(2)
        expect(Events.OnFixtureTick._count()).toBe(0)
        require("shared/greeter")
        expect(Events.OnFixtureTick._count()).toBe(1)
    end)

    it("(f) provide() entries survive resetLoaded (test fixtures, not mod code)", function()
        local tk = rawget(_G, "testkit")
        tk.provide("dep_probe", { v = "stub" })
        expect(require("dep_probe")).toEqual({ v = "stub" })
        tk.resetLoaded()
        expect(require("dep_probe")).toEqual({ v = "stub" })
    end)

    it("(g) strict interplay: resetLoaded runs clean with _G.pz_strict armed (rawget discipline)", function()
        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = true
            rawget(_G, "testkit").resetLoaded()
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end
        expect(ok).toBeTruthy()
    end)
end)

describe("resetLoaded per-test: live through pzspec.run (mod mode, reset on)", function()
    before_all(function()

        local ok = runner.wire_reset({ mod = FIX, reset_per_test = true }, true)
        expect(ok).toBeTruthy()
        hookFn = pzspec._global_befores[#pzspec._global_befores]
        expect(type(hookFn)).toBe("function")

        PzRequire.init({ U })
        __FIX_UTIL_N = 0
    end)

    after_all(function()
        removeGlobalBefore(hookFn)
        hookFn = nil
    end)

    it("(b1) first test: fresh cache -> util executes once, greeter registers once", function()
        m_b1 = require("shared/util")
        expect(type(m_b1)).toBe("table")
        expect(__FIX_UTIL_N).toBe(1)
        require("shared/greeter")
        expect(Events.OnFixtureTick._count()).toBe(1)
    end)

    it("(b2) second test: cache was reset between tests -> util re-executes (new identity, counter increments); keep + provide armed for (b3)", function()

        m_b2 = require("shared/util")
        expect(m_b2 ~= m_b1).toBeTruthy()
        expect(__FIX_UTIL_N).toBe(2)
        PzRequire.keep("shared/util")
        rawget(_G, "testkit").provide("dep_probe", { v = "stub" })

        require("shared/greeter")
        expect(Events.OnFixtureTick._count()).toBe(1)
    end)

    it("(b3) third test: kept and provided entries survived the per-test reset; greeter fresh again exactly once", function()
        local m3 = require("shared/util")
        expect(m3).toBe(m_b2)
        expect(__FIX_UTIL_N).toBe(2)
        expect(require("dep_probe")).toEqual({ v = "stub" })
        require("shared/greeter")
        expect(Events.OnFixtureTick._count()).toBe(1)
    end)
end)

describe("resetLoaded off: no reset hook, require state persists across tests", function()
    before_all(function()

        removeGlobalBefore(hookFn)
        expect(#pzspec._global_befores).toBe(BASE_GLOBALS_N)

        PzRequire.init({ U })
        __FIX_UTIL_N = 0
    end)

    it("(c1) without the hook: util executes once in the first test", function()
        m_c1 = require("shared/util")
        expect(type(m_c1)).toBe("table")
        expect(__FIX_UTIL_N).toBe(1)
    end)

    it("(c2) second test: SAME cached table, counter frozen — state persisted (a leaked reset would re-execute)", function()
        local m2 = require("shared/util")
        expect(m2).toBe(m_c1)
        expect(__FIX_UTIL_N).toBe(1)
    end)

    after_all(function()

        truncateGlobalBefores()
        if PzRequire then
            PzRequire.init({})
            if PzRequire._std then
                rawset(_G, "require", PzRequire._std)
            end
        end
        rawset(_G, "testkit", nil)
        rawset(_G, "PzRequire", nil)
        __FIX_UTIL_N = nil
        __FIX_GREETER = nil
        hookFn = nil
    end)
end)
