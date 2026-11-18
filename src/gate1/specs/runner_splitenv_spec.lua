local function runnerPath()
    for entry in package.path:gmatch("[^;]+") do
        local cand = entry:gsub("%?", "gate1/runner")
        if cand:match("gate1[/\\]runner%.lua$") then return cand end
    end
    return nil
end

local path = runnerPath()
if not path then
    error("runner_splitenv_spec: cannot locate gate1/runner.lua via package.path")
end
local runner = dofile(path)

local function withGetenv(name, value, fn)
    local saved = os.getenv
    os.getenv = function(n)
        if n == name then return value end
        return saved(n)
    end
    local ok, err = pcall(fn)
    os.getenv = saved
    if not ok then error(err, 0) end
end

describe("runner splitEnv", function()
    local NAME = "PZ_TEST_SPLITENV"

    it("(a) 'a;;b' -> {'a','b'} (inner empty segment dropped)", function()
        withGetenv(NAME, "a;;b", function()
            expect(runner.splitEnv(NAME, ";")).toEqual({ "a", "b" })
        end)
    end)

    it("(b) 'a;' -> {'a'} (trailing separator drops)", function()
        withGetenv(NAME, "a;", function()
            expect(runner.splitEnv(NAME, ";")).toEqual({ "a" })
        end)
    end)

    it("(c) ';a' -> {'a'} (leading separator drops)", function()
        withGetenv(NAME, ";a", function()
            expect(runner.splitEnv(NAME, ";")).toEqual({ "a" })
        end)
    end)

    it("(d) ';;' -> {} (separators only)", function()
        withGetenv(NAME, ";;", function()
            expect(runner.splitEnv(NAME, ";")).toEqual({})
        end)
    end)

    it("(e) 'a' -> {'a'} (no separator)", function()
        withGetenv(NAME, "a", function()
            expect(runner.splitEnv(NAME, ";")).toEqual({ "a" })
        end)
    end)

    it("(f) '' -> {} (empty value)", function()
        withGetenv(NAME, "", function()
            expect(runner.splitEnv(NAME, ";")).toEqual({})
        end)
    end)

    it("(g) unset env var -> {} (default-specs branch depends on this)", function()
        expect(runner.splitEnv("PZ_TEST_SPLITENV_UNSET", ";")).toEqual({})
    end)

    it("(h) sep parameter: ',' splits pack names, ';' stays inside a segment", function()
        withGetenv(NAME, "core,game;extra", function()
            expect(runner.splitEnv(NAME, ",")).toEqual({ "core", "game;extra" })
            expect(runner.splitEnv(NAME, ";")).toEqual({ "core,game", "extra" })
        end)
    end)
end)
