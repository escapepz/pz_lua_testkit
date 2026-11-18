# Reference

CLI commands, programmatic API, environment variables, static checks, Gate 2 real-jar execution, and repository layout for `pz_lua_testkit`.

---

## Gate 1 CLI and VS Code Debugging

Run Gate 1 with a PUC-Rio Lua 5.1.5 interpreter:

```bat
tools\lua5.1.exe src\gate1\run.lua
tools\lua5.1.exe src\gate1\run.lua path\to\spec.lua
tools\lua5.1.exe src\gate1\run.lua --mod path\to\MyMod
tools\lua5.1.exe src\gate1\run.lua --mod=path\to\MyMod path\to\specific_spec.lua
```

On POSIX shells, invoke `lua5.1 src/gate1/run.lua ...` with your Lua 5.1 binary.

- `--mod <dir>` / `--mod=<dir>` enables mod mode: resolves `mod.info` (B41 single root or B42 `common/` + `<versionDir>/`), installs the contract `require`, auto-executes the mod's Lua in engine load order, and defaults spec discovery to the mod's `TESTS` directories (`*_spec.lua`).
- Explicit spec file or directory arguments override the default spec directories (`src/specs`, `src/gate1/specs`, or `<mod>/TESTS` in mod mode).

### Exit Codes

| Code | Meaning |
| ---- | ------- |
| `0` | Suite passed (`result.ok == true`) |
| `1` | Spec load failure, mod load failure, or one or more test failures |
| `2` | Zero spec files found (`total == 0` and `failed == 0`) or CLI usage error (e.g. `--mod` without a value) |

### VS Code (`F5`)

[`.vscode/launch.json`](../.vscode/launch.json) defines the `"Debug pzspec"` configuration (`type: "lua"`, `luaVersion: "lua51"`), which launches `src/gate1/run.lua` from `${workspaceFolder}` with no arguments. Press `F5` to run and debug default specs and stubs with breakpoints.

---

## Programmatic API (`runner.run`)

Mod `TESTS/run.lua` shims and custom Lua runners can invoke Gate 1 directly without spawning a subprocess:

```lua
local runner = dofile("<testkit_root>/src/gate1/runner.lua")
local result = runner.run({
    mod = "<mod_root>",
    ctx = "sp",
    strict = true,
    stub_packs = { "java", "game" },
})
```

`runner.run(config)` **never** calls `os.exit`; the caller owns the process and maps `result` (for example via `reporter.exit_code(result)`).

### `config` Keys and Precedence

Resolution follows **`config > env > default`** (implemented in `src/gate1/config.lua`). Empty-string environment variables (`""`, such as `set PZ_CTX=` on Windows) are normalized to `nil`.

| Key | Type | Env Fallback | Default | Description |
| --- | ---- | ------------ | ------- | ----------- |
| `ctx` | `string` | `PZ_CTX` | `"sp"` | Execution context: `"sp"`, `"client"`, or `"server"`. |
| `strict` | `boolean` | `PZ_STRICT` (`"1"`) | `false` | Arms the unknown-global `_G` guard and strict `Events` check. Three-state: explicit `false` overrides `PZ_STRICT=1`. |
| `stub_packs` | `string[]` | `PZ_STUB_PACKS` (`,`-split) | `{}` | Built-in packs loaded from `src/gate1/stubs/<name>.lua` (e.g. `{ "java", "game" }`). |
| `stubs` | `string[]` | `PZ_STUBS` (`;`-split) | `{}` | User stub directories; loads every `.lua` file in each directory (non-recursive). |
| `lua_path` | `string[]` | `PZ_LUA_PATH` (`;`-split) | `{}` | Extra `package.path` entries prepended after the testkit's internal paths. |
| `specs` | `string[]` | `PZ_SPECS` (`;`-split) | `{ "src/specs", "src/gate1/specs" }` (or mod `TESTS` dirs) | Spec files or directories (`*_spec.lua`). |
| `umbrella` | `string` | `PZ_UMBRELLA` | `nil` | Path to an Umbrella clone root (containing `library/`) to enable Umbrella serve mode. |
| `mod` | `string` | — | `nil` | Mod directory under test; enables mod mode (`PzRequire` contract `require` + auto-exec). |
| `mod_path` | `string[]` | `PZ_MOD_PATH` (`;`-split) | `{}` | Ordered search directories for `mod.info` `require=` dependencies (roots only, no auto-exec). |
| `reset_per_test` | `boolean` | `PZ_RESET_PER_TEST` (`"1"`) | `true` when `mod` is set, else `false` | Registers a global `before_each` hook calling `_G.testkit.resetLoaded()` before each test when mod mode is active. Inert outside mod mode. |

