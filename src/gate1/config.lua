-- Windows `cmd.exe` (`set PZ_CTX=`) produces `""` (truthy in Lua 5.1); normalize `""` to nil.
local function envValue(name, env_fn)
    local get = env_fn or os.getenv
    local v = get(name)
    if v == "" then return nil end
    return v
end

local function splitEnv(name, sep, env_fn)
    local out = {}
    local env = envValue(name, env_fn)
    if env then
        for entry in env:gmatch("[^" .. sep .. "]+") do
            table.insert(out, entry)
        end
    end
    return out
end

local function resolveResetPerTest(config, env_fn)
    config = config or {}
    if config.reset_per_test ~= nil then
        return (config.reset_per_test == true)
    end
    local env = envValue("PZ_RESET_PER_TEST", env_fn)
    if env ~= nil then
        return (env == "1")
    end
    return (config.mod ~= nil)
end

local function resolveConfig(config, env_fn)
    config = config or {}

    local ctx = config.ctx
    if ctx == nil then ctx = envValue("PZ_CTX", env_fn) end
    if ctx == nil then ctx = "sp" end
    local strict = false
    if config.strict ~= nil then
        strict = (config.strict == true)
    else
        strict = (envValue("PZ_STRICT", env_fn) == "1")
    end
    local stubPacks = config.stub_packs or splitEnv("PZ_STUB_PACKS", ",", env_fn)
    local stubDirs = config.stubs or splitEnv("PZ_STUBS", ";", env_fn)
    local extraPath = config.lua_path or splitEnv("PZ_LUA_PATH", ";", env_fn)
    local specArgs = config.specs or splitEnv("PZ_SPECS", ";", env_fn)
    local umbrella = config.umbrella
    if umbrella == nil then umbrella = envValue("PZ_UMBRELLA", env_fn) end
    local mod = config.mod
    local modPath = config.mod_path
    if modPath == nil then
        modPath = splitEnv("PZ_MOD_PATH", ";", env_fn)
    end
    local resetPerTest = resolveResetPerTest(config, env_fn)
    return {
        ctx = ctx,
        strict = strict,
        stub_packs = stubPacks,
        stubs = stubDirs,
        lua_path = extraPath,
        specs = specArgs,
        umbrella = umbrella,
        mod = mod,
        mod_path = modPath,
        reset_per_test = resetPerTest,
    }
end

return {
    env_value = envValue,
    split_env = splitEnv,
    resolve_reset_per_test = resolveResetPerTest,
    resolve = resolveConfig,
}
