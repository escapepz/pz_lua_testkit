# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2-20261119-0312] - 2026-11-19

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

[Unreleased]: https://github.com/escapepz/pz_lua_testkit/compare/v0.1.2-20261119-0312...HEAD
[0.1.2-20261119-0312]: https://github.com/escapepz/pz_lua_testkit/compare/v0.1.1...v0.1.2-20261119-0312
[0.1.1]: https://github.com/escapepz/pz_lua_testkit/releases/tag/v0.1.1
