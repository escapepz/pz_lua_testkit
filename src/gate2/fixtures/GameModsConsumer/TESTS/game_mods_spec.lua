describe("gate2 --game-mods with common/mod.info id fallback", function()
    it("resolves WsDep via common/mod.info when 42/mod.info lacks id=", function()
        local lib = require("WsDep_Lib")
        expect(lib).toEqual({ ws = "ok" })

        local hasWsDep = false
        for _, root in ipairs(__PZ_MOD_INFO.roots) do
            if root:find("SomeFolder/common/media/lua/shared", 1, true) then
                hasWsDep = true
                break
            end
        end
        expect(hasWsDep).toBe(true)
    end)
end)
