local function runnerPath()
    for entry in package.path:gmatch("[^;]+") do
        local cand = entry:gsub("%?", "gate1/runner")

        if cand:match("[/\\]gate1[/\\]runner%.lua$") then return cand end
    end
    return nil
end

local function pzrequirePath()
    for entry in package.path:gmatch("[^;]+") do
        local cand = entry:gsub("%?", "pzrequire")
        if cand:match("stubs[/\\]pzrequire%.lua$") then return cand end
    end
    return nil
end

local runner = nil
local rp = runnerPath()
if rp then runner = dofile(rp) end

local function repoRoot()
    local dir = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
    local stripped = dir:gsub("[/\\]src[/\\]gate1$", "")
    if stripped == dir or stripped == "" then stripped = dir .. "/../.." end
    return stripped
end

local WINDOWS = (package.config:sub(1, 1) == "\\")

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

local FIX = absPath(repoRoot() .. "/.tmp/mod_deps_fixture")

local function buildFixture(fx)
    local function mkdirp(d)
        if WINDOWS then
            os.execute('mkdir "' .. (d:gsub("/", "\\")) .. '" 2>nul')
        else
            os.execute('mkdir -p "' .. d .. '" 2>/dev/null')
        end
    end
    local PM, D = fx .. "/ParentMod", fx .. "/depmod"

    local ESC = fx .. "/../mod_deps_escape_decoy"
    local dirs = {
        PM .. "/media/lua/shared",
        D .. "/media/lua/shared",
        ESC .. "/media/lua/shared",
        fx .. "/HostileMod",
    }
    for _, d in ipairs(dirs) do mkdirp(d) end
    local files = {
        [PM .. "/mod.info"] = "title=Parent Mod\nrequire=depmod\n",
        [PM .. "/media/lua/shared/consumer.lua"] =
            '__FIX_DEP_VAL = require("dep_module")\n',

        [PM .. "/media/lua/shared/dep_module.lua"] = 'return { v = "own" }\n',
        [D .. "/mod.info"] = "title=Dep Mod\n",
        [D .. "/media/lua/shared/dep_module.lua"] =
            '__FIX_DEP_LOADED = true\nreturn { v = "real" }\n',

        [fx .. "/HostileMod/mod.info"] =
            "title=Hostile Mod\n"
            .. "require=depmod,../mod_deps_escape_decoy,..,C:/abs,sub/dir,bad\"tok\n",
        [ESC .. "/mod.info"] = "title=Escape Decoy\n",
        [ESC .. "/media/lua/shared/decoy.lua"] = 'return { v = "decoy" }\n',
    }
    for path, content in pairs(files) do
        local f = io.open(path, "wb")
        if f then
            f:write(content)
            f:close()
        end
    end
end

local function fixtureReady(fx)
    for _, p in ipairs({
        fx .. "/ParentMod/mod.info",
        fx .. "/ParentMod/media/lua/shared/consumer.lua",
        fx .. "/ParentMod/media/lua/shared/dep_module.lua",
        fx .. "/depmod/mod.info",
        fx .. "/depmod/media/lua/shared/dep_module.lua",
        fx .. "/HostileMod/mod.info",
        fx .. "/../mod_deps_escape_decoy/mod.info",
        fx .. "/../mod_deps_escape_decoy/media/lua/shared/decoy.lua",
    }) do
        local f = io.open(p, "r")
        if not f then return false end
        f:close()
    end
    return true
end

