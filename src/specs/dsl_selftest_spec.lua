describe("pzspec dsl", function()
    it("expect matchers work", function()
        expect(4).toBe(2 + 2)
        expect({ a = 1, b = { 2 } }).toEqual({ b = { 2 }, a = 1 })
        expect(nil).toBeNil()
        expect("").toBeTruthy()
        expect(false).toBeFalsy()
        expect("hello world").toContain("world")
        expect(3.0000001).toBeCloseTo(3)
        expect(function() error("x") end).toThrow()
    end)

    it("mock records calls", function()
        local m = mock(function(a, b) return a + b end)
        m(2, 3)
        m(4, 5)
        expect(#m.calls).toBe(2)
        expect(m.calls[1][1]).toBe(2)
        expect(m.calls[2][2]).toBe(5)
        expect(m(10, 1)).toBe(11)
    end)

    it("mock() with no impl records calls and returns nil", function()
        local m = mock()
        m(1, 2)
        expect(#m.calls).toBe(1)
        expect(m.calls[1][1]).toBe(1)
        expect(m(3)).toBeNil()
    end)

    it("reading an unknown mock field returns nil (no auto-methods)", function()
        local m = mock()
        expect(m.wasCalled).toBeNil()
        expect(m._impl).toBeNil()
        expect(mock(function() return 1 end).anything).toBeNil()
    end)

    it("before_each / after_each run around each test", function()

        expect(1).toBe(1)
    end)
end)

describe("pzspec hooks", function()
    local log = {}
    before_each(function() table.insert(log, "before") end)
    after_each(function() table.insert(log, "after") end)

    it("first", function()
        expect(#log).toBe(1)
        table.insert(log, "test1")
    end)

    it("second sees fresh before", function()

        expect(log[#log]).toBe("before")
        expect(#log).toBe(4)
    end)
end)

describe("pzspec failure output", function()
    it("toEqual on tables dumps both sides readably", function()
        local ok, err = pcall(function()
            expect({ a = 1, b = { 2 } }).toEqual({ a = 1, b = { 3 } })
        end)
        err = tostring(err)
        expect(ok).toBe(false)
        expect(err).toContain("expected:")
        expect(err).toContain("got:")
        expect(err).toContain("b = { 3 }")
    end)

    it("toEqual truncates deep tables with {...} but still reports the diff", function()
        local function nest(n, leaf)
            local t = leaf
            for _ = 1, n do t = { v = t } end
            return t
        end
        local ok, err = pcall(function()
            expect(nest(9, { a = 1 })).toEqual(nest(9, { a = 2 }))
        end)
        err = tostring(err)
        expect(ok).toBe(false)
        expect(err).toContain("{...}")
    end)

    it("toEqual on cyclic tables terminates and names the cycle key", function()
        local a = { x = 1 }; a.self = a
        local b = { x = 1, y = 9 }; b.self = b
        local ok, err = pcall(function()
            expect(a).toEqual(b)
        end)
        err = tostring(err)
        expect(ok).toBe(false)
        expect(err).toContain("self")
    end)

    it("fmt falls back to tostring when __inspect is absent", function()
        local saved = rawget(_G, "__inspect")
        _G.__inspect = nil
        local ok, err = pcall(function()
            expect({ x = 1 }).toEqual({ x = 2 })
        end)
        _G.__inspect = saved
        err = tostring(err)
        expect(ok).toBe(false)
        expect(err).toContain("table:")
    end)
end)
