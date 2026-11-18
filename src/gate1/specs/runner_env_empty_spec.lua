local function runnerPath()
    for entry in package.path:gmatch("[^;]+") do
        local cand = entry:gsub("%?", "gate1/runner")
        if cand:match("gate1[/\\]runner%.lua$") then return cand end
    end
    return nil
end

local path = runnerPath()
if not path then
    error("runner_env_empty_spec: cannot locate gate1/runner.lua via package.path")
end
local runner = dofile(path)

local VARS = {
    "PZ_CTX", "PZ_STRICT", "PZ_STUB_PACKS", "PZ_STUBS",
    "PZ_LUA_PATH", "PZ_SPECS", "PZ_UMBRELLA",
}

local function withEnv(overrides, fn)
    local saved = os.getenv
    os.getenv = function(n)
        for _, v in ipairs(VARS) do
            if n == v then return overrides[n] end
        end
        return saved(n)
    end
    local ok, err = pcall(fn)
    os.getenv = saved
    if not ok then error(err, 0) end
end

describe("runner resolveConfig — PZ_* empty-string fallback", function()
    it("(a) all PZ_* unset -> every key resolves to its default", function()
        withEnv({}, function()
            local cfg = runner.resolveConfig({})
            expect(cfg.ctx).toBe("sp")
            expect(cfg.strict).toBe(false)
            expect(cfg.stub_packs).toEqual({})
            expect(cfg.stubs).toEqual({})
            expect(cfg.lua_path).toEqual({})
            expect(cfg.specs).toEqual({})
            expect(cfg.umbrella).toBeNil()
        end)
    end)

    it("(b) PZ_CTX='' -> default ctx 'sp' (NOT '')", function()
        withEnv({ PZ_CTX = "" }, function()
            expect(runner.resolveConfig({}).ctx).toBe("sp")
        end)
    end)

    it("(c) PZ_CTX='client' -> used", function()
        withEnv({ PZ_CTX = "client" }, function()
            expect(runner.resolveConfig({}).ctx).toBe("client")
        end)
    end)

    it("(d) config.ctx beats PZ_CTX (precedence unchanged)", function()
        withEnv({ PZ_CTX = "client" }, function()
            expect(runner.resolveConfig({ ctx = "server" }).ctx).toBe("server")
        end)
    end)

    it("(e) PZ_STRICT='' -> strict off", function()
        withEnv({ PZ_STRICT = "" }, function()
            expect(runner.resolveConfig({}).strict).toBe(false)
        end)
    end)

    it("(f) PZ_STRICT='0' -> strict off", function()
        withEnv({ PZ_STRICT = "0" }, function()
            expect(runner.resolveConfig({}).strict).toBe(false)
        end)
    end)

    it("(g) PZ_STRICT='1' -> strict armed", function()
        withEnv({ PZ_STRICT = "1" }, function()
            expect(runner.resolveConfig({}).strict).toBe(true)
        end)
    end)

    it("(h) PZ_STRICT unset -> strict off", function()
        withEnv({}, function()
            expect(runner.resolveConfig({}).strict).toBe(false)
        end)
    end)

    it("(i) config.strict=false forces off despite PZ_STRICT='1'", function()
        withEnv({ PZ_STRICT = "1" }, function()
            expect(runner.resolveConfig({ strict = false }).strict).toBe(false)
        end)
    end)

    it("(j) config.strict=true arms despite PZ_STRICT='0'", function()
        withEnv({ PZ_STRICT = "0" }, function()
            expect(runner.resolveConfig({ strict = true }).strict).toBe(true)
        end)
    end)

    it("(k) PZ_STUB_PACKS='' -> empty pack list (default)", function()
        withEnv({ PZ_STUB_PACKS = "" }, function()
            expect(runner.resolveConfig({}).stub_packs).toEqual({})
        end)
    end)

    it("(l) PZ_STUB_PACKS='core,game' -> used", function()
        withEnv({ PZ_STUB_PACKS = "core,game" }, function()
            expect(runner.resolveConfig({}).stub_packs).toEqual({ "core", "game" })
        end)
    end)

    it("(m) PZ_STUBS='' -> empty stub dir list (default)", function()
        withEnv({ PZ_STUBS = "" }, function()
            expect(runner.resolveConfig({}).stubs).toEqual({})
        end)
    end)

    it("(n) PZ_STUBS='a;b' -> used", function()
        withEnv({ PZ_STUBS = "a;b" }, function()
            expect(runner.resolveConfig({}).stubs).toEqual({ "a", "b" })
        end)
    end)

    it("(o) PZ_LUA_PATH='' -> empty extra-path list (default)", function()
        withEnv({ PZ_LUA_PATH = "" }, function()
            expect(runner.resolveConfig({}).lua_path).toEqual({})
        end)
    end)

    it("(p) PZ_LUA_PATH='x;y' -> used", function()
        withEnv({ PZ_LUA_PATH = "x;y" }, function()
            expect(runner.resolveConfig({}).lua_path).toEqual({ "x", "y" })
        end)
    end)

    it("(q) PZ_SPECS='' -> empty spec list (default set kicks in)", function()
        withEnv({ PZ_SPECS = "" }, function()
            expect(runner.resolveConfig({}).specs).toEqual({})
        end)
    end)

    it("(r) PZ_SPECS='a;b' -> used", function()
        withEnv({ PZ_SPECS = "a;b" }, function()
            expect(runner.resolveConfig({}).specs).toEqual({ "a", "b" })
        end)
    end)

    it("(s) PZ_UMBRELLA='' -> umbrella off (nil, NOT '')", function()
        withEnv({ PZ_UMBRELLA = "" }, function()
            expect(runner.resolveConfig({}).umbrella).toBeNil()
        end)
    end)

    it("(t) PZ_UMBRELLA='/clone/root' -> used", function()
        withEnv({ PZ_UMBRELLA = "/clone/root" }, function()
            expect(runner.resolveConfig({}).umbrella).toBe("/clone/root")
        end)
    end)

    it("(u) config.umbrella beats PZ_UMBRELLA (precedence unchanged)", function()
        withEnv({ PZ_UMBRELLA = "/from/env" }, function()
            local cfg = runner.resolveConfig({ umbrella = "/from/config" })
            expect(cfg.umbrella).toBe("/from/config")
        end)
    end)
end)
