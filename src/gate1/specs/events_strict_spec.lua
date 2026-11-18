describe("events allowlist + strict tier", function()
    it("(a) non-strict default: unknown On* auto-creates (legacy behavior intact)", function()
        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = false
            expect(type(Events.OnAutoThing.Add)).toBe("function")
            expect(type(Events.OnAutoThing.Remove)).toBe("function")
            expect(type(Events.OnAutoThing.Clear)).toBe("function")
            expect(type(Events.OnAutoThing._fire)).toBe("function")
            expect(type(Events.OnAutoThing._count)).toBe("function")

            expect(type(Hook.OnAutoThingHook.Add)).toBe("function")

            local called = 0
            Events.OnAutoThing.Add(function() called = called + 1 end)
            Events.OnAutoThing._fire()
            expect(called).toBe(1)
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end
    end)

    it("(b) allowlist loaded on __pz_events_list: non-empty, sorted, unique, SURFACE members present", function()
        local list = _G.__pz_events_list
        expect(type(list)).toBe("table")
        expect(type(list.names)).toBe("table")
        local n = #list.names
        expect(n >= 1).toBeTruthy()

        for i = 2, n do
            expect(list.names[i - 1] < list.names[i]).toBeTruthy()
        end

        local wanted = {
            "OnClientCommand",
            "OnContainerUpdate",
            "OnFillWorldObjectContextMenu",
            "OnGameBoot",
            "OnGameStart",
            "OnInitGlobalModData",
            "OnLoadedTileDefinitions",
            "OnPlayerUpdate",
            "OnRefreshInventoryWindowContainers",
            "OnServerCommand",
            "OnTick",
        }
        local have = {}
        for _, name in ipairs(list.names) do have[name] = true end
        for _, name in ipairs(wanted) do
            expect(have[name]).toBeTruthy()
        end
    end)

    it("(c) LuaEventManager.AddEvent registers: strict lookup passes, idempotent, callbacks kept", function()
        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = true
            expect(type(LuaEventManager)).toBe("table")
            expect(type(LuaEventManager.AddEvent)).toBe("function")
            local before = #_G.__pz_events_list.names
            LuaEventManager.AddEvent("OnMyCustomEvent")
            expect(type(Events.OnMyCustomEvent.Add)).toBe("function")
            local after = #_G.__pz_events_list.names
            expect(after == before + 1 or after == before).toBeTruthy()

            local cb = function() end
            Events.OnMyCustomEvent.Add(cb)
            expect(Events.OnMyCustomEvent._count()).toBe(1)
            LuaEventManager.AddEvent("OnMyCustomEvent")
            expect(#_G.__pz_events_list.names).toBe(after)
            expect(Events.OnMyCustomEvent._count()).toBe(1)
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end
    end)

    it("(d) strict: unknown On* index throws PZ_STRICT error; allowlisted names pass", function()
        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = true

            expect(type(Events.OnGameStart.Add)).toBe("function")

            local eok, emsg = pcall(function() return Events.OnTypoEvent end)
            expect(eok).toBe(false)
            expect(emsg:find("PZ_STRICT: unknown PZ event 'Events.OnTypoEvent'", 1, true)).toBeTruthy()
            local hok, hmsg = pcall(function() return Hook.OnTypoHook end)
            expect(hok).toBe(false)
            expect(hmsg:find("PZ_STRICT: unknown PZ event 'Hook.OnTypoHook'", 1, true)).toBeTruthy()

            expect(function() return Events.OnAnotherTypo end).toThrow()
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end
    end)
end)
