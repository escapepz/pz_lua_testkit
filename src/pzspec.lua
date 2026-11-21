-- pzspec.lua — shared spec DSL for pz_lua_testkit
-- Compatible with Lua 5.1 (gate1: lua.exe) and Kahlua/PZ fork (gate2).
-- No external dependencies. Globals installed by bootstrap:
--   describe, it, before_each, after_each, before_all, after_all,
--   expect, mock, spy

local pzspec = {
    suites = {},
    stats = { total = 0, passed = 0, failed = 0 },
    _current = nil,
    _depth = 0,
    _global_befores = {},
}

local function newSuite(name)
    local s = { name = name, tests = {}, befores = {}, afters = {} }
    table.insert(pzspec.suites, s)
    return s
end

local function currentSuite()
    return pzspec._current or newSuite("(root)")
end

function describe(name, fn)
    local parent = pzspec._current
    local label = parent and (parent.name .. " > " .. name) or name
    local suite = newSuite(label)
    suite._parent = parent
    local prev = pzspec._current
    pzspec._current = suite
    local ok, err = pcall(fn)
    pzspec._current = prev
    if not ok then
        table.insert(suite.tests, {
            name = "<describe body>",
            fn = function() error(err, 0) end,
        })
    end
end

function it(name, fn)
    table.insert(currentSuite().tests, { name = name, fn = fn })
end

local function addHook(kind, fn)
    table.insert(currentSuite()[kind], fn)
end

function before_each(fn) addHook("befores", fn) end
function after_each(fn)  addHook("afters",  fn) end
function before_all(fn)
    local s = currentSuite()
    s._beforeAll = s._beforeAll or {}
    table.insert(s._beforeAll, fn)
end
function after_all(fn)
    local s = currentSuite()
    s._afterAll = s._afterAll or {}
    table.insert(s._afterAll, fn)
end

function pzspec.global_before_each(fn)
    table.insert(pzspec._global_befores, fn)
end

function pzspec._run_global_befores()
    for _, fn in ipairs(pzspec._global_befores) do fn() end
end

_G.describe = describe
_G.it = it
_G.before_each = before_each
_G.after_each = after_each
_G.before_all = before_all
_G.after_all = after_all
_G.xit = function() end
_G.xdescribe = function() end

local function fail(msg)
    error("expect failed: " .. msg, 2)
end

local function deepEqual(a, b, seen)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for k, v in pairs(a) do
        if not deepEqual(v, b[k], seen) then return false end
    end
    for k, v in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function fmt(v)
    if type(v) ~= "table" then return tostring(v) end
    local inspect = rawget(_G, "__inspect")
    if inspect ~= nil then
        local ok, dump = pcall(inspect, v, { depth = 6, indent = "  " })
        if ok and type(dump) == "string" then return dump end
    end
    return "table: " .. tostring(v)
end

local function expect(actual)
    local m = {}
    function m.toBe(expected)
        if actual ~= expected then
            fail("expected " .. fmt(actual) .. " to be " .. fmt(expected))
        end
    end
    function m.toEqual(expected)
        if not deepEqual(actual, expected) then
            fail("toEqual mismatch\nexpected:\n" .. fmt(expected)
                .. "\ngot:\n" .. fmt(actual))
        end
    end
    function m.toBeNil()
        if actual ~= nil then fail("expected nil, got " .. fmt(actual)) end
    end
    function m.toBeTruthy()
        if not actual then fail("expected truthy, got " .. fmt(actual)) end
    end
    function m.toBeFalsy()
        if actual then fail("expected falsy, got " .. fmt(actual)) end
    end
    function m.toContain(item)
        if type(actual) == "string" then
            if not actual:find(item, 1, true) then
                fail("expected " .. fmt(actual) .. " to contain " .. fmt(item))
            end
        elseif type(actual) == "table" then
            for _, v in pairs(actual) do
                if deepEqual(v, item) then return end
            end
            fail("expected table to contain " .. fmt(item))
        else
            fail("toContain on " .. type(actual))
        end
    end
    function m.toBeCloseTo(expected, eps)
        eps = eps or 1e-6
        if type(actual) ~= "number" or math.abs(actual - expected) > eps then
            fail("expected " .. fmt(actual) .. " ~= " .. fmt(expected)
                .. " (eps " .. eps .. ")")
        end
    end
    function m.toThrow()
        if type(actual) ~= "function" then
            fail("toThrow expects a function")
        end
        local ok = pcall(actual)
        if ok then fail("expected function to throw") end
    end
    return m
