describe("gate2 Events registry", function()
    it("Events.OnGameStart exists with Add", function()
        expect(type(Events)).toBe("table")
        expect(type(Events.OnGameStart)).toBe("table")
        expect(type(Events.OnGameStart.Add)).toBe("function")
    end)

    it("a few common events are registered", function()
        local names = {
            "OnGameStart", "OnGameBoot", "OnInitGlobalModData",
            "OnPlayerUpdate", "OnFillInventoryObjectContextMenu",
        }
        for _, n in ipairs(names) do
            expect(type(Events[n])).toBe("table")
        end
    end)
end)
