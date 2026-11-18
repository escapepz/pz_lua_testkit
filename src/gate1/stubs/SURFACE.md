# SURFACE.md — union mock surface of CAF / MAF / JASM

Name-list inventory of the PZ API surface that the three mods' hand-written test mock layers
stub. Sources (read 2026-11-12):

- `pz_mods_2026/container_authority_framework/TESTS/tests/mock_pz.lua` (CAF)
- `pz_mods_2026/manipulation_authority_framework/TESTS/tests/mock_pz.lua` (MAF)
- `pz_mods_2026/just_another_shop_mod/TESTS/tests/mock_pz.lua` (JASM)
- For `## events` only: a grep of each mod's real Lua code (media/lua + TESTS) for
  `Events.On*` references. Bundled `.libraries/` API-annotation copies were excluded —
  they are vendor docs, not mod code.
- Coverage marks checked against `src/gate1/stubs/core.lua`.

Tasks 6–8 consume these lists verbatim. One line per member; facts only.
`(covered: core.lua)` = the gate1 stub already provides it.

## java

Java types and stdlib extensions the mock layers touch. Short list — the mods' test
mocks are almost pure Lua.

- `list` (java.util.List shape): `size()` and `get(i)` with 0-based `i` — JASM
  (returned by ItemContainer `getItems()` and `getItemsFromCategory(category)`; real JASM
  code calls `:size()` / `:get(i)` on results). CAF and MAF never touch Java collections.
- No HashMap, Vector2f, Vector3f or any other Java type is constructed or called by any of
  the three mock layers — nothing else to stub.
- Kahlua stdlib: the mocks rely only on standard Lua 5.1-era builtins (table.insert,
  table.remove, ipairs, pairs, setmetatable, getmetatable, type, tostring, select,
  os.time, os.clock, math.sqrt, print). No Kahlua-specific table.* / string.* extensions
  are required by any mock layer. (Real-VM semantics for the java-pack extension names:
  see `## gate2 alignment notes`.)

## game

Engine globals and classes, per member with the needing mod(s).
Member notes give arity and return shape only.

### context predicates

- `isServer()` -> boolean — CAF, MAF, JASM (covered: core.lua). Default value disagrees per mod: see DISAGREEMENTS D2.
- `isClient()` -> boolean — CAF, MAF, JASM (covered: core.lua). Defaults SP-false everywhere.
- `isMultiplayer()` -> boolean — CAF, MAF (covered: core.lua). JASM's layer omits it; union still needs it.
- `instanceof(obj, className)` -> boolean — CAF (covered: core.lua; argument order ALIGNED to the real signature per D1 RESOLVED below). CAF checks metatable identity for IsoPlayer / IsoObject / IsoDeadBody.

### logging and time

- `writeLog(category, message)` -> nil, appends {category, message} to a capture list — CAF, MAF (covered: core.lua).
- `getTimeInMillis()` -> integer milliseconds — JASM.
- `debug` — JASM, fallback only if the host lacks it: `getinfo()` -> info table with a `source` field.
- core.lua-only extras no mod mock layer needs (informational): isSinglePlayer, getTimestamp, getTimestampMs, getGameTime, Hook.

### engine globals

- `ModData` — JASM. Members: `getOrCreate(key)` -> persistent per-key table, `get(key)` -> table|nil, `add(key, val)` -> replace, `exists(key)` -> boolean, `transmit(key)` -> nil no-op, `request(key)` -> nil no-op.
- `ZomboidGlobals` — CAF, MAF. Empty table, must exist.
- `SandboxVars` — CAF, MAF, JASM. Plain table keyed by mod namespace; seeds differ per mod: see DISAGREEMENTS D6.
- `getSquare(x, y, z)` -> square mock with getX/getY/getZ (plus getObjects/addObject) — JASM.
- `getSpecificPlayer(id)` -> player mock (username, isAdmin -> boolean, getInventory -> container, getPlayerNum -> number set to id, getSquare -> square|nil, DistTo, DistTo2D) — JASM.
- `getCore()` -> object with `getGameVersion()` -> version string — JASM.
- `sendClientCommand(...)` -> nil no-op — JASM.
- `sendServerCommand(...)` -> nil no-op — JASM.
- `triggerEvent(name, ...)` -> nil no-op (plain global function; distinct from the Events table) — JASM.

