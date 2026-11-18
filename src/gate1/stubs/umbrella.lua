-- Clone-shape contract (shapes observed 2026-11-13 on the canonical 42.21.0

--   java tree:  "---@meta _" header; "---@class Name: Parent1, Parent2" with

--   lua tree:   "---@meta" header; bare top-level global functions

-- Clone files are BOM-less LF; a leading BOM is stripped defensively anyway.

local Umbrella = {}

Umbrella.on = false
Umbrella.root = nil

Umbrella._served = {}
Umbrella._served_funcs = {}

Umbrella.MAPPING = {

    player = "IsoPlayer",
    square = "IsoGridSquare",

    IsoSprite = "IsoSprite",
    ItemContainer = "ItemContainer",
    InventoryItem = "InventoryItem",
    IsoObject = "IsoObject",
    IsoPlayer = "IsoPlayer",
    IsoDeadBody = "IsoDeadBody",
    IsoGridSquare = "IsoGridSquare",
    ISPanel = "ISPanel",
    ISButton = "ISButton",
    ISScrollingListBox = "ISScrollingListBox",
    ISImage = "ISImage",
    ISLabel = "ISLabel",
    ISComboBox = "ISComboBox",
    ISTextEntryBox = "ISTextEntryBox",
    ISTiledIconListBox = "ISTiledIconListBox",
    ISInventoryPage = "ISInventoryPage",
    ISEntityWindow = "ISEntityWindow",
    ISTableLayout = "ISTableLayout",
    ISWalkToTimedAction = "ISWalkToTimedAction",
    ISDestroyStuffAction = "ISDestroyStuffAction",
    ISDismantleAction = "ISDismantleAction",
    ISMoveablesAction = "ISMoveablesAction",
}

local stem_paths = nil
local stem_index = nil
local func_index = nil
local class_cache = nil

local WINDOWS = (package.config:sub(1, 1) == "\\")

local WARN_INVALID = "PZ_UMBRELLA path invalid — mode off"

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function readLines(filepath)
    local f = io.open(filepath, "r")
    if not f then return nil end
    local lines = {}
    for line in f:lines() do
        table.insert(lines, line)
    end
    f:close()
    if lines[1] then
        lines[1] = lines[1]:gsub("^" .. "\xEF\xBB\xBF", "")
    end
    return lines
end

local function listDir(cmd)
    local p = io.popen(cmd)
    if not p then return nil end
    local out = {}
    for line in p:lines() do
        line = line:gsub("%s+$", "")
        if line ~= "" then table.insert(out, line) end
    end
    p:close()
    return out
end

local function winPath(p)
    return (p:gsub("/", "\\"))
end

local function arityOf(args)
    local p = trim(args)
    if p == "" then return 0 end
    local n = 1
    for _ in p:gmatch(",") do n = n + 1 end
    return n
end

local function quoteShellPath(p)
    if WINDOWS then
        p = p:gsub("/", "\\")
        if p:match('["\r\n|&^%%]') then return nil end
        return '"' .. p .. '"'
    end
    return "'" .. p:gsub("'", "'\\''") .. "'"
end

local function libraryProbe(root)
    local q = quoteShellPath(root .. "/library")
    if not q then return false end
    local cmd
    if WINDOWS then
        cmd = "dir /b " .. q .. " 2>nul"
    else
        cmd = "ls -1 " .. q .. " 2>/dev/null"
    end
    local lines = listDir(cmd)
    return lines ~= nil and #lines > 0
end

-- ONLY; cleared whenever the mode goes off). REAL FORMAT (canonical clone
-- library/events.lua, observed 2026-11-13): the file declares the container

local events_cache = nil

local EVENTS_DECL_PATTERN = "Events%.([%a_][%w_]*)%s*=%s*{"

local function ensureEventsCache()
    if events_cache then return events_cache end
    events_cache = {}
    local f = io.open(Umbrella.root .. "/library/events.lua", "r")
    if f then
        local content = f:read("*a")
        f:close()
        if content then
            content = content:gsub("^" .. "\xEF\xBB\xBF", "")
            for name in content:gmatch(EVENTS_DECL_PATTERN) do
                events_cache[name] = true
            end
        end
    end
    return events_cache
end

