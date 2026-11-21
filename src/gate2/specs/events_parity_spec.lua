-- gate2 events parity — two-directional, both namespaces.
-- Binding spec: docs/superpowers/specs/2026-11-21-v0.2.0-rc-event-namespace-and-
-- audit-fixes-design.md — "Allowlist completeness criterion" + "Decided parts 9".
--
-- FORWARD: every name shipped in `__pz_events_list.events` and in
-- `__pz_events_list.hooks` must exist in the real registry the runner's boot path
-- creates (LuaEventManager.register + LuaHookManager.register), minus the
-- documented exceptions below.
--
-- REVERSE: every name found via pairs(Events) / pairs(Hook) at gate2 runtime must
-- be shipped. This asserts the exhaustive criterion: a new engine event REDS this
-- suite until src/gate1/stubs/events_list.lua is regenerated — intended, that is
-- the parity tool working. Reconcile by regenerating the artifact, never by
-- widening the exceptions set here.
--
-- Forward exceptions — names shipped but NOT registered by the runner's boot path,
-- with the reason per name (exact set; nothing else may be exempted):
--   onToggleSearchMode, onEnableSearchMode, onDisableSearchMode — Lua-side
--     registrations (pz_vanilla_code_base/lua/client/Foraging/ISSearchManager.lua
--     lines 34-36 call LuaEventManager.AddEvent from game Lua). The gate2 runner
--     boots engine Java only and never executes game Lua, so these three never
--     exist in the real VM.
--   (The design anticipated conditional trading/cheats-UI registration exceptions
--   too — that exceptions class is KILLED by Task 6's real-jar verification: every
--   non-On Java name, including the trading/cheats-UI set (TradingUIAddItem,
--   TradingUIRemoveItem, TradingUIUpdateState, RefreshCheats, ViewTickets,
--   ViewBannedIPs, ViewBannedSteamIDs, ...), is unconditionally boot-registered by
--   LuaEventManager.AddEvents(). Verified against the real jar 2026-11-21: the
--   only forward misses are the three Lua-side names above.)
--   (Ruling 2026-11-21, Task 6 fix round 1: the exhaustive completeness criterion
--   extends to On* boot names too — the shipped `events` list is the FULL boot
--   registry (263 names, byte-identical to pairs(Events) at this runtime) plus the
--   3 Lua-side names = 266; reverse parity below must therefore pass clean. A new
--   engine event still reds the suite until the artifact regenerates — intended.)

describe("gate2 events parity", function()
    local list = rawget(_G, "__pz_events_list")

    local exceptions = {
        onToggleSearchMode = true,
        onEnableSearchMode = true,
        onDisableSearchMode = true,
    }

    it("runner exposes the shipped split allowlists", function()
        expect(type(list)).toBe("table")
        expect(type(list.events)).toBe("table")
        expect(type(list.hooks)).toBe("table")
        expect(#list.events > 0).toBe(true)
        expect(#list.hooks > 0).toBe(true)
        expect(list.names).toBeNil()
    end)

    it("every shipped events name is registered in the real registry (minus exceptions)", function()
        expect(type(Events)).toBe("table")
        local missing = {}
        for _, n in ipairs(list.events) do
            if not exceptions[n] and type(Events[n]) ~= "table" then
                missing[#missing + 1] = n
            end
        end
        expect(missing).toEqual({})
    end)

    it("every shipped hooks name is registered in the real Hook registry", function()
        expect(type(Hook)).toBe("table")
        local missing = {}
        for _, n in ipairs(list.hooks) do
            if type(Hook[n]) ~= "table" then
                missing[#missing + 1] = n
            end
        end
        expect(missing).toEqual({})
    end)

    it("every real Events registry name is shipped (reverse parity)", function()
        local shipped = {}
        for _, n in ipairs(list.events) do
            shipped[n] = true
        end
        local unshipped = {}
        for name, _ in pairs(Events) do
            if not shipped[name] then
                unshipped[#unshipped + 1] = name
            end
        end
        table.sort(unshipped)
        expect(unshipped).toEqual({})
    end)

    it("every real Hook registry name is shipped (hook reverse parity)", function()
        local shipped = {}
        for _, n in ipairs(list.hooks) do
            shipped[n] = true
        end
        local unshipped = {}
        for name, _ in pairs(Hook) do
            if not shipped[name] then
                unshipped[#unshipped + 1] = name
            end
        end
        table.sort(unshipped)
        expect(unshipped).toEqual({})
    end)
end)
