local function umbrellaPath()
    for entry in package.path:gmatch("[^;]+") do
        local cand = entry:gsub("%?", "umbrella")
        if cand:match("stubs[/\\]umbrella%.lua$") then return cand end
    end
    return nil
end

local Umbrella = rawget(_G, "Umbrella")
if not Umbrella then
    local path = umbrellaPath()
    if path then pcall(dofile, path) end
    Umbrella = rawget(_G, "Umbrella")
end

local function fixtureDir()
    local dir = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
    local stripped = dir:gsub("[/\\]src[/\\]gate1$", "")
    if stripped == dir or stripped == "" then stripped = dir .. "/../.." end
    return stripped .. "/.tmp/umbrella_fixture"
end

describe("umbrella parser", function()
    local root

    before_all(function()
        root = Umbrella._fixture(fixtureDir())
    end)

    after_all(function()
        Umbrella.init(nil)
    end)

    local function initOn()
        local ok = Umbrella.init(root)
        expect(ok).toBeTruthy()
    end

    it("(a) init(fixture root): validates layout, mode on, root recorded", function()
        initOn()
        expect(Umbrella.on).toBeTruthy()
        expect(Umbrella.root).toBe(root)
    end)

    it("(b) parse_class_file Foo.lua: full descriptor — parents, overloads, rets, field", function()
        initOn()
        local d = Umbrella.parse_class_file(root .. "/library/java/Foo.lua")
        expect(d).toEqual({
            name = "Foo",
            is_global = true,
            parents = { "Base", "Baz" },
            methods = { transform = { arities = { 1, 2 }, rets = { "Bar" } } },
            fields = { bar = true },
        })
    end)

    it("(c) parse_class_file Baz.lua: local-only class → is_global false", function()
        initOn()
        local d = Umbrella.parse_class_file(root .. "/library/java/Baz.lua")
        expect(d.name).toBe("Baz")
        expect(d.is_global).toBeFalsy()
        expect(d.parents).toEqual({})
        expect(type(d.methods.bazOnly)).toBe("table")
    end)

    it("(d) parse_class_file Data.lua: no methods, @field lines captured", function()
        initOn()
        local d = Umbrella.parse_class_file(root .. "/library/java/Data.lua")
        expect(d.name).toBe("Data")
        expect(d.methods).toEqual({})
        expect(d.fields.alarm).toBeTruthy()
        expect(d.fields.name).toBeTruthy()
    end)

    it("(e) stem_index(): lazy-built stem→paths covering java + lua trees, cached", function()
        initOn()
        local idx = Umbrella.stem_index()
        expect(type(idx)).toBe("table")
        expect(type(idx.Foo)).toBe("table")
        expect(#idx.Foo).toBe(1)
        expect(idx.Foo[1]).toContain("Foo.lua")
        expect(type(idx.Base)).toBe("table")
        expect(type(idx.Baz)).toBe("table")
        expect(type(idx.Data)).toBe("table")
        expect(type(idx.env)).toBe("table")

        expect(Umbrella.stem_index()).toBe(idx)
    end)

    it("(f) func_index(): bare top-level lua-tree globals with arity + raw rets, cached", function()
        initOn()
        local fi = Umbrella.func_index()
        expect(type(fi)).toBe("table")
        expect(type(fi.round)).toBe("table")
        expect(fi.round.name).toBe("round")
        expect(fi.round.arity).toBe(2)
        expect(fi.round.path).toContain("env.lua")
        expect(fi.round.rets).toEqual({ "number" })
        expect(type(fi.strsplit)).toBe("table")
        expect(fi.strsplit.arity).toBe(2)
        expect(fi.strsplit.rets).toEqual({ "string[]" })

        expect(fi.transform).toBeNil()
        expect(fi.baseMethod).toBeNil()

        expect(Umbrella.func_index()).toBe(fi)
    end)

    it("(g) init(nil): mode off silently — no warning, indexes reset", function()
        initOn()
        local warns = {}
        local realprint = print
        local ok, err = pcall(function()
            print = function(s) warns[#warns + 1] = s end
            Umbrella.init(nil)
        end)
        print = realprint
        if not ok then error(err, 0) end
        expect(#warns).toBe(0)
        expect(Umbrella.on).toBeFalsy()
        expect(Umbrella.root).toBeNil()
        expect(Umbrella.stem_index()).toBeNil()
        expect(Umbrella.func_index()).toBeNil()
    end)

    it("(h) invalid path: ONE exact warning, false+reason, stays off across re-inits", function()
        initOn()
        local bad = "Z:/definitely/not/a/real/dir_umbrella_spec"
        local warns = {}
        local realprint = print
        local ok1, reason
        local ok, err = pcall(function()
            print = function(s) warns[#warns + 1] = s end
            ok1, reason = Umbrella.init(bad)
        end)
        print = realprint
        if not ok then error(err, 0) end
        expect(ok1).toBeFalsy()
        expect(type(reason)).toBe("string")
        expect(#warns).toBe(1)
        expect(warns[1]).toBe("PZ_UMBRELLA path invalid — mode off")
        expect(Umbrella.on).toBeFalsy()

        local warns2 = {}
        local ok2
        local ok3, err3 = pcall(function()
            print = function(s) warns2[#warns2 + 1] = s end
            ok2 = Umbrella.init(bad)
        end)
        print = realprint
        if not ok3 then error(err3, 0) end
        expect(ok2).toBeFalsy()
        expect(#warns2).toBe(1)
        expect(Umbrella.on).toBeFalsy()
    end)
end)