function Umbrella.events_lookup(name)
    if not Umbrella.on then return false end
    local declared = ensureEventsCache()
    if not declared[name] then return false end

    local list = _G.__pz_events_list
    if type(list) == "table" and type(list.names) == "table" then
        local names = list.names
        local known = false
        for _, n in ipairs(names) do
            if n == name then known = true break end
        end
        if not known then
            local pos = #names + 1
            for i, n in ipairs(names) do
                if n > name then pos = i break end
            end
            table.insert(names, pos, name)
        end
    end
    return true
end

local attached = nil

local function attachFallback(t, class_name)
    if attached and attached[t] ~= nil then return t end
    local orig = getmetatable(t)
    local old_index = orig and orig.__index or nil
    local mt = {}
    if orig then
        for mk, mv in pairs(orig) do mt[mk] = mv end
    end
    mt.__index = function(tt, kk)
        local oi = old_index
        local guard = 0
        while oi ~= nil and guard < 16 do
            guard = guard + 1
            if type(oi) == "function" then
                local v = oi(tt, kk)
                if v ~= nil then return v end
                break
            end
            local entry = attached and attached[oi]
            if entry == nil then
                local v = oi[kk]
                if v ~= nil then return v end
                break
            end
            local v = rawget(oi, kk)
            if v ~= nil then return v end
            oi = entry.old_index
        end

        local ok, res = pcall(Umbrella.resolve_method, class_name, kk)
        if not ok then

            error((tostring(res):gsub("^.-:%d+: ", "")), 2)
        end
        return res
    end
    setmetatable(t, mt)
    attached = attached or {}

    attached[t] = { orig = orig, old_index = old_index, class = class_name }
    return t
end

local function detachAll()
    if not attached then return end
    for t, entry in pairs(attached) do
        setmetatable(t, entry.orig)
    end
    attached = nil
end

local seam_memo = nil

local function resetState()
    detachAll()
    Umbrella.on = false
    Umbrella.root = nil
    stem_paths = nil
    stem_index = nil
    func_index = nil
    Umbrella._served = {}
    Umbrella._served_funcs = {}
    class_cache = nil
    seam_memo = nil
    events_cache = nil
    rawset(_G, "__umbrella_event_lookup", nil)
end

function Umbrella.init(path)
    if path == nil then
        resetState()
        return true
    end
    if type(path) ~= "string" or not libraryProbe(path) then
        resetState()
        print(WARN_INVALID)
        return false, "PZ_UMBRELLA root not found or missing library/ subdir: "
            .. tostring(path)
    end
    resetState()
    Umbrella.on = true
    Umbrella.root = path

    _G.__umbrella_event_lookup = Umbrella.events_lookup
    for shipped_name, class_name in pairs(Umbrella.MAPPING) do
        local t = rawget(_G, shipped_name)
        if type(t) == "table" then
            Umbrella.w(t, class_name)
        end
    end
    return true
end

local function buildStemPaths(root)
    local q = quoteShellPath(WINDOWS and (root .. "/library/*.lua") or (root .. "/library"))
    if not q then return {} end
    local cmd
    if WINDOWS then
        cmd = "dir /s /b " .. q .. " 2>nul"
    else
        cmd = "find " .. q .. ' -name "*.lua" -type f 2>/dev/null'
    end
    local out = {}
    for _, line in ipairs(listDir(cmd) or {}) do
        if line:lower():match("%.lua$") then table.insert(out, line) end
    end
    table.sort(out)
    return out
end

local function ensureStemPaths()
    if not stem_paths then
        stem_paths = buildStemPaths(Umbrella.root)
    end
    return stem_paths
end

local function stemOf(path)
    local stem = path:gsub(".*[/\\]", "")
    if stem:lower():sub(-4) == ".lua" then stem = stem:sub(1, -5) end
    return stem
end

function Umbrella.stem_index()
    if not Umbrella.on then return nil end
    if not stem_index then
        stem_index = {}
        for _, path in ipairs(ensureStemPaths()) do
            local s = stemOf(path)
            local list = stem_index[s]
            if not list then
                list = {}
                stem_index[s] = list
            end
            table.insert(list, path)
        end
    end
    return stem_index
end

-- parse_class_file(filepath) -> descriptor

-- Rules (mirroring the observed clone shapes):
--   * the FIRST ---@class line is the file's primary class; later ---@class

--   * methods: "function <recv>:name(args) end" / "function recv.name(args)"

--   * "---@return RAW" lines bind to the NEXT function declaration; a blank

--   * is_global: a bare global assignment whose target equals the class name

--   * fields: "---@field name T" lines of the primary class, plus primary-class

