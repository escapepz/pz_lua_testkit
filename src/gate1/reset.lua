local function wirePerTest(pzspec, enabled)
    if not enabled then
        return false
    end
    if type(pzspec) ~= "table"
        or type(pzspec.global_before_each) ~= "function" then
        return false
    end
    pzspec.global_before_each(function()
        local tk = rawget(_G, "testkit")
        if type(tk) == "table" and type(tk.resetLoaded) == "function" then
            tk.resetLoaded()
        end
    end)
    return true
end

return {
    wire_per_test = wirePerTest,
}
