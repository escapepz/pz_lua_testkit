-- run.lua — gate1 CLI entry point (thin wrapper; the environment assembly and
-- the actual run live in runner.lua, which is also loadable by consumers)
-- Usage: lua5.1.exe src/gate1/run.lua [--mod <mod_dir>] [spec_file_or_dir ...]
--
-- Exit codes: 0 = suite passed, 2 = no spec files found or CLI usage error,
-- 1 = spec load fail or suite failed.
--
-- Mod mode (--mod <dir> or --mod=<dir>): loads the mod under test — its
-- mod.info (B41 single root or B42 common/ + <versionDir>/ dual layout)
-- registers the contract require roots, its own Lua auto-executes in engine
-- LoadDirBase order, and specs default to the mod's TESTS dirs (files
-- *_spec.lua). --mod args are removed from the spec candidates; explicit
-- spec args still win over the mod's TESTS.
--
-- Env vars (consumed by runner.lua):
--   PZ_CTX          = "sp" | "client" | "server"   (default "sp")
--   PZ_LUA_PATH     = extra package.path entries, ";"-separated (prepended)
--   PZ_STUB_PACKS   = built-in pack names, ","-separated
--                     -> src/gate1/stubs/<name>.lua
--   PZ_STUBS        = mod stub dirs, ";"-separated (every .lua in dir loaded)
--   PZ_SPECS        = spec files/dirs, ";"-separated (scanned like CLI args;
--                     resolved BEFORE the args, deduped against them)
--   PZ_STRICT       = "1" arms strict mode (_G.pz_strict, set before stubs
--                     load; the strict unknown-global _G guard is armed after
--                     stubs/packs load, before specs load)
--   PZ_UMBRELLA     = path to an Umbrella clone root (contains library/) —
--                     opts into serve mode: the resolver module is loaded
--                     and inited BEFORE the strict guard arms, so the guard
--                     consults Umbrella.resolve_global before erroring on
--                     unknown globals (mode off / unset: guard unchanged)

local ROOT = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local runner = dofile(ROOT .. "/runner.lua")
local reporter = dofile(ROOT .. "/reporter.lua")

local specArgs = {}
local envSpecs = os.getenv("PZ_SPECS")
if envSpecs then
    for d in envSpecs:gmatch("[^;]+") do
        table.insert(specArgs, d)
    end
end

local modDir = nil
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--mod" then
        if arg[i + 1] == nil or arg[i + 1]:match("^%-%-") then
            io.stderr:write("run.lua: --mod requires a value\n")
            os.exit(2)
        end
        modDir = arg[i + 1]
        i = i + 2
    elseif a:match("^%-%-mod=") then
        modDir = a:match("^%-%-mod=(.*)$")
        i = i + 1
    else
        table.insert(specArgs, a)
        i = i + 1
    end
end

local config = nil
if modDir or #specArgs > 0 then
    config = { mod = modDir, specs = (#specArgs > 0 and specArgs or nil) }
end

local result = runner.run(config)
os.exit(reporter.exit_code(result))
