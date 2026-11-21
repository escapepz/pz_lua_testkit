-- runner_mod_setup_spec.lua — pins the mod-setup failure contract of
-- runner.run: --mod <dir> whose mod.info is missing (prepare_mod -> nil) is
-- a setup error, not a false-green fallthrough to the kit self-test default.
-- runner.run returns the zero-total failure result (reporter.exit_code -> 2)
-- and prints nothing extra itself (modloader already printed the reason;
-- the only other print on this path is the stubs/core.lua load banner).
--
-- The unchanged defaults stay pinned where they already are:
--   good-mod run defaults to the mod's TESTS dirs -> mod_loader_spec.lua
--     e2e subprocess probe (run.lua --mod, no spec args, ALL PASS)
--   non-mod runs keep the kit self-test default -> the top-level suite run
--     itself (lua5.1 src/gate1/run.lua, no args) IS that path, and
--     runner_path_spec (a) / audit_fixes_spec #2 pin that non-mod runs are
--     not hijacked by the mod-setup early return
--
-- The __MOD_SETUP_PIN_RUNNING re-entrancy guard exists for the RED phase of
-- this pin only: before the fix, runner.run({ mod = <dir without mod.info> })
-- falls through to the kit self-test default, which re-loads THIS spec file
-- inside the nested run; the guard turns the re-entrant execution into a
-- no-op instead of infinite recursion. With the fix in place the nested run
-- never happens and the guard is inert.

local function runnerPath()
    for entry in package.path:gmatch("[^;]+") do
        local cand = entry:gsub("%?", "gate1/runner")
        if cand:match("gate1[/\\]runner%.lua$") then return cand end
    end
    return nil
end

local path = runnerPath()
if not path then
    error("runner_mod_setup_spec: cannot locate gate1/runner.lua via package.path")
end
local runner = dofile(path)

local SOURCE = debug.getinfo(1, "S").source:sub(2)
local HERE = SOURCE:match("^(.*)[/\\][^/\\]*$") or "."
local reporter = dofile(HERE .. "/../reporter.lua")

local GUARD = "__MOD_SETUP_PIN_RUNNING"

local WINDOWS = (package.config:sub(1, 1) == "\\")

local function repoRoot()
    local dir = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
    local stripped = dir:gsub("[/\\]src[/\\]gate1$", "")
    if stripped == dir or stripped == "" then stripped = dir .. "/../.." end
    return stripped
end

local function mkdirp(d)
    if WINDOWS then
        os.execute('mkdir "' .. (d:gsub("/", "\\")) .. '" 2>nul')
    else
        os.execute('mkdir -p "' .. d .. '" 2>/dev/null')
    end
end

local FIX = repoRoot() .. "/.tmp/runner_mod_setup_fixture/NoInfoMod"

local VARS = {
    "PZ_CTX", "PZ_STRICT", "PZ_STUB_PACKS", "PZ_STUBS", "PZ_LUA_PATH",
    "PZ_SPECS", "PZ_UMBRELLA", "PZ_MOD_PATH", "PZ_RESET_PER_TEST",
}

local function withEnvClean(fn)
    local saved = os.getenv
    os.getenv = function(n)
        for _, v in ipairs(VARS) do
            if n == v then return nil end
        end
        return saved(n)
    end
    local ok, err = pcall(fn)
    os.getenv = saved
    if not ok then error(err, 0) end
end

describe("runner mod-setup failure (--mod dir without mod.info)", function()
    local result, printSpy

    before_all(function()
        mkdirp(FIX)
        if rawget(_G, GUARD) then return end
        rawset(_G, GUARD, true)
        local ok, err = pcall(function()
            withEnvClean(function()
                printSpy = spyOn(_G, "print")
                local runOk, runErr = pcall(function()
                    result = runner.run({ mod = FIX })
                end)
                printSpy.restore()
                if not runOk then error(runErr, 0) end
            end)
        end)
        rawset(_G, GUARD, nil)
        if not ok then error(err, 0) end
    end)

    it("(a) returns the zero-total failure result, not the kit self-test summary", function()
        if rawget(_G, GUARD) then return end
        expect(result).toEqual({ total = 0, passed = 0, failed = 0, ok = false })
    end)

    it("(b) reporter.exit_code maps the result to 2 (setup error)", function()
        if rawget(_G, GUARD) then return end
        expect(reporter.exit_code(result)).toBe(2)
    end)

    it("(c) runner prints nothing extra: exactly the stub banner + the modloader reason", function()
        if rawget(_G, GUARD) then return end
        expect(#printSpy.calls).toBe(2)
        expect(printSpy.calls[1][1]).toBe("[pzspec] gate1 stubs loaded (ctx=sp)")
        expect(printSpy.calls[2][1]:find("PZ_MOD: mod.info not found in '", 1, true)).toBe(1)
    end)
end)
