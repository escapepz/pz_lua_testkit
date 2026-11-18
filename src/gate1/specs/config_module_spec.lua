local SOURCE = debug.getinfo(1, "S").source:sub(2)
local HERE = SOURCE:match("^(.*)[/\\][^/\\]*$") or "."
local config = dofile(HERE .. "/../config.lua")

local t = {}
local fakeEnv = function(n) return t[n] end

local function withEnv(overrides, fn)
    local saved = t
    t = {}
    for k, v in pairs(overrides) do t[k] = v end
    local ok, err = pcall(fn)
    t = saved
    if not ok then error(err, 0) end
end

local function keyset(tbl)
    local keys = {}
    for k in pairs(tbl) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

describe("config module", function()

    it("(a) env_value: set value passes through", function()
        withEnv({ PZ_TEST_V = "x" }, function()
            expect(config.env_value("PZ_TEST_V", fakeEnv)).toBe("x")
        end)
    end)

    it("(b) env_value: '' -> nil (Windows `set PZ_CTX=` empty-string posture)", function()
        withEnv({ PZ_TEST_V = "" }, function()
            expect(config.env_value("PZ_TEST_V", fakeEnv)).toBeNil()
        end)
    end)

    it("(c) env_value: missing -> nil", function()
        withEnv({}, function()
            expect(config.env_value("PZ_TEST_V", fakeEnv)).toBeNil()
        end)
    end)

    it("(d) split_env: splits on sep, empty segments never survive ('a;;b' -> {'a','b'})", function()
        withEnv({ PZ_TEST_S = "a;;b" }, function()
            expect(config.split_env("PZ_TEST_S", ";", fakeEnv)).toEqual({ "a", "b" })
        end)
    end)

    it("(e) split_env: unset -> {}", function()
        withEnv({}, function()
            expect(config.split_env("PZ_TEST_S", ";", fakeEnv)).toEqual({})
        end)
    end)

    it("(f) explicit config true/false win over env", function()
        withEnv({ PZ_RESET_PER_TEST = "1" }, function()
            expect(config.resolve_reset_per_test({ reset_per_test = false }, fakeEnv)).toBe(false)
            expect(config.resolve_reset_per_test({ reset_per_test = true }, fakeEnv)).toBe(true)
        end)
    end)

    it("(g) key absent + env '1' -> true", function()
        withEnv({ PZ_RESET_PER_TEST = "1" }, function()
            expect(config.resolve_reset_per_test({}, fakeEnv)).toBe(true)
        end)
    end)

    it("(h) key absent + env '' -> falls to default (cfg.mod ~= nil)", function()
        withEnv({ PZ_RESET_PER_TEST = "" }, function()
            expect(config.resolve_reset_per_test({ mod = "m" }, fakeEnv)).toBe(true)
            expect(config.resolve_reset_per_test({}, fakeEnv)).toBe(false)
        end)
    end)

    it("(i) key absent + env unset -> cfg.mod ~= nil (mod set true, no-mod false)", function()
        withEnv({}, function()
            expect(config.resolve_reset_per_test({ mod = "m" }, fakeEnv)).toBe(true)
            expect(config.resolve_reset_per_test({}, fakeEnv)).toBe(false)
        end)
    end)

    it("(j) explicit ctx beats env (precedence unchanged)", function()
        withEnv({ PZ_CTX = "client" }, function()
            expect(config.resolve({ ctx = "server" }, fakeEnv).ctx).toBe("server")
        end)
    end)

    it("(k) env '' ctx -> default 'sp' (NOT '')", function()
        withEnv({ PZ_CTX = "" }, function()
            expect(config.resolve({}, fakeEnv).ctx).toBe("sp")
        end)
    end)

    it("(l) strict three-state: env '1' arms; explicit false forces off despite env '1'; env unset -> off", function()
        withEnv({ PZ_STRICT = "1" }, function()
            expect(config.resolve({}, fakeEnv).strict).toBe(true)
            expect(config.resolve({ strict = false }, fakeEnv).strict).toBe(false)
        end)
        withEnv({}, function()
            expect(config.resolve({}, fakeEnv).strict).toBe(false)
        end)
    end)

    it("(m) list keys default {} when keys absent and env unset", function()
        withEnv({}, function()
            local cfg = config.resolve({}, fakeEnv)
            expect(cfg.stub_packs).toEqual({})
            expect(cfg.stubs).toEqual({})
            expect(cfg.lua_path).toEqual({})
            expect(cfg.specs).toEqual({})
            expect(cfg.mod_path).toEqual({})
            expect(cfg.umbrella).toBeNil()
            expect(cfg.mod).toBeNil()
            expect(cfg.reset_per_test).toBe(false)
        end)
    end)

    it("(n) every PZ_* read routes through env_fn, not os.getenv", function()
        withEnv({
            PZ_CTX = "client", PZ_STRICT = "1", PZ_STUB_PACKS = "core",
            PZ_STUBS = "sd", PZ_LUA_PATH = "lp", PZ_SPECS = "sf",
            PZ_UMBRELLA = "/u", PZ_MOD_PATH = "mp", PZ_RESET_PER_TEST = "0",
        }, function()
            local cfg = config.resolve({}, fakeEnv)
            expect(cfg.ctx).toBe("client")
            expect(cfg.strict).toBe(true)
            expect(cfg.stub_packs).toEqual({ "core" })
            expect(cfg.stubs).toEqual({ "sd" })
            expect(cfg.lua_path).toEqual({ "lp" })
            expect(cfg.specs).toEqual({ "sf" })
            expect(cfg.umbrella).toBe("/u")
            expect(cfg.mod_path).toEqual({ "mp" })
            expect(cfg.reset_per_test).toBe(false)
        end)
    end)

    it("(o) resolve returns EXACTLY the pinned key set", function()
        withEnv({}, function()

            expect(keyset(config.resolve({ mod = "m", umbrella = "/u" }, fakeEnv))).toEqual({
                "ctx", "lua_path", "mod", "mod_path", "reset_per_test",
                "specs", "strict", "stub_packs", "stubs", "umbrella",
            })
        end)
    end)

    it("(p) dofileing runner.lua leaves package.loaded['config'] and ['discovery'] nil (dofile siblings, never require)", function()
        dofile(HERE .. "/../runner.lua")
        local loaded = rawget(package, "loaded")
        expect(loaded["config"]).toBeNil()
        expect(loaded["discovery"]).toBeNil()
    end)
end)
