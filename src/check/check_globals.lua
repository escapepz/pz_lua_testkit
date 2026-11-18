-- Usage:
--   module:  local cg = dofile("src/check/check_globals.lua")
--            local findings, warnings = cg.check(paths, { stdlib = true })
--   CLI:     lua5.1.exe src/check/check_globals.lua <file-or-dir>... [--stdlib]
-- Exit codes: 0 clean, 1 unknown globals/events found, 2 usage error.
-- Known globals: hardcoded baseline + (with --stdlib) a runtime harvest of
-- _G after dofileing src/gate1/stubs/core.lua. Events allowlist comes from
-- src/gate1/stubs/events_list.lua when present. PZ_UMBRELLA symbols are out
-- of scope (deferred; see q9 report).

local M = {}

local BASELINE = {
    assert = true, collectgarbage = true, dofile = true, error = true,
    getmetatable = true, ipairs = true, load = true, loadfile = true,
    loadstring = true, module = true, next = true, pairs = true,
    pcall = true, print = true, rawequal = true, rawget = true,
    rawset = true, require = true, select = true, setfenv = true,
    setmetatable = true, tonumber = true, tostring = true, type = true,
    unpack = true, xpcall = true,
    string = true, table = true, math = true, io = true, os = true,
    coroutine = true, debug = true, package = true,
    _G = true, arg = true, newproxy = true,
}
M.BASELINE = BASELINE

local OP_GETGLOBAL, OP_GETTABLE, OP_SETGLOBAL, OP_SETTABLE, OP_SELF
    = 5, 6, 7, 9, 11

local function rd_bytes(rd, n)
    local p = rd.pos
    if p + n - 1 > #rd.s then error("truncated dump", 0) end
    rd.pos = p + n
    return rd.s:sub(p, p + n - 1)
end

local function rd_uint(rd, n)
    local b = rd_bytes(rd, n)
    local v = 0
    for i = n, 1, -1 do v = v * 256 + b:byte(i) end
    return v
end

local function rd_sint(rd, n)
    local v = rd_uint(rd, n)
    local sign = 2 ^ (8 * n - 1)
    if v >= sign then v = v - 2 * sign end
    return v
end

local function rd_string(rd)
    local len = rd_uint(rd, rd.sizet)
    if len == 0 then return nil end
    return rd_bytes(rd, len):sub(1, len - 1)
end

