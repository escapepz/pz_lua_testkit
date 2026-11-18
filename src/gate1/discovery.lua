local function scanDir(dir, out)
    out = out or {}
    local cmd
    if package.config:sub(1, 1) == "\\" then
        cmd = 'dir /b /s "' .. dir .. '"'
    else
        cmd = 'find "' .. dir .. '" -name "*_spec.lua" -type f'
    end
    local p = io.popen(cmd)
    if not p then return out end
    for line in p:lines() do
        line = line:gsub("%s+$", "")
        if line:match("_spec%.lua$") then
            table.insert(out, line)
        end
    end
    p:close()
    return out
end

local function normalizeSpecKey(p)
    local k = p:gsub("\\", "/")
    k = k:gsub("/+$", "")
    k = k:gsub("^%./", "")
    return k
end

local function resolveSpecPath(p, out, seen)
    local f = io.open(p, "r")
    if f then
        f:close()
        local key = normalizeSpecKey(p)
        if not seen[key] then
            seen[key] = true
            table.insert(out, p)
        end
    else
        for _, s in ipairs(scanDir(p)) do
            local key = normalizeSpecKey(s)
            if not seen[key] then
                seen[key] = true
                table.insert(out, s)
            end
        end
    end
end

local function collectSpecs(list)
    local specs = {}
    local seen = {}
    for _, a in ipairs(list) do
        resolveSpecPath(a, specs, seen)
    end
    return specs
end

return {
    scan_dir = scanDir,
    normalize_spec_key = normalizeSpecKey,
    resolve_spec_path = resolveSpecPath,
    collect_specs = collectSpecs,
}
