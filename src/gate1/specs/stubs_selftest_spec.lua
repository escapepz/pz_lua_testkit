describe("gate1 pz stubs", function()
    it("context predicates", function()

        expect(isServer()).toBeFalsy()
        expect(isClient()).toBeFalsy()
        expect(isMultiplayer()).toBeFalsy()
        expect(isSinglePlayer()).toBeTruthy()
    end)

    it("Events.OnX.Add captures callbacks", function()
        local called = 0

        LuaEventManager.AddEvent("OnUnitDeath")
        Events.OnUnitDeath.Add(function() called = called + 1 end)
        expect(Events.OnUnitDeath._count()).toBe(1)
        Events.OnUnitDeath._fire()
        expect(called).toBe(1)
    end)

    it("__pz_is_dispatcher: factory identity, not duck typing", function()
        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = false
            local ev = Events.OnIdentityProbe
            expect(__pz_is_dispatcher(ev)).toBeTruthy()
            local parked = { Clear = function() end }
            expect(__pz_is_dispatcher(parked)).toBeFalsy()
            expect(__pz_is_dispatcher("nope")).toBeFalsy()
            expect(__pz_is_dispatcher(nil)).toBeFalsy()
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end
    end)

    it("timestamp globals: seconds + epoch-ms scale pairing", function()
        local t1 = getTimestamp()
        expect(type(t1)).toBe("number")
        local m = getTimestampMs()
        local t2 = getTimestamp()
        expect(m >= t1 * 1000).toBeTruthy()
        expect(m <= t2 * 1000).toBeTruthy()
    end)

    it("getGameTime: deterministic GameTime stub", function()
        local gt = getGameTime()
        expect(type(gt)).toBe("table")
        expect(gt.getHours()).toBe(7)
        expect(gt.getMinutes()).toBe(30)
        expect(gt.getSeconds()).toBe(0)
        expect(gt.getDay()).toBe(1)
        expect(gt.getTimeOfDay()).toBe(7.5)
        expect(gt.getMinutesPerDay()).toBe(60)
        expect(gt.daysInMonth()).toBe(31)
        expect(gt.getModData()).toBe(gt.getModData())
        expect(gt.getMultiplier()).toBe(1)
    end)

    it("writeLog captures", function()
        writeLog("TEST", "hello")
        expect(_pz_logs[#_pz_logs].message).toBe("hello")
    end)
end)
