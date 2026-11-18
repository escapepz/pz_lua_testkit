describe("gate2 dep-scan guard: backslash require= tokens", function()
    it("records declared tokens verbatim, in mod.info order", function()
        expect(__PZ_MOD_INFO.deps).toEqual({
            "..\\EscapeDecoy", "sub\\dir",
        })
    end)

    it("rejects backslash traversal tokens so no roots are added", function()
        expect(#__PZ_MOD_INFO.roots).toBe(0)
    end)
end)
