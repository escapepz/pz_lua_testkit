# Mod Loader and Stubs

This guide covers how `pz_lua_testkit` loads Project Zomboid mods offline in Gate 1, how `require` and dependencies work in mod mode, and how to configure built-in stub packs, custom stubs, and Umbrella EmmyLua serve mode.

---

## Mod Mode (`--mod`)

Pass `--mod <dir>` (or `--mod=<dir>`) to `src/gate1/run.lua`, or set `config.mod` when calling `runner.run(config)`:

```sh
lua src/gate1/run.lua --mod /path/to/MyMod
```

When `--mod` is set, the runner:

1. Resolves the mod layout and reads `mod.info`.
2. Registers `media/lua/{shared,client,server}` as `require` roots.
3. Auto-executes the mod's Lua files in engine load order.
4. Discovers specs in `<modDir>/TESTS/**/*_spec.lua` unless explicit spec paths or `PZ_SPECS` are provided.

### B41 vs B42 Layout & `mod.info` Precedence

`modloader.lua` supports both Project Zomboid mod layouts:

- **B41 single root**: if `<modDir>/mod.info` exists, `<modDir>` is used as the single layout root.
- **B42 dual layout**: otherwise, if `<modDir>/common/mod.info` or `<modDir>/<versionDir>/mod.info` exists, the loader uses `common/` and `<versionDir>/` (in that order, when present).
  - `<versionDir>` is the numeric-named subdirectory with the highest integer value (for example `42`).
  - `mod.info` is read from `<modDir>/<versionDir>/mod.info` first, falling back to `<modDir>/common/mod.info`.
- **Missing `mod.info`**: if neither layout has a `mod.info`, the runner prints `PZ_MOD: mod.info not found in '<dir>'` and leaves mod mode off.

### Engine Load Order & Contexts

Auto-execution follows the engine's `LoadDirBase` order based on `PZ_CTX` (or `config.ctx`, default `"sp"`):

| `PZ_CTX` | Auto-executed subdirectories | Registered `require` roots |
| --- | --- | --- |
| `"sp"` / `"client"` | `shared` -> `client` -> `server` | `shared`, `client`, `server` |
| `"server"` | `shared` -> `server` | `shared`, `client`, `server` |

- On `PZ_CTX=server`, `client/` files are **never auto-executed**, matching dedicated server behavior, while `client/` **stays registered as a `require` root** in all contexts.
- In B42 dual layout, for each `media/lua/<sub>`, the `common/` batch loads before the `<versionDir>/` batch.
- Within each batch, `.lua` files are sorted case-insensitively (`a:lower() < b:lower()`).

### Activation Order in `runner.run()`

`runner.lua` assembles the Gate 1 environment in this fixed order:

1. Resolve config (`config` -> environment variables -> defaults).
2. Set `package.path` (plus `PZ_LUA_PATH`).
3. Load `pzspec.lua` and `src/gate1/stubs/core.lua`.
4. Load built-in stub packs (`PZ_STUB_PACKS`) and custom stub directories (`PZ_STUBS`).
5. Initialize Umbrella serve mode (`Umbrella.init(umbrella)`), if `PZ_UMBRELLA` / `config.umbrella` is set.
6. Prepare mod layout and install `PzRequire` (`_G.require` + `_G.testkit`), if `--mod` / `config.mod` is set.
7. Arm the strict `_G` `__index` guard, if `PZ_STRICT=1` / `config.strict = true`.
8. Auto-execute the mod's Lua files through `PzRequire.require_file`.
9. Wire per-test `testkit.resetLoaded()` (when `reset_per_test` is active).
10. Load specs and run `pzspec.run()`.

> **Strict mode note:** Because the strict `_G` guard arms before mod auto-execution, top-level mod code that checks possibly-uninitialized globals should use `rawget(_G, "MyGlobal") or default` instead of `MyGlobal or default`. Plain top-level assignments are unaffected.

---

## `require` Contract in Mod Mode

In mod mode, `src/gate1/stubs/pzrequire.lua` replaces `_G.require` with `PzRequire.require`:

