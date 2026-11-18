local function pzrequirePath()
    for entry in package.path:gmatch("[^;]+") do
        local cand = entry:gsub("%?", "pzrequire")
        if cand:match("stubs[/\\]pzrequire%.lua$") then return cand end
    end
    return nil
end

local PzRequire = rawget(_G, "PzRequire")
if not PzRequire then
    local path = pzrequirePath()
    if path then pcall(dofile, path) end
    PzRequire = rawget(_G, "PzRequire")
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
local R = FIX .. "/root_b"

describe("pzrequire contract require", function()
    local util_m

    before_all(function()
        buildFixture(FIX)

        LuaEventManager.AddEvent("OnFixtureTick")

        __FIX_UTIL_N = 0

        local f = io.open(U .. "/shared/util.lua", "r")
        expect(f ~= nil).toBeTruthy()
        if f then f:close() end
    end)

    after_all(function()

        if PzRequire then
            PzRequire.init({})
            if PzRequire._std then
                rawset(_G, "require", PzRequire._std)
            end
        end
        rawset(_G, "testkit", nil)
        __FIX_UTIL_N = nil
        __FIX_CLI = nil
        __FIX_SRV = nil
        __FIX_GREETER = nil
    end)

    it("(a) install: _G.require swapped, testkit facade created, _std saved once (idempotent)", function()
        local stdBefore = rawget(_G, "require")
        PzRequire.install()
        expect(rawget(_G, "require")).toBe(PzRequire.require)
        expect(type(PzRequire._std)).toBe("function")
        expect(PzRequire._std).toBe(stdBefore)
        local tk = rawget(_G, "testkit")
        expect(type(tk)).toBe("table")
        expect(type(tk.resetLoaded)).toBe("function")
        expect(type(tk.keep)).toBe("function")
        expect(type(tk.std_require)).toBe("function")

        expect(tk.std_require).toBe(stdBefore)

        PzRequire.install()
        expect(PzRequire._std).toBe(stdBefore)
        expect(rawget(_G, "require")).toBe(PzRequire.require)
    end)

    it("(b) init: normalizes and records roots in order, returns true", function()
        expect(PzRequire.init({ U .. "/", R .. "\\" })).toBe(true)
        expect(PzRequire._roots).toEqual({ U, R })
    end)

    it("(c) init: missing root dir -> ONE exact warn, skipped, others kept", function()
        local missing = FIX .. "/no_such_root_dir"
        local warns = {}
        local s = spyOn(_G, "print")
        local ok, err = pcall(function()
            PzRequire.init({ U, missing })
        end)
        s.restore()
        if not ok then error(err, 0) end
        expect(#s.calls).toBe(1)
        expect(s.calls[1][1]).toBe("PZ_REQUIRE: root dir missing '" .. missing .. "'")
        expect(PzRequire._roots).toEqual({ U })
    end)

    it("(d) require: .lua append + first-hit scan -> module table, executes once", function()
        PzRequire.init({ U })
        util_m = require("shared/util")
        expect(type(util_m)).toBe("table")
        expect(util_m.marker).toBe("util")
        expect(__FIX_UTIL_N).toBe(1)
        local abs = PzRequire.resolve("shared/util")
        expect(PzRequire._done[abs]).toBe(true)
    end)

    it("(e) cache: .lua / ./ / backslash forms -> same table identity, counter still 1", function()
        expect(require("shared/util.lua")).toBe(util_m)
        expect(require("./shared/util")).toBe(util_m)
        expect(require("shared\\util")).toBe(util_m)
        expect(__FIX_UTIL_N).toBe(1)

        expect(PzRequire.resolve("shared/util.lua")).toBe(PzRequire.resolve("shared/util"))
        expect(PzRequire.resolve("./shared/util")).toBe(PzRequire.resolve("shared/util"))
        expect(PzRequire.resolve("shared\\util")).toBe(PzRequire.resolve("shared/util"))
    end)

    it("(f) ordered roots: first-hit scan; re-init resets the cache between orders", function()
        local n0 = __FIX_UTIL_N
        PzRequire.init({ U, R })
        local a = require("shared/util")
        expect(a.marker).toBe("util")
        expect(__FIX_UTIL_N).toBe(n0 + 1)
        PzRequire.init({ R, U })
        local b = require("shared/util")

        expect(b.marker).toBe("shadow")
        expect(__FIX_UTIL_N).toBe(n0 + 1)
        expect(b ~= a).toBeTruthy()
    end)

    it("(g) not-found: soft-fail nil, no error, ONE exact warn", function()
        PzRequire.init({ U })
        local s = spyOn(_G, "print")
        local v
        local ok, err = pcall(function()
            v = require("shared/nope")
        end)
        s.restore()
        if not ok then error(err, 0) end
        expect(v).toBeNil()
        expect(#s.calls).toBe(1)
        expect(s.calls[1][1]).toBe("PZ_REQUIRE: module not found 'shared/nope'")
    end)

    it("(h) nil-return module: no error, nil twice, done flag set (execute-once)", function()
        PzRequire.init({ U })
        local abs = PzRequire.resolve("shared/nilret")
        expect(type(abs)).toBe("string")
        local v1 = PzRequire.require_file(abs)
        expect(v1).toBeNil()
        expect(PzRequire._done[abs]).toBe(true)
        local v2 = PzRequire.require_file(abs)
        expect(v2).toBeNil()
        expect(PzRequire._value[abs]).toBeNil()
    end)

    it("(i) circular require: nil + circular warn, no hang", function()
        PzRequire.init({ U })
        local s = spyOn(_G, "print")
        local v
        local ok, err = pcall(function()
            v = require("shared/circular_a")
        end)
        s.restore()
        if not ok then error(err, 0) end
        expect(v).toBeNil()
        local found = false
        for _, c in ipairs(s.calls) do
            if type(c[1]) == "string" and c[1]:find("circular require", 1, true) then
                found = true
            end
        end
        expect(found).toBeTruthy()
    end)

    it("(j) broken module: raises with pinned prefix + path, entry NOT cached", function()
        PzRequire.init({ U })
        local ok, err = pcall(function()
            return require("shared/broken")
        end)
        expect(ok).toBe(false)
        expect(type(err)).toBe("string")
        expect(err:find("PZ_REQUIRE: load error in '", 1, true)).toBeTruthy()
        local abs = PzRequire.resolve("shared/broken")
        expect(err:find("'" .. abs .. "'", 1, true)).toBeTruthy()
        expect(PzRequire._done[abs]).toBeNil()
    end)

    it("(k) soft-fail under strict: not-found still nil + warn, no error", function()
        local saved = _G.pz_strict
        local s = spyOn(_G, "print")
        local ok, err = pcall(function()
            _G.pz_strict = true
            local v = require("shared/nope")
            expect(v).toBeNil()
        end)
        _G.pz_strict = saved
        s.restore()
        if not ok then error(err, 0) end
        expect(#s.calls).toBe(1)
        expect(s.calls[1][1]).toBe("PZ_REQUIRE: module not found 'shared/nope'")
    end)

    it("(l) greeter: top-level Events registration; reset_events clears listeners, allowlist untouched", function()
        PzRequire.init({ U })
        local v = require("shared/greeter")
        expect(v).toBeNil()
        expect(__FIX_GREETER).toBe(true)
        expect(Events.OnFixtureTick._count()).toBe(1)

        Hook.OnFixtureTick.Add(function() end)
        expect(Hook.OnFixtureTick._count()).toBe(1)
        PzRequire.reset_events()
        expect(Events.OnFixtureTick._count()).toBe(0)
        expect(Hook.OnFixtureTick._count()).toBe(0)

        local have = false
        for _, n in ipairs(_G.__pz_events_list.names) do
            if n == "OnFixtureTick" then have = true end
        end
        expect(have).toBeTruthy()

        require("shared/greeter")
        expect(Events.OnFixtureTick._count()).toBe(0)

        PzRequire.reset()
        require("shared/greeter")
        expect(Events.OnFixtureTick._count()).toBe(1)
    end)

    it("(m) reset: dropped entries re-execute exactly once; in-flight cleared", function()
        local n0 = __FIX_UTIL_N
        PzRequire.init({ U })
        local m1 = require("shared/util")
        expect(__FIX_UTIL_N).toBe(n0 + 1)
        PzRequire.reset()
        local m2 = require("shared/util")
        expect(__FIX_UTIL_N).toBe(n0 + 2)
        expect(m1 ~= m2).toBeTruthy()
        expect(m2).toEqual({ marker = "util" })

        PzRequire._inflight["probe/path"] = true
        PzRequire.reset()
        expect(PzRequire._inflight["probe/path"]).toBeNil()
    end)

    it("(n) persistent tier: keep() survives resetLoaded; events still cleared (cache-only tier)", function()
        local n0 = __FIX_UTIL_N
        PzRequire.init({ U })
        local m1 = require("shared/util")
        expect(__FIX_UTIL_N).toBe(n0 + 1)
        PzRequire.keep("shared/util")
        _G.testkit.resetLoaded()
        local m2 = require("shared/util")
        expect(__FIX_UTIL_N).toBe(n0 + 1)
        expect(m2).toBe(m1)

        expect(Events.OnFixtureTick._count()).toBe(0)

        require("shared/greeter")
        expect(Events.OnFixtureTick._count()).toBe(1)
    end)

    it("(o) keep of an unloaded name: ONE exact warn (em dash), no state change", function()
        PzRequire.init({ U })
        local s = spyOn(_G, "print")
        local ok, err = pcall(function()
            PzRequire.keep("shared/not_loaded_yet")
        end)
        s.restore()
        if not ok then error(err, 0) end
        expect(#s.calls).toBe(1)
        expect(s.calls[1][1]).toBe("PZ_REQUIRE: keep('shared/not_loaded_yet') — not loaded")
    end)

    it("(p) client/ and server/ subdir names resolve through the same root scan", function()
        PzRequire.init({ U })
        require("client/cli_only")
        expect(__FIX_CLI).toBe(true)
        require("server/srv_only")
        expect(__FIX_SRV).toBe(true)
    end)

    it("(q) persistent tier covers the CACHE only: kept module's listeners stay cleared, no re-registration", function()
        PzRequire.init({ U })
        require("shared/greeter")
        PzRequire.keep("shared/greeter")
        _G.testkit.resetLoaded()
        local abs = PzRequire.resolve("shared/greeter")
        expect(PzRequire._done[abs]).toBe(true)
        expect(Events.OnFixtureTick._count()).toBe(0)
        require("shared/greeter")
        expect(Events.OnFixtureTick._count()).toBe(0)
    end)
end)
