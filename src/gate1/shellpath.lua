-- shellpath.lua — single source of the per-OS shell quoting shared by every
-- directory-listing probe (modloader, discovery, pzrequire, umbrella,
-- check_globals). Windows cmd.exe: convert to backslashes, reject the
-- quote/newline/pipe/ampersand/caret/percent metacharacters (a quoted
-- cmd.exe token cannot escape the parser, and % would expand), wrap in
-- double quotes. POSIX: single-quote with the '\'' escape.
--
-- Loadable standalone: dofile(...) returns { quote = quoteShellPath }.

local function quoteShellPath(p)
    if package.config:sub(1, 1) == "\\" then
        p = p:gsub("/", "\\")
        if p:match('["\r\n|&^%%]') then return nil end
        return '"' .. p .. '"'
    end
    return "'" .. p:gsub("'", "'\\''") .. "'"
end

return {
    quote = quoteShellPath,
}