function Umbrella.parse_class_file(filepath)
    local lines = readLines(filepath)
    if not lines then return nil end

    local desc = {
        name = nil,
        is_global = false,
        parents = {},
        methods = {},
        fields = {},
    }
    local current_class = nil
    local pending_rets = nil
    local arity_seen = {}
    local ret_seen = {}

    for _, line in ipairs(lines) do
        if line:match("^%s*---@class%s+") then
            local cls, plist = line:match("^%s*---@class%s+([%w_.]+)%s*:?(.*)$")
            if cls then
                current_class = cls
                if not desc.name then
                    desc.name = cls
                    for p in plist:gmatch("[^,%s]+") do
                        table.insert(desc.parents, p)
                    end
                end
            end
        elseif line:match("^%s*---@return%s+") then
            local raw = line:match("^%s*---@return%s+(.+)%s*$")
            pending_rets = pending_rets or {}
            table.insert(pending_rets, raw)
        elseif line:match("^%s*---@field%s+") then
            local fld = line:match("^%s*---@field%s+([%w_]+)")
            if fld and current_class ~= nil and current_class == desc.name then
                desc.fields[fld] = true
            end
        elseif line:match("^%s*function%s+") then
            local mname, args =
                line:match("^%s*function%s+[%w_]+[.:]([%w_]+)%s*%(([^)]*)%)")
            if mname then
                local arity = arityOf(args)
                local m = desc.methods[mname]
                if not m then
                    m = { arities = {}, rets = {} }
                    desc.methods[mname] = m
                    arity_seen[mname] = {}
                    ret_seen[mname] = {}
                end
                if not arity_seen[mname][arity] then
                    arity_seen[mname][arity] = true
                    table.insert(m.arities, arity)
                end
                if pending_rets then
                    for _, raw in ipairs(pending_rets) do
                        if not ret_seen[mname][raw] then
                            ret_seen[mname][raw] = true
                            table.insert(m.rets, raw)
                        end
                    end
                end
            end
            pending_rets = nil

        elseif line:match("^%s*%-%-") or trim(line) == "" then

        else

            local assignee = line:match("^%s*([%w_]+)%s*=[^=]")
            if assignee and desc.name and assignee == desc.name then
                desc.is_global = true
            end
            local sprefix, sfield =
                line:match("^%s*([%w_]+)%.([%w_]+)%s*=[^=]")
            if sprefix and sfield and desc.name and sprefix == desc.name then
                desc.fields[sfield] = true
            end
            pending_rets = nil
        end
    end

    if not desc.name then return nil end
    return desc
end

local LUA_TREE_MARK = "[/\\]library[/\\]lua[/\\]"

local function buildFuncIndex()
    local idx = {}
    for _, path in ipairs(ensureStemPaths()) do
        if path:match(LUA_TREE_MARK) then
            local lines = readLines(path)
            if lines then
                local pending_rets = nil
                local ret_seen = {}
                for _, line in ipairs(lines) do
                    if line:match("^%s*---@return%s+") then
                        local raw = line:match("^%s*---@return%s+(.+)%s*$")
                        pending_rets = pending_rets or {}
                        table.insert(pending_rets, raw)
                    elseif line:match("^%s*function%s+") then
                        local fname, args =
                            line:match("^%s*function%s+([%w_]+)%s*%(([^)]*)%)")
                        if fname and not idx[fname] then
                            local rets = {}
                            if pending_rets then
                                for _, raw in ipairs(pending_rets) do
                                    if not ret_seen[raw] then
                                        ret_seen[raw] = true
                                        table.insert(rets, raw)
                                    end
                                end
                            end
                            idx[fname] = {
                                path = path,
                                name = fname,
                                arity = arityOf(args),
                                rets = rets,
                            }
                        end
                        pending_rets = nil
                    elseif line:match("^%s*%-%-") or trim(line) == "" then

                    else
                        pending_rets = nil
                    end
                end
            end
        end
    end
    return idx
end

function Umbrella.func_index()
    if not Umbrella.on then return nil end
    if not func_index then
        func_index = buildFuncIndex()
    end
    return func_index
end

function Umbrella.l1_policy(desc, method_name, m_desc, self, ...)
    return nil
end

Umbrella.return_policy = Umbrella.l1_policy

local function newRecorder(impl)
    local mk = rawget(_G, "mock")
    if mk then return mk(impl) end
    local rec = { calls = {} }
    local fn = function(...)
        local args = { n = select("#", ...), ... }
        table.insert(rec.calls, args)
        return impl(...)
    end
    rec.fn = fn
    return setmetatable(rec, { __call = function(_, ...) return fn(...) end })