local function add(out, seen, file, line, name, kind)
    local key = file .. "\1" .. kind .. "\1" .. name .. "\1" .. line
    if not seen[key] then
        seen[key] = true
        out[#out + 1] = { file = file, line = line, name = name, kind = kind }
    end
end

local function const_key(ins, consts, shift)
    local v = math.floor(ins / 2 ^ shift) % 512
    if v >= 256 then
        local c = consts[v - 255]
        if type(c) == "string" then return c end
    end
    return nil
end

local function line_of(lines, pc)
    local line = lines[pc] or 0
    if line < 0 then line = 0 end
    return line
end

local function analyze(code, consts, lines, file, out, seen, known, events)
    local pending_reg
    for pc = 1, #code do
        local ins = code[pc]
        local op = ins % 64
        if op == OP_GETGLOBAL or op == OP_SETGLOBAL then
            pending_reg = nil
            local name = consts[math.floor(ins / 2 ^ 14) % 2 ^ 18 + 1]
            if type(name) == "string" then
                local line = line_of(lines, pc)
                if op == OP_GETGLOBAL and name == "Events" then
                    local nxt = code[pc + 1]
                    local key = nil
                    if nxt then
                        local nop = nxt % 64
                        if nop == OP_GETTABLE or nop == OP_SELF then
                            key = const_key(nxt, consts, 14)
                        end
                    end
                    if key then
                        if not events[key] then
                            add(out, seen, file, line, key, "event")
                        end
                    else
                        if not known[name] then
                            add(out, seen, file, line, name, "read")
                        end
                        pending_reg = math.floor(ins / 64) % 256
                    end
                elseif not known[name] then
                    add(out, seen, file, line, name,
                        op == OP_SETGLOBAL and "write" or "read")
                end
            end
        elseif op == OP_SETTABLE then
            if pending_reg and math.floor(ins / 64) % 256 == pending_reg then
                local key = const_key(ins, consts, 23)
                if key and not events[key] then
                    add(out, seen, file, line_of(lines, pc), key, "event")
                end
            end
        end
    end
end

local function walk_proto(rd, file, out, seen, known, events)
    rd_string(rd)
    rd_uint(rd, rd.intsize)
    rd_uint(rd, rd.intsize)
    rd_bytes(rd, 4)
    local ncode = rd_uint(rd, rd.intsize)
    local code = {}
    for i = 1, ncode do code[i] = rd_uint(rd, rd.instrsize) end
    local nconst = rd_uint(rd, rd.intsize)
    local consts = {}
    for i = 1, nconst do
        local tag = rd_bytes(rd, 1):byte()
        if tag == 4 then
            consts[i] = rd_string(rd)
        elseif tag == 3 then
            rd_bytes(rd, rd.numsize)
        elseif tag == 1 then
            consts[i] = rd_bytes(rd, 1):byte() ~= 0
        end
    end
    local nprotos = rd_uint(rd, rd.intsize)
    for _ = 1, nprotos do
        walk_proto(rd, file, out, seen, known, events)
    end
    local nlines = rd_uint(rd, rd.intsize)
    local lines = {}
    for i = 1, nlines do lines[i] = rd_sint(rd, rd.intsize) end
    local nloc = rd_uint(rd, rd.intsize)
    for _ = 1, nloc do
        rd_string(rd)
        rd_uint(rd, rd.intsize)
        rd_uint(rd, rd.intsize)
    end
    local nups = rd_uint(rd, rd.intsize)
    for _ = 1, nups do rd_string(rd) end

    analyze(code, consts, lines, file, out, seen, known, events)
end

local function scan_dump(dump, file, out, seen, known, events)
    if #dump < 12 then error("dump too short", 0) end
    if dump:sub(1, 4) ~= "\27Lua" then error("bad signature", 0) end
    if dump:byte(5) ~= 0x51 then error("need a Lua 5.1 dump", 0) end
    if dump:byte(7) ~= 1 then error("big-endian dump unsupported", 0) end
    local rd = {
        s = dump,
        pos = 13,
        intsize = dump:byte(8),
        sizet = dump:byte(9),
        instrsize = dump:byte(10),
        numsize = dump:byte(11),
    }
    if rd.intsize < 1 or rd.intsize > 8 or rd.sizet < 1 or rd.sizet > 8
        or rd.instrsize < 2 or rd.numsize < 1 or rd.numsize > 8 then
        error("implausible header sizes", 0)
    end
    walk_proto(rd, file, out, seen, known, events)
end

local function module_dir()
    local src = ""
    if debug and debug.getinfo then
        local info = debug.getinfo(1, "S")
        if info and type(info.source) == "string" and info.source:sub(1, 1) == "@" then
            src = info.source:sub(2)
        end
    end
    if src == "" and arg and arg[0] then src = arg[0] end
    return src:match("^(.*)[/\\][^/\\]*$") or "."
end

local function stub_path(name)
    return module_dir() .. "/../gate1/stubs/" .. name
end

local function harvest_stub_globals(warn)
    local core = stub_path("core.lua")
    local fh = io.open(core, "rb")
    if not fh then
        warn("stdlib harvest: core stub not found: " .. core)
        return {}
    end
    fh:close()
    local stubdir = core:match("^(.*)[/\\][^/\\]*$") or "."
    package.path = stubdir .. "/?.lua;" .. package.path
    if rawget(_G, "overlords_ctx") == nil then
        rawset(_G, "overlords_ctx", "sp")
    end
    local ok, err = pcall(dofile, core)
    if not ok then
        warn("stdlib harvest: core stub errored: " .. tostring(err))
    end
    local out = {}
    for k in pairs(_G) do out[k] = true end
    return out
end

local function load_events_list(warn)
    local path = stub_path("events_list.lua")
    local fh = io.open(path, "rb")
    if not fh then
        warn("events allowlist not found: " .. path)
        return {}
    end
    fh:close()
    local ok, list = pcall(dofile, path)
    local out = {}
    if ok and type(list) == "table" and type(list.names) == "table" then
        for _, n in ipairs(list.names) do
            if type(n) == "string" then out[n] = true end
        end
    else
        warn("events allowlist unusable: " .. tostring(ok and list or list))
    end
    return out
end

M.known = function(opts)
    opts = opts or {}
    local known = {}
    for k in pairs(BASELINE) do known[k] = true end
    if opts.stdlib then
        local warnings = {}
        for k in pairs(harvest_stub_globals(function(w) warnings[#warnings + 1] = w end)) do
            known[k] = true
        end
        if opts.on_warning then
            for _, w in ipairs(warnings) do opts.on_warning(w) end
        end
    end
    return known
end

M.events_allowlist = function(on_warning)
    return load_events_list(function(w) if on_warning then on_warning(w) end end)
end

-- check(paths, opts) -> findings, warnings
--   findings: sorted list of { file, line, name, kind = "read"|"write"|"event" }
--   warnings: per-file warn lines (unreadable / not Lua / walk failure)
--   opts: { stdlib = bool, known = set (overrides), events = set (overrides) }
local function quoteShellPath(p)
    if package.config:sub(1, 1) == "\\" then
        p = p:gsub("/", "\\")
        if p:match('["\r\n|&^%%]') then return nil end
        return '"' .. p .. '"'
    end
    return "'" .. p:gsub("'", "'\\''") .. "'"
end

M.check = function(paths, opts)
    opts = opts or {}
    local warnings = {}
    local function warn(msg) warnings[#warnings + 1] = msg end
    local known = opts.known or M.known({ stdlib = opts.stdlib, on_warning = warn })
    local events = opts.events or load_events_list(warn)
    local findings, seen = {}, {}
    for _, path in ipairs(paths or {}) do
        local targets = {}
        local fh = io.open(path, "rb")
        local is_file = false
        if fh then
            local _, rerr = fh:read(1)
            fh:close()
            is_file = (rerr == nil)
        end
        if is_file then
            targets[1] = path
        else
            local q = quoteShellPath(path)
            if q then
                local listCmd
                if package.config:sub(1, 1) == "\\" then
                    listCmd = "dir /s /b " .. q
                else
                    listCmd = "find " .. q .. ' -name "*.lua" -type f 2>/dev/null'
                end
                local ok, handle = pcall(io.popen, listCmd)
                if ok and handle then
                    for line in handle:lines() do
                        if line:sub(-4):lower() == ".lua" then
                            targets[#targets + 1] = line
                        end
                    end
                    handle:close()
                end
            end
            if #targets == 0 then warn("cannot open '" .. path .. "'") end
        end
        for _, file in ipairs(targets) do
            local chunk, err = loadfile(file)
            if not chunk then
                warn(file .. ": not loadable: " .. tostring(err))
            else
                local ok, dump = pcall(string.dump, chunk)
                if not ok then
                    warn(file .. ": string.dump failed: " .. tostring(dump))
                else
                    local ok2, ferr = pcall(scan_dump, dump, file, findings, seen, known, events)
                    if not ok2 then
                        warn(file .. ": bytecode walk failed: " .. tostring(ferr))
                    end
                end
            end
        end
    end
    table.sort(findings, function(a, b)
        if a.file ~= b.file then return a.file < b.file end
        if a.line ~= b.line then return a.line < b.line end
        if a.name ~= b.name then return a.name < b.name end
        return a.kind < b.kind
    end)
    return findings, warnings
end

M.format = function(f)
    if f.kind == "event" then
        return string.format("%s:%d: unknown event 'Events.%s'", f.file, f.line, f.name)
    elseif f.kind == "write" then
        return string.format("%s:%d: unknown global '%s' (assigned)", f.file, f.line, f.name)
    end
    return string.format("%s:%d: unknown global '%s'", f.file, f.line, f.name)
end

M.exit_code = function(findings)
    return (findings and #findings > 0) and 1 or 0
end

local function main(argv)
    local usage = "usage: lua5.1.exe src/check/check_globals.lua <file-or-dir>... [--stdlib]"
        .. "  (exit 0 clean, 1 findings, 2 usage error)"
    local paths, stdlib = {}, false
    for _, a in ipairs(argv) do
        if a == "--stdlib" then
            stdlib = true
        elseif a:sub(1, 1) == "-" then
            io.stderr:write("check_globals: unknown option '" .. a .. "'\n" .. usage .. "\n")
            return 2
        else
            paths[#paths + 1] = a
        end
    end
    if #paths == 0 then
        io.stderr:write(usage .. "\n")
        return 2
    end
    local findings, warnings = M.check(paths, { stdlib = stdlib })
    for _, w in ipairs(warnings) do
        io.stderr:write("warning: " .. w .. "\n")
    end
    for _, f in ipairs(findings) do
        print(M.format(f))
    end
    print(string.format("%d finding(s)", #findings))
    return M.exit_code(findings)
end

local a0 = arg and arg[0]
if type(a0) == "string" and a0:match("check_globals%.lua$") then
    local argv = {}
    for i = 1, #arg do argv[i] = arg[i] end
    os.exit(main(argv))
end

return M