### Return Value

`runner.run(config)` returns a summary table:

```lua
{
    total = <int>,   -- total specs executed
    passed = <int>,  -- passing specs
    failed = <int>,  -- failing specs (or 1 on mod/spec load failure)
    ok = <bool>,     -- true iff all specs passed
}
```

`runner.lua` also exports `collect_specs(list)`, `prepare_mod(mod_dir, ctx, mod_path)`, `wire_reset(config, installed)`, `resolveConfig(config, env_fn)`, and `splitEnv(name, sep, env_fn)`.

---

## Environment Variables (`PZ_*`)

| Variable | Values | Meaning |
| -------- | ------ | ------- |
| `PZ_CTX` | `sp` \| `client` \| `server` (default `sp`) | Sets stub context: `isServer()` (`server`), `isClient()` (`client`), `isMultiplayer()` (`~= "sp"`), `isSinglePlayer()` (`"sp"`). |
| `PZ_STRICT` | `"1"` (any other value = off) | Arms strict mode: unknown global reads error with `PZ_STRICT: unknown global '<name>'` (top-level writes remain allowed), and unknown `Events.On<Name>` / `Hook.On<Name>` reads error with `PZ_STRICT: unknown PZ event 'Events.On<Name>'` / `'Hook.On<Name>'`. |
| `PZ_STUB_PACKS` | Comma-separated pack names (e.g. `java,game`) | Loads built-in stub packs from `src/gate1/stubs/<name>.lua` after `core.lua` and before `PZ_STUBS`. |
| `PZ_STUBS` | Semicolon-separated directory paths | Loads every `.lua` file in each directory (non-recursive). Errors in one file are reported without aborting other files. |
| `PZ_SPECS` | Semicolon-separated file or directory paths | Spec files or directories (`*_spec.lua`). When set with no CLI spec args, replaces the default spec dirs; when combined with CLI args, `PZ_SPECS` entries are resolved and deduplicated first (before all collected spec paths are sorted lexicographically). |
| `PZ_LUA_PATH` | Semicolon-separated `package.path` templates | Prepended to `package.path` after the testkit's internal paths. |
| `PZ_HOME` | Path to Project Zomboid install directory (e.g. `path/to/ProjectZomboid`) | Gate 2 only: directory containing `projectzomboid.jar` and `stdlib.lua`. |
| `PZ_UMBRELLA` | Path to an Umbrella clone root containing `library/` (e.g. `path/to/umbrella`) | Enables Umbrella serve mode: initializes `Umbrella` before the strict guard arms so `PZ_STRICT` consults `Umbrella.resolve_global` before erroring. |
| `PZ_MOD_PATH` | Semicolon-separated directory paths (e.g. `path/to/depmods`) | Dependency mod search directories for `mod.info` `require=` entries. Hits add `media/lua/{shared,client,server}` as require roots (no auto-exec); misses warn once and continue. |
| `PZ_RESET_PER_TEST` | `"1"` (on) \| `"0"` (off) | Overrides the default per-test `testkit.resetLoaded()` hook in mod mode (`true` in mod mode, `false` otherwise). |

---

## Static Global Checker and Consumer Sweep

### `src/check/check_globals.lua`

Static unknown-global and unknown-event scanner. Compiles target `.lua` files with `loadfile` and `string.dump`, then walks the Lua 5.1 bytecode to report exact file and line numbers for unknown global reads/writes and unknown `Events.<Name>` accesses.

```bat
tools\lua5.1.exe src\check\check_globals.lua <file-or-dir>... [--stdlib]
```

- `--stdlib`: harvests globals from `src/gate1/stubs/core.lua` in addition to the Lua 5.1 `BASELINE` globals. Events are checked against `src/gate1/stubs/events_list.lua`. (`PZ_UMBRELLA` symbols are out of scope.)
- Also loadable as a module: `local cg = dofile("src/check/check_globals.lua"); local findings, warnings = cg.check(paths, { stdlib = true })`.
- **Exit codes:** `0` = clean, `1` = unknown globals or events found, `2` = usage error.

### `src/check/sweep_consumers.lua`

Runs `TESTS/run.lua` across one or more mod workspace directories, spawning one fresh child process per workspace on the invoking Lua interpreter (`arg[-1]`):

```bat
tools\lua5.1.exe src\check\sweep_consumers.lua path\to\mod_a path\to\mod_b
```

