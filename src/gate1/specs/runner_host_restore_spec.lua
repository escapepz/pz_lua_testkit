describe("runner host restoration on a raising run", function()
    local function repoRoot()
        local dir = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
        local stripped = dir:gsub("[/\\]src[/\\]gate1$", "")
        if stripped == dir or stripped == "" then stripped = dir .. "/../.." end
        return stripped
    end

    local WINDOWS = (package.config:sub(1, 1) == "\\")
    local FIX = repoRoot() .. "/.tmp/runner_host_restore_fixture"

    local function buildFixture()
        local function mkdirp(d)
            if WINDOWS then
                os.execute('mkdir "' .. (d:gsub("/", "\\")) .. '" 2>nul')
            else
                os.execute('mkdir -p "' .. d .. '" 2>/dev/null')
            end
        end
        mkdirp(FIX)
        local f = io.open(FIX .. "/boom_spec.lua", "wb")
        if f then
            f:write(table.concat({
                "describe(\"boom suite\", function()",
                "    before_each(function() error(\"boom-in-before-each\") end)",
                "    it(\"t\", function() end)",
                "end)",
            }, "\n") .. "\n")
            f:close()
        end
    end

    it("a raising before_each propagates the error AND leaves the host restored", function()
        buildFixture()
        local ROOT = repoRoot()
        local runner = dofile(ROOT .. "/src/gate1/runner.lua")
        local savedMeta = getmetatable(_G)
        local savedPath = package.path
        local ok, err = pcall(function()
            runner.run({ strict = true, specs = { FIX .. "/boom_spec.lua" } })
        end)
        expect(ok).toBe(false)
        expect(tostring(err):find("boom-in-before-each", 1, true)).toBeTruthy()
        expect(getmetatable(_G)).toBe(savedMeta)
        expect(package.path).toBe(savedPath)
    end)
end)
