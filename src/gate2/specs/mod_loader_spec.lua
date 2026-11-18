local INFO = rawget(_G, "__PZ_MOD_INFO")
if type(INFO) ~= "table" or not INFO.base:match("/MyMod$") then
    return
end

local M = INFO.base
local FIX = M:match("^(.*)/MyMod$")
local DEP_ROOT = FIX and (FIX .. "/DepLibs/DepMod/media/lua/shared") or nil
local WITH_DEP = (DEP_ROOT ~= nil) and (INFO.roots[#INFO.roots] == DEP_ROOT)

local OWN_ROOTS = {
    M .. "/common/media/lua/shared",
    M .. "/42/media/lua/shared",
    M .. "/42/media/lua/client",
    M .. "/42/media/lua/server",
}

local SP_LOAD = {
    M .. "/common/media/lua/shared/order.lua",
    M .. "/42/media/lua/shared/a.lua",
    M .. "/42/media/lua/shared/B.lua",
    M .. "/42/media/lua/shared/order2.lua",
    M .. "/42/media/lua/client/c.lua",
    M .. "/42/media/lua/server/s.lua",
}

local SERVER_LOAD = {
    M .. "/common/media/lua/shared/order.lua",
    M .. "/42/media/lua/shared/a.lua",
    M .. "/42/media/lua/shared/B.lua",
    M .. "/42/media/lua/shared/order2.lua",
    M .. "/42/media/lua/server/s.lua",
}

describe("gate2 mod loader parity (Phase 6)", function()
    it("dual layout roots: sub-major, common-before-42 per sub", function()
        local want = {
            OWN_ROOTS[1], OWN_ROOTS[2], OWN_ROOTS[3], OWN_ROOTS[4],
        }
        if WITH_DEP then
            want[5] = DEP_ROOT
        end
        expect(INFO.roots).toEqual(want)
    end)

    if INFO.ctx == "server" then
        it("load order ctx server: shared+server only; client in roots, not executed", function()
            expect(INFO.load_files).toEqual(SERVER_LOAD)
        end)
    else
        it("load order ctx sp: shared(common->42) -> client -> server, case-insensitive batches", function()
            expect(INFO.load_files).toEqual(SP_LOAD)
        end)
    end

    it("auto-exec actually ran on the real VM in the pinned order", function()
        local want
        if INFO.ctx == "server" then
            want = { "common-shared", "42-shared", "42-server" }
        else
            want = { "common-shared", "42-shared", "42-client", "42-server" }
        end
        expect(__FIX_ORDER).toEqual(want)
    end)

    it("require= deps parsed from the preferred (versionDir) mod.info", function()
        expect(INFO.deps).toEqual({ "DepMod" })
    end)

    if WITH_DEP then
        it("dep mod contributes ROOTS ONLY: dep lua never auto-executes", function()
            expect(rawget(_G, "__FIX_DEP_EXECUTED")).toBeNil()
        end)
    end
end)
