# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1-rc.202611211738] - 2026-11-21

### Fixed
- **CI npm-pack assertion never had a manifest to grep (`.github/workflows/ci.yml`):** `npm pack --dry-run` writes its `npm notice` report to STDERR, so `npm pack --dry-run | tee pack_manifest.txt` teed an EMPTY file and every critical-path grep failed with a bogus `MISSING from npm package: src/gate1/run.lua` — on the step's first-ever execution (all previous CI rounds died at Gate 1 before reaching it). The step now merges stderr (`npm pack --dry-run 2>&1 | tee ...`). Verified with the exact step block locally (npm 11.20.0) and on the Debian VM (npm 10.9.7 — CI's npm major): all 5 critical paths grep green.

## [0.2.1-rc.202611211728] - 2026-11-21

### Changed
- **Workflow run cleanup (`.github/workflows/cleanup.yml`):** weekly scheduled sweep deleting stale workflow runs — 7-day retention with a minimum of 5 runs kept per workflow; `actions: write` declared explicitly so the job also works under read-only default GITHUB_TOKEN permissions. Manual trigger available via `workflow_dispatch`.

### Fixed
- **Gate 1 (l5) case-variant must live at the exact required path (`src/gate1/specs/pzrequire_spec.lua`):** the 202611211718 attempt wrote the fixture file under lowercase `shared/`, but (l5) requires `Shared/Util` — Linux keeps BOTH segments case-sensitive, so the file stayed invisible (`module not found`, count stuck at 1; CI round 3 red with the same expect). The variant now lands at `Shared/Util.lua` (capital-S dir created too), content identical to `util.lua` so case-insensitive non-Windows FS (macOS) cannot diverge on last-write-wins. Proven on a real Debian VM before push: Gate 1 default 280/280, strict 280/280, and the `--mod` fixture step 1/1 — the first Linux run ever to reach that CI step.

## [0.2.1-rc.202611211718] - 2026-11-21

### Fixed
- **Gate 1 (l5) fixture never shipped its POSIX case-variant (`src/gate1/specs/pzrequire_spec.lua`):** the spec expects `N=2` on POSIX — case folding is Windows-only, so a differently-cased require must be a separate execution — but `buildFixture` only ever wrote lowercase `shared/util.lua`, so `require("Shared/Util")` warned not-found and the count stayed 1. Latent since the spec was written; first Linux exposure was this cycle's CI (the 0.2.x code had never reached a `main` push before). `buildFixture` now writes `shared/Util.lua` on non-Windows with content identical to `util.lua` — on case-insensitive non-Windows FS (macOS) both names hit one real file, so last-write-wins must not diverge. Windows fixture and expectations unchanged.

## [0.2.1-rc.202611211706] - 2026-11-21

### Fixed
- **Gate 1 require on POSIX absolute roots (`src/gate1/stubs/pzrequire.lua`):** the canonical cache key collapsed empty segments, so a POSIX absolute root (`/home/...`) lost its leading `/` when the key was reused as the `loadfile` path — every require from an absolute root failed with `No such file or directory` on Linux (CI red at 276/280: mod deps (f)(g)(h) + pzrequire (l5)); Windows never saw it because drive-letter keys (`E:/...`) stay loadable. The key is cache identity only now: `_paths` maps each key to its first-seen real path and `loadfile` always loads the real path; `resolve()` still returns the canonical key and error messages still quote the key — the (j)/(q)/(l5) pins are unchanged.

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

[Unreleased]: https://github.com/escapepz/pz_lua_testkit/compare/0.2.1-rc.202611211738...HEAD
[0.2.1-rc.202611211738]: https://github.com/escapepz/pz_lua_testkit/compare/0.2.1-rc.202611211728...0.2.1-rc.202611211738
[0.2.1-rc.202611211728]: https://github.com/escapepz/pz_lua_testkit/compare/0.2.1-rc.202611211718...0.2.1-rc.202611211728
[0.2.1-rc.202611211718]: https://github.com/escapepz/pz_lua_testkit/compare/0.2.1-rc.202611211706...0.2.1-rc.202611211718
[0.2.1-rc.202611211706]: https://github.com/escapepz/pz_lua_testkit/compare/0.2.1-rc.202611211559...0.2.1-rc.202611211706
[0.2.1-rc.202611211559]: https://github.com/escapepz/pz_lua_testkit/compare/0.2.1-rc.202611211058...0.2.1-rc.202611211559
[0.2.1-rc.202611211058]: https://github.com/escapepz/pz_lua_testkit/compare/0.1.2-rc.202611190505...0.2.1-rc.202611211058
[0.1.2-rc.202611190505]: https://github.com/escapepz/pz_lua_testkit/compare/0.1.1...0.1.2-rc.202611190505
[0.1.1]: https://github.com/escapepz/pz_lua_testkit/releases/tag/0.1.1
