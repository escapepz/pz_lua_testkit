# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1-rc.202611211559] - 2026-11-21

### Consumer-visible behavior changes
- **Mock Java contract fixes (audit follow-ups):** the `getSpecificPlayer`/`getPlayer` factory now gives the player a real `ItemContainer` (`size`/`contains`/`addItem` usable — matches the class form and JASM's own mock); list-shape `get(i)` throws `IndexOutOfBoundsException` outside `0..size-1` like `java.lua` (both gates' list shapes agree); `HashMap` stores nil VALUES in a sentinel box — `containsKey` true, `get` returns nil, `size` counts, `put` returns the decoded previous value (Java null-value contract; null KEYS stay a documented residual divergence); `newEvent` drops its unused name parameter.
- **Gate 2 hook-register diagnostic (`PzKahluaRunner.java`):** a `LuaHookManager.register` failure now reports its own `[gate2] LuaHookManager unavailable` label instead of piggybacking on the `LuaEventManager` catch.

### Changed
- **One `shellpath.lua` for the shell-quoting probes (`src/gate1/shellpath.lua`):** the probe copy-pasted across `check_globals.lua`, `modloader.lua`, `discovery.lua`, `umbrella.lua`, and `pzrequire.lua` is consolidated into one sourced module (npm-covered by the `src/gate1/` glob).
- **CI npm-pack assertions (`.github/workflows/ci.yml`):** the pack dry-run step greps the manifest for the critical shipped paths (`run.lua`, `shellpath.lua`, `PzKahluaRunner.java`, `SKILL.md`, `VERSION`) so a files-glob regression fails CI.
- **Comment sweep:** 95 tracked files unified — 11 inline narration comment units removed; constraint/file-header comments kept (no behavior change).
- **Documentation (`SKILL.md`):** Part 2.1 states `RECIPE`/`EXPECTED_TOTAL` are per-workspace conventions with no shipped template.

## [0.2.1-rc.202611211058] - 2026-11-21

### Consumer-visible behavior changes
- **Strict mode widens to `Hook` typos and all vanilla events:** `Events`/`Hook` stub registries now auto-create a dispatcher for ANY non-empty string key, while strict consults split per-registry allowlists — `events` ships the FULL real engine boot registry (266 names = 217 `On*` + 46 non-`On` + 3 Lua-side ISSearchManager registrations) plus the 8 `Hook` keys, so no boot-registered vanilla event can false-red strict anymore, and cross-namespace names (`Hook.OnTick`, `Events.UseItem`) now correctly fail. The strict error prefix is unchanged; the quoted name may be `Events.<Name>` or `Hook.<Name>`.
- **Default-mode auto-create widens:** `Events.<any string>` returns a live dispatcher where non-`On` keys previously returned `nil` — `if Events.X then` existence probes auto-vivify; probe with `rawget(Events, "X")`.
- **Per-test reset is factory-identity based:** every stub-created dispatcher on `Events`/`Hook` is cleared regardless of key name; a hand-built event-like table parked on a registry (even one with a `Clear` method) is NOT cleared. If `core.lua` is absent, `reset_events` falls back to the old `^On` duck-typed clearing with one warn.
- **Timestamp globals match real-engine scales:** `getTimestamp()` now returns epoch SECONDS (was milliseconds), `getTimestampMs()` returns epoch milliseconds (was CPU time), `getGameTime()` returns a deterministic GameTime stub table (was `0`).
- **Contract require rejects `..` traversal:** any require name whose normalized form contains `..` soft-fails with `PZ_REQUIRE: rejected '..' traversal in '<name>'` (one warn; `require` suppresses its not-found warn for rejected names).
- **`--mod` with an unresolvable `mod.info` exits 2:** the runner returns the zero-total result instead of silently running the kit's own self-test suite green.

### Added
- **Gate 2 `LuaManager.thread` wiring (`PzKahluaRunner.java`):** the runner's `KahluaThread` is wired into the `LuaManager.thread` static after `debugOwnerThread` is set — `IsMainThread()` now reads the right thread, so `triggerEvent` dispatches instead of queueing forever. Regression spec `src/gate2/specs/trigger_event_spec.lua`.
- **Gate 2 `LuaHookManager.register` at boot (`PzKahluaRunner.java`):** mirrors the real game boot's two-register order so the env has a real `Hook` registry (8 keys) for parity assertions.
- **Gate 2 two-directional parity (`src/gate2/specs/events_parity_spec.lua`):** forward (every shipped name registered in the real registry, minus exactly the 3 Lua-side ISSearchManager exceptions — the anticipated conditional trading/cheats-UI class verified EMPTY) and reverse (every real `pairs(Events)`/`pairs(Hook)` name is shipped). A new engine event reds the parity suite until `events_list.lua` regenerates — intended.
- **Gate 1 dispatcher identity (`src/gate1/stubs/core.lua`):** `_G.__pz_is_dispatcher` (weak-keyed factory set) drives per-test reset and is spec-pinned.
- **Gate 1 pins:** non-`On` vanilla events pass strict, cross-namespace registration rejected, timestamp/GameTime scale pins, traversal edge pins (`a/..`, `..`), check_globals SETTABLE event write-path fixtures.

