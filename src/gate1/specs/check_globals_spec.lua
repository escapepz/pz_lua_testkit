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
