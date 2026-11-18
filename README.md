# PZ Lua Testkit

Offline unit and integration testkit for Project Zomboid B42 Lua mods — execute and verify your mod Lua in seconds without launching the game.

[![npm](https://img.shields.io/npm/v/pz_lua_testkit?style=flat-square&labelColor=000000)](https://www.npmjs.com/package/pz_lua_testkit)
[![Project Zomboid](https://img.shields.io/badge/Project%20Zomboid-42.x-orange.svg?style=flat-square&labelColor=000000)](https://projectzomboid.com/)
[![CI](https://img.shields.io/github/actions/workflow/status/escapepz/pz_lua_testkit/ci.yml?branch=main&style=flat-square)](https://github.com/escapepz/pz_lua_testkit/actions/workflows/ci.yml)
[![Ask_Zread](https://img.shields.io/badge/Ask_Zread-_.svg?style=flat-square&color=00b0aa&labelColor=000000&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB3aWR0aD0iMTYiIGhlaWdodD0iMTYiIHZpZXdCb3g9IjAgMCAxNiAxNiIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTQuOTYxNTYgMS42MDAxSDIuMjQxNTZDMS44ODgxIDEuNjAwMSAxLjYwMTU2IDEuODg2NjQgMS42MDE1NiAyLjI0MDFWNC45NjAxQzEuNjAxNTYgNS4zMTM1NiAxLjg4ODEgNS42MDAxIDIuMjQxNTYgNS42MDAxSDQuOTYxNTZDNS4zMTUwMiA1LjYwMDEgNS42MDE1NiA1LjMxMzU2IDUuNjAxNTYgNC45NjAxVjIuMjQwMUM1LjYwMTU2IDEuODg2NjQgNS4zMTUwMiAxLjYwMDEgNC45NjE1NiAxLjYwMDFaIiBmaWxsPSIjZmZmIi8%2BCjxwYXRoIGQ9Ik00Ljk2MTU2IDEwLjM5OTlIMi4yNDE1NkMxLjg4ODEgMTAuMzk5OSAxLjYwMTU2IDEwLjY4NjQgMS42MDE1NiAxMS4wMzk5VjEzLjc1OTlDMS42MDE1NiAxNC4xMTM0IDEuODg4MSAxNC4zOTk5IDIuMjQxNTYgMTQuMzk5OUg0Ljk2MTU2QzUuMzE1MDIgMTQuMzk5OSA1LjYwMTU2IDE0LjExMzQgNS42MDE1NiAxMy43NTk5VjExLjAzOTlDNS42MDE1NiAxMC42ODY0IDUuMzE1MDIgMTAuMzk5OSA0Ljk2MTU2IDEwLjM5OTlaIiBmaWxsPSIjZmZmIi8%2BCjxwYXRoIGQ9Ik0xMy43NTg0IDEuNjAwMUgxMS4wMzg0QzEwLjY4NSAxLjYwMDEgMTAuMzk4NCAxLjg4NjY0IDEwLjM5ODQgMi4yNDAxVjQuOTYwMUMxMC4zOTg0IDUuMzEzNTYgMTAuNjg1IDUuNjAwMSAxMS4wMzg0IDUuNjAwMUgxMy43NTg0QzE0LjExMTkgNS42MDAxIDE0LjM5ODQgNS4zMTM1NiAxNC4zOTg0IDQuOTYwMVYyLjI0MDFDMTQuMzk4NCAxLjg4NjY0IDE0LjExMTkgMS42MDAxIDEzLjc1ODQgMS42MDAxWiIgZmlsbD0iI2ZmZiIvPgo8cGF0aCBkPSJNNCAxMkwxMiA0TDQgMTJaIiBmaWxsPSIjZmZmIi8%2BCjxwYXRoIGQ9Ik00IDEyTDEyIDQiIHN0cm9rZT0iI2ZmZiIgc3Ryb2tlLXdpZHRoPSIxLjUiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIvPgo8L3N2Zz4K&logoColor=ffffff)](https://zread.ai/escapepz/pz_lua_testkit)
[![DeepWiki](https://img.shields.io/badge/DeepWiki-_.svg?style=flat-square&color=6a0dad&labelColor=000000&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB3aWR0aD0iMTYiIGhlaWdodD0iMTYiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHJva2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI%2BPHBhdGggZD0iTTEyIDJMMiA3bDEwIDUgMTAtNS0xMC01eiIvPjxwYXRoIGQ9Ik0yIDE3bDEwIDUgMTAtNXBNMiAxMmwxMCA1IDEwLTUiLz48L3N2Zz4%3D&logoColor=ffffff)](https://deepwiki.com/escapepz/pz_lua_testkit)

## Why pz_lua_testkit

Static type-checkers like Umbrella catch signature drift immediately, but they cannot execute your Lua to catch runtime logic bugs. `pz_lua_testkit` runs your mod's Lua in two gates: **Gate 1** (clean-room Lua 5.1 stubs, fast and CI-ready) and **Gate 2** (local-only cross-check against Project Zomboid's real Kahlua runtime). Using both together gives you instant static checks plus real execution coverage.

| Criterion        | pz_lua_testkit            | Umbrella only         | Manual in-game testing       |
| ---------------- | ------------------------- | --------------------- | ---------------------------- |
| Level of testing | Executes code (2 gates)   | Static type-checking  | Manual, in game              |
| Feedback speed   | Seconds                   | Instant in the editor | Minutes (launch the game)    |
| CI automation    | Yes (Gate 1)              | Yes                   | Not feasible                 |
| IP risk          | Safe (ships no game code) | Safe                  | Decompiled code leaks easily |
| Setup cost       | Moderate                  | Low                   | None                         |

## Quickstart

### 1. Install Lua 5.1

`pz_lua_testkit` requires a **PUC-Rio Lua 5.1.x** interpreter (32-bit or 64-bit; do **not** use LuaJIT or Lua 5.2+, because `check_globals.lua` reads Lua 5.1 `string.dump` bytecode).

Install it anywhere on your `PATH` — for example via Chocolatey on Windows (`choco install lua51`), your OS package manager, or by extracting a standalone binary (if extracting a Windows zip manually, keep `lua5.1.dll`, `.manifest` files, and `Microsoft.VC80.CRT/` next to `lua5.1.exe`). Verify:

```bat
lua5.1 -v
```

### 2. Add `pz_lua_testkit` to your mod

**Via npm / pnpm (recommended):**

```bash
pnpm add -D pz_lua_testkit   # or: npm i -D pz_lua_testkit
```

Optionally add a `"test"` script to your mod's `package.json`:

```json
{
    "scripts": {
        "test": "lua5.1 node_modules/pz_lua_testkit/src/gate1/run.lua --mod ."
    }
}
```

**Without npm (git clone):** Clone this repository to a central folder and point `lua5.1` at `src/gate1/run.lua` (you can also smoke-test the kit itself by running `lua5.1 src/gate1/run.lua` inside the clone).

> If you prefer a standalone `TESTS/run.lua` entry script with custom `runner.run(config)` defaults instead of CLI flags, see the programmatic API in [docs/reference.md](docs/reference.md#programmatic-api-runnerrun).

### 3. Write your first spec

Create `TESTS/specs/first_spec.lua` inside your mod using the `pzspec` DSL (`describe`, `it`, `expect`):

```lua
describe("MyMod", function()
    it("computes expected value", function()
        expect(1 + 1).toBe(2)
    end)
end)
```

### 4. Run tests and enable strict mode

Run your mod suite, then re-run with `PZ_STRICT=1` to catch typos in globals or event names before launching the game:

```bat
lua5.1 node_modules/pz_lua_testkit/src/gate1/run.lua --mod .
set "PZ_STRICT=1" && lua5.1 node_modules/pz_lua_testkit/src/gate1/run.lua --mod .
```

_(Using a git clone? Replace `node_modules/pz_lua_testkit/` with your clone path and `--mod .` with `--mod path/to/MyMod`.)_

## Documentation

- [Specs, assertions & mocking](docs/specs-and-mocking.md) — `pzspec` DSL, matchers, spies/mocks, `testkit` API, and `PZ_STRICT`.
- [Mod loader & stubs](docs/mod-loader-and-stubs.md) — B41/B42 layout resolution, `require`, `PZ_MOD_PATH`, stub packs, and `PZ_UMBRELLA`.
- [Configuration, CLI & Gate 2 reference](docs/reference.md) — `runner.run(config)` keys, env vars, exit codes, and local Gate 2 setup.
- [Stub surface record](src/gate1/stubs/SURFACE.md) — clean-room stub coverage and sizing notes.
- [Vendored patches](src/vendor/PATCHES.md) — changes applied to vendored third-party files.

## IP & License

- **No game code or binaries shipped:** this repository contains zero Project Zomboid source, Lua files, or binaries. You provide PUC-Rio Lua 5.1.x yourself (`tools/` and `build/` are gitignored).
- **Gate 2 is local-only:** Gate 2 requires a local JDK and your installed `projectzomboid.jar` via reflection; it never runs in CI.
- **License:** clean-room testkit code is licensed under the MIT [LICENSE](LICENSE).
