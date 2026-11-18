describe("runner package.path accumulation across run(config) calls", function()
    local WINDOWS = (package.config:sub(1, 1) == "\\")

    local function repoRoot()
        local dir = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
        local stripped = dir:gsub("[/\\]src[/\\]gate1$", "")
        if stripped == dir then stripped = dir .. "/../.." end
        return stripped
    end

    local function join(root, rel)
        if root == "" then return rel end
        return root .. "/" .. rel
    end

    local function mkdirp(d)
        if WINDOWS then
            os.execute('mkdir "' .. d:gsub("/", "\\") .. '" 2>nul')
        else
            os.execute('mkdir -p "' .. d .. '" 2>/dev/null')
        end
    end

    local function writeFile(path, content)
        local f = io.open(path, "wb")
        assert(f, "runner_path fixture write failed: " .. path)
        f:write(content)
        f:close()
    end

    local runner, dirA, dirB

    before_all(function()
        local root = repoRoot()
        runner = dofile(join(root, "src/gate1/runner.lua"))
        dirA = join(root, ".tmp/runner_path_fixture/a")
        dirB = join(root, ".tmp/runner_path_fixture/b")
        mkdirp(dirA)
        mkdirp(dirB)
        writeFile(dirA .. "/a_spec.lua", table.concat({
            "-- self-authored fixture (runner_path_spec.lua): ONE passing test",
            'describe("fixture a", function()',
            '\tit("a passes", function()',
            "\t\texpect(1 + 1).toBe(2)",
            "\tend)",
            "end)",
            "",
        }, "\n"))
        writeFile(dirB .. "/b_spec.lua", table.concat({
            "-- self-authored fixture (runner_path_spec.lua): TWO passing tests",
            'describe("fixture b", function()',
            '\tit("b passes 1", function()',
            '\t\texpect("x" .. "y").toBe("xy")',
            "\tend)",
            '\tit("b passes 2", function()',
            "\t\texpect(#{}).toBe(0)",
            "\tend)",
            "end)",
            "",
        }, "\n"))
    end)

    it("(a) run(config) twice in-process: package.path byte-identical after run 2, each run executes its own specs", function()
        local savedPath = package.path
        local savedPrint = print
        local path1, path2, r1, r2
        local ok, err = pcall(function()
            print = function() end

            r1 = runner.run({ specs = { dirA } })
            path1 = package.path
            r2 = runner.run({ specs = { dirB } })
            path2 = package.path
        end)
        print = savedPrint
        package.path = savedPath
        if not ok then error(err, 0) end

        expect(r1.ok).toBeTruthy()
        expect(r1.total).toBe(1)
        expect(r1.passed).toBe(1)
        expect(r1.failed).toBe(0)
        expect(r2.ok).toBeTruthy()
        expect(r2.total).toBe(2)
        expect(r2.passed).toBe(2)
        expect(r2.failed).toBe(0)

        expect(#path2).toBe(#path1)
        expect(path2).toBe(path1)
    end)
end)
