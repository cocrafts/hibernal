# Compiler bugs found on the on-chain AI lane

Found while building package 4 of `docs/ON-CHAIN-AI.md` (`sim/env/`, `rules/policy.ms`, `train/`). Both are worked around in place in Hibernal; the workaround is named in each entry so it can be removed when the fix lands.

Every entry was reproduced on the installed `msc 0.2.54` (installed from recompiler `cc7ea0b7`, 2026-09-16) on the C and JS backends, with passing neighbours to bound the trigger. Not re-run on recompiler `main`; source references are to `main` at `f8a913e5` (2026-09-17) and are leads, not traced root causes. No Nim twin was run. Repros as files: `/tmp/hib-ai-bugs/generic/` and `/tmp/hib-ai-bugs/barrel/` (volatile; the full sources are inline below).

| # | Bug | Kind | Status |
|---|---|---|---|
| 1 | `a < x … b > (y)` parses as a generic call `a<…>(y)` | parser lookahead; the checker then accepts a call on an `int32` | open |
| 2 | An extension named like a prelude method (`has`, `isEmpty`, `size`) is lost behind a barrel unless its module is the first `export *` | checker, star re-export | open |

## 1. A comparison chain parses as a generic call

```ms
function probe(value: int32, high: int32): boolean {
	return value < 0 || value > (high + 1);
}
function main(): int32 {
	console.log(probe(5, 3) ? "true" : "false");
	return 0;
}
process.exit(main());
```

- Measured:
  - `msc check`: `OK no type errors`.
  - C: `error: called object type 'int32_t' (aka 'int') is not a function or function pointer` at 2:15.
  - JS: builds; emits `return value((high + 1));` and throws `TypeError: value is not a function` at run time. Silent until the line executes.
  - `msc dump-ast`: `CallExpr [2:30-2:40] … ta=0 || value`, so `0 || value` was captured as the type argument list and everything left of it (`value < 0 ||`) is gone from the expression.
- Trigger: a `<`, later a `>` at the same nesting depth, immediately followed by `(`. What stands between them does not matter.

| Expression | C | JS |
|---|---|---|
| `value < 0 \|\| value > (high + 1)` | compile error | runtime `TypeError` |
| `value < 0 && value > (high + 1)` | compile error | runtime `TypeError` |
| `value < high \|\| value > (3)` | compile error | runtime `TypeError` |
| `value < 0 \|\| high > (value)` | compile error | runtime `TypeError` |
| `value < 0 \|\| 1 > (high)` | compile error | runtime `TypeError` |
| `value < high + 1 \|\| value > (high)` | compile error | runtime `TypeError` |
| `value < 0 \|\| value > high + 1` (no parenthesis after `>`) | `true` | `true` |
| `value > (high + 1)` (no `<`) | `true` | `true` |
| `value < 0 \|\| (value > (high + 1))` (`>` one paren deeper) | `true` | `true` |
| `0 > value \|\| value > (high + 1)` | `true` | `true` |
| `value < 0 \|\| value >= (high + 1)` | `true` | `true` |

- Where (lead): `isGenericCallAhead` in `src/parser/context.ms:278`. It is a token-balance scan: from `<` it walks up to 100 tokens, tracks `{}`, `[]`, `()` depth, and answers "generic call" as soon as the angle depth returns to zero and the next token is `(`. It bails only on `;`, `=` and end of file, so `||`, `&&`, `+`, `-`, comparison operators and numeric literals are all accepted inside the would-be type argument list. `captureGenericTypeArgs` (:316) then consumes those tokens as text.
- Direction: the lookahead has to recognise a *type argument list*, not balanced brackets. TypeScript parses the type arguments speculatively and rewinds when what follows `<` is not a type list closed by `>` and followed by `(`; a cheaper first cut is to refuse the scan on any token that cannot appear in a type (`||`, `&&`, arithmetic and comparison operators, numeric literals outside `T[N]`).
- Second defect, same repro: the checker accepts a call whose callee is a local of type `int32`. With a correct parse this cannot happen from source, but `value(…)` on a non-callable should be a type error on its own; that is what let the JS build through.
- Workaround in Hibernal: `sim/env/ffi.ms` `isHead` is written `head >= 0 && head <= (Head.Attack as int32)`. Nothing to undo; the form is fine as it stands.

