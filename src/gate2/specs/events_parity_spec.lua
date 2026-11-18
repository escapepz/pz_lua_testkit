describe("gate2 events parity", function()
    local list = rawget(_G, "__pz_events_list")

    it("runner exposes the shipped allowlist", function()
        expect(type(list)).toBe("table")
        expect(type(list.names)).toBe("table")
        expect(#list.names > 0).toBe(true)
    end)

    it("every shipped name is registered in the real Events registry", function()
        expect(type(list)).toBe("table")
        expect(type(Events)).toBe("table")
        local missing = {}
        for _, n in ipairs(list.names) do
            if type(Events[n]) ~= "table" then
                missing[#missing + 1] = n
            end
        end
        expect(missing).toEqual({})
    end)
end)
