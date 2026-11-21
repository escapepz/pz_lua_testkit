local function runnerPath()
    for entry in package.path:gmatch("[^;]+") do
        local cand = entry:gsub("%?", "gate1/runner")

        if cand:match("[/\\]gate1[/\\]runner%.lua$") then return cand end
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

local FIX = absPath(repoRoot() .. "/.tmp/mod_loader_fixture")

local function buildFixture(fx)
    local function mkdirp(d)
        if WINDOWS then
            os.execute('mkdir "' .. (d:gsub("/", "\\")) .. '" 2>nul')
        else
            os.execute('mkdir -p "' .. d .. '" 2>/dev/null')
        end
    end
    local M = fx .. "/MyMod"
    local dirs = {
        M .. "/common/media/lua/shared",
        M .. "/42/media/lua/shared",
        M .. "/42/media/lua/client",
        M .. "/42/media/lua/server",
        M .. "/TESTS",
        fx .. "/PlainMod/media/lua/shared",
        fx .. "/NoInfo",
    }
    for _, d in ipairs(dirs) do mkdirp(d) end
    local orderChunk =
        '__FIX_ORDER = rawget(_G, "__FIX_ORDER") or {} ; table.insert(__FIX_ORDER, "%s")\n'
    local files = {
        [M .. "/common/mod.info"] = "title=My Mod Common\nrequire=depmod\n",
        [M .. "/42/mod.info"] = "title=My Mod 42\nrequire=depmod\n",
        [M .. "/common/media/lua/shared/order.lua"] = orderChunk:format("common-shared"),
        [M .. "/42/media/lua/shared/order2.lua"] =
            orderChunk:format("42-shared")
            .. '__FIX_ORDER2_N = (rawget(_G, "__FIX_ORDER2_N") or 0) + 1\n',
        [M .. "/42/media/lua/shared/a.lua"] = "",
        [M .. "/42/media/lua/shared/B.lua"] = "",
        [M .. "/42/media/lua/client/c.lua"] =
            orderChunk:format("42-client") .. "__FIX_CLI_FILE = true\n",
        [M .. "/42/media/lua/server/s.lua"] = orderChunk:format("42-server"),
        [M .. "/TESTS/order_spec.lua"] = [[
describe("mod loader e2e probe", function()
    it("auto-exec order is the engine sp sequence", function()
        expect(__FIX_ORDER).toEqual({ "common-shared", "42-shared", "42-client", "42-server" })
    end)
    it("require after auto-exec is a cache hit (no re-execution)", function()
        local m = require("order2")
        expect(m).toBeNil()
        expect(__FIX_ORDER2_N).toBe(1)
        local n = require("shared/order2")
        expect(n).toBeNil()
        expect(__FIX_ORDER2_N).toBe(1)
    end)
end)
]],
        [fx .. "/PlainMod/mod.info"] = "title=Plain Mod\n",
        [fx .. "/PlainMod/media/lua/shared/plain.lua"] = orderChunk:format("plain-shared"),
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
        fx .. "/MyMod/common/mod.info",
        fx .. "/MyMod/42/mod.info",
        fx .. "/PlainMod/mod.info",
        fx .. "/MyMod/TESTS/order_spec.lua",
    }) do
        local f = io.open(p, "r")
        if not f then return false end
        f:close()
    end
    return true
end

