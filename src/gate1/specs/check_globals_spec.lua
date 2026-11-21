local ROOT = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local cg = dofile(ROOT .. "/../check/check_globals.lua")
local TMP = ROOT .. "/../../.tmp"

local CLEAN = table.concat({
    "-- clean fixture: baseline globals + an allowlisted event only",
    "local t = { 1, 2, 3 }",
    "print(#t)",
    "for _, v in ipairs(t) do tostring(v) end",
    "local n = tonumber(\"42\")",
    "Events.OnGameStart(function() print(n) end)",
}, "\n") .. "\n"

local UNKNOWN = table.concat({
    "-- unknown-global fixture (exact lines pinned below)",
    "local a = 1",
    "local b = zzReadGlobal",
    "zzWriteGlobal = a + b",
    "print(a, b)",
}, "\n") .. "\n"

local EVENTS_TYPO = table.concat({
    "-- unknown-event fixture",
    "Events.OnTypo(function() end)",
    "Events.OnGameStart(function() end)",
}, "\n") .. "\n"

local EVENTS_NON_ON = table.concat({
    "-- non-`On` allowlisted event fixture (exhaustive-list pin)",
    "Events.EveryOneMinute(function() end)",
}, "\n") .. "\n"

local EVENTS_UNKNOWN = table.concat({
    "-- unknown Events.<Name> fixture",
    "Events.NotARealEvent(function() end)",
}, "\n") .. "\n"

local HOOK_USE = table.concat({
    "-- allowlisted hook fixture",
    "Hook.UseItem(function(item) print(item) end)",
}, "\n") .. "\n"

local HOOK_TYPO = table.concat({
    "-- unknown-hook fixture",
    "Hook.NotARealHook(function() end)",
    "Hook.UseItem(function() end)",
}, "\n") .. "\n"

local CROSS_NS = table.concat({
    "-- cross-namespace uses: each name belongs to the other registry",
    "Events.UseItem(function() end)",
    "Hook.OnTick(function() end)",
}, "\n") .. "\n"

local EVENTS_WRITE_TYPO = table.concat({
    "-- unknown event via assignment (SETTABLE write-path fixture)",
    "Events.OnTypoEvent = function() end",
}, "\n") .. "\n"

local HOOK_WRITE_TYPO = table.concat({
    "-- unknown hook via assignment (SETTABLE write-path fixture)",
    "Hook.OnTypoHook = function() end",
}, "\n") .. "\n"

local EVENTS_WRITE_GLOBAL_RHS = table.concat({
    "-- RHS is a global read: its GETGLOBAL must not clobber the write latch",
    "Events.OnMyHook = MyMod.OnMyHook",
}, "\n") .. "\n"

local EVENTS_WRITE_REUSED_REG = table.concat({
    "-- register reuse after the write must not re-fire the stale latch",
    "Events.OnTypoReg = 1",
    "do local t = {}",
    "t.OnTypoReg = 2",
    "end",
}, "\n") .. "\n"

local EVENTS_WRITE_LOCAL_ALIAS = table.concat({
    "-- two-layer local alias: the tracker must follow MOVE",
    "local e = Events",
    "local e2 = e",
    "e2.OnTypoMove = function() end",
}, "\n") .. "\n"

local EVENTS_WRITE_UPVALUE = table.concat({
    "-- inline closure with an upvalue: CLOSURE nups pseudo-instructions skipped",
    "local uv",
    "Events.OnTypoUp = function() return uv end",
}, "\n") .. "\n"

local function write_fixture(name, text)
    local fh = assert(io.open(TMP .. "/" .. name, "wb"))
    fh:write(text)
    fh:close()
    return TMP .. "/" .. name
end

os.execute('mkdir "' .. TMP .. '" 2>nul')

