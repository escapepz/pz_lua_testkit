# Vendor patches

This directory vendors third-party files. Constraint: **vendor = upstream +
documented patches, never silent.** Every deviation from upstream lives in
this file with an exact diff; re-apply after any future vendor upgrade.

## inspect.lua

- **Upstream:** kikito/inspect.lua 3.1.0
  (source: `pz_lua_commons/submodule/kikito/inspect.lua`; pristine copy at
  vendor time — `diff` clean before patching)
- **Patched:** 2026-11-13
- **Reason:** The Project Zomboid Kahlua environment does not expose a global
  `next` (`type(next) == "nil"`), so upstream `rawpairs` returns a nil
  iterator and every generic-for over it fails with
  `tried to call nil` (first hit at `countCycles:147`). Falling back to the
  platform's `pairs` is correct for inspect's traversal: on PZ, `pairs` is
  the game's insertion-ordered table.pairs, and inspect re-sorts keys via
  `table.sort` anyway, so output is deterministic and complete.
- **Re-apply note:** after upgrading the vendored inspect.lua, re-check
  whether upstream `rawpairs` still returns the `next, t, nil` triple; if the
  upstream no longer uses `next` (or PZ exposes `next`), drop the patch and
  update this file. Gate2 (`scripts\test-gate2.cmd`, 21/21) is the
  regression test for this patch; gate1 (67/67) guards standard Lua 5.1.

### Diff (vs upstream 3.1.0, unified-ish)

```diff
--- inspect.lua (upstream kikito/inspect.lua 3.1.0)
+++ inspect.lua (vendored)
@@ -55,7 +55,8 @@
 local gsub = string.gsub
 local fmt = string.format

 local function rawpairs(t)
-   return next, t, nil
+   if next ~= nil then return next, t, nil end
+   return pairs(t)
 end
```

(Exact upstream line context: `rawpairs` sits at lines 57-59; the patch
changes only its body — `return next, t, nil` becomes the two-line
next-or-pairs fallback. No other line of the file is modified.)