describe("mod loader (prepare_mod)", function()
    local M, P, N

    before_all(function()
        buildFixture(FIX)
        expect(fixtureReady(FIX)).toBeTruthy()
        M = FIX .. "/MyMod"
        P = FIX .. "/PlainMod"
        N = FIX .. "/NoInfo"
    end)

    it("(a) dual layout: roots are sub-major, common-before-42 per sub; shared count 2; client/server from 42 only", function()
        local r = runner.prepare_mod(M, "sp")
        expect(type(r)).toBe("table")

        expect(r.roots).toEqual({
            M .. "/common/media/lua/shared",
            M .. "/42/media/lua/shared",
            M .. "/42/media/lua/client",
            M .. "/42/media/lua/server",
        })

        expect(r.spec_dirs).toEqual({ M .. "/TESTS" })
    end)

    it("(b) load order ctx sp: shared(common->42) -> client -> server, case-insensitive batches", function()
        local r = runner.prepare_mod(M, "sp")

        expect(r.load_files).toEqual({
            M .. "/common/media/lua/shared/order.lua",
            M .. "/42/media/lua/shared/a.lua",
            M .. "/42/media/lua/shared/B.lua",
            M .. "/42/media/lua/shared/order2.lua",
            M .. "/42/media/lua/client/c.lua",
            M .. "/42/media/lua/server/s.lua",
        })
    end)

    it("(c) load order ctx server: shared+server only, client file still among ROOTS", function()
        local r = runner.prepare_mod(M, "server")

        expect(r.load_files).toEqual({
            M .. "/common/media/lua/shared/order.lua",
            M .. "/42/media/lua/shared/a.lua",
            M .. "/42/media/lua/shared/B.lua",
            M .. "/42/media/lua/shared/order2.lua",
            M .. "/42/media/lua/server/s.lua",
        })

        expect(r.roots).toEqual({
            M .. "/common/media/lua/shared",
            M .. "/42/media/lua/shared",
            M .. "/42/media/lua/client",
            M .. "/42/media/lua/server",
        })
    end)

    it("(d) PlainMod: B41 single root from <modDir>/mod.info", function()
        local r = runner.prepare_mod(P, "sp")
        expect(type(r)).toBe("table")
        expect(r.roots).toEqual({ P .. "/media/lua/shared" })
        expect(r.load_files).toEqual({ P .. "/media/lua/shared/plain.lua" })

        expect(r.deps).toEqual({})
        expect(r.spec_dirs).toEqual({})
    end)

    it("(e) NoInfo: nil result + ONE exact warn", function()
        local warns = {}
        local s = spyOn(_G, "print")
        local ok, err = pcall(function()
            local r = runner.prepare_mod(N, "sp")
            expect(r).toBeNil()
        end)
        s.restore()
        if not ok then error(err, 0) end
        expect(#s.calls).toBe(1)
        expect(s.calls[1][1]).toBe("PZ_MOD: mod.info not found in '" .. N .. "'")
    end)

    it("(f) mod.info read prefers <versionDir>/mod.info; require= parsed into deps", function()
        local r = runner.prepare_mod(M, "sp")

        expect(r.deps).toEqual({ "depmod" })
    end)

    it("(g) mod_path search dir without the dep: result identical to the no-mod_path call (dep warn + continue)", function()
        local r1 = runner.prepare_mod(M, "sp")
        local r2 = runner.prepare_mod(M, "sp", { FIX .. "/somewhere_else" })
        expect(r2).toEqual(r1)
    end)

    it("(h) a directory named *.lua inside media/lua is not a load file", function()
        local fx = FIX .. "/DirLuaMod"
        local mkdirp = function(d)
            if WINDOWS then
                os.execute('mkdir "' .. (d:gsub("/", "\\")) .. '" 2>nul')
            else
                os.execute('mkdir -p "' .. d .. '" 2>/dev/null')
            end
        end
        mkdirp(fx)
        mkdirp(fx .. "/media/lua/shared")
        mkdirp(fx .. "/media/lua/shared/zz_dir.lua")
        local f = io.open(fx .. "/mod.info", "wb")
        if f then f:write("name=DirLuaMod\nid=dirluamod\n"); f:close() end
        local ok_file = io.open(fx .. "/media/lua/shared/zz_ok.lua", "wb")
        if ok_file then ok_file:write("__DIR_LUA_OK = true\n"); ok_file:close() end

        local r = runner.prepare_mod(absPath(fx), "sp")
        expect(r ~= nil).toBeTruthy()
        local bad, good = false, false
        for _, f2 in ipairs(r.load_files) do
            if f2:match("zz_dir%.lua$") then bad = true end
            if f2:match("zz_ok%.lua$") then good = true end
        end
        expect(bad).toBeFalsy()
        expect(good).toBeTruthy()
        expect(#r.load_files).toBe(1)
    end)
end)

describe("mod loader e2e subprocess probe", function()
    it("run.lua --mod runs the mod's TESTS with engine load order and contract require", function()

        if not WINDOWS then return end
        local exe = repoRoot() .. "/tools/lua5.1.exe"
        local f = io.open(exe, "r")
        if not f then return end
        f:close()

        local modAbs = absPath(FIX .. "/MyMod")
        local cmd = 'cmd /c "set PZ_STRICT=&& set PZ_SPECS=&& set PZ_UMBRELLA=&&'
            .. ' set PZ_STUB_PACKS=&& set PZ_STUBS=&& set PZ_MOD_PATH=&&'
            .. ' set PZ_RESET_PER_TEST=0&&'
            .. ' tools\\lua5.1.exe src\\gate1\\run.lua --mod ' .. modAbs .. '"'
        local p = io.popen(cmd)
        expect(p ~= nil).toBeTruthy()
        if not p then return end
        local out = p:read("*a")
        p:close()

        expect(out:find("ALL PASS", 1, true)).toBeTruthy()
        expect(out:find("total=", 1, true)).toBeTruthy()
    end)
end)