### engine managers and utilities

- `luautils` — JASM. Members: `countItemsRecursive(containerList, initialCount)` -> number (sums each container:getItems():size()), `walkAdj(player, square, isWalk)` -> nil, `walkToContainer(container, playerNum)` -> boolean true, `okModal(text, centerX, centerY, target, onOk)` -> nil. Note: JASM installs countItemsRecursive at file scope, the other three only when no luautils exists yet.
- `IsoUtils` — JASM. Members: `DistanceTo(x1, y1, z1, x2, y2, z2)` -> number, `DistanceTo2D(x1, y1, x2, y2)` -> number.
- `AdjacentFreeTileFinder` — JASM. Members: `isTileOrAdjacent(sq1, sq2)` -> boolean, `Find(sq, player)` -> square (returns input).
- `ScriptManager` — JASM. Members: `instance.getItem(fullType)` -> script item exposing `getActualWeight()` -> number.
- `HaloTextHelper` — JASM. Members: `addBadText(player, text)` -> nil, `addText(player, text)` -> nil.
- `ISTransferAction` — CAF. Members: `transferItem()` -> nil.
- `LuaEventManager` — not stubbed by any mock layer; no `LuaEventManager.AddEvent` or trigger call exists in any of the three mods' Lua code (only inside bundled .libraries annotation copies, out of scope).

### UI classes (IS tree) — JASM unless marked

- `ISPanel` — base. Members: `derive(name)` -> derived class, `new(x, y, width, height)` -> instance, initialise, instantiate, createChildren, setVisible(visible), addToUIManager.
- Derived panels (inherit ISPanel surface, no extra members): ISButton, ISScrollingListBox, ISImage, ISLabel, ISComboBox, ISTiledIconListBox, ISTextEntryBox.
- `ISInventoryPage` — adds `setNewContainer(inventory)`.
- `ISTableLayout` — adds calculateLayout, addColumn, addColumnFill, `addRow()` -> row with `index()` -> 0, addRowFill, setElement.
- `ISEntityWindow` — adds nothing beyond ISPanel surface in the mock.
- `ISWorldObjectContextMenu` — `addToolTip()` -> tooltip with `setName(name)`.
- `ISContextMenu` — `getNew(playerOrParent)` -> menu with `addOption(name, target, onSelect, ...)`, `addSubMenu(option, menu)`, and nested getNew.
- `ISTimedActionQueue` — `add(action)` -> nil (covered: core.lua, which also adds getTimedActionQueue).
- `ISBaseTimedAction` — JASM, MAF (covered: core.lua, partial — see DISAGREEMENTS D7). JASM members: `derive(name)`, `new(character)` -> action storing character, `setOnComplete(func, ...)` storing func plus varargs. MAF members: `new(character)`, `stop()`.
- `ISWalkToTimedAction` — JASM. Derived from ISBaseTimedAction, no extra members.
- MAF-only placeholders, existence required: ISDestroyStuffAction, ISDismantleAction, ISMoveablesAction (each inheriting the ISBaseTimedAction surface), ISMoveableSpriteProps, ISDestroyCursor, ISMoveableCursor, ISMoveableInfoWindow, ISMoveablesIconToolTip (empty tables).

### player and world classes

