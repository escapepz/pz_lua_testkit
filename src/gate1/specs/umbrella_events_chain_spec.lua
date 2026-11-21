local function umbrellaPath()
    for entry in package.path:gmatch("[^;]+") do
        local cand = entry:gsub("%?", "umbrella")
        if cand:match("stubs[/\\]umbrella%.lua$") then return cand end
    end
    return nil
end

local Umbrella = rawget(_G, "Umbrella")
if not Umbrella then
    local path = umbrellaPath()
    if path then pcall(dofile, path) end
    Umbrella = rawget(_G, "Umbrella")
end

if rawget(_G, "ModData") == nil then
    pcall(require, "game")
end

local function fixtureDir()
    local dir = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
    local stripped = dir:gsub("[/\\]src[/\\]gate1$", "")
    if stripped == dir or stripped == "" then stripped = dir .. "/../.." end
    return stripped .. "/.tmp/umbrella_fixture"
end

local function snapshotAllowlist()
    local list = _G.__pz_events_list
    if not (type(list) == "table" and type(list.events) == "table") then
        return nil
    end
    local copy = {}
    for i, n in ipairs(list.events) do copy[i] = n end
    return copy
end

local function restoreAllowlist(copy)
    if not copy then return end
    local names = _G.__pz_events_list.events
    for i = #names, 1, -1 do names[i] = nil end
    for i, n in ipairs(copy) do names[i] = n end
end

local function clearEvent(name)
    _G.Events[name] = nil
end

local pristine_names = snapshotAllowlist()

