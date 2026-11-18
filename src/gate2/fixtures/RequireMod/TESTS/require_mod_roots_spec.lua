describe("gate2 mod.roots require and testkit facade", function()
    it("shares path-keyed cache between require and mod.loadFiles", function()
        expect(__REQ_UTIL_COUNT).toBe(1)
        expect(type(__REQ_BOOTSTRAP_UTIL)).toBe("table")
        expect(__REQ_BOOTSTRAP_UTIL.tag).toBe("shared-util")
    end)

    it("resolves case-insensitively on Windows without re-executing", function()
        local isWin = (type(package) == "table" and type(package.config) == "string"
            and package.config:sub(1, 1) == "\\")
            or (type(__PZ_MOD_INFO) == "table" and type(__PZ_MOD_INFO.base) == "string"
            and __PZ_MOD_INFO.base:match("^[A-Za-z]:/") ~= nil)
        if not isWin then
            return
        end
        local lower = require("02_sharedutil")
        expect(lower).toBe(__REQ_BOOTSTRAP_UTIL)
        expect(lower.tag).toBe("shared-util")
        expect(__REQ_UTIL_COUNT).toBe(1)
    end)

    it("caches nil returns without re-executing", function()
        local a = require("NilModule")
        local b = require("NilModule")
        expect(a).toBe(nil)
        expect(b).toBe(nil)
        expect(__REQ_NIL_COUNT).toBe(1)
    end)

    it("blocks path-traversal require names", function()
        local escaped = require("../MyMod/common/media/lua/shared/order")
        expect(escaped).toBe(nil)
    end)

    it("falls back to GlobalObject.require for engine modules", function()
        local ok, res = pcall(require, "ISBaseObject")
        expect(ok).toBe(true)
        expect(res).toBe(nil)
    end)

    it("exposes testkit.keep as no-op and fails fast on Gate 1 isolation helpers", function()
        expect(type(testkit)).toBe("table")
        testkit.keep("02_SharedUtil")

        local okProvide, errProvide = pcall(testkit.provide, "x", {})
        expect(okProvide).toBe(false)
        expect(tostring(errProvide):find("Gate 1 unit-isolation", 1, true) ~= nil).toBe(true)

        local okReset, errReset = pcall(testkit.resetLoaded)
        expect(okReset).toBe(false)
        expect(tostring(errReset):find("Gate 1 unit-isolation", 1, true) ~= nil).toBe(true)
    end)

    it("resolves transitive require= deps and guards cycles without auto-executing", function()
        local a = require("DepA_Lib")
        expect(type(a)).toBe("table")
        expect(a.from).toBe("DepA")
        expect(type(a.dep)).toBe("table")
        expect(a.dep.from).toBe("DepB")

        local b = require("DepB_Lib")
        expect(type(b)).toBe("table")
        expect(b.from).toBe("DepB")

        local hasDepA, hasDepB = false, false
        for _, root in ipairs(__PZ_MOD_INFO.roots) do
            if root:find("DepA/42/media/lua/shared", 1, true) then hasDepA = true end
            if root:find("DepB/common/media/lua/shared", 1, true) then hasDepB = true end
        end
        expect(hasDepA).toBe(true)
        expect(hasDepB).toBe(true)
    end)

    it("cleans up inFlight on require error so BrokenModule retries", function()
        local ok1 = pcall(require, "BrokenModule")
        local ok2 = pcall(require, "BrokenModule")
        expect(ok1).toBe(false)
        expect(ok2).toBe(false)
        expect(__REQ_BROKEN_COUNT).toBe(2)
    end)

    it("guards circular require calls without stack overflow", function()
        local res = require("CycleA")
        expect(res).toEqual({ a = true })
    end)
end)
