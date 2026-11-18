local function failResult(label, path, err, write)
    (write or print)(label .. " " .. path .. ": " .. tostring(err))
    return { total = 0, passed = 0, failed = 1, ok = false }
end

local function summarize(ok, stats)
    return {
        total = stats.total,
        passed = stats.passed,
        failed = stats.failed,
        ok = ok,
    }
end

local function exitCode(result)
    return result.ok and 0 or (result.total == 0 and result.failed == 0 and 2 or 1)
end

return {
    fail_result = failResult,
    summarize = summarize,
    exit_code = exitCode,
}