## 2. An extension named like a prelude method is lost behind a barrel

`units.ms`:

```ms
export const UNIT: int32 = 1;
```

`tree.ms`:

```ms
export struct Tree { bits: uint64; }
export function has(this tree: Tree, id: int32): boolean { return ((tree.bits >> (id as uint64)) & 1) == 1; }
export function isEmpty(this tree: Tree): boolean { return tree.bits == 0; }
export function size(this tree: Tree): int32 { return 3; }
export function touches(this tree: Tree, id: int32): boolean { return id == 2; }
```

`unitsFirst.ms`:

```ms
export * from "./units";
export * from "./tree";
```

Entry:

```ms
import { Tree } from "./unitsFirst";
function main(): int32 {
	const tree: Tree = { bits: 4 };
	console.log(tree.has(2) ? "yes" : "no");
	return 0;
}
process.exit(main());
```

- Measured, identical on C and JS (it is a checker error, so neither backend is reached): `Property 'has' does not exist on type 'Tree'. Available: bits`.

| Barrel | Call | Result |
|---|---|---|
| `units` then `tree` | `tree.has(2)` | `Property 'has' does not exist` |
| `units` then `tree` | `tree.isEmpty()` | `Property 'isEmpty' does not exist` |
| `units` then `tree` | `tree.size()` | `Property 'size' does not exist` |
| `units` then `tree` | `tree.touches(2)` | `yes` |
| `tree` then `units` | `tree.has(2)` | `yes` |
| none, `import { Tree } from "./tree"` | `tree.has(2)` | `yes` |
| `units` then `tree`, `import { Tree, has } from "./unitsFirst"` | `tree.has(2)` | `Property 'has' does not exist` |
| `units` then `tree`, plus `import { has } from "./tree"` | `tree.has(2)` | `yes` |

- Trigger: all three conditions together.
  - The extension's name is also a built-in or prelude method name: `has`, `isEmpty` and `size` fail; `touches`, `nodeCount` and `withNode` pass in the same position.
  - It is reached through `export *`.
  - Its module is not the first `export *` of the barrel. The module in front can be anything; one exported `const` is enough.
- Naming the extension in the import from the barrel does not help. A direct import from the defining module does.
- A barrel with a single `export *`, or with the defining module first, hides the bug. That is why `rules/` never saw it: every earlier caller of `Tree.has` imports `./tree` directly.
- In Hibernal: `rules/index.ms` exports `./tree` fourth, so `tree.has(…)` and `tree.isEmpty()` fail in any file that takes `Tree` from `rules/index`. Bisected on the real barrel: any prefix of `rules/index.ms` that puts one module before `./tree` fails; `./tree` alone or first passes.
- Where (lead, not traced): the star re-export arm of `collectExport` in `src/checker/collectPass.ms:1242`. It walks `modExports.symbols`, skips a name when `lookupLocal(ctx.table, expInfo.name) != null`, and only otherwise calls `importSymFromRegistry` and `propagateImportedExtensions`. If a prelude `has`/`isEmpty`/`size` is already in the barrel's table when the second `export *` is collected, the user extension is skipped and its dispatch entry never reaches the barrel's `extensionRegistry`. Not explained yet: why the first `export *` is exempt.
- Related but different: `SOLANA-BUGS.md` #14 (same-name *static* extensions across modules, export registry). Here there is one user declaration of the name; the collision is with the prelude.
- Workaround in Hibernal, remove when fixed: `sim/env/observe.ms` has `import { has, touches } from "../../rules/tree";` next to its `rules/index` import.

## Not compiler bugs, recorded so nobody re-measures them

- `Math.abs` returns `float64` for `int32` arguments (`implicit float64 → int32 narrowing`), unlike the generic `Math.min`/`Math.max`. Integer code writes `Math.max(a - b, b - a)`.
- A left shift of a negative `int32` panics in a debug build (`left shift of negative value -1`), as C's undefined behaviour check; `rules/policy.ms` assembles little-endian words by multiplication. A right shift of a negative value is an arithmetic shift on C and JS (`-7 >> 1 == -4`).