- **`.lua` extension**: appends `.lua` if the module name does not already end with `.lua`.
- **Root scan order**: scans registered `media/lua/{shared,client,server}` roots in order (`shared` -> `client` -> `server`, with `common/` before `<versionDir>/`), loading the first matching file.
- **Execute-once path-keyed cache**: normalizes slashes (`\` -> `/`), strips trailing `/` and leading `./`, and caches the return value after execution—even if the module returns `nil`.
- **Missing module (soft-fail)**: prints `PZ_REQUIRE: module not found '<name>'` and returns `nil`. This is independent of `PZ_STRICT=1`, so optional dependency checks (`local dep = require("OptionalMod") or nil`) continue to work.
- **Circular `require` (soft-fail)**: if a module is already in-flight, prints `PZ_REQUIRE: circular require of '<path>' skipped` and returns `nil`.
- **Compile or runtime error (hard-raise)**: if a found module fails to compile or raises during execution, `require` raises `PZ_REQUIRE: load error in '<path>': <msg>` and does **not** cache the module.

### `testkit` Global API

Mod mode also exposes `_G.testkit` for controlling module state between tests:

- `testkit.resetLoaded()` — clears the `require` cache (preserving `keep` and `provide` entries) and clears `Events.*` / `Hook.*` listeners (preserving the known-event allowlist).
- `testkit.keep(name)` — marks an already-loaded module as persistent across `resetLoaded()`. Note that `keep` only preserves the `require` cache entry; load-time event listeners are still cleared by `resetLoaded()`, so register listeners inside functions or `before_each`.
- `testkit.provide(name, value)` — seeds a persistent stub value for `name` that takes precedence over disk lookup and survives `resetLoaded()`.
- `testkit.std_require(name)` — escape hatch to the original Lua `require`.

By default in mod mode, `reset_per_test` is enabled and calls `testkit.resetLoaded()` before every test. Set `PZ_RESET_PER_TEST=0` (or `config.reset_per_test = false`) to keep cached modules across tests.

---

## Dependencies (`PZ_MOD_PATH` / `config.mod_path`)

`modloader.lua` parses `require=` lines from `mod.info` as bare mod IDs (tokens equal to `.` or `..`, or containing `/`, `:`, or `"`, are rejected with a warning and skipped).

- **Stub-by-default posture**: if `PZ_MOD_PATH` is unset (or a dependency is not found), `require`ing a dependency module soft-fails with `nil`. Tests can supply lightweight stubs with `testkit.provide("DepModule", stubTable)`.
- **Opting into real dependency roots**: set `PZ_MOD_PATH` (`;`-separated search directories) or `config.mod_path`. Each dependency token is searched as `<searchDir>/<token>/` using the same B41/B42 layout rules.
- **Roots only, no auto-exec**: found dependency `media/lua/{shared,client,server}` directories are appended to the `require` roots in `require=` order **after** the mod's own roots. Dependency files are **not** auto-executed at startup; they only run when explicitly `require`d (execute-once).
- **Own roots beat dependency roots**: if both the mod under test and a dependency provide the same relative module path, the mod's own file is resolved first.

---

## Built-in Stub Packs & Custom Stubs

Gate 1 always loads `src/gate1/stubs/core.lua`, which provides core context predicates (`isServer`, `isClient`, `isMultiplayer`, `isSinglePlayer`), `Events`, `Hook`, `LuaEventManager.AddEvent`, `writeLog`, `getTimestamp`, `getTimestampMs`, `getGameTime`, `instanceof`, `ISTimedActionQueue`, and `ISBaseTimedAction`.

To load additional stubs:

- **Built-in stub packs (`PZ_STUB_PACKS` / `config.stub_packs`)**: comma-separated pack names resolved to `src/gate1/stubs/<name>.lua`, for example:

  ```sh
  PZ_STUB_PACKS=java,game lua src/gate1/run.lua --mod /path/to/MyMod
  ```

- **Custom stub directories (`PZ_STUBS` / `config.stubs`)**: semicolon-separated directory paths; every `*.lua` file in each directory is loaded after the built-in packs.

See [src/gate1/stubs/SURFACE.md](../src/gate1/stubs/SURFACE.md) for the exact inventory of globals, classes, and member shapes provided by the shipped stubs.

---

## Umbrella Serve Mode (`PZ_UMBRELLA`)

Umbrella serve mode lazily serves class, method, global function, and event shapes from a local [Umbrella](https://github.com/asledgehammer/Umbrella) EmmyLua annotation clone without needing to hand-write stubs for every vanilla class.

Set `PZ_UMBRELLA` (or `config.umbrella`) to the root directory containing `library/`:

```sh
PZ_UMBRELLA=/path/to/umbrella-root PZ_STRICT=1 lua src/gate1/run.lua --mod /path/to/MyMod
```

- **Validation**: if the path is invalid or missing `library/`, the runner prints `PZ_UMBRELLA path invalid — mode off` and continues with Umbrella off. When `PZ_UMBRELLA` is unset, Umbrella is completely inactive.
- **Lazy indexing & L1 shape serving**: builds a filename-stem index of `library/**/*.lua` without opening files upfront. Class files are parsed only when touched, walking `---@class Name: Parent1, Parent2` inheritance with cycle protection. Served methods record calls (via `mock` when available) and return `nil`—Umbrella never guesses return values.
- **Shipped-packs-win precedence**:
  - **Globals**: `rawget(_G, k)` is always checked first; `Umbrella.resolve_global` only runs when a global is absent.
  - **Methods**: `Umbrella.init` attaches fallback `__index` metatables to shipped tables mapped in `Umbrella.MAPPING` (or wrapped with `Umbrella.w(obj, className)`). Existing keys and original `__index` chains are checked before falling back to `Umbrella.resolve_method`.
- **`PZ_STRICT=1` interaction**:
  - `Umbrella.resolve_global` is consulted inside the strict `_G` guard. Without `PZ_STRICT=1`, unknown globals return `nil` as usual, while method-level delegation on mapped/served tables and `Umbrella.chain` still operate.
  - With `PZ_STRICT=1`, unknown globals raise `PZ_STRICT: unknown global '<name>'`, and unknown methods/fields on served or mapped classes raise `PZ_STRICT: unknown method 'Class:name'`.
  - Under `PZ_STRICT=1`, `Events.*` lookups that miss the shipped allowlist consult `library/events.lua` via `Umbrella.events_lookup` and extend the allowlist on match.
- **`Hook.*` limitation**: `library/events.lua` only declares `Events.*`, never `Hook.*`. Umbrella event extension therefore applies to `Events.*` only; `Hook.*` remains limited to the shipped allowlist.
- **`Umbrella.chain(obj, "m1", "m2", ...)`**: explicit L1 materializer that walks each method's `@return` annotation step by step. When a return token matches a class in the stem index, it returns a served stub for that class; primitive, union, generic, or non-class return types do not coerce and return `nil`.
