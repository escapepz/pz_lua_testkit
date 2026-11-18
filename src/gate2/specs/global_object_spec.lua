local GATE2 = (rawget(_G, "PZ_GATE") == "gate2")
if not GATE2 then
    return
end

describe("gate2 GlobalObject exposure", function()
    it("engine-injected globals exist as functions", function()
        local names = {
            "instanceof", "typeof", "fastfloor", "require", "getSquare",
            "getSpecificPlayer", "convertToPZNetTable", "getRandomUUID",
            "isIngameState", "getClassSimpleName",
        }
        for _, n in ipairs(names) do
            expect(type(rawget(_G, n))).toBe("function")
        end
    end)

    it("fastfloor answers real engine values", function()
        expect(fastfloor(2.7)).toBe(2)
        expect(fastfloor(-0.5)).toBe(-1)
        expect(fastfloor(3)).toBe(3)
    end)

    it("typeof answers the Lua-visible type of probe values", function()
        expect(typeof({})).toBe("table")
        expect(typeof(5)).toBe("number")
    end)

    it("instanceof answers real booleans through the engine resolver", function()

        local probe = convertToPZNetTable({ a = 1 })
        expect(type(probe)).toBe("table")
        expect(probe.a).toBe(1)
        local ok, r = pcall(instanceof, probe, "zombie.iso.IsoObject")
        expect(ok).toBeTruthy()
        expect(type(r)).toBe("boolean")
        expect(r).toBeFalsy()
        local ok2, r2 = pcall(instanceof, {}, "java.lang.Object")
        expect(ok2).toBeTruthy()
        expect(type(r2)).toBe("boolean")

        local ok3, err3 = pcall(instanceof)
        expect(ok3).toBeFalsy()
        expect(tostring(err3):find("expected 2 arguments", 1, true) ~= nil)
            .toBeTruthy()
    end)

    it("isIngameState returns a real boolean without a world", function()
        expect(type(isIngameState())).toBe("boolean")
    end)

    it("instanceof TRUE-case: a real engine instance resolves through typeMap", function()

        local w = getWorld()
        expect(w ~= nil).toBeTruthy()

        expect(typeof(w)).toBe("IsoWorld")
        expect(type(w)).toBe("userdata")
        local ok, r = pcall(instanceof, w, "IsoWorld")
        expect(ok).toBeTruthy()
        expect(r).toBeTruthy()

        local ok2, r2 = pcall(instanceof, w, "IsoObject")
        expect(ok2).toBeTruthy()
        expect(r2).toBeFalsy()
        local ok3, r3 = pcall(instanceof, {}, "IsoWorld")
        expect(ok3).toBeTruthy()
        expect(r3).toBeFalsy()

        local ok4, r4 = pcall(instanceof, w, "zombie.iso.IsoWorld")
        expect(ok4).toBeTruthy()
        expect(r4).toBeFalsy()
    end)

    it("world-free engine getters pin their real deterministic values", function()

        expect(getGameVersion()).toBe("42.22")

        expect(isServer()).toBeFalsy()

        local a, b = getWorld(), getWorld()
        expect(a == b).toBeTruthy()
    end)

    it("getRandomUUID returns distinct strings", function()
        local a, b = getRandomUUID(), getRandomUUID()
        expect(type(a)).toBe("string")
        expect(#a > 0).toBeTruthy()
        expect(a ~= b).toBeTruthy()
    end)
end)
