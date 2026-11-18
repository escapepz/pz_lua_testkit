local SOURCE = debug.getinfo(1, "S").source:sub(2)
local HERE = SOURCE:match("^(.*)[/\\][^/\\]*$") or "."
local P = HERE .. "/../../pzspec.lua"

local PZSPEC_GLOBALS = {
    "describe", "it", "before_each", "after_each", "before_all",
    "after_all", "xit", "xdescribe", "expect", "expect_eq",
    "mock", "spy", "spyOn", "__pzspec",
}

local function freshRun(register)
    local saved = {}
    for _, k in ipairs(PZSPEC_GLOBALS) do
        saved[k] = rawget(_G, k)
    end
    local ok, runOk, stats, out = pcall(function()
        local A = dofile(P)
        register()
        local lines = {}
        local s = _G.spyOn(_G, "print")
        local rok, st = A.run()
        s.restore()
        for _, c in ipairs(s.calls) do
            lines[#lines + 1] = tostring(c[1])
        end
        return rok, st, table.concat(lines, "\n")
    end)
    for _, k in ipairs(PZSPEC_GLOBALS) do
        _G[k] = saved[k]
    end
    if not ok then error(runOk, 0) end
    return runOk, stats, out
end

describe("pzspec hook failure reporting", function()
    it("(a) after_each error fails the passed test's own slot: one FAIL, hook line, no second count", function()
        local runOk, stats, out = freshRun(function()
            _G.describe("h", function()
                _G.after_each(function() error("boom") end)
                _G.it("t", function() end)
            end)
        end)
        expect(runOk).toBe(false)
        expect(stats.total).toBe(1)
        expect(stats.passed).toBe(0)
        expect(stats.failed).toBe(1)
        expect(out).toContain("FAIL h :: t")

        expect(out).toContain("after_each:")
        expect(out).toContain("boom")
    end)

    it("(b) body fail + after_each error: ONE slot, body error on the FAIL line, hook error as extra line", function()
        local runOk, stats, out = freshRun(function()
            _G.describe("h", function()
                _G.after_each(function() error("hook boom") end)
                _G.it("t", function() error("body boom") end)
            end)
        end)
        expect(runOk).toBe(false)
        expect(stats.total).toBe(1)
        expect(stats.failed).toBe(1)
        expect(out).toContain("FAIL h :: t")
        expect(out).toContain("body boom")
        expect(out).toContain("after_each:")
        expect(out).toContain("hook boom")
    end)

    it("(c) after_all error: one synthetic slot like before_all, chain stops on the first error", function()
        local ranSecond = false
        local runOk, stats, out = freshRun(function()
            _G.describe("h", function()
                _G.it("t", function() end)
                _G.after_all(function() error("teardown boom") end)
                _G.after_all(function() ranSecond = true end)
            end)
        end)
        expect(runOk).toBe(false)
        expect(stats.total).toBe(2)
        expect(stats.passed).toBe(1)
        expect(stats.failed).toBe(1)
        expect(out).toContain("FAIL h <after_all>:")
        expect(out).toContain("teardown boom")
        expect(ranSecond).toBe(false)
    end)

    it("(d) later after_each hooks still run when an earlier one errors (only the first error reports)", function()
        local ranSecond = false
        local runOk, stats, out = freshRun(function()
            _G.describe("h", function()
                _G.after_each(function() error("first boom") end)
                _G.after_each(function() ranSecond = true end)
                _G.it("t", function() end)
            end)
        end)
        expect(runOk).toBe(false)
        expect(stats.failed).toBe(1)
        expect(out).toContain("after_each:")
        expect(out).toContain("first boom")
        expect(out:find("second", 1, true)).toBeNil()
        expect(ranSecond).toBe(true)
    end)
end)
