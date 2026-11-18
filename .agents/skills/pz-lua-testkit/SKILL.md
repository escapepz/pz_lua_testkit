---
name: pz-lua-testkit
description: Write and run pzspec tests for a Project Zomboid B42 mod with pz_lua_testkit - setup, conventions, error decoding, failure-first workflows
---

# pz_lua_testkit skill — writing pzspec tests for Project Zomboid B42 mods

For coding agents working in a mod repo that integrates pz_lua_testkit. This file is
procedural, not reference: it is an execution loop plus hard invariants and an
error-decode table. Human-facing docs live in the testkit README; the mock-surface
inventory lives in `src/gate1/stubs/SURFACE.md` (read it when this file points you there).

## Part 1 — The 6 invariants (never violate these)

1. **Stub-by-default.** The mod's `mod.info` `require=` deps are NOT loaded. A dep name
   resolves to: `testkit.provide()`-seeded entry → own/dep roots (only when
   `PZ_MOD_PATH` is configured) → soft-fail `nil` + one warn line. To test code that
   needs a dep, either `testkit.provide("dep_name", fake_table)` in the spec (or in
   `before_each`), or run with `PZ_MOD_PATH` pointing at the real dep's workspace.
2. **Strict-safe reads.** Possibly-absent globals MUST be read as
   `rawget(_G, "Name") or default`. NEVER `(Name or default)` — under `PZ_STRICT=1` the
   bare read hits the unknown-global guard and raises `PZ_STRICT: unknown global 'Name'`.
   This applies to mod code under test AND to spec code. Plain top-level ASSIGNMENT is
   always free (the guard is read-only).
3. **Reset asymmetry.** With `reset_per_test` (default ON in mod mode), every test
   starts with: require cache cleared (except `testkit.keep()`-marked and
   `testkit.provide()`-seeded entries) and every `^On` dispatcher on `Events`/`Hook`
   Cleared — but top-level `_G` tables created during mod auto-exec SURVIVE. Register
   event listeners inside functions or re-register in `before_each`; reset any global
   table's state in `before_each` yourself.
4. **Mock packs are OPT-IN.** `PZ_STUB_PACKS=game,java` loads the shipped clean-room
   packs. Without the flag those globals don't exist (strict mode will tell you).
   Before inventing a mock, look the class up in `src/gate1/stubs/SURFACE.md` — if it's
   there, enable the pack instead of hand-rolling.
5. **Strict mode is your typo net, not an obstacle.** `PZ_STRICT=1` turns unknown
   globals and unknown `Events.OnX`/`Hook.OnX` names into instant errors. When a strict
   error fires: fix the spelling, add the missing stub, or switch to `rawget` — NEVER
   disable strict mode to make a failure go away.
6. **Testkit-scope blockers escalate, never self-patch.** When a blocker's fix belongs
   in the testkit repo, STOP: do not edit the testkit checkout (any resolved copy), do
   not hack around it silently in the mod. Report per Part 6 and let your human decide.

## Part 2 — The execution loop (do these in order)

1. **Resolve the entry.** The workspace runs tests through its own `TESTS/run.lua`
   (single-file integration). Find the testkit checkout the way `TESTS/run.lua` does:
   `PZ_TESTKIT` env → `<workspace>/node_modules/pz_lua_testkit` →
   `<workspace>/.pz_testkit/<tag>` → sibling guesses. Read the `RECIPE` table in
   `TESTS/run.lua` first — it declares this mod's `mod`, `specs`, `mod_path`, `ctx`,
   `stub_packs`, `strict`, `reset_per_test`, and (optionally) `EXPECTED_TOTAL`.
2. **Map the surface before writing tests.** Run the static scanner from the testkit
   root: `tools/lua5.1.exe src/check/check_globals.lua <mod-lua-dir> [--stdlib]`. It
   walks Lua 5.1 bytecode and lists every global read/write and `Events.<Name>` use —
   including branches that never execute in your tests — with exact line numbers
   (exit 0 clean / 1 findings / 2 usage). Use the report to decide which stubs/packs
   the specs need and which globals are mod-owned vs game-owned.
3. **Write the spec.** Files: `TESTS/**/*_spec.lua` (the naming IS the contract —
   anything else is not collected). DSL: `describe(name, fn)` / `it(name, fn)` /
   `before_each(fn)` / `after_each(fn)` / `before_all` / `after_all`; matchers
   `expect(x): toBe / toEqual / toBeNil / toBeTruthy / toBeFalsy / toContain /
toBeCloseTo / toThrow`; `mock(fn)` records calls (`m.calls[1][1]` = first arg of the
   first call); `spyOn(obj, "method")` + `s.restore()`. Keep one `describe` per
   behavior; use `before_each` for state construction, never file top-level.
