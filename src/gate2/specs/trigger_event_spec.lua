describe("gate2 triggerEvent dispatch", function()
    local ran
    local handler

    before_each(function()
        ran = false
        handler = function()
            ran = true
        end
        Events.OnGameBoot.Add(handler)
    end)

    after_each(function()
        if handler then
            Events.OnGameBoot.Remove(handler)
            handler = nil
        end
    end)

    it("triggerEvent is exposed", function()
        expect(type(rawget(_G, "triggerEvent"))).toBe("function")
    end)

    it("triggerEvent runs registered handlers immediately", function()
        rawget(_G, "triggerEvent")("OnGameBoot")
        expect(ran).toBeTruthy()
    end)
end)
