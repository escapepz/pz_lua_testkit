-- Usage:
--   lua5.1.exe src/check/sweep_consumers.lua <workspace-root> [...]
--   (each arg = a mod workspace dir holding TESTS/run.lua; zero args ->
--   usage, exit 2). One fresh child per workspace: <arg[-1]> <root>/TESTS/
--   run.lua — arg[-1] in script mode is the absolute path of the invoking
--   interpreter, so children run on the same interpreter; stdout+stderr
--   captured via io.popen(cmd .. " 2>&1").
-- Exit codes: 0 all workspaces green, 1 any workspace not green (child's
-- tail lines printed for diagnosis), 2 usage error (zero args).

local M = {}

local function os_is_windows()
    return package.config:sub(1, 1) == "\\"
end

local function quote_cmd(windows, path)
    if windows then return '"' .. path .. '"' end
    return "'" .. path .. "'"
end

M.parse_total = function(output)
    local tok = type(output) == "string" and output:match("total=(%d+)") or nil
    if tok == nil then return nil end
    return tonumber(tok)
end

M.is_all_pass = function(output)
    return type(output) == "string" and output:find("ALL PASS", 1, true) ~= nil
end

M.shim_path = function(root)
    return (root:gsub("\\", "/"):gsub("/+$", "")) .. "/TESTS/run.lua"
end

M.display_name = function(root)
    return (root:gsub("\\", "/"):gsub("/+$", "")):match("[^/]+$") or root
end

local TAIL_LINES = 20

local function tail_lines(out, n)
    local lines = {}
    for line in out:gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
    end
    for i = math.max(1, #lines - n + 1), #lines do
        print("  | " .. lines[i])
    end
end

local function main(args)
    if #args == 0 then
        io.stderr:write("sweep_consumers: no workspace roots given\n"
            .. "usage: lua5.1.exe src/check/sweep_consumers.lua"
            .. " <workspace-root> [...]\n"
            .. "  (each root holds TESTS/run.lua; exit 0 all green,"
            .. " 1 any not green, 2 usage)\n")
        return 2
    end
    local interp = arg and arg[-1]
    if type(interp) ~= "string" or interp == "" then
        io.stderr:write("sweep_consumers: interpreter path unknown"
            .. " (arg[-1] missing — run as a script)\n")
        return 2
    end
    local windows = os_is_windows()
    local any_fail = false
    for _, root in ipairs(args) do
        local shim = M.shim_path(root)
        local name = M.display_name(root)
        local f = io.open(shim, "r")
        if not f then
            any_fail = true
            print("fail " .. name .. ": no TESTS/run.lua at " .. shim)
        else
            f:close()
            local cmd = quote_cmd(windows, interp) .. " "
                .. quote_cmd(windows, shim)
            -- cmd.exe /c strips the FIRST and LAST quote of a command that
            -- starts with a quote — a bare `"interp" "script"` collapses into
            -- one broken token. Doubling the outer quotes survives the strip
            -- (classic cmd /c rule; the old sweep dodged it by starting with
            -- `set "K=V"`). `2>&1` stays outside the doubled pair.
            local wrapped = windows and ('"' .. cmd .. '"') or cmd
            local handle = io.popen(wrapped .. " 2>&1")
            local out = ""
            if handle then
                out = handle:read("*a") or ""
                handle:close()
            end
            local total = M.parse_total(out)
            if total ~= nil and total >= 1 and M.is_all_pass(out) then
                print(string.format("ok %s total=%d", name, total))
            else
                any_fail = true
                print("fail " .. name .. " total="
                    .. (total ~= nil and tostring(total) or "none")
                    .. " (need total >= 1 and ALL PASS)")
                tail_lines(out, TAIL_LINES)
            end
        end
    end
    return any_fail and 1 or 0
end

local a0 = arg and arg[0]
if type(a0) == "string" and a0:match("sweep_consumers%.lua$") then
    os.exit(main(arg))
end

return M
