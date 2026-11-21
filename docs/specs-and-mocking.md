# Writing Specs, Mocking, and Strict Mode

This guide covers how `pz_lua_testkit` discovers spec files, the `pzspec` testing DSL, mocking and spying, the mod-mode `testkit` API, and `PZ_STRICT=1` rules.

## Spec File Discovery

In mod mode (`--mod <dir>`), the runner scans `<modDir>/TESTS/` by default, picking up files matching `TESTS/**/*_spec.lua`.

Under the hood, `collectSpecs` resolves each entry in the target list:

- If the path opens as a file, it is added directly.
- Otherwise, the path is treated as a directory and scanned recursively for files ending in `_spec.lua`.
- Paths are normalized (`\` to `/`, trailing `/` and leading `./` stripped), deduplicated, and sorted lexicographically before execution.

Files not ending in `_spec.lua` are ignored by directory discovery. Passing explicit spec paths on the CLI (or via `PZ_SPECS`) overrides the default `TESTS/` scan.

---

## `pzspec` DSL

`pzspec` provides a Mocha/Jest-style DSL as globals (`describe`, `it`, `xit`, `xdescribe`, `before_each`, `after_each`, `before_all`, `after_all`, `expect`, `expect_eq`, `mock`, `spy`, `spyOn`).

### Suites, Tests, and Skipping

```lua
describe("InventoryHelper", function()
    describe("stacking", function()
        it("merges identical items", function()
            expect(1 + 1).toBe(2)
        end)

        xit("skips unfinished case", function()
        end)
    end)
end)

xdescribe("temporarily disabled suite", function()
end)
```

- Nested `describe` blocks flatten their suite labels with `" > "` (for example, `"InventoryHelper > stacking"`).
- `xit` and `xdescribe` are no-op functions for temporarily skipping tests or suites.

### Lifecycle Hooks

- `before_each(fn)` / `after_each(fn)`: run before and after each `it` in the current suite, including hooks inherited from enclosing `describe` blocks (collected outer-to-inner). `after_each` still runs via `pcall` if the test body errors.
- `before_all(fn)` / `after_all(fn)`: run once before and once after all tests in the current suite.

```lua
describe("craft queue", function()
    local queue

    before_all(function()
    end)

    before_each(function()
        queue = {}
    end)

    after_each(function()
        queue = nil
    end)

    after_all(function()
    end)

    it("starts empty", function()
        expect(#queue).toBe(0)
    end)
end)
```

### Assertions (`expect` and `expect_eq`)

`expect(actual)` returns a matcher table with the following methods:

| Matcher | Behavior |
| --- | --- |
| `.toBe(expected)` | Strict equality (`actual == expected`). |
| `.toEqual(expected)` | Recursive deep equality for tables and primitives. |
| `.toBeNil()` | Passes when `actual == nil`. |
| `.toBeTruthy()` | Passes when `actual` is neither `false` nor `nil`. |
| `.toBeFalsy()` | Passes when `actual` is `false` or `nil`. |
| `.toContain(item)` | On a string: plain substring search (`find(item, 1, true)`). On a table: `deepEqual` match against any value in `pairs(actual)`. |
| `.toBeCloseTo(expected, eps)` | Numeric check `math.abs(actual - expected) <= eps` (`eps` defaults to `1e-6`). |
| `.toThrow()` | Calls `actual()` via `pcall` and fails if it does not raise an error. |

Standalone helper:

- `expect_eq(actual, expected, msg)`: checks `deepEqual(actual, expected)` and fails with optional prefix `msg`.

### Mocking and Spying (`mock`, `spy`, `spyOn`)

`mock(impl)` (also aliased as `spy`) creates a callable table that records every invocation in `.calls`:

```lua
local fn = mock(function(a, b)
    return a + b
end)

local sum = fn(2, 3)
expect(sum).toBe(5)
expect(#fn.calls).toBe(1)
expect(fn.calls[1].n).toBe(2)
expect(fn.calls[1][1]).toBe(2)
expect(fn.calls[1][2]).toBe(3)
```

- Each entry `calls[i]` is `{ n = select("#", ...), ... }`, where `n` is the argument count and `calls[i][1]`, `calls[i][2]`, ... are the positional arguments (preserving `nil` holes).
- When `impl` is omitted (`mock()`), calls are recorded and return `nil`.
- `m.fn` holds the underlying Lua function (`type(m.fn) == "function"`), which is needed when passing a mock to code that checks `type(cb) == "function"` (since `type(m) == "table"`).

`spyOn(obj, name)` replaces `obj[name]` with a `mock` wrapping the original value and adds `.restore()`:

```lua
local s = spyOn(player, "Say")
player:Say("hello")
expect(#s.calls).toBe(1)
s.restore()
```

---

## `testkit` API (Mod Mode Only)

When running in mod mode (`--mod`), the runner replaces `_G.require` with the contract loader and exposes `_G.testkit`:

| API | Description |
| --- | --- |
| `testkit.provide(name, value)` | Seeds a persistent module entry (`provided:<name>`) that takes precedence over disk lookup and survives `testkit.resetLoaded()`. Use this to stub optional or dependency mods. |
| `testkit.keep(name)` | Marks an already-loaded module as persistent so its cached return value survives `testkit.resetLoaded()`. |
| `testkit.resetLoaded()` | Clears non-persistent entries from the `require` cache and clears every stub-created `Events` / `Hook` dispatcher regardless of key name (factory-identity based — hand-built event-like tables parked on the registries are NOT cleared; the known event-name allowlist is preserved). |
| `testkit.std_require(name)` | Calls Lua's original `require` directly, bypassing the mod `require` cache. |

> **Important (`testkit.keep` and event listeners):** `keep()` preserves the module **cache entry only**. Any `Events.*` or `Hook.*` listeners registered at module load time are still cleared by `testkit.resetLoaded()`. Register listeners inside a dedicated init function or re-register them in `before_each`.

### `PZ_RESET_PER_TEST`

In mod mode, `reset_per_test` defaults to `true`: the runner registers a global `before_each` hook that calls `testkit.resetLoaded()` before every test so each test starts with a clean `require` cache and event listener state (while `provide()` and `keep()` entries remain).

- `PZ_RESET_PER_TEST=0`: disables automatic per-test reset (for example, when testing module-cache reuse across tests).
- `PZ_RESET_PER_TEST=1`: enables automatic per-test reset (no effect when mod mode is off).

---

## `PZ_STRICT=1` Behavior and Strict-Safe Mod Patterns

Setting `PZ_STRICT=1` arms two read-time guards after stubs and the mod loader initialize, and **before** mod files auto-execute and specs run:

1. **Unknown-global guard**: reading an undefined global raises `PZ_STRICT: unknown global '<name>'`. Top-level assignments remain allowed because the guard only intercepts reads (`__index`).
2. **Strict-events guard**: reading `Events.OnX` or `Hook.OnX` for a name outside the known-event allowlist raises `PZ_STRICT: unknown PZ event 'Events.OnX'` (or `'Hook.OnX'`).

### Strict-Safe Patterns in Mod Code

Because mod files auto-execute in engine load order (`shared` -> `client` -> `server`, or `shared` -> `server` in `server` ctx), globals defined in later files are still `nil` while earlier files load.

1. **Guarding shared namespace tables at top level**

   Writing `MyMod = MyMod or {}` reads `MyMod` before assigning it, which triggers `PZ_STRICT: unknown global 'MyMod'` if it has not been created yet. Use `rawget`:

   ```lua
   MyMod = rawget(_G, "MyMod") or {}
   ```

2. **Registering custom events before subscribing**

   Register custom events with `LuaEventManager.AddEvent(name)` before reading `Events.<name>`:

   ```lua
   LuaEventManager.AddEvent("OnMyModInitialized")
   Events.OnMyModInitialized.Add(function()
   end)
   ```

   `LuaEventManager.AddEvent` is idempotent, adds the event name to the strict allowlist, and pre-creates `Events[name]`.
