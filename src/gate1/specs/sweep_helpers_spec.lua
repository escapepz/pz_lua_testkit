local SOURCE = debug.getinfo(1, "S").source:sub(2)
local HERE = SOURCE:match("^(.*)[/\\][^/\\]*$") or "."
local sweep = dofile(HERE .. "/../../check/sweep_consumers.lua")

describe("sweep_consumers helpers (pure)", function()

    it("parse_total: FIRST total=(%d+) token; total=71 is not 7; garbage -> nil", function()
        expect_eq(sweep.parse_total("total=71 passed=71 failed=0"), 71,
            "the 71-vs-7 trap: numeric parse, not substring")
        expect(sweep.parse_total("total=71 passed=71 failed=0") == 7):toBeFalsy()
        expect_eq(sweep.parse_total("noise\ntotal=3 passed=3 failed=0\ntotal=99"), 3,
            "first token wins")
        expect_eq(sweep.parse_total("total=0 passed=0 failed=0"), 0)
        expect_eq(sweep.parse_total("garbage"), nil)
        expect_eq(sweep.parse_total(""), nil)
    end)

    it("is_all_pass: literal ALL PASS marker, case-sensitive", function()
        expect(sweep.is_all_pass("total=7 passed=7 failed=0\nALL PASS")):toBeTruthy()
        expect(sweep.is_all_pass("ALL PASS")):toBeTruthy()
        expect(sweep.is_all_pass("total=7 passed=6 failed=1\nFAILURES")):toBeFalsy()
        expect(sweep.is_all_pass("all pass")):toBeFalsy()
        expect(sweep.is_all_pass("")):toBeFalsy()
    end)

    it("shim_path: backslashes to /, trailing / stripped, /TESTS/run.lua appended", function()
        expect_eq(sweep.shim_path("R/ws"), "R/ws/TESTS/run.lua")
        expect_eq(sweep.shim_path("R\\ws\\"), "R/ws/TESTS/run.lua")
        expect_eq(sweep.shim_path("R/ws///"), "R/ws/TESTS/run.lua")
    end)

    it("display_name: last path segment (report label)", function()
        expect_eq(sweep.display_name("R/ws/caf"), "caf")
        expect_eq(sweep.display_name("R\\ws\\jasm\\"), "jasm")
        expect_eq(sweep.display_name("ws"), "ws")
    end)
end)
