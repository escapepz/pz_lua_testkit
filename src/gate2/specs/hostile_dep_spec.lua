local INFO = rawget(_G, "__PZ_MOD_INFO")
if type(INFO) ~= "table" or not INFO.base:match("/HostileMod$") then
    return
end

describe("gate2 dep-scan guard: hostile require= tokens", function()
    it("records declared tokens verbatim, in mod.info order", function()
        expect(INFO.deps).toEqual({
            "../EscapeDecoy", "..", "C:/abs", "sub/dir", "DepMod",
        })
    end)

    it("only the bare-ID token contributes a root; the escape decoy does not", function()

        expect(#INFO.roots).toBe(1)
        expect(INFO.roots[1]:match("/DepLibs/DepMod/media/lua/shared$"))
            .toBeTruthy()
    end)

    it("hostile mod has no auto-exec load list", function()
        expect(INFO.load_files).toEqual({})
    end)
end)
