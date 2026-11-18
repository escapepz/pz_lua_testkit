-- runner.lua — loadable gate1 runner (plain Lua 5.1, zero deps)
-- Consumer-facing API:
--   runner.run(config) -> { total = int, passed = int, failed = int, ok = bool }
--   runner.collect_specs(list) -> spec files (resolve file-or-dir + dedupe)
--   runner.prepare_mod(mod_dir, ctx, mod_path) -> mod loader result table
--       or nil — layout resolution (B41 single root / B42 common/ +
--       <versionDir>/ dual layout), require roots + auto-exec load order in
--       engine order, <modDir>/TESTS spec dirs, mod.info require= deps
--
-- config keys (explicit config -> env -> default):
--   ctx        = "sp" | "client" | "server"   (default "sp"; env PZ_CTX)
--   strict     = true arms strict mode, false forces it off (default: key
--               absent -> env PZ_STRICT == "1" decides; off either way)
--   stub_packs = built-in pack names          (default {}; env PZ_STUB_PACKS,
--               ","-separated -> src/gate1/stubs/<name>.lua)
--   stubs      = mod stub dirs                (default {}; env PZ_STUBS,
--               ";"-separated, every .lua in dir loaded)
--   lua_path   = extra package.path entries   (default {}; env PZ_LUA_PATH,
--               ";"-separated, prepended)
--   specs      = spec files/dirs              (default {SRC.."/specs",
--               ROOT.."/specs"}; env PZ_SPECS, ";"-separated, scanned like
--               CLI args)
--   umbrella   = path to an Umbrella clone root (contains library/) —
--               (default nil; env PZ_UMBRELLA) — opts into serve mode: the
--               resolver module is loaded and inited BEFORE the strict guard
--               arms, so the guard consults Umbrella.resolve_global before
--               erroring on unknown globals (mode off / unset: guard
--               unchanged)
--   mod        = dir of the mod under test (default nil) — opts into mod
--               mode: the contract require (stubs/pzrequire.lua) is
--               installed, the mod's own Lua auto-executes in engine
--               LoadDirBase order (ctx-driven), and specs default to the
--               mod's TESTS dirs (mod mode off / unset: runner path
--               unchanged — _G.require stays std, no _G.testkit)
--   mod_path   = ordered dep mod search dirs (default {}; env PZ_MOD_PATH,
--               ";"-separated via splitEnv): each mod.info require= token
--               is looked up as <searchDir>/<token>/ (same layout rule as
--               the own mod) and a hit's media/lua/{shared,client,server}
--               dirs are appended to the require roots AFTER the own roots;
--               dep mods contribute ROOTS ONLY — no auto-exec (dep code
--               executes on require, execute-once); a miss warns once and
--               continues (stub-by-default posture)
--   reset_per_test = per-test testkit.resetLoaded() wiring (default: key
--               absent -> env PZ_RESET_PER_TEST == "1"; env unset -> true
--               when mod is set, false otherwise) — three-state like strict.
--               When the mod loader installed the contract require AND this
--               resolves true, run() registers a hook on pzspec's global
--               before_each tier (pzspec.global_before_each) that calls
--               _G.testkit.resetLoaded() before every test, so each test
--               sees a fresh require cache (keep()/provide() entries
--               survive; Events listeners re-register exactly once). Without
--               the loader the key is inert. The hook body is TOTAL:
--               rawget reads + type guards — pzspec does NOT pcall before
--               hooks, so a raising hook would kill the whole run.
--
-- runner.wire_reset(config, installed) -> boolean — the run() step-9 block
-- extracted for spec-drivability (no nested run needed): resolves
-- reset_per_test three-state against config (+ env) and, iff `installed` is
-- truthy (the loader installed the contract require) and the result is true,
-- delegates the resetLoaded hook registration to reset.wire_per_test
-- (reset.lua) with rawget(_G, "__pzspec"). Returns whether a hook was
-- registered.
--
-- run() NEVER calls os.exit: hosts own the process. The CLI entry (run.lua)
-- maps the result to exit codes via reporter.exit_code (reporter.lua): the
-- frozen formula reads only the result table — ok -> 0, zero specs -> 2,
-- else 1.

local SOURCE = debug.getinfo(1, "S").source:sub(2)
local ROOT = SOURCE:match("^(.*)[/\\][^/\\]*$") or "."
local SRC = ROOT .. "/.."

local config = dofile(ROOT .. "/config.lua")
local resolveConfig = config.resolve
local resolveResetPerTest = config.resolve_reset_per_test

local discovery = dofile(ROOT .. "/discovery.lua")
local collectSpecs = discovery.collect_specs

local modloader = dofile(ROOT .. "/modloader.lua")
local prepare_mod = modloader.prepare_mod

local reset = dofile(ROOT .. "/reset.lua")

local reporter = dofile(ROOT .. "/reporter.lua")

local wire_reset

