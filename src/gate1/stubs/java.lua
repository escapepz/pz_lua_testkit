-- java.lua — java/stdlib stub pack for gate1 (loaded via PZ_STUB_PACKS=java)
--
-- Clean-room: every function here is OUR implementation. The semantics are
-- ALIGNED to the real gate2 VM (PZ Kahlua), probed on the real jar 2026-11-12
-- — where the real VM already provides a member, its observed semantics below
-- are authoritative (see SURFACE.md "## gate2 alignment notes" for the full
-- decision log and probe evidence):
--
--   table.isempty(t)   real gate2 (TableLib): true iff t has no entries;
--                      errors on non-table args.
--   table.wipe(t)      real gate2: clears t IN PLACE and returns NOTHING
--                      (nil) — deliberately NOT "returns t" as the plan text
--                      said; the real VM decides.
--   table.newarray(...) real gate2: fresh array seeded with the args —
--                      newarray() -> {}, newarray(5) -> {5} (arg is a VALUE,
--                      not capacity), newarray(1,2,3) -> {1,2,3}.
--   table.getn(t)      real gate2 does NOT have table.getn (probed nil). This
--                      pack provides it as a Lua-5.0-compat alias of #t —
--                      gate1-only surface. (tools/lua5.1.exe also ships a
--                      native 5.0-compat getn with the same semantics, so the
--                      overwrite is invisible.)
--   string.trim(s)     real gate2 (StringLib): strips leading/trailing
--                      whitespace; numbers are coerced via the converter
--                      ("5"); other non-strings error.
--   string.split(s, sep) real gate2: Java String.split semantics — sep acts
--                      as a regex, ALL trailing empty parts are dropped
--                      (",a," -> {"", "a"}, "a,," -> {"a"}, ",," -> {}),
--                      empty input -> {""}, empty sep -> per-char, nil /
--                      non-string args error (numbers coerced). The pack
--                      treats sep as a LUA PATTERN, which reproduces every
--                      probed real behavior (including regex-meta "." ->
--                      {}); Java-regex syntax beyond simple separators
--                      cannot be replicated in Lua and is a documented
--                      residual divergence.
--   string.contains(s, sub) real gate2: literal substring test (Java
--                      String.contains); empty needle -> true; numbers
--                      coerced; nil/other non-strings error.
--
--   ArrayList / HashMap / Vector2f / Vector3f — absent in the bare gate2 env
--   (the Java exposer lands in Phase 6). The pack implements Java's real
--   contracts so Phase 6 parity validates against them: 0-indexed get with
--   IndexOutOfBounds-style throws, put() returning the previous value, get()
--   nil on miss, zero-arg Vector constructors.
--
-- Plain Lua tables and closures only — no metatable magic. Written without
-- the `next` global (absent in Kahlua) so the file itself stays loadable on
-- both gates, even though only gate1's runner ever loads it. Loading twice is
-- idempotent: plain global reassignment, no load-time state.

function table.isempty(t)
    if type(t) ~= "table" then
        error("bad argument #1 to 'isempty' (table expected, got "
            .. type(t) .. ")", 2)
    end
    for _ in pairs(t) do return false end
    return true
end

function table.wipe(t)
    if type(t) ~= "table" then
        error("bad argument #1 to 'wipe' (table expected, got "
            .. type(t) .. ")", 2)
    end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    for i = 1, #keys do t[keys[i]] = nil end
    return nil
end

function table.newarray(...)
    return { ... }
end

function table.getn(t)
    return #t
end

local function stringArg(fnName, pos, v)
    if type(v) == "string" then return v end
    if type(v) == "number" then return tostring(v) end
    error("bad argument #" .. pos .. " to '" .. fnName
        .. "' (string expected, got " .. type(v) .. ")", 3)
end

function string.trim(s)
    s = stringArg("trim", 1, s)
    return (s:match("^%s*(.-)%s*$"))
end

function string.split(s, sep)
    s = stringArg("split", 1, s)
    sep = stringArg("split", 2, sep)
    if s == "" then return { "" } end
    if sep == "" then
        local chars = {}
        for i = 1, #s do chars[i] = s:sub(i, i) end
        return chars
    end
    local parts = {}
    local pos = 1
    while pos <= #s + 1 do
        local mStart, mEnd = s:find(sep, pos)
        if mStart then
            parts[#parts + 1] = s:sub(pos, mStart - 1)
            if mEnd < mStart then
                pos = mStart + 1
            else
                pos = mEnd + 1
            end
        else
            parts[#parts + 1] = s:sub(pos, #s)
            break
        end
    end
    while #parts > 0 and parts[#parts] == "" do
        parts[#parts] = nil
    end
    return parts
end

function string.contains(s, sub)
    s = stringArg("contains", 1, s)
    sub = stringArg("contains", 2, sub)
    return s:find(sub, 1, true) ~= nil
end

local function newList()
    local items = {}
    local list = {}
    function list:add(v)
        items[#items + 1] = v
        return self
    end
    function list:get(i)
        if type(i) ~= "number" or i ~= math.floor(i)
            or i < 0 or i >= #items then
            error("IndexOutOfBoundsException: Index: " .. tostring(i)
                .. ", Size: " .. #items)
        end
        return items[i + 1]
    end
    function list:size() return #items end
    function list:isEmpty() return #items == 0 end
    function list:contains(v)
        for _, item in ipairs(items) do
            if item == v then return true end
        end
        return false
    end
    return list
end

local function newMap()
    local store = {}
    local map = {}
    function map:put(k, v)
        local previous = store[k]
        store[k] = v
        return previous
    end
    function map:get(k)
        return store[k]
    end
    function map:containsKey(k)
        return store[k] ~= nil
    end
    function map:size()
        local n = 0
        for _ in pairs(store) do n = n + 1 end
        return n
    end
    return map
end

local function newVector(dims)
    return function(x, y, z)
        local v = {
            x = x or 0,
            y = y or 0,
            z = z or 0,
        }
        function v:length()
            local sum = v.x * v.x + v.y * v.y
            if dims == 3 then sum = sum + v.z * v.z end
            return math.sqrt(sum)
        end
        function v:lengthSquared()
            local sum = v.x * v.x + v.y * v.y
            if dims == 3 then sum = sum + v.z * v.z end
            return sum
        end
        return v
    end
end

_G.ArrayList = { new = newList }
_G.HashMap = { new = newMap }
_G.Vector2f = { new = newVector(2) }
_G.Vector3f = { new = newVector(3) }
