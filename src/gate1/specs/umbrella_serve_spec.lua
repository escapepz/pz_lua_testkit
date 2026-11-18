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

describe("umbrella serve layer", function()
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

    it("(a) mode off: resolve_global consults nothing — nil for class, func, unknown", function()
        Umbrella.init(nil)
        expect(Umbrella.resolve_global("Foo")).toBeNil()
        expect(Umbrella.resolve_global("round")).toBeNil()
        expect(Umbrella.resolve_global("NotAnywhere")).toBeNil()
        local served_n = 0
        for _ in pairs(Umbrella._served) do served_n = served_n + 1 end
        expect(served_n).toBe(0)
    end)

    it("(b) resolve_global('Foo'): truthy, memoized identity, registered in _served", function()
        initOn()
        local a = Umbrella.resolve_global("Foo")
        expect(a).toBeTruthy()
        local b = Umbrella.resolve_global("Foo")
        expect(b).toBe(a)
        expect(Umbrella._served.Foo).toBe(a)
    end)

    it("(c) phantom guard: local-only Baz + global-less Data resolve nil in BOTH strict states", function()
        initOn()
        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = false
            expect(Umbrella.resolve_global("Baz")).toBeNil()
            expect(Umbrella.resolve_global("Data")).toBeNil()
            _G.pz_strict = true
            expect(Umbrella.resolve_global("Baz")).toBeNil()
            expect(Umbrella.resolve_global("Data")).toBeNil()
            expect(Umbrella.resolve_global("NotAnywhere")).toBeNil()
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end
    end)

    it("(d) served Foo: transform(1) records one call, returns nil (L1), mock memoized", function()
        initOn()
        local stub = Umbrella.resolve_global("Foo")
        expect(stub.transform).toBeTruthy()
        expect(stub.transform).toBe(stub.transform)
        expect(stub.transform(1)).toBeNil()
        expect(#stub.transform.calls).toBe(1)
        expect(stub.transform.calls[1].n).toBe(1)
        expect(stub.transform.calls[1][1]).toBe(1)
    end)

    it("(e) DAG: baseMethod resolves via lazily-parsed Base parent; find_method provenance + visited guard", function()
        initOn()
        local stub = Umbrella.resolve_global("Foo")
        expect(stub.baseMethod).toBeTruthy()
        expect(stub:baseMethod(5)).toBeNil()
        expect(#stub.baseMethod.calls).toBe(1)

        local owner, m = Umbrella.find_method("Foo", "baseMethod")
        expect(owner.name).toBe("Base")
        expect(m).toBeTruthy()

        local owner2, m2 = Umbrella.find_method("Foo", "bazOnly")
        expect(owner2.name).toBe("Baz")
        expect(m2.arities).toEqual({ 0 })

        expect(Umbrella.find_method("Foo", "nope")).toBeNil()

        expect(Umbrella.find_method("Foo", "transform", { Foo = true })).toBeNil()
    end)

    it("(f) declared field bar → nil, never a strict error (fields are declared members)", function()
        initOn()
        local stub = Umbrella.resolve_global("Foo")
        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = true
            expect(stub.bar).toBeNil()
            _G.pz_strict = false
            expect(stub.bar).toBeNil()
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end
    end)

    it("(g) unknown method 'nope': nil non-strict; strict error 'PZ_STRICT: unknown method 'Foo:nope''", function()
        initOn()
        local stub = Umbrella.resolve_global("Foo")
        local saved = _G.pz_strict

        local ok, err = pcall(function()
            _G.pz_strict = false
            expect(stub.nope).toBeNil()
            expect(stub.nope).toBeNil()
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end

        local ok2, err2 = pcall(function()
            _G.pz_strict = true
            local eok, emsg = pcall(function() return stub.nope end)
            expect(eok).toBe(false)
            expect(emsg:find("PZ_STRICT: unknown method 'Foo:nope'", 1, true)).toBeTruthy()
            expect(stub.transform).toBeTruthy()
            expect(stub.bar).toBeNil()
        end)
        _G.pz_strict = saved
        if not ok2 then error(err2, 0) end
    end)

    it("(h) function stub: resolve_global('round') callable, records args, nil return, memoized", function()
        initOn()
        local f = Umbrella.resolve_global("round")
        expect(f).toBeTruthy()
        expect(f(1, 2)).toBeNil()
        expect(#f.calls).toBe(1)
        expect(f.calls[1].n).toBe(2)
        expect(f.calls[1][2]).toBe(2)
        expect(Umbrella.resolve_global("round")).toBe(f)
        expect(Umbrella.resolve_global("strsplit")).toBeTruthy()
    end)

    it("(i) return_policy seam: default is l1_policy; swap → 'X' on the same memoized mock; restore → nil", function()
        initOn()
        expect(Umbrella.return_policy).toBe(Umbrella.l1_policy)
        local stub = Umbrella.resolve_global("Foo")
        local saved = Umbrella.return_policy
        local ok, err = pcall(function()
            Umbrella.return_policy = function() return "X" end
            expect(stub.transform(3)).toBe("X")
        end)
        Umbrella.return_policy = saved
        if not ok then error(err, 0) end
        expect(stub.transform(4)).toBeNil()
    end)

    it("(j) inherited field: parent-declared baseHP → nil, BOTH strict states; nowhere-declared field still strict-errors", function()
        initOn()
        local stub = Umbrella.resolve_global("Foo")

        expect(Umbrella.find_field("Foo", "baseHP")).toBeTruthy()
        expect(Umbrella.find_field("Foo", "bar")).toBeTruthy()
        expect(Umbrella.find_field("Foo", "ghostHP")).toBeNil()
        expect(Umbrella.find_field("Foo", "bar", { Foo = true })).toBeNil()
        local saved = _G.pz_strict
        local ok, err = pcall(function()
            _G.pz_strict = false
            expect(stub.baseHP).toBeNil()
            _G.pz_strict = true
            expect(stub.baseHP).toBeNil()

            local eok, emsg = pcall(function() return stub.ghostHP end)
            expect(eok).toBe(false)
            expect(emsg:find("PZ_STRICT: unknown method 'Foo:ghostHP'", 1, true)).toBeTruthy()
        end)
        _G.pz_strict = saved
        if not ok then error(err, 0) end
    end)
end)
