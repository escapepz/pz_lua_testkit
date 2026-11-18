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

local orig_player_mt
local orig_container_mt
local orig_panel_mt
local shipped_player_getUsername
local shipped_panel_setVisible

describe("umbrella integration (run.lua wiring + Seam C)", function()
    local root

    before_all(function()
        root = Umbrella._fixture(fixtureDir())
        Umbrella.init(nil)
        orig_player_mt = getmetatable(_G.IsoPlayer)
        orig_container_mt = getmetatable(_G.ItemContainer)
        orig_panel_mt = getmetatable(_G.ISPanel)
        shipped_player_getUsername = _G.IsoPlayer.getUsername
        shipped_panel_setVisible = _G.ISPanel.setVisible
    end)

    after_all(function()
        Umbrella.init(nil)
    end)

    local function initOn()
        local ok = Umbrella.init(root)
        expect(ok).toBeTruthy()
    end

    it("(a) Seam C surfaces exist: MAPPING (player->IsoPlayer + class inventory), w, resolve_method, events_lookup", function()
        expect(type(Umbrella.MAPPING)).toBe("table")
        expect(Umbrella.MAPPING.player).toBe("IsoPlayer")
        expect(Umbrella.MAPPING.IsoPlayer).toBe("IsoPlayer")
        expect(Umbrella.MAPPING.ItemContainer).toBe("ItemContainer")
        expect(Umbrella.MAPPING.ISPanel).toBe("ISPanel")
        expect(Umbrella.MAPPING.ISWalkToTimedAction).toBe("ISWalkToTimedAction")
        expect(type(Umbrella.w)).toBe("function")
        expect(type(Umbrella.resolve_method)).toBe("function")
        expect(type(Umbrella.events_lookup)).toBe("function")
    end)

    it("(b) mode off: w is identity — wrapped tables and fresh factory products get NO metatable", function()
        Umbrella.init(nil)
        local probe = { shipped = function() return "S" end }
        local r = Umbrella.w(probe, "Foo")
        expect(r).toBe(probe)
        expect(getmetatable(probe)).toBeNil()
        local p = getSpecificPlayer(0)
        local r2 = Umbrella.w(p, "IsoPlayer")
        expect(r2).toBe(p)
        expect(getmetatable(p)).toBeNil()
        local sq = getSquare(1, 2, 3)

        expect(type(getmetatable(sq).__index)).toBe("table")
    end)

    it("(c) init-on assigns __umbrella_event_lookup = events_lookup; init-off clears it", function()
        Umbrella.init(nil)
        expect(rawget(_G, "__umbrella_event_lookup")).toBeNil()
        initOn()
        expect(rawget(_G, "__umbrella_event_lookup")).toBe(Umbrella.events_lookup)
        Umbrella.init(nil)
        expect(rawget(_G, "__umbrella_event_lookup")).toBeNil()
    end)

    it("(d) events_lookup is the REAL Task 4 body (scans the fixture clone's events.lua — OnFoo/OnBar only, so both probes miss)", function()
        initOn()
        expect(Umbrella.events_lookup("OnGameStart")).toBe(false)
        expect(Umbrella.events_lookup("OnAnythingElse")).toBe(false)
        Umbrella.init(nil)
    end)

    it("(e) init-on attaches fallback __index to shipped class tables; shipped table keys keep their identity", function()
        initOn()

        expect(getmetatable(_G.IsoPlayer) == orig_player_mt).toBeFalsy()
        expect(getmetatable(_G.ItemContainer) == orig_container_mt).toBeFalsy()

        expect(_G.IsoPlayer.getUsername).toBe(shipped_player_getUsername)
        expect(_G.ISPanel.setVisible).toBe(shipped_panel_setVisible)

        expect(_G.ISInventoryPage.setVisible).toBe(shipped_panel_setVisible)
        expect(type(_G.IsoPlayer.new)).toBe("function")
        Umbrella.init(nil)

        expect(getmetatable(_G.IsoPlayer)).toBe(orig_player_mt)
        expect(_G.ISInventoryPage.setVisible).toBe(shipped_panel_setVisible)
    end)

    it("(f) factory player under mode-on: shipped methods win by CALL identity (shipped recorder runs, records)", function()
        initOn()
        local p = getSpecificPlayer(0)
        expect(getmetatable(p)).toBeTruthy()
        expect(p.getUsername).toBe(p.getUsername)
        local who = p:getUsername()
        expect(who).toBe("TestPlayer_0")
        expect(#p.getUsername.calls).toBe(1)
        expect(p:isAdmin()).toBe(false)
        expect(p.inventory).toBeTruthy()
        local sq = getSquare(3, 4, 5)
        expect(sq:getX()).toBe(3)
        Umbrella.init(nil)
    end)

    it("(g) strict method miss through Seam C names the MAPPED class (factory player, class table, instance)", function()
        initOn()
        local p = getSpecificPlayer(0)
        local inst = _G.IsoPlayer.new("Bob")
        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = true
            local eok, emsg = pcall(function() return p.unknownX end)
            expect(eok).toBe(false)
            expect(tostring(emsg):find("PZ_STRICT: unknown method 'IsoPlayer:unknownX'", 1, true)).toBeTruthy()

            expect(tostring(emsg):match("^.-:%d+: ")).toBeTruthy()

            local cok, cmsg = pcall(function() return _G.IsoPlayer.unknownX end)
            expect(cok).toBe(false)
            expect(tostring(cmsg):find("PZ_STRICT: unknown method 'IsoPlayer:unknownX'", 1, true)).toBeTruthy()

            local iok, imsg = pcall(function() return inst.unknownX end)
            expect(iok).toBe(false)
            expect(tostring(imsg):find("PZ_STRICT: unknown method 'IsoPlayer:unknownX'", 1, true)).toBeTruthy()
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end

        local ok2, err2 = pcall(function()
            _G.pz_strict = false
            expect(p.unknownX).toBeNil()
            expect(p.unknownX).toBeNil()
            expect(_G.IsoPlayer.unknownX).toBeNil()
        end)
        _G.pz_strict = saved
        if not ok2 then error(err2, 0) end
        Umbrella.init(nil)
    end)

    it("(h) delegation: wrapped-probe misses resolve through the mapped class DAG (fixture Foo), shipped keys beat the DAG", function()
        initOn()

        local winner = { transform = function() return "SHIPPED" end }
        Umbrella.w(winner, "Foo")
        expect(winner.transform()).toBe("SHIPPED")

        local probe = {}
        Umbrella.w(probe, "Foo")
        expect(probe.transform).toBeTruthy()
        expect(probe.transform).toBe(probe.transform)
        expect(probe:transform(1)).toBeNil()
        expect(#probe.transform.calls).toBe(1)

        expect(probe.transform.calls[1].n).toBe(2)
        expect(probe.transform.calls[1][1]).toBe(probe)
        expect(probe.transform.calls[1][2]).toBe(1)

        expect(probe.baseMethod).toBeTruthy()
        expect(probe:baseMethod(5)).toBeNil()
        expect(#probe.baseMethod.calls).toBe(1)
        local owner = Umbrella.find_method("Foo", "baseMethod")
        expect(owner.name).toBe("Base")

        expect(probe.bar).toBeNil()

        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = true
            local eok, emsg = pcall(function() return probe.ghostHP end)
            expect(eok).toBe(false)
            expect(tostring(emsg):find("PZ_STRICT: unknown method 'Foo:ghostHP'", 1, true)).toBeTruthy()
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end
        Umbrella.init(nil)
    end)

    it("(i) w composes with an existing __index: inherited shipped hits win, misses delegate", function()
        initOn()
        local base = { inherited = function() return "SUPER" end }
        local t = setmetatable({}, { __index = base })
        Umbrella.w(t, "Foo")
        expect(t.inherited()).toBe("SUPER")
        expect(t.transform).toBeTruthy()
        Umbrella.init(nil)

        expect(t.inherited()).toBe("SUPER")
        expect(t.transform).toBeNil()
    end)

    it("(j) events hook: lookup hit treats the name as known via the existing dispatcher path; Hook stays shipped-only", function()
        initOn()
        local saved = _G.pz_strict
        local saved_lookup = rawget(_G, "__umbrella_event_lookup")
        local ok, err = pcall(function()
            _G.pz_strict = true
            _G.__umbrella_event_lookup = function(name)
                return name == "OnUmbrellaProbe"
            end

            local e = Events.OnUmbrellaProbe
            expect(type(e.Add)).toBe("function")
            expect(type(e._fire)).toBe("function")

            local eok, emsg = pcall(function() return Events.OnUmbrellaMiss end)
            expect(eok).toBe(false)
            expect(tostring(emsg):find("PZ_STRICT: unknown PZ event 'Events.OnUmbrellaMiss'", 1, true)).toBeTruthy()

            local hok, hmsg = pcall(function() return Hook.OnUmbrellaProbe end)
            expect(hok).toBe(false)
            expect(tostring(hmsg):find("PZ_STRICT: unknown PZ event 'Hook.OnUmbrellaProbe'", 1, true)).toBeTruthy()
        end)
        _G.pz_strict = saved
        _G.__umbrella_event_lookup = saved_lookup
        if not ok then error(err, 0) end

        local ok2, err2 = pcall(function()
            _G.pz_strict = false
            expect(type(Events.OnUmbrellaLegacy.Add)).toBe("function")
        end)
        _G.pz_strict = saved
        if not ok2 then error(err2, 0) end
        Umbrella.init(nil)
    end)

    it("(k) strict _G guard composes with resolve_global: served fixture global via bare read; phantom/unknown still error", function()
        if not _G.pz_strict then return end
        initOn()
        local ok, err = pcall(function()

            expect(Foo).toBeTruthy()
            expect(Foo).toBe(Foo)

            local bok, bmsg = pcall(function() return Baz end)
            expect(bok).toBe(false)
            expect(tostring(bmsg):find("PZ_STRICT: unknown global 'Baz'", 1, true)).toBeTruthy()

            local uok, umsg = pcall(function() return __pz_integration_undefined_probe__ end)
            expect(uok).toBe(false)
            expect(tostring(umsg):find("PZ_STRICT: unknown global '__pz_integration_undefined_probe__'", 1, true)).toBeTruthy()
        end)
        if not ok then error(err, 0) end
        Umbrella.init(nil)

        local ok2, err2 = pcall(function()
            local fok, fmsg = pcall(function() return Foo end)
            expect(fok).toBe(false)
            expect(tostring(fmsg):find("PZ_STRICT: unknown global 'Foo'", 1, true)).toBeTruthy()
            local uok, umsg = pcall(function() return __pz_integration_undefined_probe__ end)
            expect(uok).toBe(false)
            expect(tostring(umsg):find("PZ_STRICT: unknown global '__pz_integration_undefined_probe__'", 1, true)).toBeTruthy()
        end)
        if not ok2 then error(err2, 0) end
    end)

    it("(k2) asymmetry pin: under mode-on + NON-strict, resolve_global may serve the stub but _G.Foo is NEVER materialized", function()
        initOn()
        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = false

            expect(rawget(_G, "Foo")).toBeNil()

            expect(Umbrella.resolve_global("Foo")).toBeTruthy()

            expect(rawget(_G, "Foo")).toBeNil()
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end
        Umbrella.init(nil)
    end)

    it("(l) feature-off identity: init(nil) restores original metatables exactly, w is identity, delegation dead", function()
        initOn()
        local probe = {}
        Umbrella.w(probe, "Foo")
        local p = getSpecificPlayer(0)
        local sq = getSquare(1, 1, 1)
        expect(getmetatable(_G.IsoPlayer)).toBeTruthy()
        expect(getmetatable(probe)).toBeTruthy()
        expect(getmetatable(p)).toBeTruthy()
        expect(type(getmetatable(sq).__index)).toBe("function")
        expect(probe.transform).toBeTruthy()
        Umbrella.init(nil)
        expect(Umbrella.on).toBe(false)

        expect(getmetatable(_G.IsoPlayer)).toBe(orig_player_mt)
        expect(getmetatable(_G.ItemContainer)).toBe(orig_container_mt)
        expect(getmetatable(_G.ISPanel)).toBe(orig_panel_mt)

        expect(getmetatable(probe)).toBeNil()
        expect(getmetatable(p)).toBeNil()

        expect(probe.transform).toBeNil()

        local p2 = getSpecificPlayer(0)
        expect(getmetatable(p2)).toBeNil()
        local sq2 = getSquare(1, 1, 1)
        expect(type(getmetatable(sq2).__index)).toBe("table")

        expect(rawget(_G, "__umbrella_event_lookup")).toBeNil()
    end)
end)
