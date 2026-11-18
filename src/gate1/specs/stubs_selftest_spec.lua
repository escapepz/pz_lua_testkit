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

    it("writeLog captures", function()
        writeLog("TEST", "hello")
        expect(_pz_logs[#_pz_logs].message).toBe("hello")
    end)
end)
