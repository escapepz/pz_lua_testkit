local SOURCE = debug.getinfo(1, "S").source:sub(2)
local HERE = SOURCE:match("^(.*)[/\\][^/\\]*$") or "."
local discovery = dofile(HERE .. "/../discovery.lua")

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

local FIX = absPath(repoRoot() .. "/.tmp/discovery_fixture")

local function buildFixture(fx)
    local function mkdirp(d)
        if WINDOWS then
            os.execute('mkdir "' .. (d:gsub("/", "\\")) .. '" 2>nul')
        else
            os.execute('mkdir -p "' .. d .. '" 2>/dev/null')
        end
    end
    mkdirp(fx)
    mkdirp(fx .. "/nested")
    local files = {
        [fx .. "/a_spec.lua"] = "-- contentless stub (name-only scanning)\n",
        [fx .. "/notes.txt"] = "not a spec\n",
        [fx .. "/nested/b_spec.lua"] = "-- contentless stub\n",
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
        fx .. "/a_spec.lua",
        fx .. "/notes.txt",
        fx .. "/nested/b_spec.lua",
    }) do
        local f = io.open(p, "r")
        if not f then return false end
        f:close()
    end
    return true
end

local function canon(p) return (p:gsub("\\", "/")) end

local function canonSorted(t)
    local out = {}
    for i, p in ipairs(t) do out[i] = canon(p) end
    table.sort(out)
    return out
end

local function keyset(tbl)
    local keys = {}
    for k in pairs(tbl) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

describe("discovery module", function()
    before_all(function()
        buildFixture(FIX)
        expect(fixtureReady(FIX)).toBeTruthy()
    end)

    it("(a) exports exactly the four scanning functions", function()
        expect(keyset(discovery)).toEqual({
            "collect_specs", "normalize_spec_key", "resolve_spec_path", "scan_dir",
        })
        expect(type(discovery.scan_dir)).toBe("function")
        expect(type(discovery.normalize_spec_key)).toBe("function")
        expect(type(discovery.resolve_spec_path)).toBe("function")
        expect(type(discovery.collect_specs)).toBe("function")
    end)

    it("(b) scan_dir: recursive *_spec.lua only (notes.txt excluded, nested/ descended)", function()
        local out = discovery.scan_dir(FIX)
        expect(#out).toBe(2)
        expect(canonSorted(out)).toEqual({
            FIX .. "/a_spec.lua", FIX .. "/nested/b_spec.lua",
        })
    end)

    it("(c) scan_dir: appends into a caller-supplied out and returns that same table", function()
        local out = { "sentinel" }
        local ret = discovery.scan_dir(FIX, out)
        expect(ret).toBe(out)
        expect(#out).toBe(3)
        expect(out[1]).toBe("sentinel")
    end)

    it("(d) normalize_spec_key shapes: \\ -> /, trailing / stripped, leading ./ stripped", function()
        expect(discovery.normalize_spec_key("a\\b\\")).toBe("a/b")
        expect(discovery.normalize_spec_key("./c")).toBe("c")
        expect(discovery.normalize_spec_key("x/y/")).toBe("x/y")
    end)

    it("(e) resolve_spec_path: file arg passes through verbatim (output is the untouched input string)", function()

        local p = FIX .. "/./a_spec.lua"
        local out, seen = {}, {}
        discovery.resolve_spec_path(p, out, seen)
        expect(#out).toBe(1)
        expect(out[1]).toBe(p)
    end)

    it("(f) resolve_spec_path: dir arg contributes its recursive scan, deduped into out", function()
        local out, seen = {}, {}
        discovery.resolve_spec_path(FIX, out, seen)
        expect(#out).toBe(2)
        expect(canonSorted(out)).toEqual({
            FIX .. "/a_spec.lua", FIX .. "/nested/b_spec.lua",
        })

        discovery.resolve_spec_path(FIX, out, seen)
        expect(#out).toBe(2)
    end)

    it("(g) collect_specs: file args pass through verbatim, result ordered by the arg list", function()
        local fa = FIX .. "/nested/b_spec.lua"
        local fb = FIX .. "/a_spec.lua"
        local specs = discovery.collect_specs({ fa, fb })
        expect(specs).toEqual({ fa, fb })
    end)

    it("(h) collect_specs: same file reached twice (file arg + via its dir) appears exactly once (first form wins)", function()

        local fa = FIX .. "/a_spec.lua"
        local specs = discovery.collect_specs({ fa, FIX })
        expect(#specs).toBe(2)
        expect(canonSorted(specs)).toEqual({
            FIX .. "/a_spec.lua", FIX .. "/nested/b_spec.lua",
        })

        expect(specs[1]).toBe(fa)
    end)

    it("(i) non-existent path contributes nothing and raises no error", function()
        local ok, specs = pcall(discovery.collect_specs, { FIX .. "/does_not_exist" })
        expect(ok).toBeTruthy()
        expect(type(specs)).toBe("table")
        expect(#specs).toBe(0)

        local out, seen = {}, {}
        local ok2 = pcall(discovery.resolve_spec_path, FIX .. "/does_not_exist", out, seen)
        expect(ok2).toBeTruthy()
        expect(#out).toBe(0)
    end)
end)