### Changed
- **`src/gate1/stubs/events_list.lua`:** split shape `{ events, hooks }` (no merged `names` key), both sorted and deduped.
- **`src/gate1/stubs/umbrella.lua`:** the Umbrella event extension targets the `Events` allowlist only (fixes the order-dependent `Hook` strictness under `PZ_UMBRELLA`).
- **`src/check/check_globals.lua`:** consumes the split shape (fail-closed warn on the old `names`-only shape), scans `Hook.<Name>` against the hooks set, and adds an additive `registry` field to event findings.
- **Documentation (`SKILL.md`, `SURFACE.md`, `docs/`):** SKILL.md teaches `Events.OnGameStart._fire()` (no `Run` exists), the rawget event-probe rule, and the registry-scoped decode row; SURFACE.md documents the split allowlists, auto-create/strict/reset semantics and the time pins; `docs/reference.md`, `docs/mod-loader-and-stubs.md`, `docs/specs-and-mocking.md` match the shipped behavior.

### Fixed
- **Gate 1 false green (`src/gate1/runner.lua`):** `--mod` pointing at a directory without a resolvable `mod.info` previously fell through to running the kit's own self-test suite green (exit 0); it now fails as a setup error.

## [0.1.2-rc.202611190505] - 2026-11-19

### Added
- **Gate 2 `require()` mod-roots parity (`PzKahluaRunner.java`):** Wired `mod.roots` into `_G.require` with a `Path.toRealPath()`-keyed execute-once cache shared with `loadMod()` auto-execution, `finally`-cleaned `inFlight` circular guard, path-traversal containment, and fallback to stock `GlobalObject.require` for vanilla classes.
- **Gate 2 transitive deps & `--game-mods`:** Added BFS transitive `mod.info` `require=` resolution (with `visitedModIds` cycle guard and `common/mod.info` `id=` fallback) plus opt-in `--game-mods` lazy indexing over `~/Zomboid/mods`, `~/Zomboid/Workshop`, and Steam `workshop/content/108600`.
- **Gate 2 `_G.testkit` fail-fast facade:** Exposed `testkit.keep` (no-op) and fail-fast `testkit.provide` / `testkit.resetLoaded` errors for shared specs.
- **GitHub Actions setup & CI (`action.yml`, `.github/workflows/ci.yml`):** Added composite action for Lua 5.1 setup across Linux, Windows, and macOS plus two-stage Gate 1 and `npm pack` CI checks.
- **Documentation (`README.md`, `docs/`):** Added modder-focused `README.md` with badges and shipped `docs/specs-and-mocking.md`, `docs/mod-loader-and-stubs.md`, and `docs/reference.md` in the npm package.

### Changed
- **npm package contents (`package.json`):** Shipped `src/gate2/java/`, `docs/`, and `CHANGELOG.md`; added `repository` metadata.
- **Gate 2 `PzKahluaRunner.java`:** Reused `main`'s `J2SEPlatform` instance in `installTestkitFacade`.

### Fixed
- **Gate 1 CLI (`src/gate1/run.lua`):** Rejected unknown `--*` flags with exit code `2` instead of treating them as spec paths.
- **Gate 1 strict isolation (`src/gate1/runner.lua`):** Snapshotted and restored `_G`'s metatable and `pz_strict` across `runner.run()` (including early bailouts and nested runs).
- **Gate 1 / Gate 2 `require=` parity (`src/gate1/modloader.lua`, `PzKahluaRunner.java`):** Split `require=` on `[,;]`, trimmed whitespace, stripped only leading `\`, and rejected tokens containing `\` (blocking `..\EscapeDecoy` and `sub\dir` traversal).
- **Safe `io.popen` path quoting:** Quoted paths safely per OS across `modloader.lua`, `discovery.lua`, `pzrequire.lua`, `umbrella.lua`, and `check_globals.lua`.
- **Docs accuracy (`docs/reference.md`):** Fixed `after_each` hook name for dual-gate `Events.OnX.Remove` cleanup.

## [0.1.1] - 2026-11-18

### Added
- Initial public npm release (`pz_lua_testkit`) with Gate 1 (`pzspec`, clean-room stubs, `modloader`, `pzrequire`, `Umbrella` serve mode), `check_globals.lua` Lua 5.1 bytecode scanner, `sweep_consumers.lua`, and `.agents/skills/pz-lua-testkit/`.
- Verified Gate 2 parity against local Project Zomboid B42 JAR (including `events_parity_spec.lua`).

[Unreleased]: https://github.com/escapepz/pz_lua_testkit/compare/0.2.1-rc.202611211559...HEAD
[0.2.1-rc.202611211559]: https://github.com/escapepz/pz_lua_testkit/compare/0.2.1-rc.202611211058...0.2.1-rc.202611211559
[0.2.1-rc.202611211058]: https://github.com/escapepz/pz_lua_testkit/compare/0.1.2-rc.202611190505...0.2.1-rc.202611211058
[0.1.2-rc.202611190505]: https://github.com/escapepz/pz_lua_testkit/compare/0.1.1...0.1.2-rc.202611190505
[0.1.1]: https://github.com/escapepz/pz_lua_testkit/releases/tag/0.1.1