- `IsoPlayer` — CAF, MAF, JASM. Class form (CAF, MAF): `new(username)`, `getUsername()` -> string, `getAccessLevel()` -> "Admin"|"None". Factory form (JASM): fields username/admin/inventory/playerNum, members getUsername, `isAdmin()` -> boolean, `getInventory()` -> container, getPlayerNum, getSquare, `DistTo(target|x, y)` (accepts square-like or coords, delegates to IsoUtils), `DistTo2D(x, y)` -> number. Authority API diverges: see DISAGREEMENTS D5.
- `InventoryItem` — CAF, JASM. CAF class form: `new(fullType)`, `getFullType()` -> string. JASM factory form: fields type/count/weight, members getFullType, `getActualWeight()` -> number, `setWeight(weight)`, getCount -> number, getCategory -> string, getInventory -> nil, isContainer -> false.
- `ItemContainer` — CAF, JASM. CAF class form: `new(type, parent)`, `getType()` -> string, `getParent()` -> container|nil. JASM factory form members: getParent, `setParent(parent)`, getType, `getInventory()` -> self, `isExplored()` -> boolean, `setExplored(bool)`, `getItemsFromCategory(category)` -> list shape, `getCapacityWeight()` -> number (see DISAGREEMENTS D8), `getCapacity()` -> number (max limit), `getEffectiveCapacity(chr)` -> number (max limit), `getContentsWeight()` -> number (sum of item weights), `getItems()` -> list shape, `getItemCount(itemType)` -> number, `getCountRecurse(predicate)` -> number, `contains(item|fullType)` -> boolean, `addItem(item|fullType)`, `AddItem` (alias of addItem), `removeItem(item|fullType)`, `Remove` (alias of removeItem), `getContainer()` -> self.
- `IsoObject` — CAF, MAF, JASM. Three divergent forms: see DISAGREEMENTS D4. CAF: `new()` no args, `getModData()` -> table. MAF: `new(objectName)`, getModData, `getObjectName()` -> string. JASM: getModData, `getSquare()` -> square|nil, `setSquare(square)`, `getSprite()` -> sprite, `getContainer()` -> nil.
- `IsoDeadBody` — CAF. Members: `new()`, `getModData()` -> table; instance must satisfy `instanceof(obj, "IsoDeadBody")`.
- `IsoGridSquare` — MAF, JASM. Same member trio getX/getY/getZ -> numbers, divergent construction: see DISAGREEMENTS D3. MAF: class `new(x, y, z)`. JASM square factory: `getObjects()` -> table, `addObject(obj)`.
- `IsoSprite` — JASM. Members: `getName()` -> string, `getProperties()` -> property map with `has(key)` -> boolean, `get(key)` -> nil.
- `middleclass` — JASM. OOP factory: `middleclass(name)` -> class; `class.new(...)` invokes `initialize`; class itself callable. Global plus module form (see package.preload list).
- `JASM_AcceptTradeAction` — JASM. `new(player, entity, payload)` -> instance.
- `JASM_PublishTradeAction` — JASM. `new(player, entity, payload)` -> instance.
- Mod singletons: `ContainerAuthorityFramework` — CAF (empty placeholder table). `ManipulationAuthorityFramework` — MAF (nil placeholder).

### module dependencies (package.preload) — JASM

JASM's layer installs these require keys; a JASM mock pack must provide equivalents.

- `pz_utils_shared`: `konijima.Utilities` { IsPlayerAdmin(player) -> false, SendClientCommand(...), SendServerCommandTo(...), `SquareToString(square)` -> string }, `escape.SandboxVarsModule()` -> { `Init(namespace, defaults)`, `Create(name, defaults)` -> { `Get(key, default)` }, `Get(namespace, key, default)`, `GetAll(namespace)` -> table }, `escape.Utilities` { `GetIRLTimestamp()` -> number }.
- `pz_lua_commons_shared`: `kikito` { middleclass }.
- `zul`: `ZUL.new(name)` -> logger with info, error, debug, trace, warn, setLevel.
- PZ engine modules returning the matching global table from above: `ISUI/ISPanel`, `ISUI/ISButton`, `ISUI/ISScrollingListBox`, `ISUI/ISImage`, `ISUI/ISLabel`, `ISUI/ISComboBox`, `ISUI/ISTextEntryBox`, `ISUI/ISInventoryPage`, `TimedActions/ISBaseTimedAction`, `TimedActions/ISWalkToTimedAction`, `TimedActions/ISTimedActionQueue`, `Entity/ISUI/Windows/ISEntityWindow`, `Entity/ISUI/Controls/ISTableLayout`, `Entity/ISUI/CraftRecipe/ISTiledIconListBox`.
- JASM-internal UI modules stubbed to no-op (existence only): just_another_shop_mod/entity_ui/customer_view_window (open), owner_view_window (open), entity_ui/models/shop_data_manager, entity_ui/components/shop/shared/shop_search_filter_panel, entity_ui/components/product/product_list_panel, entity_ui/components/shop/customer/shop_item_header, entity_ui/components/shop/customer/shop_item_gives_panel, entity_ui/components/shop/customer/shop_item_requirements_panel, entity_ui/components/shop/customer/shop_item_action_footer, entity_ui/components/shop/owner/shop_trade_offer_panel, entity_ui/components/shop/owner/shop_requirement_panel, entity_ui/components/shop/owner/shop_footer_panel.

