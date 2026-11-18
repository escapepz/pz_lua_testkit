local SOURCE = debug.getinfo(1, "S").source:sub(2)
local HERE = SOURCE:match("^(.*)[/\\][^/\\]*$") or "."
local reporter = dofile(HERE .. "/../reporter.lua")

local captured
local function spy(s) captured = s end

local function armSpy()
    captured = nil
    return spy
end

local function keyset(tbl)
    local keys = {}
    for k in pairs(tbl) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

describe("reporter module: exit_code + fail_result + summarize", function()
    it("(a) exports exactly fail_result, summarize, exit_code", function()
        expect(type(reporter)).toBe("table")
        expect(keyset(reporter)).toEqual({ "exit_code", "fail_result", "summarize" })
        expect(type(reporter.fail_result)).toBe("function")
        expect(type(reporter.summarize)).toBe("function")
        expect(type(reporter.exit_code)).toBe("function")
    end)

    it("(b) exit_code: ok=true -> 0 (suite passed)", function()
        expect(reporter.exit_code({ ok = true, total = 5, passed = 5, failed = 0 })).toBe(0)
    end)

    it("(c) exit_code: total=0 failed=0 ok=false -> 2 (zero specs)", function()
        expect(reporter.exit_code({ total = 0, passed = 0, failed = 0, ok = false })).toBe(2)
    end)

    it("(d) exit_code: total=3 failed=1 ok=false -> 1 (suite failed)", function()
        expect(reporter.exit_code({ total = 3, passed = 2, failed = 1, ok = false })).toBe(1)
    end)

    it("(e) fail_result SPEC LOAD FAIL -> exact string + fail table", function()
        local write = armSpy()
        local r = reporter.fail_result("SPEC LOAD FAIL", "x.lua", "boom", write)
        expect(captured).toBe("SPEC LOAD FAIL x.lua: boom")
        expect(keyset(r)).toEqual({ "failed", "ok", "passed", "total" })
        expect(r.total).toBe(0)
        expect(r.passed).toBe(0)
        expect(r.failed).toBe(1)
        expect(r.ok).toBe(false)
    end)

    it("(f) fail_result PZ_MOD LOAD FAIL -> same shape (underscore label verbatim)", function()
        local write = armSpy()
        local r = reporter.fail_result("PZ_MOD LOAD FAIL", "media.lua", "bad", write)
        expect(captured).toBe("PZ_MOD LOAD FAIL media.lua: bad")
        expect(keyset(r)).toEqual({ "failed", "ok", "passed", "total" })
        expect(r.total).toBe(0)
        expect(r.passed).toBe(0)
        expect(r.failed).toBe(1)
        expect(r.ok).toBe(false)
    end)

    it("(g) fail_result non-string err -> tostring'd (load errors are strings, not always)", function()
        local write = armSpy()

        reporter.fail_result("SPEC LOAD FAIL", "x.lua", { code = 42 }, write)
        expect(captured).toContain("SPEC LOAD FAIL x.lua: table: ")

        captured = nil
        reporter.fail_result("SPEC LOAD FAIL", "x.lua", 99, write)
        expect(captured).toBe("SPEC LOAD FAIL x.lua: 99")
    end)

    it("(h) fail_result write=nil -> default print, no error", function()
        local ok, err = pcall(reporter.fail_result, "SPEC LOAD FAIL", "x.lua", "boom")
        expect(ok).toBeTruthy()

        if not ok then error(err, 0) end
    end)

    it("(i) summarize(true, stats) -> stats fields + ok=true (ok from FIRST arg)", function()
        local r = reporter.summarize(true, { total = 2, passed = 2, failed = 0 })
        expect(keyset(r)).toEqual({ "failed", "ok", "passed", "total" })
        expect(r).toEqual({ total = 2, passed = 2, failed = 0, ok = true })
    end)

    it("(j) summarize(false, stats) -> ok=false (pzspec.run returns ok, stats — first)", function()
        local r = reporter.summarize(false, { total = 2, passed = 1, failed = 1 })
        expect(r).toEqual({ total = 2, passed = 1, failed = 1, ok = false })
    end)
end)