end

local function classDescriptor(name)
    if class_cache and class_cache[name] then
        return class_cache[name]
    end
    local desc = nil
    local candidates = Umbrella.stem_index()
    candidates = candidates and candidates[name]
    for _, path in ipairs(candidates or {}) do
        local d = Umbrella.parse_class_file(path)
        if d then
            if d.name == name then
                desc = d
                break
            end
            if not desc then desc = d end
        end
    end
    if desc then
        class_cache = class_cache or {}
        class_cache[name] = desc
    end
    return desc
end

function Umbrella.find_method(class_name, method_name, visited)
    visited = visited or {}
    if visited[class_name] then return nil end
    local desc = classDescriptor(class_name)
    if not desc then return nil end
    visited[class_name] = true
    local m = desc.methods[method_name]
    if m then return desc, m end
    for _, parent in ipairs(desc.parents) do
        local owner, md = Umbrella.find_method(parent, method_name, visited)
        if owner then return owner, md end
    end
    return nil
end

function Umbrella.find_field(class_name, field_name, visited)
    visited = visited or {}
    if visited[class_name] then return nil end
    local desc = classDescriptor(class_name)
    if not desc then return nil end
    visited[class_name] = true
    if desc.fields[field_name] then return true end
    for _, parent in ipairs(desc.parents) do
        if Umbrella.find_field(parent, field_name, visited) then return true end
    end
    return nil
end

local function methodRecorder(owner, method_name, m_desc, stub)
    return newRecorder(function(...)
        return Umbrella.return_policy(owner, method_name, m_desc, stub, ...)
    end)
end

function Umbrella.resolve_method(class_name, k)
    local per_class = seam_memo and seam_memo[class_name]
    if per_class and per_class[k] then return per_class[k] end
    local owner, m = Umbrella.find_method(class_name, k)
    if owner then
        local rec = methodRecorder(owner, k, m, nil)
        seam_memo = seam_memo or {}
        seam_memo[class_name] = seam_memo[class_name] or {}
        seam_memo[class_name][k] = rec
        return rec
    end
    if _G.pz_strict and not Umbrella.find_field(class_name, k) then
        error("PZ_STRICT: unknown method '" .. class_name .. ":"
            .. tostring(k) .. "'", 2)
    end
    return nil
end

function Umbrella.w(obj, class_name)
    if not Umbrella.on then return obj end
    if type(obj) ~= "table" then return obj end
    return attachFallback(obj, class_name)
end

local function serveClassStub(desc)
    local stub = {}
    setmetatable(stub, {
        __index = function(t, k)
            if desc.fields[k] then return nil end
            local owner, m = Umbrella.find_method(desc.name, k)
            if owner then
                local rec = methodRecorder(owner, k, m, t)
                rawset(t, k, rec)
                return rec
            end
            if _G.pz_strict and not Umbrella.find_field(desc.name, k) then
                error("PZ_STRICT: unknown method '" .. desc.name .. ":"
                    .. tostring(k) .. "'", 2)
            end
            return nil
        end,
    })
    return stub
end

local function serveFuncStub(finfo)
    local rec = Umbrella._served_funcs[finfo.name]
    if not rec then
        rec = newRecorder(function(...)
            return Umbrella.return_policy(nil, finfo.name, finfo, nil, ...)
        end)
        Umbrella._served_funcs[finfo.name] = rec
    end
    return rec
end

function Umbrella.resolve_global(k)
    if not Umbrella.on then return nil end
    local si = Umbrella.stem_index()
    if si and si[k] then
        local desc = classDescriptor(k)
        if desc and desc.is_global then
            local stub = Umbrella._served[k]
            if not stub then
                stub = serveClassStub(desc)
                Umbrella._served[k] = stub
            end
            return stub
        end
        return nil
    end
    local fi = Umbrella.func_index()
    if fi and fi[k] then
        return serveFuncStub(fi[k])
    end
    return nil
end