### test-support API (module-local, not engine surface)

CAF and MAF mock modules expose: setupGlobalEnvironment(), triggerOnInit(); CAF additionally setServer/setClient/setMultiplayer(active) and triggerEvent(name). Internal capture tables (_eventCallbacks, _initCallbacks, _testLogs) are private to each mock, not surface.

## events

Every `Events.OnX` name referenced via `Events.OnX.Add` in real mod Lua code or registered
as a stub by a mock layer. Nine names; no `LuaEventManager.AddEvent` registrations exist in
any of the three mods.

1. `OnClientCommand` — MAF, JASM
2. `OnContainerUpdate` — JASM
3. `OnFillWorldObjectContextMenu` — CAF, MAF, JASM
4. `OnGameBoot` — CAF (mock stub only; no direct CAF code reference), MAF, JASM
5. `OnGameStart` — CAF, MAF, JASM
6. `OnInitGlobalModData` — CAF, MAF, JASM
7. `OnLoadedTileDefinitions` — JASM
8. `OnRefreshInventoryWindowContainers` — JASM
9. `OnServerCommand` — JASM

CAF and MAF enumerate exactly their three lifecycle events; JASM and core.lua accept any
`On*` name. Dispatch-semantics divergence: DISAGREEMENTS D9. core.lua Events (covered:
core.lua) auto-creates any On* name with Add/Remove/Clear/_fire/_count.

Task 6 (2026-11-12) additions on top of the auto-create base:

- Allowlist: `src/gate1/stubs/events_list.lua` returns `{ names = <sorted A->Z> }` —
  the 9 names above plus core B42 lifecycle `OnTick`, `OnPlayerUpdate` (plan-pinned).
  Exposed as `_G.__pz_events_list`; `LuaEventManager.AddEvent(name)` (core.lua mock)
  sorted-inserts into it and creates the `Events[name]` dispatcher, idempotently.
