# Compiler bugs found on the on-chain AI lane

Found while building package 4 of `docs/ON-CHAIN-AI.md` (`sim/env/`, `rules/policy.ms`, `train/`). All are worked around in place in Hibernal; the workaround is named in each entry so it can be removed when the fix lands.

Entries 1 and 2 were reproduced on the installed `msc 0.2.54` (installed from recompiler `cc7ea0b7`, 2026-09-16) on the C and JS backends, with passing neighbours to bound the trigger. Not re-run on recompiler `main`; source references are to `main` at `f8a913e5` (2026-09-17) and are leads, not traced root causes. No Nim twin was run. Repros as files: `/tmp/hib-ai-bugs/generic/` and `/tmp/hib-ai-bugs/barrel/` (volatile; the full sources are inline below).

| # | Bug | Kind | Status |
|---|---|---|---|
| 1 | `a < x … b > (y)` parses as a generic call `a<…>(y)` | parser lookahead; the checker then accepts a call on an `int32` | open |
| 2 | An extension named like a prelude method (`has`, `isEmpty`, `size`) is lost behind a barrel unless its module is the first `export *` | checker, star re-export | open |
| 3 | The type annotation of a `for (let i: T = …)` counter is dropped; the counter takes the initializer's type | parser | open |
| 4 | An argument of a method-syntax call (`x.f(a)`) gets no implicit numeric conversion; on JS a Number reaches a BigInt formal | checker, call argument fitting | open |

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

Entries 3 and 4 were found together on package 3 (`sim/world.ms`, first recorded in `docs/ON-CHAIN-AI.md`) as one symptom: `pet.tickTo(global, epoch)` with a `uint64` loop counter throws `TypeError: Cannot mix BigInt and other types` on JS. They are two independent defects. Both were re-measured on recompiler `main` `f8a913e5` (built in a private worktree, clean `out/`) and traced against Nim (`/trace-nim`). Repros: `/tmp/hib-ai-bugs/forInit/` and `/tmp/hib-ai-bugs/memberCall/`.

## 3. A `for` counter loses its type annotation

```ms
function main(): int32 {
	let last: uint64 = 0;
	for (let big: uint64 = 2147483646; big < 2147483650; big++) { last = big; }
	console.log(String(last));
	return 0;
}
process.exit(main());
```

- Measured:
  - C: `big` is declared `int32_t`; debug build panics `signed integer overflow: 2147483647 + 1 cannot be represented in type 'int'`.
  - JS: prints `2147483649`, but `big` is a `Number`. It escapes only because every use site that expects `uint64` is fitted from `int32` (`BigInt.asUintN(64, BigInt(big))`); a site without that fit (entry 4) throws.
  - `msc dump-ast`: `let body: uint64 = 1` in the body carries `declType: uint64`; the `for` counter's `VariableDecl` has no `declType`.

| Counter | C type | JS init |
|---|---|---|
| `let outside: uint64 = 1` (statement) | `uint64_t` | `1n` |
| `for (let a: uint64 = 1; …)` | `int32_t` | `1` |
| `let h: uint64 = 0; for (h = 1; …)` | `uint64_t` | `1n` |

