local PROBE = "__pz_strict_guard_undefined_probe__"

describe("strict _G guard (PZ_STRICT=1)", function()
    it("undefined global read: nil + no metatable by default, PZ_STRICT error when armed", function()

        expect(rawget(_G, PROBE)).toBeNil()

        if _G.pz_strict then

            local mt = debug.getmetatable(_G)
            expect(mt ~= nil).toBeTruthy()
            expect(type(mt.__index)).toBe("function")

            expect(type(print)).toBe("function")

            local ok, err = pcall(function() return _G[PROBE] end)
            expect(ok).toBe(false)
            expect(tostring(err):find("PZ_STRICT: unknown global '" .. PROBE .. "'", 1, true)).toBeTruthy()
        else

            expect(debug.getmetatable(_G)).toBeNil()
            local ok, v = pcall(function() return _G[PROBE] end)
            expect(ok).toBe(true)
            expect(v).toBeNil()
        end
    end)
end)