- Strict tier: only under `_G.pz_strict` (`PZ_STRICT=1`, armed by gate1's runner.lua),
  indexing an unknown `On*` name on Events/Hook errors `PZ_STRICT: unknown PZ event`.
  Non-strict behavior unchanged (auto-create).
- Real-jar probe (gate2, 2026-11-12): the gate2 env exposes NO `LuaEventManager`
  global at all, and indexing an unknown name on the real `Events` registry returns
  nil (no auto-create, no error). `OnUnitDeath` (used as a fixture name in the gate1
  selftest) does not exist in the real registry — it is not a real B42 event.
  `OnGameStart` / `OnTick` / `OnPlayerUpdate` from the allowlist DO exist there.
  Events allowlist + strict tier is therefore gate1-only surface until Phase 6 parity.

### DISAGREEMENTS

Where the three mods (or a mod vs core.lua) give the same member different semantics.
Task 7 resolves each against gate2.

- **D1 — instanceof argument order.** RESOLVED (2026-11-12, Task 8): the real PZ signature is `instanceof(obj, className)` — decompiled `zombie.Lua.LuaManager$GlobalObject.instof(Object obj, String name)` at `pz_vanilla_code_base/java/zombie/Lua/LuaManager.java:2919` (`@LuaMethod(name = "instanceof", global = true)`; vanilla Lua usage agrees, e.g. `pz_vanilla_code_base/lua/client/BuildingObjects/TimedActions/ISBuildAction.lua:12` — `instanceof(object, "IsoWindow")`). CAF's mock shape was correct; core.lua was aligned from the reversed `(class, obj)` to `(obj, className)` (subclass walk over stub classes' `__class`/`__name`/`__super`). Pinned by `src/gate1/specs/game_pack_spec.lua` (instanceof suite). Original disagreement text: CAF mock: `instanceof(obj, className)`. core.lua: `instanceof(class, obj)` (reversed). Mod code written against the CAF shape would misbehave silently under core.lua's order.
- **D2 — default network context.** CAF mock defaults all three predicates false (SP). MAF mock defaults `isServer()` TRUE (server context by default), isClient/isMultiplayer false. JASM defaults server/client false. core.lua keys everything off an overlords_ctx global instead of fixed defaults.
- **D3 — square construction.** MAF exposes a class `IsoGridSquare.new(x, y, z)`; JASM exposes plain-table factories `getSquare(x, y, z)` / createSquare. Same reader members (getX/getY/getZ), incompatible construction path.
- **D4 — IsoObject shape.** CAF: no-arg constructor, getModData only. MAF: objectName-arg constructor adding getObjectName. JASM: spriteName-arg factory adding getSquare/setSquare/getSprite/getContainer. Union needs a superset with a constructor that accepts optional name.
- **D5 — player authority API.** CAF/MAF: `getAccessLevel()` -> "Admin"|"None" string. JASM: `isAdmin()` -> boolean. Both must exist on the union player mock.
- **D6 — SandboxVars seeds.** CAF seeds a CAF-example namespace (two boolean flags). MAF seeds a MAF namespace with three numeric listener limits. JASM seeds a numeric ItemNumbersLimitPerContainer default (real code adds its own namespace module). The mock pack must be a namespace-agnostic store, not any single mod's shape.
- **D7 — ISBaseTimedAction surface.** MAF: minimal new/stop. JASM: derive/new/setOnComplete with varargs capture. core.lua: bare new() -> {} only — lacks derive, stop, setOnComplete. JASM- and MAF-style consumers both break under current core.lua.
- **D8 — ItemContainer weight semantics.** JASM (B42 adaptation): `getCapacityWeight()` returns CURRENT contents weight while `getCapacity()` / `getEffectiveCapacity(chr)` return the MAX limit; `getContentsWeight()` sums items. CAF's container has no weight members at all. Task 7 must not "fix" getCapacityWeight into a constant max — mod logic depends on the JASM shape.
- **D9 — Events dispatch semantics.** CAF: per-event callback lists. MAF: routes ALL of OnInitGlobalModData / OnGameStart / OnGameBoot into ONE shared list, so firing any fires all. JASM: generic no-op Add per On* key. core.lua: per-event isolated Add/Remove/Clear/_fire/_count. A per-event testkit mock silently changes MAF-style test semantics; the shared-list behavior cannot be preserved by an isolated-per-event pack.

## umbrella serve mode notes

Facts about the Umbrella serve mode (`PZ_UMBRELLA`, `src/gate1/stubs/umbrella.lua`,
wired by `src/gate1/runner.lua`) that constrain how shipped stub bodies are written
and how verification must run. Mode shipped 2026-11-13 (Tasks 1-5); design doc:
`docs/superpowers/specs/2026-11-13-umbrella-serve-mode-design.md`.

- What Umbrella serves vs what shipped packs serve: Umbrella lazily serves SHAPE
  for the canonical clone's whole API (class/parent names, method names, param
  arities, raw `@return` tokens) from the user's local EmmyLua clone — served
  methods record calls and return nil (pure L1). The shipped packs (`core.lua`,
  `game.lua`, `java.lua`) provide BEHAVIOR for the members CAF/MAF/JASM actually
  touch. Shipped wins at TWO layers: global level (the resolver only fires when
  `rawget(_G, k)` misses) and method level (shipped class tables get a fallback
  `__index` attached at init-on; Lua hits rawget keys before `__index`, so
  shipped methods never reach the resolver — only true misses delegate).

- Strict-proof convention (Task 4 fix rounds, 2026-11-13): shipped bodies read
  internal/unmaterialized state via `rawget(self, "field")` / `rawget(arg,
  "field")` — a plain `self.field` read on a Seam C-wrapped object reaches the
  attached fallback `__index` and strict-errors `PZ_STRICT: unknown method
  'Class:field'` under mode-on + PZ_STRICT whenever the key is nil-assigned or
  absent. Fixed sites: game.lua `IsoObject:getSquare` + `newCorePlayer`
  (`square`), `ItemContainer:getParent` (`parent`), `ISContextMenu.getNew`
  (the arg's `player` field), core.lua `instanceof` walk (`obj.__class` /
  `c.__super` — `defineClass` nil-assigns `__super` on root classes). A plain
  read stays safe only when the key is guaranteed materialized AND the lookup
  cannot reach an attached fallback. The discipline carries a semantic delta:
  a `rawget` read skips class-level statics that a plain read would find
  through the attached fallback `__index` — no shipped class carries the
  affected statics today, so no shipped behavior changes (future pack bodies
  must not rawget a field that lives only on the class table).