- Trigger: a declaration in the init clause of a C-style `for`. `for..of`, `for..in` and statement declarations are unaffected.
- Where: `parseForStmt` in `src/parser/statements/control.ms:209` calls `skipOptionalType(state)` and builds the `VariableDecl` with `declType: ""` (:218). The statement parser `parseVariableDecl` (`declaration.ms:112`) uses `captureOptionalType` and sets `typeExpr`. Present since the parser's first commit (`51f08221`, 2026-02-21; `skipOptionalType` from `1eb790b1`), never recorded as a divergence.
- Nim: `semVarOrLet` (`semstmts.nim:848-875`) types the symbol from the annotation (`semTypeNode`) and fits the initializer to it (`fitNodeConsiderViewType`); the initializer's type is used only when there is no annotation. Verdict: DIVERGE-UNINTENTIONAL; the fix is to keep the annotation, as `parseVariableDecl` does.
- Fix verified, not landed: `captureOptionalType` + `getLastTypeExpr` in `parseForStmt` (7 lines, worktree `/tmp/hib-js64/rc` on `f8a913e5`, binary `mscA`). The overflow repro prints `2147483649` on C and JS, and so does `out/jsUint64/dotCall.ms` (`6`), because the counter is now a `uint64` and needs no conversion. Entry 4 is still red on the same binary. The recompiler suite has not been run yet.
- Found alongside, separate and not traced: `let x: uint64 = 1n;` as a plain statement fails to compile on C (`assigning to 'uint64_t' from 'msBigInt *'`), before and after the fix.
- Hibernal counters it touches today, all below 2^31 so harmless on C: `rules/actions.ms:531,553`, `rules/fight.ms:352,397,459`, `sim/digests.ms:80`.

## 4. A method-syntax call skips implicit numeric conversion of its arguments

```ms
struct Holder { epoch: uint64; }
function single(this holder: Holder, epoch: uint64): uint64 { return holder.epoch + epoch; }
function main(): int32 {
	const holder: Holder = { epoch: 1 };
	const small: int32 = 3;
	console.log(String(holder.single(small)));
	return 0;
}
process.exit(main());
```

- Measured: C prints `4` (C converts at the call on its own). JS throws `TypeError: Cannot mix BigInt and other types`; the call is emitted `single(holder, small)` with no `BigInt()`.

| Call, `int32` argument | JS |
|---|---|
| `single(holder, small)` (free call) | `4` |
| `holder.single(small)` (one extension) | `TypeError` |
| `holder.over(small)` (overloaded extension) | `TypeError` |
| `holder.widen64(small)` (`int64` formal) | `TypeError` |
| `new Box().add(small)` (class method) | `TypeError` |

- Trigger: the callee is a member expression. The formal is `int64`/`uint64` and the argument a narrower integer; other widenings are invisible on C and were not probed on JS.
- Where: the checker marks each numeric widening at a call with a `HiddenStdConv` (`src/checker/callResolve.ms:1358`, inside the general argument loop), and `src/transform/coercion/bigIntJS.ms` turns the mark into `BigInt()`. A single pre-resolved extension returns at about :1177, before that loop; its own loop (:1103-1115) calls `fitNode` only for a non-assignable argument, and `int32 → uint64` is assignable. Overloaded extensions go through `resolveExtensionOverloadCall` (:2438). The class-method leg fails the same way, but its exact exit was not pinned.
- Nim: method-call syntax is rewritten to an ordinary call (`semFieldAccess` → `dotTransformation`, `semexprs.nim:1670-1702`) and resolved by the one overload resolver, whose `paramTypesMatch` inserts `nkHiddenStdConv` for every argument (`sigmatch.nim:2563-2622`). `paper/NIM-REF.md` records the MetaScript invariant "every fit position shares the one wrap". Verdict: DIVERGE-UNINTENTIONAL, the same root as the dot-call rewrite in `SOLANA-BUGS.md` (group B): extension calls resolve through a parallel path that forgot this step.
- Workaround in Hibernal, remove when fixed: an explicit cast at the call, `world.beginEpoch(day as uint64)` in `sim/teacher.ms:133` and `sim/env/observe.ms:420`, with an `int32` day counter.

## Not compiler bugs, recorded so nobody re-measures them

- `Math.abs` returns `float64` for `int32` arguments (`implicit float64 → int32 narrowing`), unlike the generic `Math.min`/`Math.max`. Integer code writes `Math.max(a - b, b - a)`.
- A left shift of a negative `int32` panics in a debug build (`left shift of negative value -1`), as C's undefined behaviour check; `rules/policy.ms` assembles little-endian words by multiplication. A right shift of a negative value is an arithmetic shift on C and JS (`-7 >> 1 == -4`).