A workspace passes only when its output includes both `total=<N>` (`N >= 1`) and `ALL PASS`.

- **Exit codes:** `0` = all workspaces green, `1` = one or more workspaces failed (prints the last 20 lines of failing output), `2` = usage error (no workspace arguments or missing `arg[-1]`).

---

## Gate 2 (Real Kahlua Cross-Check)

`src/gate2/java/PzKahluaRunner.java` executes `pzspec` suites on Project Zomboid's actual Kahlua VM using reflection against your local `projectzomboid.jar`. It imports only `se.krka.kahlua.*` and JDK classes (no game source is shipped). It exposes `zombie.Lua.LuaManager$GlobalObject` `@LuaMethod` statics, real `Events`, and mod loading.

Gate 2 is **dev-time only** and **cannot run on CI** because it requires a local JDK and a local Project Zomboid installation (`%PZ_HOME%`); Gate 1 covers CI.

### Build and Run

If you installed `pz_lua_testkit` via `npm`/`pnpm`, `<kit-root>` is `<abs-mod-dir>\node_modules\pz_lua_testkit` (the npm package ships `src\gate2\java\PzKahluaRunner.java` for `--mod` runs; the internal `src\specs` and `src\gate2\specs` suites are only in a git clone):

```bat
javac -d build\gate2 -cp "%PZ_HOME%\projectzomboid.jar" <kit-root>\src\gate2\java\PzKahluaRunner.java
cd /d "%PZ_HOME%"
java -cp "%PZ_HOME%\projectzomboid.jar;<abs-mod-dir>\build\gate2" PzKahluaRunner <kit-root> --mod <abs-mod-dir> [--modpath <dir>[;<dir>...]] [--game-mods] [--ctx sp|client|server]
```

From a git clone of `pz_lua_testkit`, you can also run the built-in Gate 2 self-tests:

```bat
java -cp "%PZ_HOME%\projectzomboid.jar;<repo-root>\build\gate2" PzKahluaRunner <repo-root> <repo-root>\src\specs <repo-root>\src\gate2\specs
```

### Flags, Globals, and Exit Codes

- `--mod <dir>` / `--mod=<dir>`: resolves B41 or B42 layout and auto-executes the mod's `media/lua` in engine load order before specs run (records `__PZ_MOD_INFO`).
- `--modpath <dir>[;<dir>...]`: adds ordered dependency mod search directories (`mod.info` `require=` tokens resolve transitively and contribute require roots only, no auto-exec).
- `--game-mods`: opt-in fallback discovery in PZ user/Steam Workshop mod directories when a `mod.info` `require=` dependency is not found in `--modpath` (off by default).
- `--ctx <sp|client|server>`: sets load context (default `sp`).
- **`require()` resolution (`--mod`):** checks `mod.roots` first (primary mod roots + transitive `mod.info` `require=` dependency roots) using a shared path-keyed cache with `loadMod` auto-exec (preventing double execution and skipping circular `require` calls), then falls back to `GlobalObject.require`.
- **`_G.testkit`:** `testkit.keep(...)` is a no-op; `testkit.provide(...)` and `testkit.resetLoaded(...)` fail fast with an error directing you to use `--modpath` or `--game-mods` in Gate 2.
- Stamps `_G.PZ_GATE = "gate2"` (Gate 1 stamps `"gate1"`), allowing shared specs in `src/specs/` to branch when needed.
- **Exit codes:** `0` = pass, `1` = suite or spec-load failure, `2` = usage error or zero specs found.

### Quirks

- **Working directory:** You must `cd` into `%PZ_HOME%` before running `java`, because the game's `J2SEPlatform` loads `stdlib.lua` relative to the JVM current working directory.
- **Absolute spec paths:** Hand-passed spec file or directory arguments must be absolute paths (since the JVM CWD is `%PZ_HOME%`).
- **Default specs:** Without `--mod`, there are no default spec directories (omitting spec arguments prints `no *_spec.lua files found` and exits `2`). With `--mod` and no explicit spec args, specs default to the mod's `TESTS` directories.
- **Dual-gate event cleanup:** Specs shared across Gate 1 and Gate 2 must unregister any `Events.OnX.Add(fn)` listeners in `after_each` via `Events.OnX.Remove(fn)` — Gate 2 runs on real `Events` without per-spec sandboxing, so leaked listeners persist across specs.

---

## GitHub Actions CI Setup

`pz_lua_testkit` provides a setup-only composite GitHub Action (`action.yml`) that installs **PUC-Rio Lua 5.1.5** (not LuaJIT or Lua 5.2+) and exposes the testkit path and Lua executable name to downstream steps. It does not execute tests automatically; your workflow chooses how to invoke Gate 1 or static checks.