- init(nil) restore asymmetry: metatables restore byte-identically (feature-off
  identity), but allowlist extensions made by `events_lookup` PERSIST across
  `init(nil)` — the extension inserts into the shipped `_G.__pz_events_list`
  (same shape as the `LuaEventManager.AddEvent` precedent); resetState clears
  umbrella-owned state only, never the shipped allowlist.

- Sixth launch shape (of the six shipped verification shapes: default /
  strict / clone / clone+strict / packs+clone / packs+clone+strict) to pin in
  future verification: `PZ_STUB_PACKS=game PZ_UMBRELLA=<clone> PZ_STRICT=1`.
  It was never run before the Task 4 fix round and is the configuration that
  EXPOSED the strict-proof classes above. What attaches fallbacks to shipped
  tables BEFORE spec files load is packs pre-load + mode-on (strict is not
  the differentiator — without `PZ_STUB_PACKS` the shipped class tables do not
  exist yet at runner.lua's startup init, and PZ_STRICT does not change attach
  timing); this is also the shape that breaks file-level pristine captures —
  see the capture note in `src/gate1/specs/umbrella_integration_spec.lua`.

- Namespaced ret tokens abort `Umbrella.chain`: a raw `@return` token only
  continues a chain when it resolves to a parsed class via the stem index;
  namespaced tokens (e.g. `umbrella.ContextMenuItemStack`), primitives, unions
  and generics (`Data[]`) never coerce — the chain aborts with nil at that
  step. Future enrichment (namespace-prefix resolution) would be an L2/Seam-B
  change, not an L1 one.

## mod loader notes

Facts about the Phase 3 mod loader (`--mod` / `config.mod`,
`src/gate1/stubs/pzrequire.lua`, wired by `runner.prepare_mod` + `runner.run`
pinned steps 6-9) that constrain how mod/fixture top-level code must be
written and how verification must run. Shipped 2026-11-14 (Tasks 1-4); plan:
`docs/superpowers/plans/2026-11-14-gate1-mod-loader-plan.md`.

- Strict-proof convention extends to MOD top-level code (Task 2 review
  ruling, 2026-11-14 — the `## umbrella serve mode notes` strict-proof
  convention above, applied to the loader shape): under `--mod` +
  `PZ_STRICT=1` the unknown-global guard arms BEFORE mod auto-exec
  (runner.lua pinned step 7 precedes step 8), so mod top-level code reading
  a possibly-unmaterialized global must read it via
  `rawget(_G, "name") or <default>` — the plain `(name or default)` form
  reaches the guard's `__index` and errors `PZ_STRICT: unknown global
  '<name>'`, which surfaces as `PZ_MOD LOAD FAIL <file>: ...` and fails the
  run. Pure top-level ASSIGNMENTS stay free (the guard is `__index`-only —
  reads only). The spec-side fixture builders write this shape
  (`mod_loader_spec` orderChunk/order2 counter, `pzrequire_spec` +
  `reset_loaded_spec` util counter — the T4 copy kept byte-identical to the
  T1 original).
- Dep mods are require ROOTS ONLY (documented deviation, plan Global
  Constraints): a `PZ_MOD_PATH` hit appends the dep's
  `media/lua/{shared,client,server}` dirs AFTER the own roots and contributes
  NO auto-exec files — dep code executes on require, execute-once. Own-root
  shadowing is deliberate: for the same module name the own mod's root wins
  over the dep root (first-hit scan order); `testkit.provide(name, value)`
  wins over both (synthetic PERSISTENT cache entry keyed `provided:<name>`
  that survives `resetLoaded()`), `testkit.keep(name)` marks the resolved
  path persistent — the persistent tier covers the CACHE ONLY (a kept
  module's load-time-registered Events listeners still clear; register
  inside a function or re-register in `before_each`).
- Verification shape note: the strict+mod shape (`PZ_STRICT=1` + `--mod`)
  was never runnable before the Task 2 review round — it is the
  configuration that EXPOSED the fixture reads above; pin it alongside the
  six Umbrella launch shapes in future verification (see
  `## umbrella serve mode notes` for the shape list).

