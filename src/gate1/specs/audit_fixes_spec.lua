describe("audit fixes #1, #2, #3", function()
    local WINDOWS = (package.config:sub(1, 1) == "\\")

    local function repoRoot()
        local dir = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
        local stripped = dir:gsub("[/\\]src[/\\]gate1$", "")
        if stripped == dir or stripped == "" then stripped = dir .. "/../.." end
        return stripped
    end

    local function absPath(p)
        if p:match("^%a:[/\\]") or p:match("^[/\\]") then
            p = p:gsub("\\", "/")
        else
            local pp = io.popen(WINDOWS and "cd" or "pwd")
            if not pp then return p end
            local cwd = pp:read("*l") or ""
            pp:close()
            cwd = cwd:gsub("%s+$", ""):gsub("\\", "/")
            if cwd == "" then return p end
            p = cwd .. "/" .. p:gsub("\\", "/")
        end
        local root = ""
        if p:sub(1, 1) == "/" then root = "/" end
        local parts = {}
        for seg in p:gmatch("[^/]+") do
            if seg == ".." and #parts > 0 and parts[#parts] ~= ".." then
                parts[#parts] = nil
            elseif seg ~= "." then
                parts[#parts + 1] = seg
            end
        end
        return root .. table.concat(parts, "/")
    end

    local function mkdirp(d)
        if WINDOWS then
            os.execute('mkdir "' .. (d:gsub("/", "\\")) .. '" 2>nul')
        else
            os.execute('mkdir -p "' .. d .. '" 2>/dev/null')
        end
    end

    local function rmdir(d)
        if WINDOWS then
            os.execute('rmdir /s /q "' .. (d:gsub("/", "\\")) .. '" 2>nul')
        else
            os.execute('rm -rf "' .. d .. '" 2>/dev/null')
        end
    end

    local function writeFile(path, content)
        local f = io.open(path, "wb")
        assert(f, "audit_fixes_spec fixture write failed: " .. path)
        f:write(content)
        f:close()
    end

    local ROOT = absPath(repoRoot())
    local FIX = ROOT .. "/.tmp/audit_fixes_fixture"
    local runner = dofile(ROOT .. "/src/gate1/runner.lua")
    local modloader = dofile(ROOT .. "/src/gate1/modloader.lua")
    local discovery = dofile(ROOT .. "/src/gate1/discovery.lua")

    before_each(function()
        rmdir(FIX)
        mkdirp(FIX)
    end)

    after_all(function()
        rmdir(FIX)
    end)

    it("#1 run.lua --unknown-flag exits 2 and prints unknown option to stderr", function()
        local luaBin = (arg and arg[-1]) or "lua5.1"
        local runLua = ROOT .. "/src/gate1/run.lua"
        local outFile = FIX .. "/cli_out.txt"
        local cmd = luaBin .. ' "' .. runLua .. '" --unknown-flag > "' .. outFile .. '" 2>&1'
        local rc = os.execute(cmd)
        local exitCode = WINDOWS and rc or math.floor(rc / 256)

        local f = io.open(outFile, "rb")
        local out = f and f:read("*a") or ""
        if f then f:close() end

        expect(exitCode).toBe(2)
        expect(out:find("unknown option", 1, true) ~= nil).toBeTruthy()
    end)

    local PZSPEC_GLOBALS = {
        "describe", "it", "before_each", "after_each", "before_all",
        "after_all", "xit", "xdescribe", "expect", "expect_eq",
        "mock", "spy", "spyOn", "__pzspec",
    }

    it("#2 runner.run restores _G metatable and pz_strict on normal, syntax-error, and nested strict=false runs", function()
        local passSpec = FIX .. "/pass_spec.lua"
        local errSpec = FIX .. "/syntax_err_spec.lua"
        writeFile(passSpec, 'describe("p", function() it("ok", function() expect(1).toBe(1) end) end)\n')
        writeFile(errSpec, 'this is not valid lua syntax (((\n')

        local outerMeta = getmetatable(_G)
        local outerStrict = rawget(_G, "pz_strict")
        local savedPrint = print
        local savedPzspec = {}
        for _, k in ipairs(PZSPEC_GLOBALS) do
            savedPzspec[k] = rawget(_G, k)
        end

        local ok, err = pcall(function()
            print = function() end

            -- (a) strict = true on passing spec restores non-strict _G
            setmetatable(_G, nil)
            rawset(_G, "pz_strict", false)
            local r1 = runner.run({ strict = true, specs = { passSpec } })
            expect(r1.ok).toBe(true)
            expect(getmetatable(_G)).toBe(nil)
            expect(rawget(_G, "pz_strict")).toBe(false)

            -- (b) strict = true on syntax-error spec (early SPEC LOAD FAIL) restores _G
            setmetatable(_G, nil)
            rawset(_G, "pz_strict", false)
            local r2 = runner.run({ strict = true, specs = { errSpec } })
            expect(r2.ok).toBe(false)
            expect(getmetatable(_G)).toBe(nil)
            expect(rawget(_G, "pz_strict")).toBe(false)

            -- (c) strict = false nested inside pz_strict = true restores pz_strict and metatable
            local sentinelMeta = { __index = function() return nil end }
            setmetatable(_G, sentinelMeta)
            rawset(_G, "pz_strict", true)
            local r3 = runner.run({ strict = false, specs = { passSpec } })
            expect(r3.ok).toBe(true)
            expect(rawget(_G, "pz_strict")).toBe(true)
            expect(getmetatable(_G)).toBe(sentinelMeta)
        end)

        print = savedPrint
        setmetatable(_G, outerMeta)
        rawset(_G, "pz_strict", outerStrict)
        for _, k in ipairs(PZSPEC_GLOBALS) do
            rawset(_G, k, savedPzspec[k])
        end
        if not ok then error(err, 0) end
    end)

    it("#3 modloader.prepare_mod handles leading backslash and rejects backslash traversal in require=", function()
        local ownMod = FIX .. "/OwnMod"
        local depSearch = FIX .. "/deps"
        local depMod = depSearch .. "/DepMod"
        local subDirMod = depSearch .. "/sub/dir"
        local escapeDecoy = FIX .. "/EscapeDecoy"

        mkdirp(ownMod .. "/media/lua/shared")
        mkdirp(depMod .. "/media/lua/shared")
        mkdirp(subDirMod .. "/media/lua/shared")
        mkdirp(escapeDecoy .. "/media/lua/shared")

        writeFile(ownMod .. "/mod.info", "title=Own Mod\nrequire=\\DepMod, sub\\dir, ..\\EscapeDecoy\n")
        writeFile(depMod .. "/mod.info", "title=Dep Mod\n")
        writeFile(depMod .. "/media/lua/shared/dep.lua", "return 1\n")
        writeFile(subDirMod .. "/mod.info", "title=Sub Dir\n")
        writeFile(subDirMod .. "/media/lua/shared/sub.lua", "return 2\n")
        writeFile(escapeDecoy .. "/mod.info", "title=Escape Decoy\n")
        writeFile(escapeDecoy .. "/media/lua/shared/esc.lua", "return 3\n")

        local savedPrint = print
        local res
        local logs = {}
        local ok, err = pcall(function()
            print = function(...)
                local parts = {}
                for i = 1, select("#", ...) do
                    parts[#parts + 1] = tostring(select(i, ...))
                end
                logs[#logs + 1] = table.concat(parts, "\t")
            end
            res = modloader.prepare_mod(ownMod, "sp", { depSearch })
        end)
        print = savedPrint
        if not ok then error(err, 0) end

        expect(res ~= nil).toBeTruthy()
        expect(res.deps[1]).toBe("DepMod")
        expect(res.deps[2]).toBe("sub\\dir")
        expect(res.deps[3]).toBe("..\\EscapeDecoy")

        local joined = table.concat(logs, "\n")
        expect(joined:find("dependency 'sub\\dir' is not a bare mod ID, skipped", 1, true) ~= nil).toBeTruthy()
        expect(joined:find("dependency '..\\EscapeDecoy' is not a bare mod ID, skipped", 1, true) ~= nil).toBeTruthy()

        local rootSet = {}
        for _, r in ipairs(res.roots) do
            rootSet[r] = true
        end
        expect(rootSet[depMod .. "/media/lua/shared"]).toBe(true)
        expect(rootSet[subDirMod .. "/media/lua/shared"]).toBe(nil)
        expect(rootSet[escapeDecoy .. "/media/lua/shared"]).toBe(nil)
    end)

    it("#5 discovery.collect_specs finds specs in directories with spaces and parentheses", function()
        local spacedDir = FIX .. "/my mod (v1)"
        local specPath = spacedDir .. "/foo_spec.lua"
        mkdirp(spacedDir)
        writeFile(specPath, 'describe("spaced", function() it("ok", function() expect(1).toBe(1) end) end)\n')

        local specs = discovery.collect_specs({ spacedDir })
        expect(#specs).toBe(1)
        expect(specs[1]:gsub("\\", "/"):match("my mod %(v1%)/foo_spec%.lua$") ~= nil).toBeTruthy()
    end)

    it("#5 discovery.collect_specs and modloader.prepare_mod reject unsafe shell chars safely", function()
        local popenCalls = 0
        local origPopen = io.popen
        io.popen = function(...)
            popenCalls = popenCalls + 1
            return origPopen(...)
        end

        local ok, err = pcall(function()
            local badQuote = FIX .. '/bad"dir'
            local badPipe = FIX .. '/bad|dir'

            local s1 = discovery.collect_specs({ badQuote })
            expect(#s1).toBe(0)

            local m1 = modloader.prepare_mod(badQuote, "sp", {})
            expect(m1).toBe(nil)

            if WINDOWS then
                local s2 = discovery.collect_specs({ badPipe })
                expect(#s2).toBe(0)

                local m2 = modloader.prepare_mod(badPipe, "sp", {})
                expect(m2).toBe(nil)

                expect(popenCalls).toBe(0)
            end
        end)

        io.popen = origPopen
        if not ok then error(err, 0) end
    end)
end)