describe("mod deps: PZ_MOD_PATH dep roots + testkit.provide", function()
    local PzRequire
    local FIX_PM, FIX_DEP, PM, DEP, PM_ROOT, DEP_ROOT

    before_all(function()
        local pp = pzrequirePath()
        if pp then PzRequire = dofile(pp) end
        buildFixture(FIX)
        expect(fixtureReady(FIX)).toBeTruthy()
        PM = FIX .. "/ParentMod"
        DEP = FIX .. "/depmod"
        PM_ROOT = PM .. "/media/lua/shared"
        DEP_ROOT = DEP .. "/media/lua/shared"

        __FIX_DEP_LOADED = false
    end)

    after_all(function()

        if PzRequire and PzRequire._std then
            rawset(_G, "require", PzRequire._std)
        end
        rawset(_G, "testkit", nil)
        rawset(_G, "PzRequire", nil)
        __FIX_DEP_VAL = nil
        __FIX_DEP_LOADED = nil
    end)

    it("(a) prepare_mod without mod_path: roots contain only own dirs; deps still parsed", function()
        local r

        local s = spyOn(_G, "print")
        local ok, err = pcall(function()
            r = runner.prepare_mod(PM, "sp")
        end)
        s.restore()
        if not ok then error(err, 0) end
        expect(type(r)).toBe("table")
        expect(r.roots).toEqual({ PM_ROOT })
        expect(r.deps).toEqual({ "depmod" })

        expect(r.load_files).toEqual({
            PM .. "/media/lua/shared/consumer.lua",
            PM .. "/media/lua/shared/dep_module.lua",
        })
        expect(r.spec_dirs).toEqual({})
    end)

    it("(b) with mod_path: dep roots appended AFTER own; deps order preserved; dep contributes NO load_files", function()
        local r = runner.prepare_mod(PM, "sp", { FIX })
        expect(type(r)).toBe("table")
        expect(r.roots).toEqual({ PM_ROOT, DEP_ROOT })
        expect(r.deps).toEqual({ "depmod" })

        expect(r.load_files).toEqual({
            PM .. "/media/lua/shared/consumer.lua",
            PM .. "/media/lua/shared/dep_module.lua",
        })
    end)

    it("(c) mod_path is scanned IN ORDER: missing first search dir skipped silently, dep found via the second", function()
        local r
        local s = spyOn(_G, "print")
        local ok, err = pcall(function()
            r = runner.prepare_mod(PM, "sp", { FIX .. "/no_such_search_dir", FIX })
        end)
        s.restore()
        if not ok then error(err, 0) end
        expect(r.roots).toEqual({ PM_ROOT, DEP_ROOT })

        expect(#s.calls).toBe(0)
    end)

    it("(d) missing dep: ONE exact warn + continue — result returned with own roots intact", function()
        local r
        local s = spyOn(_G, "print")
        local ok, err = pcall(function()

            r = runner.prepare_mod(PM, "sp", {})
        end)
        s.restore()
        if not ok then error(err, 0) end
        expect(#s.calls).toBe(1)
        expect(s.calls[1][1]).toBe("PZ_MOD: dependency 'depmod' not found in PZ_MOD_PATH")
        expect(type(r)).toBe("table")
        expect(r.roots).toEqual({ PM_ROOT })
        expect(r.deps).toEqual({ "depmod" })
    end)

    it("(e) provide: testkit facade entry; synthetic persistent key; provide wins over disk; survives resetLoaded", function()
        PzRequire.install()
        local tk = rawget(_G, "testkit")
        expect(type(tk)).toBe("table")
        expect(type(tk.provide)).toBe("function")
        expect(tk.provide).toBe(PzRequire.provide)

        PzRequire.init({ PM_ROOT, DEP_ROOT })
        tk.provide("dep_module", { v = "stub" })

        expect(PzRequire._done["provided:dep_module"]).toBe(true)
        expect(PzRequire._persistent["provided:dep_module"]).toBe(true)
        local m = require("dep_module")
        expect(m).toEqual({ v = "stub" })
        expect(__FIX_DEP_LOADED).toBe(false)

        tk.resetLoaded()
        expect(require("dep_module")).toEqual({ v = "stub" })

        tk.provide("./dep_module", { v = "stub2" })
        expect(PzRequire._value["provided:dep_module"]).toEqual({ v = "stub2" })
        expect(require("dep_module")).toEqual({ v = "stub2" })
    end)

    it("(f) real dep: fresh init wipes the provided entry; no provide -> real module executes exactly once", function()
        PzRequire.init({ DEP_ROOT })

        expect(PzRequire._done["provided:dep_module"]).toBeNil()
        local m = require("dep_module")
        expect(m).toEqual({ v = "real" })
        expect(__FIX_DEP_LOADED).toBe(true)
        expect(require("dep_module")).toBe(m)
        expect(__FIX_DEP_LOADED).toBe(true)
    end)

    it("(g) consumer: a mod file's require sees the provided stub (integration through the global require)", function()
        PzRequire.init({ PM_ROOT, DEP_ROOT })
        __FIX_DEP_LOADED = false
        PzRequire.provide("dep_module", { v = "stub" })
        require("consumer")
        expect(__FIX_DEP_VAL).toEqual({ v = "stub" })
        expect(__FIX_DEP_LOADED).toBe(false)
    end)

    it("(h) own-root shadowing: both roots present, no provide -> the own copy wins", function()
        PzRequire.init({ PM_ROOT, DEP_ROOT })
        __FIX_DEP_LOADED = false
        local m = require("dep_module")
        expect(m).toEqual({ v = "own" })
        expect(__FIX_DEP_LOADED).toBe(false)
    end)

    it("(i) provide before roots: cache seeding is independent of root registration", function()
        PzRequire.init({})
        __FIX_DEP_LOADED = false
        PzRequire.provide("dep_module", { v = "stub" })
        expect(require("dep_module")).toEqual({ v = "stub" })
        expect(__FIX_DEP_LOADED).toBe(false)
    end)

    it("(j) hostile require= tokens: bare-mod-ID guard skips them, one warn each; legit token still resolves", function()

        local HM = FIX .. "/HostileMod"
        local r
        local s = spyOn(_G, "print")
        local ok, err = pcall(function()
            r = runner.prepare_mod(HM, "sp", { FIX })
        end)
        s.restore()
        if not ok then error(err, 0) end
        expect(type(r)).toBe("table")

        expect(r.deps).toEqual({
            "depmod", "../mod_deps_escape_decoy", "..", "C:/abs", "sub/dir",
            'bad"tok',
        })

        expect(r.roots).toEqual({ DEP_ROOT })

        expect(#s.calls).toBe(5)
        expect(s.calls[1][1])
            .toBe("PZ_MOD: dependency '../mod_deps_escape_decoy' is not a bare mod ID, skipped")
        expect(s.calls[2][1])
            .toBe("PZ_MOD: dependency '..' is not a bare mod ID, skipped")
        expect(s.calls[3][1])
            .toBe("PZ_MOD: dependency 'C:/abs' is not a bare mod ID, skipped")
        expect(s.calls[4][1])
            .toBe("PZ_MOD: dependency 'sub/dir' is not a bare mod ID, skipped")
        expect(s.calls[5][1])
            .toBe("PZ_MOD: dependency 'bad\"tok' is not a bare mod ID, skipped")
    end)
end)