## gate2 alignment notes

Real-jar probe facts recorded 2026-11-12 (Task 7; throwaway probe scripts, run then deleted).
Source of the native members: `se/krka/kahlua/stdlib/TableLib.class` + `StringLib.class`
inside projectzomboid.jar (the Lua-side stdlib.lua in the game dir does not define them).
Where the java pack (`src/gate1/stubs/java.lua`, loaded via `PZ_STUB_PACKS=java`) stubs a
name the real VM also provides, the pack follows these probed semantics; both-gate cases
in `src/specs/java_pack_spec.lua` keep them locked on both gates.

- Bare gate2 env exposes NO `ArrayList` / `HashMap` / `Vector2f` / `Vector3f` globals
  (probed nil) — the Java exposer is Phase 6. Constructor cases in the java pack spec are
  gate1-only, guarded by the spec's detector `GATE1 = (LuaEventManager ~= nil)`
  (gate1's core.lua always installs LuaEventManager; bare gate2 has none — same probe
  basis as the `## events` facts above).
- `table.isempty(t)` — native on gate2: true iff no entries; errors on non-table args.
- `table.wipe(t)` — native on gate2: clears t IN PLACE and returns NOTHING (probed
  ret == nil, all keys gone), and errors on non-table args (probed: `wipe(5)` errors,
  same argcheck as `isempty`). ALIGNED: the java pack wipe returns nil, NOT the table as
  the plan's interface line said; spec pins the falsy return.
- `table.newarray(...)` — native on gate2: fresh array seeded with the args —
  `newarray()` -> {}, `newarray(5)` -> `{5}` (arg is a value, not capacity),
  `newarray(1,2,3)` -> `{1,2,3}`. Pack uses `{ ... }`.
- `table.getn` — NOT present on gate2 (probed nil). The java pack provides it as an
  alias of `#t` semantics; gate1-only surface (tools/lua5.1.exe also ships a native
  5.0-compat `getn` with the same semantics).
- `string.trim(s)` — native on gate2: strips leading/trailing whitespace (`\t`, `\n`,
  `\r` probed); numbers coerced via the converter (`trim(5)` -> `"5"`); booleans/nil
  error. Pack mirrors: numbers tostring-coerced, other non-strings error.
- `string.split(s, sep)` — native on gate2 with Java `String.split` semantics (probed):
  sep acts as a regex (`"a.b"` split on `"."` -> `{}` — zero parts), ALL trailing empty
  parts dropped (`",a,"` -> `{"", "a"}`, `"a,,"` -> `{"a"}`, `",,"` -> `{}`), middle
  empties kept (`"a,,c"` -> `{"a","","c"}`), leading empties kept, empty input ->
  `{""}`, empty sep -> per-char (`"a,b"` -> `{"a", ",", "b"}`), multi-char literal seps
  work (`"aXXb"`/`"XX"` -> `{"a","b"}`), nil/non-string args error (numbers coerced).
  Pack alignment: sep is matched as a LUA PATTERN with the same trailing-empty-drop,
  which reproduces every probed case including `"."` -> `{}`. Residual divergence
  (documented, not fixable in pure Lua): Java-regex syntax beyond simple separators
  (meta chars with Java-specific meaning, zero-width patterns) may behave differently.
- `string.contains(s, sub)` — native on gate2: literal substring test, empty needle ->
  true, numbers coerced, nil errors. Pack mirrors via plain `find`.
- Kahlua env quirk relevant to pack code: the bare gate2 env has NO `next` global
  (pairs = table.pairs). The java pack is written without `next` (collect-keys-then-nil
  wipe, pairs-loop isempty), so the file itself stays loadable on both gates even though
  only gate1's runner ever loads it.