function Umbrella.chain(obj, ...)
    if not Umbrella.on then return nil end
    if type(obj) ~= "table" then return nil end
    local class_name = nil
    for name, stub in pairs(Umbrella._served) do
        if stub == obj then
            class_name = name
            break
        end
    end
    if not class_name and attached and attached[obj] then
        class_name = attached[obj].class
    end
    if not class_name then
        for shipped_name, mapped in pairs(Umbrella.MAPPING) do
            if rawget(_G, shipped_name) == obj then
                class_name = mapped
                break
            end
        end
    end
    if not class_name then return nil end
    local stub = obj
    for i = 1, select("#", ...) do
        local step = select(i, ...)
        if type(step) ~= "string" then return nil end
        local owner, m = Umbrella.find_method(class_name, step)
        if not owner then return nil end
        local next_name = nil
        local si = Umbrella.stem_index()
        for _, raw in ipairs(m.rets or {}) do
            if raw and si[raw] and classDescriptor(raw) then
                next_name = raw
                break
            end
        end
        if not next_name then return nil end
        local next_stub = Umbrella._served[next_name]
        if not next_stub then
            next_stub = serveClassStub(classDescriptor(next_name))
            Umbrella._served[next_name] = next_stub
        end
        stub = next_stub
        class_name = next_name
    end
    return stub
end

local FIXTURE_FILES = {

    ["java/Foo.lua"] = table.concat({
        "---@meta _",
        "",
        "---@class Foo: Base, Baz",
        "---@field bar number",
        "local __Foo = {}",
        "",
        "---@return Bar",
        "function __Foo:transform(a) end",
        "",
        "---@return Bar",
        "function __Foo:transform(a, b) end",
        "",
        "Foo = Foo or {}",
        "",
    }, "\n"),

    ["java/Base.lua"] = table.concat({
        "---@meta _",
        "",
        "---@class Base",
        "---@field baseHP number",
        "local __Base = {}",
        "",
        "function __Base:baseMethod(x) end",
        "",
        "---@return Data",
        "function __Base:getThing() end",
        "",
        "---@return number",
        "function __Base:getNum(x) end",
        "",
        "---@return Data[]",
        "function __Base:getMany() end",
        "",
        "---@return number",
        "---@return Data",
        "function __Base:getLoose() end",
        "",
        "---@return Baz",
        "function __Base:getHelper() end",
        "",
        "Base = Base or {}",
        "",
    }, "\n"),

    ["java/Baz.lua"] = table.concat({
        "---@meta _",
        "",
        "---@class Baz",
        "local __Baz = {}",
        "",
        "function __Baz:bazOnly() end",
        "",
        "---@return number",
        "function __Baz:getCount() end",
        "",
        "---@return Data",
        "function __Baz:getPayload() end",
        "",
    }, "\n"),

    ["java/Data.lua"] = table.concat({
        "---@meta _",
        "",
        "---@class Data",
        "---@field alarm boolean",
        "---@field name string",
        "local __Data = {}",
        "",
    }, "\n"),

    ["lua/shared/env.lua"] = table.concat({
        "---@meta",
        "",
        "---@param x number",
        "---@param n number",
        "---@return number",
        "function round(x, n) end",
        "",
        "---@param sep string",
        "---@param s string",
        "---@return string[]",
        "function strsplit(sep, s) end",
        "",
    }, "\n"),
    -- mirrors: the canonical clone's library/events.lua SHAPE (Task 4;

    ["events.lua"] = table.concat({
        "---@meta _",
        "Events = {}",
        "",
        "---OnFoo: fixture event.",
        "Events.OnFoo = {",
        "\t---@param callback fun()",
        "\tAdd = function(callback) end,",
        "\t---@param callback fun(callback)",
        "\tRemove = function(callback) end,",
        "}",
        "",
        "---OnBar: fixture event.",
        "Events.OnBar = {",
        "\t---@param callback fun()",
        "\tAdd = function(callback) end,",
        "\t---@param callback fun(callback)",
        "\tRemove = function(callback) end,",
        "}",
        "",
    }, "\n"),
}

function Umbrella._fixture(dir)
    local lib = dir .. "/library"
    local dirs = {
        lib,
        lib .. "/java",
        lib .. "/lua",
        lib .. "/lua/shared",
    }
    for _, d in ipairs(dirs) do
        if WINDOWS then
            os.execute('mkdir "' .. winPath(d) .. '" 2>nul')
        else
            os.execute('mkdir -p "' .. d .. '" 2>/dev/null')
        end
    end
    for rel, content in pairs(FIXTURE_FILES) do
        local f = io.open(lib .. "/" .. rel, "wb")
        if f then
            f:write(content)
            f:close()
        end
    end
    return dir
end

_G.Umbrella = Umbrella
return Umbrella