describe("umbrella events extension + chain (Task 4)", function()
    local root

    before_all(function()
        root = Umbrella._fixture(fixtureDir())
    end)

    after_all(function()
        Umbrella.init(nil)
        restoreAllowlist(pristine_names)
    end)

    local function initOn()
        local ok = Umbrella.init(root)
        expect(ok).toBeTruthy()
    end

    it("(a) events_lookup: OnFoo/OnBar true (fixture events.lua scan), extension sorted+idempotent, misses do not extend, mode-gated", function()
        local saved_strict = _G.pz_strict
        local saved_names = snapshotAllowlist()
        local ok, err = pcall(function()
            initOn()
            local names = _G.__pz_events_list.events
            local before = #names
            expect(Umbrella.events_lookup("OnFoo")).toBe(true)
            expect(Umbrella.events_lookup("OnBar")).toBe(true)

            local have = {}
            for _, n in ipairs(names) do have[n] = true end
            expect(have.OnFoo).toBeTruthy()
            expect(have.OnBar).toBeTruthy()
            for i = 2, #names do
                expect(names[i - 1] < names[i]).toBeTruthy()
            end

            expect(Umbrella.events_lookup("OnFoo")).toBe(true)
            expect(#names).toBe(before + 2)

            expect(Umbrella.events_lookup("OnNope")).toBe(false)
            expect(#names).toBe(before + 2)

            expect(Umbrella.events_lookup(42)).toBe(false)
            expect(Umbrella.events_lookup(nil)).toBe(false)
        end)
        _G.pz_strict = saved_strict
        restoreAllowlist(saved_names)
        Umbrella.init(nil)
        if not ok then error(err, 0) end

        local saved_names2 = snapshotAllowlist()
        local ok2, err2 = pcall(function()
            expect(Umbrella.events_lookup("OnFoo")).toBe(false)
            expect(#_G.__pz_events_list.events).toBe(#saved_names2)
        end)
        restoreAllowlist(saved_names2)
        if not ok2 then error(err2, 0) end
    end)

    it("(b) strict mode-on: Events.OnFoo dispatcher via umbrella-extended events allowlist; OnNope still errors; Hook does NOT see the extension (umbrella consult is Events-only)", function()
        local saved_strict = _G.pz_strict
        local saved_names = snapshotAllowlist()
        local ok, err = pcall(function()
            initOn()
            _G.pz_strict = true

            local e = Events.OnFoo
            expect(type(e)).toBe("table")
            expect(type(e.Add)).toBe("function")
            expect(type(e.Remove)).toBe("function")
            expect(type(e.Clear)).toBe("function")
            expect(type(e._fire)).toBe("function")
            expect(type(e._count)).toBe("function")
            expect(e._count()).toBe(0)

            local called = 0
            e.Add(function() called = called + 1 end)
            e._fire()
            expect(called).toBe(1)

            local have = {}
            for _, n in ipairs(_G.__pz_events_list.events) do have[n] = true end
            expect(have.OnFoo).toBeTruthy()

            local hok, herr = pcall(function() return Hook.OnFoo end)
            expect(hok).toBe(false)
            expect(tostring(herr):find("PZ_STRICT: unknown PZ event 'Hook.OnFoo'", 1, true)).toBeTruthy()
            expect(rawget(Hook, "OnFoo")).toBeNil()

            local eok, emsg = pcall(function() return Events.OnNope end)
            expect(eok).toBe(false)
            expect(tostring(emsg):find("PZ_STRICT: unknown PZ event 'Events.OnNope'", 1, true)).toBeTruthy()
            expect(rawget(_G.Events, "OnNope")).toBeNil()
        end)
        _G.pz_strict = saved_strict
        restoreAllowlist(saved_names)
        clearEvent("OnFoo")
        clearEvent("OnNope")
        Umbrella.init(nil)
        if not ok then error(err, 0) end
    end)

    it("(c) non-strict mode-on: OnFoo/OnNope auto-create as today, allowlist NOT extended (lookup not consulted)", function()
        local saved_strict = _G.pz_strict
        local saved_names = snapshotAllowlist()
        local ok, err = pcall(function()
            initOn()
            _G.pz_strict = false
            local before = #_G.__pz_events_list.events
            expect(type(Events.OnFoo.Add)).toBe("function")
            expect(type(Events.OnNope.Add)).toBe("function")
            expect(#_G.__pz_events_list.events).toBe(before)
        end)
        _G.pz_strict = saved_strict
        restoreAllowlist(saved_names)
        clearEvent("OnFoo")
        clearEvent("OnNope")
        Umbrella.init(nil)
        if not ok then error(err, 0) end
    end)

    it("(d) feature-off: strict Events.OnFoo errors (no hook), non-strict auto-creates — today's behavior in both states", function()
        local saved_strict = _G.pz_strict
        local saved_names = snapshotAllowlist()
        local ok, err = pcall(function()
            Umbrella.init(nil)
            _G.pz_strict = true
            local eok, emsg = pcall(function() return Events.OnFoo end)
            expect(eok).toBe(false)
            expect(tostring(emsg):find("PZ_STRICT: unknown PZ event 'Events.OnFoo'", 1, true)).toBeTruthy()
        end)
        _G.pz_strict = saved_strict
        restoreAllowlist(saved_names)
        clearEvent("OnFoo")
        if not ok then error(err, 0) end
        local ok2, err2 = pcall(function()
            _G.pz_strict = false
            expect(type(Events.OnFoo.Add)).toBe("function")
        end)
        _G.pz_strict = saved_strict
        clearEvent("OnFoo")
        if not ok2 then error(err2, 0) end
    end)

    it("(e) chain: Foo stub ->getThing-> served Data stub (stable identity, fields nil); 2-step success shares it; local-only Baz served", function()
        local saved_strict = _G.pz_strict
        local ok, err = pcall(function()
            initOn()
            local foo = Umbrella.resolve_global("Foo")
            expect(foo).toBeTruthy()
            local data = Umbrella.chain(foo, "getThing")
            expect(type(data)).toBe("table")
            expect(data).toBe(Umbrella.chain(foo, "getThing"))
            expect(data.alarm).toBeNil()
            expect(data.name).toBeNil()

            local data2 = Umbrella.chain(foo, "getHelper", "getPayload")
            expect(data2).toBe(data)
            local baz = Umbrella.chain(foo, "getHelper")
            expect(type(baz)).toBe("table")
            expect(baz).toBe(Umbrella.chain(foo, "getHelper"))
            expect(baz.bazOnly).toBeTruthy()

            expect(Umbrella.chain(foo)).toBe(foo)
        end)
        _G.pz_strict = saved_strict
        Umbrella.init(nil)
        if not ok then error(err, 0) end
    end)

    it("(f) chain rets: first RESOLVING entry wins (getLoose: number+Data -> Data)", function()
        local saved_strict = _G.pz_strict
        local ok, err = pcall(function()
            initOn()
            local foo = Umbrella.resolve_global("Foo")
            local data = Umbrella.chain(foo, "getThing")
            expect(Umbrella.chain(foo, "getLoose")).toBe(data)
        end)
        _G.pz_strict = saved_strict
        Umbrella.init(nil)
        if not ok then error(err, 0) end
    end)

    it("(g) chain aborts: primitive/union/generic rets and unknown methods return nil, never coerced", function()
        local saved_strict = _G.pz_strict
        local ok, err = pcall(function()
            initOn()
            local foo = Umbrella.resolve_global("Foo")

            expect(Umbrella.chain(foo, "nope")).toBeNil()

            expect(Umbrella.chain(foo, "transform")).toBeNil()

            expect(Umbrella.chain(foo, "getNum")).toBeNil()

            expect(Umbrella.chain(foo, "getMany")).toBeNil()

            expect(Umbrella.chain(foo, "getThing")).toBeTruthy()

            expect(Umbrella.chain(foo, "getThing", "nope")).toBeNil()

            expect(Umbrella.chain(foo, "getHelper", "getCount")).toBeNil()

            expect(Umbrella.chain({}, "getThing")).toBeNil()
            expect(Umbrella.chain(nil, "getThing")).toBeNil()
            expect(Umbrella.chain(42, "getThing")).toBeNil()

            expect(Umbrella.chain(foo, "getThing", 42)).toBeNil()
        end)
        _G.pz_strict = saved_strict
        Umbrella.init(nil)
        if not ok then error(err, 0) end
    end)

    it("(h) chain via Seam C: wrapped probe -> Foo DAG -> Data; shipped class tables resolve via MAPPING; clone-absent classes abort nil", function()
        local saved_strict = _G.pz_strict
        local ok, err = pcall(function()
            initOn()
            local foo = Umbrella.resolve_global("Foo")
            local data = Umbrella.chain(foo, "getThing")

            local probe = {}
            Umbrella.w(probe, "Foo")
            expect(Umbrella.chain(probe, "getThing")).toBe(data)

            expect(Umbrella.chain(_G.IsoPlayer, "getThing")).toBeNil()

            local p = getSpecificPlayer(0)
            expect(Umbrella.chain(p, "getThing")).toBeNil()
        end)
        _G.pz_strict = saved_strict
        Umbrella.init(nil)
        if not ok then error(err, 0) end
    end)

    it("(i) mode off: chain -> nil (identity-safe), events_lookup -> false", function()
        Umbrella.init(nil)
        expect(Umbrella.chain({}, "getThing")).toBeNil()
        expect(Umbrella.chain(_G.IsoPlayer, "getThing")).toBeNil()
        expect(Umbrella.events_lookup("OnFoo")).toBe(false)
    end)
end)