local function run(config)
    local cfg = resolveConfig(config)
    local ctx = cfg.ctx
    local strict = cfg.strict
    local stubPacks = cfg.stub_packs
    local stubDirs = cfg.stubs
    local extraPath = cfg.lua_path
    local specArgs = cfg.specs
    local umbrella = cfg.umbrella
    local mod = cfg.mod
    local modPath = cfg.mod_path

    local savedPath = package.path

    _G.PZ_GATE = "gate1"

    package.path = SRC .. "/?.lua;"
        .. ROOT .. "/stubs/?.lua;"
        .. ROOT .. "/stubs/?/init.lua;"
        .. SRC .. "/specs/?.lua;"
        .. table.concat(extraPath, ";") .. ";"
        .. package.path

    _G.__inspect = dofile(SRC .. "/vendor/inspect.lua")
    local pzspec = dofile(SRC .. "/pzspec.lua")

    overlords_ctx = ctx

    _G.pz_strict = strict

    dofile(ROOT .. "/stubs/core.lua")

    for _, name in ipairs(stubPacks) do
        local pack = SRC .. "/gate1/stubs/" .. name .. ".lua"
        local f = io.open(pack, "r")
        if f then
            f:close()
            local ok, err = pcall(dofile, pack)
            if not ok then
                print("STUB LOAD FAIL " .. pack .. ": " .. tostring(err))
            end
        else
            print("STUB PACK MISSING " .. name)
        end
    end

    for _, d in ipairs(stubDirs) do
        local p = io.popen((package.config:sub(1,1) == "\\")
            and ('dir /b "' .. d .. '\\*.lua"')
            or ('ls "' .. d .. '"/*.lua 2>/dev/null'))
        if p then
            for line in p:lines() do
                line = line:gsub("%s+$", "")
                if line ~= "" then
                    local full = (d .. "/" .. line:gsub(".*[/\\]", ""))
                    local ok, err = pcall(dofile, full)
                    if not ok then
                        print("STUB LOAD FAIL " .. full .. ": " .. tostring(err))
                    end
                end
            end
            p:close()
        end
    end

    if umbrella then
        if rawget(_G, "Umbrella") == nil then
            dofile(ROOT .. "/stubs/umbrella.lua")
        end
        local U = rawget(_G, "Umbrella")
        if type(U) == "table" and type(U.init) == "function" then
            U.init(umbrella)
        end
    end

    local PzRequire = nil
    local modResult = nil
    if mod then
        if rawget(_G, "PzRequire") == nil then
            dofile(ROOT .. "/stubs/pzrequire.lua")
        end
        PzRequire = rawget(_G, "PzRequire")
        if type(PzRequire) == "table"
            and type(PzRequire.init) == "function"
            and type(PzRequire.install) == "function"
            and type(PzRequire.require_file) == "function" then
            modResult = prepare_mod(mod, ctx, modPath)
            if modResult then
                PzRequire.init(modResult.roots)
                PzRequire.install()
            end
        else
            PzRequire = nil
        end
    end

    if _G.pz_strict then
        setmetatable(_G, {
            __index = function(_, k)
                if not _G.pz_strict then
                    return rawget(_G, k)
                end
                local U = rawget(_G, "Umbrella")
                if U and U.on then
                    local v = U.resolve_global(k)
                    if v ~= nil then return v end
                end
                error("PZ_STRICT: unknown global '" .. tostring(k) .. "'", 2)
            end,
        })
    end

    if modResult then
        for _, f in ipairs(modResult.load_files) do
            local ok, err = pcall(PzRequire.require_file, f)
            if not ok then
                package.path = savedPath
                return reporter.fail_result("PZ_MOD LOAD FAIL", f, err)
            end
        end
    end

    wire_reset(cfg, modResult ~= nil)

    if #specArgs == 0 then
        if modResult then
            specArgs = modResult.spec_dirs
        else
            specArgs = { SRC .. "/specs", ROOT .. "/specs" }
        end
    end

    local specs = collectSpecs(specArgs)
    table.sort(specs)
    if #specs == 0 then
        print("no spec files found")
        package.path = savedPath
        return { total = 0, passed = 0, failed = 0, ok = false }
    end

    for _, s in ipairs(specs) do
        local ok, err = pcall(dofile, s)
        if not ok then
            package.path = savedPath
            return reporter.fail_result("SPEC LOAD FAIL", s, err)
        end
    end

    local ok, stats = pzspec.run()
    package.path = savedPath
    return reporter.summarize(ok, stats)
end

function wire_reset(config, installed)
    if not installed or not resolveResetPerTest(config) then
        return false
    end
    return reset.wire_per_test(rawget(_G, "__pzspec"), true)
end

return {
    run = run,
    collect_specs = discovery.collect_specs,
    splitEnv = config.split_env,
    resolveConfig = config.resolve,
    prepare_mod = modloader.prepare_mod,
    wire_reset = wire_reset,
}
