local SOURCE = debug.getinfo(1, "S").source:sub(2)
local HERE = SOURCE:match("^(.*)[/\\][^/\\]*$") or "."
local reset = dofile(HERE .. "/../reset.lua")

local captured

local function fakePzspec()
    captured = nil
    return { global_before_each = function(h) captured = h end }
end

local savedTestkit = rawget(_G, "testkit")

local function withTestkit(tk, fn)
    rawset(_G, "testkit", tk)
    local ok, err = pcall(fn)
    rawset(_G, "testkit", savedTestkit)
    if not ok then error(err, 0) end
end

local function keyset(tbl)
    local keys = {}
    for k in pairs(tbl) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

describe("reset module: wire_per_test registration", function()
    after_all(function()

        rawset(_G, "testkit", savedTestkit)
    end)

    it("(a) exports exactly wire_per_test", function()
        expect(type(reset)).toBe("table")
        expect(keyset(reset)).toEqual({ "wire_per_test" })
        expect(type(reset.wire_per_test)).toBe("function")
    end)

    it("(b) enabled=false -> false, nothing registered", function()
        local pz = fakePzspec()
        local r = reset.wire_per_test(pz, false)
        expect(r).toBe(false)
        expect(captured).toBeNil()
    end)

    it("(c) nil pzspec -> false (the guard must tolerate a missing __pzspec)", function()
        local r = reset.wire_per_test(nil, true)
        expect(r).toBe(false)
        expect(captured).toBeNil()
    end)

    it("(d) non-table pzspec -> false (hostile stub/pack leftovers)", function()
        expect(reset.wire_per_test("not a table", true)).toBe(false)
        expect(reset.wire_per_test(42, true)).toBe(false)
        expect(reset.wire_per_test(true, true)).toBe(false)
        expect(captured).toBeNil()
    end)

    it("(e) table pzspec without a FUNCTION global_before_each -> false (preserved wire_reset guard)", function()
        expect(reset.wire_per_test({}, true)).toBe(false)
        expect(reset.wire_per_test({ global_before_each = "nope" }, true)).toBe(false)
        expect(captured).toBeNil()
    end)

    it("(f) enabled + valid pzspec -> true, hook captured via global_before_each", function()
        local pz = fakePzspec()
        local r = reset.wire_per_test(pz, true)
        expect(r).toBe(true)
        expect(type(captured)).toBe("function")
    end)

    it("(g) hook is TOTAL: _G.testkit = nil -> silent no-op, no raise", function()
        local pz = fakePzspec()
        expect(reset.wire_per_test(pz, true)).toBe(true)
        local ok = pcall(captured)
        expect(ok).toBeTruthy()
    end)

    it("(h) hook drives testkit.resetLoaded EXACTLY once per invocation (rawset discipline, strict-safe)", function()
        local pz = fakePzspec()
        expect(reset.wire_per_test(pz, true)).toBe(true)
        local calls = 0
        local savedStrict = _G.pz_strict
        withTestkit({ resetLoaded = function() calls = calls + 1 end }, function()
            _G.pz_strict = true
            captured()
        end)
        _G.pz_strict = savedStrict
        expect(calls).toBe(1)
    end)
end)
