local quoteShellPath = dofile(
    (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".")
        .. "/shellpath.lua").quote

local function dirEntries(dir)
    local q = quoteShellPath(dir)
    if not q then return nil end
    local cmd
    if package.config:sub(1, 1) == "\\" then
        cmd = "dir /b " .. q .. " 2>nul"
    else
        cmd = "ls -1 " .. q .. " 2>/dev/null"
    end
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

local function dirExists(dir)
    local entries = dirEntries(dir)
    return entries ~= nil and #entries > 0
end

local function fileExists(path)
    local f = io.open(path, "r")
    if f then
        local _, rerr = f:read(1)
        f:close()
        return rerr == nil
    end
    return false
end

local function absPath(p)
    if p:match("^%a:[/\\]") or p:match("^[/\\]") then
        p = p:gsub("\\", "/")
    else
        local pp = io.popen(package.config:sub(1, 1) == "\\" and "cd" or "pwd")
        if not pp then return p end
        local cwd = pp:read("*l") or ""
        pp:close()
        cwd = cwd:gsub("%s+$", ""):gsub("\\", "/")
        if cwd == "" then return p end
        p = cwd .. "/" .. p:gsub("\\", "/")
    end
    local root = ""
    if p:sub(1, 1) == "/" then root = "/" end
    local parts = {}
    for seg in p:gmatch("[^/]+") do
        if seg == ".." and #parts > 0 and parts[#parts] ~= ".." then
            parts[#parts] = nil
        elseif seg ~= "." then
            parts[#parts + 1] = seg
        end
    end
    return root .. table.concat(parts, "/")
end

local function numericVersionDir(base)
    local best, bestN = nil, nil
    for _, name in ipairs(dirEntries(base) or {}) do
        if name:match("^%d+$") then
            local n = tonumber(name)
            if n and (bestN == nil or n > bestN) then
                best, bestN = name, n
            end
        end
    end
    return best
end

local function listLuaFiles(dir)
    local out = {}
    local q = quoteShellPath(dir)
    if not q then return out end
    local cmd
    if package.config:sub(1, 1) == "\\" then
        cmd = "dir /b /s /a:-d " .. q .. " 2>nul"
    else
        cmd = "find " .. q .. ' -name "*.lua" -type f 2>/dev/null'
    end
    local p = io.popen(cmd)
    if p then
        for line in p:lines() do
            line = line:gsub("%s+$", "")
            if line:match("%.lua$") then
                table.insert(out, (line:gsub("\\", "/")))
            end
        end
        p:close()
    end
    return out
end

local function readModInfoDeps(path)
    local deps = {}
    local f = io.open(path, "r")
    if not f then return deps end
    for line in f:lines() do
        line = line:gsub("%s+$", "")
        local value = line:match("^require=(.*)$")
        if value then
            for tok in value:gmatch("[^,;]+") do
                tok = tok:match("^%s*(.-)%s*$")
                tok = tok:gsub("^\\+", "")
                if tok ~= "" then
                    table.insert(deps, tok)
                end
            end
        end
    end
    f:close()
    return deps
end

local function resolveModLayout(base)
    if fileExists(base .. "/mod.info") then
        return { base }, base .. "/mod.info"
    end
    local versionDir = numericVersionDir(base)
    local versionInfo = versionDir ~= nil
        and fileExists(base .. "/" .. versionDir .. "/mod.info")
    if fileExists(base .. "/common/mod.info") or versionInfo then
        local layoutDirs = {}
        if dirExists(base .. "/common") then
            layoutDirs[#layoutDirs + 1] = base .. "/common"
        end
        if versionDir ~= nil and dirExists(base .. "/" .. versionDir) then
            layoutDirs[#layoutDirs + 1] = base .. "/" .. versionDir
        end
        local infoPath = versionInfo
            and (base .. "/" .. versionDir .. "/mod.info")
            or (base .. "/common/mod.info")
        return layoutDirs, infoPath
    end
    return nil
end

local function prepare_mod(mod_dir, ctx, mod_path)
    if type(mod_dir) ~= "string" or mod_dir == "" then
        print("PZ_MOD: mod.info not found in '" .. tostring(mod_dir) .. "'")
        return nil
    end
    local base = mod_dir:gsub("\\", "/")
    base = base:gsub("/+$", "")
    base = absPath(base)

    local layoutDirs, infoPath = resolveModLayout(base)
    if not layoutDirs then
        print("PZ_MOD: mod.info not found in '" .. base .. "'")
        return nil
    end

    -- require ROOTS: sub-major {shared, client, server} — client registered
    -- even on dedicated (engine adds client/ to paths unconditionally,
    -- LuaManager.java:1138-1141); each sub scans the layout dirs
    -- common-before-version; deduped, only when <dir>/media/lua/<sub> exists
    local roots, seenRoot = {}, {}
    for _, sub in ipairs({ "shared", "client", "server" }) do
        for _, d in ipairs(layoutDirs) do
            local cand = d .. "/media/lua/" .. sub
            if dirExists(cand) and not seenRoot[cand] then
                seenRoot[cand] = true
                roots[#roots + 1] = cand
            end
        end
    end

    -- auto-exec LOAD ORDER: ctx "server" -> {shared, server} (dedicated never
    -- executes client/ — LoadDirBase checksum-only), ctx sp/client -> {shared,
    -- client, server}; per (mod, sub) the common batch precedes the version
    -- batch (LuaManager.java:1161-1180) and each batch sorts CASE_INSENSITIVE_
    -- ORDER — kept per-batch (not merged across layout dirs) so the pinned
    -- common-before-version order holds regardless of file names
    local loadSubs
    if ctx == "server" then
        loadSubs = { "shared", "server" }
    else
        loadSubs = { "shared", "client", "server" }
    end
    local load_files = {}
    for _, sub in ipairs(loadSubs) do
        for _, d in ipairs(layoutDirs) do
            local dir = d .. "/media/lua/" .. sub
            if dirExists(dir) then
                local batch = listLuaFiles(dir)
                table.sort(batch, function(x, y)
                    return x:lower() < y:lower()
                end)
                for _, f in ipairs(batch) do
                    load_files[#load_files + 1] = f
                end
            end
        end
    end

    local spec_dirs = {}
    if dirExists(base .. "/TESTS") then
        spec_dirs[#spec_dirs + 1] = base .. "/TESTS"
    end

    local deps = readModInfoDeps(infoPath)
    local searchDirs = (type(mod_path) == "table") and mod_path or {}
    for _, tok in ipairs(deps) do
        local depDirs = nil
        local rejected = tok == "." or tok == ".."
            or tok:find("/", 1, true) ~= nil
            or tok:find("\\", 1, true) ~= nil
            or tok:find(":", 1, true) ~= nil
            or tok:find('"', 1, true) ~= nil
        if rejected then
            print("PZ_MOD: dependency '" .. tok
                .. "' is not a bare mod ID, skipped")
        else
            for _, searchDir in ipairs(searchDirs) do
                local sdir = tostring(searchDir):gsub("\\", "/")
                sdir = sdir:gsub("/+$", "")
                if sdir ~= "" then
                    depDirs = resolveModLayout(absPath(sdir .. "/" .. tok))
                    if depDirs then break end
                end
            end
        end
        if depDirs then
            for _, sub in ipairs({ "shared", "client", "server" }) do
                for _, d in ipairs(depDirs) do
                    local cand = d .. "/media/lua/" .. sub
                    if dirExists(cand) and not seenRoot[cand] then
                        seenRoot[cand] = true
                        roots[#roots + 1] = cand
                    end
                end
            end
        elseif not rejected then
            print("PZ_MOD: dependency '" .. tok .. "' not found in PZ_MOD_PATH")
        end
    end

    return {
        roots = roots,
        load_files = load_files,
        spec_dirs = spec_dirs,
        deps = deps,
    }
end

return {
    prepare_mod = prepare_mod,
}