describe("check_globals (string.dump static checker)", function()

    it("dogfoods: scans its own source file with zero findings/warnings", function()
        local self_path = ROOT .. "/../check/check_globals.lua"
        local findings, warnings = cg.check({ self_path })
        expect_eq(#warnings, 0, "warnings: " .. table.concat(warnings, "; "))
        expect_eq(#findings, 0, "unexpected findings in checker itself")
    end)

    it("clean fixture yields zero findings (exit-code 0)", function()
        local p = write_fixture("cg_clean.lua", CLEAN)
        local findings, warnings = cg.check({ p })
        expect_eq(#warnings, 0, "warnings: " .. table.concat(warnings, "; "))
        expect_eq(#findings, 0, "clean fixture should have no findings")
        expect_eq(cg.exit_code(findings), 0)
    end)

    it("reports unknown global read and write with exact line numbers", function()
        local p = write_fixture("cg_unknown.lua", UNKNOWN)
        local findings = cg.check({ p })
        expect_eq(#findings, 2, "expected exactly 2 findings")
        expect_eq(findings[1].name, "zzReadGlobal")
        expect_eq(findings[1].kind, "read")
        expect_eq(findings[1].line, 3)
        expect_eq(findings[2].name, "zzWriteGlobal")
        expect_eq(findings[2].kind, "write")
        expect_eq(findings[2].line, 4)
        expect(cg.format(findings[2])).toContain("(assigned)")
        expect_eq(cg.exit_code(findings), 1)
    end)

    it("reports unknown Events.<Name> with line; allows listed events", function()
        local p = write_fixture("cg_events.lua", EVENTS_TYPO)
        local findings = cg.check({ p })
        expect_eq(#findings, 1, "OnTypo unknown, OnGameStart allowlisted")
        expect_eq(findings[1].name, "OnTypo")
        expect_eq(findings[1].kind, "event")
        expect_eq(findings[1].line, 2)
        expect(findings[1].file).toContain("cg_events.lua")
        expect(cg.format(findings[1])).toContain("unknown event 'Events.OnTypo'")
    end)

    it("non-`On` allowlisted event passes (Events.EveryOneMinute)", function()
        local p = write_fixture("cg_event_nonon.lua", EVENTS_NON_ON)
        local findings, warnings = cg.check({ p })
        expect_eq(#warnings, 0, "warnings: " .. table.concat(warnings, "; "))
        expect_eq(#findings, 0, "EveryOneMinute is in the exhaustive events list")
    end)

    it("reports unknown Events.<Name> findings for non-`On` names too", function()
        local p = write_fixture("cg_event_unknown.lua", EVENTS_UNKNOWN)
        local findings = cg.check({ p })
        expect_eq(#findings, 1)
        expect_eq(findings[1].name, "NotARealEvent")
        expect_eq(findings[1].kind, "event")
        expect_eq(findings[1].line, 2)
        expect(cg.format(findings[1])).toContain("unknown event 'Events.NotARealEvent'")
    end)

    it("allowlisted Hook.<Name> use passes (Hook.UseItem)", function()
        local p = write_fixture("cg_hook_use.lua", HOOK_USE)
        local findings, warnings = cg.check({ p })
        expect_eq(#warnings, 0, "warnings: " .. table.concat(warnings, "; "))
        expect_eq(#findings, 0, "UseItem is in the hooks allowlist")
    end)

    it("reports unknown Hook.<Name> with line; allows listed hooks", function()
        local p = write_fixture("cg_hook_typo.lua", HOOK_TYPO)
        local findings = cg.check({ p })
        expect_eq(#findings, 1, "NotARealHook unknown, UseItem allowlisted")
        expect_eq(findings[1].name, "NotARealHook")
        expect_eq(findings[1].kind, "event")
        expect_eq(findings[1].line, 2)
        expect(findings[1].file).toContain("cg_hook_typo.lua")
        expect(cg.format(findings[1])).toContain("unknown event 'Hook.NotARealHook'")
    end)

    it("cross-namespace uses are findings (Events.UseItem, Hook.OnTick)", function()
        local p = write_fixture("cg_cross_ns.lua", CROSS_NS)
        local findings = cg.check({ p })
        expect_eq(#findings, 2, "each name belongs to the other registry only")
        expect_eq(findings[1].name, "UseItem")
        expect_eq(findings[1].kind, "event")
        expect_eq(findings[1].registry, "Events")
        expect_eq(findings[1].line, 2)
        expect_eq(findings[2].name, "OnTick")
        expect_eq(findings[2].kind, "event")
        expect_eq(findings[2].registry, "Hook")
        expect_eq(findings[2].line, 3)
    end)

    it("reports unknown Events.<Name> assigned directly (SETTABLE write path)", function()
        local p = write_fixture("cg_event_write.lua", EVENTS_WRITE_TYPO)
        local findings = cg.check({ p }, { known = cg.known({ stdlib = true }) })
        expect_eq(#findings, 1, "Events.OnX = f must hit the events allowlist too")
        expect_eq(findings[1].name, "OnTypoEvent")
        expect_eq(findings[1].kind, "event")
        expect_eq(findings[1].registry, "Events")
        expect_eq(findings[1].line, 2)
        expect(findings[1].file).toContain("cg_event_write.lua")
        expect(cg.format(findings[1])).toContain("unknown event 'Events.OnTypoEvent'")
    end)

    it("reports unknown Hook.<Name> assigned directly (SETTABLE write path)", function()
        local p = write_fixture("cg_hook_write.lua", HOOK_WRITE_TYPO)
        local findings = cg.check({ p }, { known = cg.known({ stdlib = true }) })
        expect_eq(#findings, 1, "Hook.OnX = f must hit the hooks allowlist too")
        expect_eq(findings[1].name, "OnTypoHook")
        expect_eq(findings[1].kind, "event")
        expect_eq(findings[1].registry, "Hook")
        expect_eq(findings[1].line, 2)
        expect(findings[1].file).toContain("cg_hook_write.lua")
        expect(cg.format(findings[1])).toContain("unknown event 'Hook.OnTypoHook'")
    end)

    it("reports unknown Events.<Name> assigned from a global read (RHS GETGLOBAL must not clobber the write latch)", function()
        local p = write_fixture("cg_event_write_global_rhs.lua", EVENTS_WRITE_GLOBAL_RHS)
        local findings = cg.check({ p }, { known = cg.known({ stdlib = true }) })
        local event_findings, read_findings = {}, {}
        for _, f in ipairs(findings) do
            if f.kind == "event" then event_findings[#event_findings + 1] = f
            else read_findings[#read_findings + 1] = f end
        end
        expect_eq(#event_findings, 1, "Events.OnX = MyMod.OnX must hit the events allowlist too")
        expect_eq(event_findings[1].name, "OnMyHook")
        expect_eq(event_findings[1].registry, "Events")
        expect_eq(#read_findings, 1, "the RHS unknown global read is still reported")
        expect_eq(read_findings[1].name, "MyMod")
    end)

    it("tracks registers: reuse after a write does not re-fire; local alias chains detected", function()
        local p = write_fixture("cg_event_write_reuse.lua", EVENTS_WRITE_REUSED_REG)
        local findings = cg.check({ p }, { known = cg.known({ stdlib = true }) })
        expect_eq(#findings, 1, "register reuse after Events.X = v must not re-fire the stale latch")
        expect_eq(findings[1].line, 2)
        expect_eq(findings[1].name, "OnTypoReg")

        local p2 = write_fixture("cg_event_write_local_alias.lua", EVENTS_WRITE_LOCAL_ALIAS)
        local findings2 = cg.check({ p2 }, { known = cg.known({ stdlib = true }) })
        expect_eq(#findings2, 1, "local e = Events; local e2 = e; e2.OnX = f must hit the events allowlist")
        expect_eq(findings2[1].name, "OnTypoMove")
        expect_eq(findings2[1].registry, "Events")
        expect_eq(findings2[1].line, 4)
    end)

    it("tracks CLOSURE upvalue pseudo-instructions: inline closures with upvalues still detected", function()
        local p = write_fixture("cg_event_write_upvalue.lua", EVENTS_WRITE_UPVALUE)
        local findings = cg.check({ p }, { known = cg.known({ stdlib = true }) })
        expect_eq(#findings, 1, "Events.OnX = function() return upval end must be detected")
        expect_eq(findings[1].name, "OnTypoUp")
        expect_eq(findings[1].registry, "Events")
        expect_eq(findings[1].line, 3)
    end)

    it("old-shape events_list warns once and fails closed (both sets empty)", function()
        local old_list = write_fixture("cg_old_events_list.lua",
            "return { names = { \"OnGameStart\", \"UseItem\" } }\n")
        local warns = {}
        local lists = cg.load_events_list(function(w) warns[#warns + 1] = w end, old_list)
        expect_eq(#warns, 1, "warn exactly once for the old names-only shape")
        expect(warns[1]).toContain("names")
        local function count(t)
            local n = 0
            for _ in pairs(t) do n = n + 1 end
            return n
        end
        expect_eq(count(lists.events), 0, "events set empty (fail-closed)")
        expect_eq(count(lists.hooks), 0, "hooks set empty (fail-closed)")
    end)

    it("multi-file runs report the same finding from every file", function()
        local p1 = write_fixture("cg_dup_a.lua", UNKNOWN)
        local p2 = write_fixture("cg_dup_b.lua", UNKNOWN)
        local findings = cg.check({ p1, p2 })
        expect_eq(#findings, 4, "2 findings x 2 files, no cross-file suppression")
        expect_eq(findings[1].file, p1)
        expect_eq(findings[3].file, p2)
        expect_eq(findings[3].name, "zzReadGlobal")
        expect_eq(findings[3].line, 3)
        expect_eq(cg.exit_code(findings), 1)
    end)

    it("exit-code contract: 0 when clean, 1 when any finding", function()
        expect_eq(cg.exit_code({}), 0)
        expect_eq(cg.exit_code(nil), 0)
        expect_eq(cg.exit_code({ { name = "x" } }), 1)
    end)

    it("unreadable target becomes a warning, not an error", function()
        local findings, warnings = cg.check({ TMP .. "/cg_no_such_file.lua" })
        expect_eq(#findings, 0)
        expect_eq(#warnings, 1)
        expect(warnings[1]).toContain("cannot open")
    end)

    it("--stdlib harvest adds stub globals to the known set", function()
        local known = cg.known({ stdlib = true })
        expect_eq(known.print, true)
        expect_eq(known.Events, true)
        expect_eq(known.Hook, true)
        expect_eq(known.isServer, true)
        expect_eq(known.zzNeverDefined, nil)
    end)

    it("baseline known set covers the standard Lua 5.1 surface", function()
        local known = cg.known()
        expect_eq(known.string, true)
        expect_eq(known._G, true)
        expect_eq(known.unpack, true)
        expect_eq(known.Events, nil)
    end)
end)
