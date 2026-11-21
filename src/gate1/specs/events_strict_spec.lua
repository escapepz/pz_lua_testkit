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

    it("(b) allowlist loaded on __pz_events_list: split shape, non-empty, sorted, unique, members present", function()
        local list = _G.__pz_events_list
        expect(type(list)).toBe("table")
        expect(type(list.events)).toBe("table")
        expect(type(list.hooks)).toBe("table")
        expect(list.names).toBeNil()

        local n = #list.events
        expect(n >= 1).toBeTruthy()

        for i = 2, n do
            expect(list.events[i - 1] < list.events[i]).toBeTruthy()
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
        for _, name in ipairs(list.events) do have[name] = true end
        for _, name in ipairs(wanted) do
            expect(have[name]).toBeTruthy()
        end

        local hooks_wanted = {
            "UseItem", "Attack", "CalculateStats", "WeaponSwing",
            "WeaponSwingHitPoint", "WeaponHitCharacter", "ContextualAction", "AutoDrink",
        }
        expect(#list.hooks).toBe(8)
        local haveh = {}
        for _, name in ipairs(list.hooks) do haveh[name] = true end
        for _, name in ipairs(hooks_wanted) do
            expect(haveh[name]).toBeTruthy()
            expect(have[name]).toBeFalsy()
        end
    end)

    it("(c) LuaEventManager.AddEvent registers: strict lookup passes, idempotent, callbacks kept", function()
        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = true
            expect(type(LuaEventManager)).toBe("table")
            expect(type(LuaEventManager.AddEvent)).toBe("function")
            local before = #_G.__pz_events_list.events
            LuaEventManager.AddEvent("OnMyCustomEvent")
            expect(type(Events.OnMyCustomEvent.Add)).toBe("function")
            local after = #_G.__pz_events_list.events
            expect(after == before + 1 or after == before).toBeTruthy()

            local cb = function() end
            Events.OnMyCustomEvent.Add(cb)
            expect(Events.OnMyCustomEvent._count()).toBe(1)
            LuaEventManager.AddEvent("OnMyCustomEvent")
            expect(#_G.__pz_events_list.events).toBe(after)
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

    it("(e) strict: non-On vanilla events pass, non-On typos error with the same prefix, cross-namespace registration rejected", function()
        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = true

            expect(type(Events.EveryOneMinute.Add)).toBe("function")
            expect(type(Events.onLoadModDataFromServer.Add)).toBe("function")
            expect(type(Hook.UseItem.Add)).toBe("function")

            local nok, nmsg = pcall(function() return Events.EveryOneMinut end)
            expect(nok).toBe(false)
            expect(nmsg:find("PZ_STRICT: unknown PZ event 'Events.EveryOneMinut'", 1, true)).toBeTruthy()

            local xok, xmsg = pcall(function() return Hook.OnTick end)
            expect(xok).toBe(false)
            expect(xmsg:find("PZ_STRICT: unknown PZ event 'Hook.OnTick'", 1, true)).toBeTruthy()
            local yok, ymsg = pcall(function() return Events.UseItem end)
            expect(yok).toBe(false)
            expect(ymsg:find("PZ_STRICT: unknown PZ event 'Events.UseItem'", 1, true)).toBeTruthy()

            expect(rawget(Events, "EveryOneMinut")).toBeNil()
            expect(rawget(Hook, "OnTick")).toBeNil()
            expect(rawget(Events, "UseItem")).toBeNil()
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end
    end)

    it("(f) non-strict: any non-empty string key auto-creates on both registries; numeric keys stay nil", function()
        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = false
            expect(type(Events.EveryOneMinute.Add)).toBe("function")
            expect(type(Events.MyModTickEvent.Add)).toBe("function")
            expect(type(Hook.UseItem.Add)).toBe("function")
            expect(Events[42]).toBeNil()
            expect(Events[""]).toBeNil()
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end
    end)
end)