> **Note:** Gate 2 (`src/gate2/java/PzKahluaRunner.java`) remains **local-only** and never runs in CI because it requires a local JDK and Project Zomboid installation (`%PZ_HOME%`).

### Minimal Workflow

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup pz_lua_testkit
        id: testkit
        uses: escapepz/pz_lua_testkit@0.1.2-rc.202611190505 # or @main

      - name: Run mod tests (strict)
        env:
          PZ_STRICT: "1"
        run: ${{ steps.testkit.outputs.lua-bin }} "${{ steps.testkit.outputs.testkit-path }}/src/gate1/run.lua" --mod .
```

### Action Inputs and Outputs

#### Inputs

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `lua-version` | No | `"5.1.5"` | Lua 5.1 version passed to `xpol/setup-lua@v1` and `actions/cache@v4` on macOS. |

#### Outputs

| Output | Value | Description |
| ------ | ----- | ----------- |
| `testkit-path` | `${{ github.action_path }}` | Absolute path to the `pz_lua_testkit` repository root. |
| `lua-bin` | `lua5.1` (Linux/Windows) or `lua` (macOS) | Name of the Lua 5.1 executable installed on `PATH`. |

### Usage Examples

1. **Direct mod mode (`--mod .` + `PZ_STRICT=1`)**

   ```yaml
   - name: Run Gate 1 in mod mode
     env:
       PZ_STRICT: "1"
     run: ${{ steps.testkit.outputs.lua-bin }} "${{ steps.testkit.outputs.testkit-path }}/src/gate1/run.lua" --mod .
   ```

2. **Custom `TESTS/run.lua` shim**

   ```yaml
   - name: Run mod test shim
     env:
       PZ_TESTKIT_DIR: ${{ steps.testkit.outputs.testkit-path }} # example consumer-defined var read by your TESTS/run.lua
     run: ${{ steps.testkit.outputs.lua-bin }} TESTS/run.lua
   ```

3. **Static global check (`check_globals.lua`)**

   ```yaml
   - name: Check globals and Events
     run: ${{ steps.testkit.outputs.lua-bin }} "${{ steps.testkit.outputs.testkit-path }}/src/check/check_globals.lua" media/lua --stdlib
   ```

---

## Repository Layout and Colocated Docs

```text
action.yml                    Setup-only composite GitHub Action (PUC-Rio Lua 5.1.5)
.github/workflows/ci.yml      Testkit self-check CI workflow (Ubuntu, Windows, macOS)
src/
  pzspec.lua                  DSL shared by both gates (describe/it/expect/mock/hooks)
  specs/                      Shared specs runnable on both Gate 1 and Gate 2
  gate1/
    run.lua                   Gate 1 CLI entry point
    runner.lua                Gate 1 orchestrator (runner.run)
    config.lua                Config/env resolution (config > env > default)
    discovery.lua             Spec file/directory scanning and deduplication
    modloader.lua             B41/B42 mod layout, dependency roots, engine load order
    reset.lua                 Per-test resetLoaded hook wiring
    reporter.lua              Result formatting and CLI exit code mapping
    stubs/                    core.lua, events_list.lua, java.lua, game.lua, umbrella.lua, pzrequire.lua
    stubs/SURFACE.md          Stub surface inventory and Gate 2 alignment notes
    specs/                    Gate 1-only self-test specs
  gate2/
    java/PzKahluaRunner.java  Clean-room real-jar Kahlua runner
    specs/                    Gate 2-only parity and GlobalObject specs
    fixtures/                 Self-authored mod fixtures for Gate 2
  check/
    check_globals.lua         Static Lua 5.1 bytecode global/event checker
    sweep_consumers.lua       Multi-workspace TESTS/run.lua sweep runner
  vendor/
    inspect.lua               Vendored table serializer (MIT)
    PATCHES.md                Notes on vendored files and local patches
docs/
  specs-and-mocking.md        Writing specs, assertions, mocks, and strict mode
  mod-loader-and-stubs.md     Mod mode, require/resetLoaded, stub packs, and Umbrella
  reference.md                This reference
.vscode/launch.json           VS Code "Debug pzspec" launch configuration
tools/                        User-provisioned Lua 5.1.5 binaries (gitignored)
```

- [Stub surface & Gate 2 alignment notes](../src/gate1/stubs/SURFACE.md)
- [Vendored library patch notes](../src/vendor/PATCHES.md)
