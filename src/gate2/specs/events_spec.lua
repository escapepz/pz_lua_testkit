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
            "EveryOneMinute", "ReceiveSafehouseInvite", "RequestTrade",
        }
        for _, n in ipairs(names) do
            expect(type(Events[n])).toBe("table")
        end
    end)

    it("Hook.UseItem is accessible on the real Hook registry", function()
        expect(type(rawget(_G, "Hook"))).toBe("table")
        expect(type(Hook.UseItem)).toBe("table")
        expect(type(Hook.UseItem.Add)).toBe("function")
        expect(type(Hook.UseItem.Remove)).toBe("function")
    end)
end)