4. **Run + read.** `<lua5.1.exe> TESTS/run.lua` (from the workspace root). Exit codes:
   0 all green, 1 test/spec-load failures, 2 zero specs collected or setup error. For a
   bug fix, RED-GREEN: first write an `it()` that reproduces the bug, run it, and
   confirm it FAILS (exit 1) before touching mod source — then make it green. Never
   adjust a test's expectation just to reach green; adjust code, or justify a behavior
   change to your human.
5. **Escalate to gate 2 only for Kahlua2 deltas.** Gate 1 (this loop) covers ~all mod
   logic. The real-VM gate exists for Kahlua2-specific behavior (its stdlib overrides,
   Java varargs, real `Events` registry) — see the testkit README's Gate 2 section.

## Part 3 — Error decode table (exact terminal strings → cause → fix)

| Terminal string                                      | Cause                                                                                        | Fix                                                                                                                                                              |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PZ_REQUIRE: load error in '<path>': <msg>`          | A FOUND dep module failed to compile/execute during require (raise, not cached — deliberate) | The dep's real code crashed offline. `testkit.provide("dep_name", fake)` a stub, or add the missing symbol to your stub                                          |
| `PZ_REQUIRE: module not found '<name>'`              | Dep name soft-failed nil (stub-by-default posture)                                           | Intentional. `provide()` the dep or configure `PZ_MOD_PATH` if you truly need the real one                                                                       |
| `PZ_MOD LOAD FAIL <file>: ...`                       | The mod's own Lua crashed during auto-exec (engine load order)                               | Read the inner error: usually `PZ_REQUIRE: load error` (dep) or a strict unknown-global (see next row)                                                           |
| `PZ_STRICT: unknown global '<name>'`                 | Bare read of a global that doesn't exist yet at that point                                   | If it may legitimately be absent: `rawget(_G, "name") or default`. If it's a typo: fix it. If it's a game global: enable the right `PZ_STUB_PACKS` or add a stub |
| `PZ_STRICT: unknown PZ event 'Events.OnX'`           | Event name outside the allowlist (typo, or a custom event)                                   | Fix the spelling, or register the custom event first (`LuaEventManager.AddEvent(name)`)                                                                          |
| `PZ_STRICT: unknown method 'Class:name'`             | Method miss with Umbrella serve mode on                                                      | Check the class/method in SURFACE.md or the Umbrella clone; fix the call shape                                                                                   |
| `SPEC LOAD FAIL <path>: <msg>`                       | A spec file itself failed to compile/execute                                                 | Fix the spec (a load failure stops the whole run)                                                                                                                |
| `STUB PACK MISSING <name>` / `STUB LOAD FAIL <path>` | `PZ_STUB_PACKS` names a pack that doesn't exist / a stub file crashed                        | Fix the pack name (game, java) or the stub file                                                                                                                  |
| `total=0 ... exit 2`                                 | Zero specs collected                                                                         | Spec files must be named `TESTS/**/*_spec.lua` and `specs` (or `PZ_SPECS`) must point at their dir                                                               |
| run.lua: `total=N but EXPECTED_TOTAL=M`              | The suite's size changed or the wrong suite ran                                              | Update `EXPECTED_TOTAL` in `TESTS/run.lua` ONLY if the change is real and reviewed                                                                               |

## Part 4 — The 3 standard patterns (distilled from the real migrated suites)

**Pattern 1 — isolate a dependency with `provide` (CAF/MAF style).** The mod's module
`require`s a dep at load time; you need that load to succeed offline, with controlled
fakes:

```lua
describe("rules pruner", function()
    local deps = dofile(<spec_dir> .. "/dep_stubs.lua") -- your builder: returns complete fake tables
    before_each(function()
        testkit.provide("pz_utils_shared", deps.pz_utils())   -- wins over disk, survives reset
        testkit.provide("zul", deps.zul())
    end)
    it("prunes beyond the limit", function()
        local pruner = require("rules_pruner")                -- re-executes per test: fresh state
        -- assertions against pruner behavior with the fake injected
    end)
end)
```

`provide` seeds are persistent and beat disk; the per-test reset evicts everything else,
so each test re-requires a FRESH module instance with your fake bound — that is the
mock-after-load mechanism, don't fight it with `keep()`.

**Pattern 2 — event listener registration under reset (JASM style).** Listeners
registered at load time are wiped by the per-test reset (the persistent tier is
cache-only):

```lua
before_each(function()
    testkit.provide("dep_mod", fake_dep())
    Events.OnGameStart.Add(handler)        -- re-register per test, or register
    mod_entry.register_listeners()          -- inside a function the test calls
end)
it("reacts to the event", function()
    Events.OnGameStart.Run()                -- fire the dispatcher (stub core supports it)
    expect(fake_dep.observed).toBeTruthy()
end)
```

**Pattern 3 — look SURFACE.md up BEFORE hand-rolling a mock.** If the mod touches
`getPlayer`, `ModData`, `ISPanel`-family UI, collections, etc., the shipped
`game`/`java` packs already mock them (sized from the real mods' union surface, with
gate2-probed semantics):

```lua
-- first: read src/gate1/stubs/SURFACE.md for the exact members + shapes
-- then enable, don't re-invent:  RECIPE.stub_packs = { "game" }  (or PZ_STUB_PACKS=game)
```

If a member is missing from SURFACE.md, that is a Part 6 escalation — report it; add it
to the pack (with the SURFACE.md line) ONLY via option (b) with your human's approval,
or keep going on a temporary spec-level stub (option a) if they pick that. The pack is
shared by the whole fleet.

## Part 5 — Traps agents fall into (each one has cost someone a false-green)

- Don't use standard-Lua `require` hygiene (`package.loaded` games) — the contract
  require is path-keyed execute-once with its own reset; use `provide`/`keep`.
- Don't register listeners at file top level and expect them to survive (they're
  Cleared per test — Part 1.3).
- Don't assume `_G` is wiped (it is NOT) — clean up your own global tables in
  `before_each`.
- Don't assume a mock getter returns a real table — served stubs return `nil`
  (L1, never guessed values); assert against recorded CALLS, not return data.
- Don't iterate Java collections 1-based — `ArrayList:size()` pairs with
  `for i = 0, list:size() - 1` (Java interop is 0-based).
- Don't invent `Events.On*` names — check `events_list.lua` / SURFACE.md, or register
  the custom event first.
- Don't run the suite without `PZ_STRICT=1` at least once before finishing — the strict
  sweep is the typo net; a suite that only passes strict-off may be testing phantoms.
- Don't copy the framework into the mod repo — it stays ONE central checkout
  (`TESTS/run.lua` resolves it); an in-place edit inside a resolved copy helps nobody.
- Don't mask a testkit bug with a mod-repo hack (a fake that turns a framework failure
  green) — that is the false-green factory; escalate per Part 6 instead.

## Part 6 — Out-of-scope escalation (the fix belongs in the testkit)

When you have exhausted every mod-scope fix this skill teaches (stubs, packs,
`provide`, RECIPE config, spec changes) and the blocker remains, it is a
TESTKIT-SCOPE issue. Typical triggers:

- framework/runner/reset bug — tests crash, or state leaks in a way the per-test
  reset should have prevented
- strict-mode false positive — a legitimate Lua pattern flagged as unknown
  global/event/method
- a `game`/`java` pack member missing AND not reproducible with a spec-level
  `provide()` stub, or a shipped stub's semantics are wrong vs the real game API
- `check_globals.lua` misreports, or `SURFACE.md` documents a shape that isn't served

**STOP there.** Do NOT edit the testkit checkout (including the resolved copy under
`node_modules/pz_lua_testkit` or `.pz_testkit/<tag>` — it diverges from upstream and
helps nobody), and do NOT fake your way past it in the mod repo — a masked testkit
bug is a false-green factory (Part 5).

**Report to your human** in copy-pasteable form for the testkit devs:

1. resolved testkit: path + version/tag (`VERSION` file, `.pz_testkit/<tag>`, or the
   npm package version)
2. the exact terminal error string (from the Part 3 table, or raw)
3. minimal repro: the smallest spec file + the exact run command
4. suspected testkit location: which pack/module/file should change
5. what you already tried within the mod, and why it cannot cover it

Then present these options and let your human decide (no auto-choice):

- **(a) temporary mod-scope workaround** — a spec-level stub via `provide()`, the
  task continues; the feedback still goes to the testkit devs
- **(b) approve a local testkit edit** — only if your human owns the checkout and
  asks for it; it diverges from upstream and must be tracked
- **(c) park the task** — until the testkit fix ships and the consumer updates
