local SOURCE = debug.getinfo(1, "S").source:sub(2)
local HERE = SOURCE:match("^(.*)[/\\][^/\\]*$") or "."
local P = HERE .. "/../../pzspec.lua"

local PZSPEC_GLOBALS = {
    "describe", "it", "before_each", "after_each", "before_all",
    "after_all", "xit", "xdescribe", "expect", "expect_eq",
    "mock", "spy", "spyOn", "__pzspec",
}

describe("pzspec fresh instance per load", function()
    it("double dofile yields a fresh instance: empty suites/stats, new __pzspec, clean zero-test run", function()

        local saved = {}
        for _, k in ipairs(PZSPEC_GLOBALS) do
            saved[k] = rawget(_G, k)
        end

        local ok, err = pcall(function()

            local A = dofile(P)

            _G.describe("leak", function()
                _G.it("t", function() end)
            end)
            expect(#A.suites).toBe(1)
            expect(A.suites[1].name).toBe("leak")
            expect(#A.suites[1].tests).toBe(1)

            local B = dofile(P)
            expect(B == A).toBeFalsy()
            expect(#B.suites).toBe(0)
            expect(B.stats.total).toBe(0)
            expect(rawget(_G, "__pzspec")).toBe(B)

            local runOk, stats = B.run()
            expect(runOk).toBe(true)
            expect(stats.total).toBe(0)
            expect(stats.failed).toBe(0)
        end)

        for _, k in ipairs(PZSPEC_GLOBALS) do
            _G[k] = saved[k]
        end

        if not ok then error(err, 0) end
    end)
end)