end
_G.expect = expect

function expect_eq(actual, expected, msg)
    if not deepEqual(actual, expected) then
        fail((msg or "not equal") .. ": expected " .. fmt(expected)
            .. ", got " .. fmt(actual))
    end
end
_G.expect_eq = expect_eq

function mock(impl)
    local m = { calls = {}, _impl = impl }
    local f = function(...)
        local args = { n = select("#", ...), ... }
        table.insert(m.calls, args)
        if m._impl then return m._impl(...) end
    end
    m.fn = f
    return setmetatable(m, {
        __call = function(self, ...) return f(...) end,
    })
end
_G.mock = mock
_G.spy = mock

function spyOn(obj, name)
    local orig = obj[name]
    local s = mock(orig)
    obj[name] = s.fn
    s.restore = function() obj[name] = orig end
    return s
end
_G.spyOn = spyOn

local function runHooks(list)
    for _, fn in ipairs(list) do fn() end
end

local function collectHooks(suite, kind)
    local chain = {}
    local s = suite
    while s do
        table.insert(chain, 1, s)
        s = s._parent
    end
    local out = {}
    for _, node in ipairs(chain) do
        for _, fn in ipairs(node[kind] or {}) do
            table.insert(out, fn)
        end
    end
    return out
end

local function runSuite(suite)
    local beforesAll = suite._beforeAll or {}
    local aftersAll = suite._afterAll or {}
    for _, fn in ipairs(beforesAll) do
        local ok, err = pcall(fn)
        if not ok then
            pzspec.stats.failed = pzspec.stats.failed + 1
            pzspec.stats.total = pzspec.stats.total + 1
            print("FAIL " .. suite.name .. " <before_all>: " .. tostring(err))
            print("  SKIP " .. suite.name .. " :: "
                .. #suite.tests .. " tests skipped (before_all failed)")
            return
        end
    end

    local beforeEach = collectHooks(suite, "befores")
    local afterEach = collectHooks(suite, "afters")

    for _, test in ipairs(suite.tests) do
        pzspec.stats.total = pzspec.stats.total + 1
        pzspec._run_global_befores()
        for _, fn in ipairs(beforeEach) do fn() end
        local bodyOk, err = pcall(test.fn)
        local hookErr = nil
        for _, fn in ipairs(afterEach) do
            local hok, herr = pcall(fn)
            if not hok and hookErr == nil then hookErr = herr end
        end
        local ok
        if not bodyOk and hookErr ~= nil then
            err = err .. "\n       after_each: " .. tostring(hookErr)
            ok = false
        elseif hookErr ~= nil then
            ok = false
            err = "after_each: " .. tostring(hookErr)
        else
            ok = bodyOk
        end
        if ok then
            pzspec.stats.passed = pzspec.stats.passed + 1
            print("  ok   " .. suite.name .. " :: " .. test.name)
        else
            pzspec.stats.failed = pzspec.stats.failed + 1
            print("  FAIL " .. suite.name .. " :: " .. test.name)
            print("       " .. tostring(err))
        end
    end

    for _, fn in ipairs(aftersAll) do
        local ok, err = pcall(fn)
        if not ok then
            pzspec.stats.failed = pzspec.stats.failed + 1
            pzspec.stats.total = pzspec.stats.total + 1
            print("FAIL " .. suite.name .. " <after_all>: " .. tostring(err))
            return
        end
    end
end

function pzspec.run()
    print("=" .. string.rep("=", 69))
    print("pzspec run")
    print("=" .. string.rep("=", 69))
    for _, suite in ipairs(pzspec.suites) do
        runSuite(suite)
    end
    print("-" .. string.rep("-", 70))
    print(string.format("total=%d passed=%d failed=%d",
        pzspec.stats.total, pzspec.stats.passed, pzspec.stats.failed))
    print(pzspec.stats.failed == 0 and "ALL PASS" or "FAILURES")
    return pzspec.stats.failed == 0, pzspec.stats
end

_G.__pzspec = pzspec

return pzspec
