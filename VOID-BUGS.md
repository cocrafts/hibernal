# Compiler bugs blocking Void

Found while designing Void's scene model. The model is columnar storage plus a *binder* — a value struct `{ scene: Scene; id: NodeId; }` that pairs a store with a row and carries the ergonomic surface. Every setter in that design writes through a reference-typed field of a by-value parameter, and every kind's faces are meant to be macro-generated from one table. Both of those paths are broken today, so these are fixed in the compiler, not worked around.

Reproduced on msc 0.2.54 against recompiler `main` at `b707175d`. Entry 1 was traced to the responsible pass and has a fix direction; entries 2-4 have a bounded trigger but no root cause yet, and none has been compared against a Nim twin. File and line references are to `b707175d`, except entries 7 and 8, which were traced and fixed at `ba16897a`. Repros live in `scratchpad/binder/` and `scratchpad/span7/` of the sessions that found them; each is reproduced inline below.

| # | Bug | Kind | State |
|---|---|---|---|
| 1 | Assignment through a reference-typed field of a value parameter | checker, Nim `isAssignable` divergence | **fixed**, not landed |
| 2 | Macro-emitted `StructDecl` cannot have user-declared field types | macro decl collection | bounded |
| 3 | Compiler segfaults on certain macro-emitted `ExportDecl` splices | crash | bounded |
| 4 | Macro-emitted decls vanish silently when composed | macro decl collection | bounded |
| 5 | `msc fmt` drops `this`, producing a file that no longer compiles | printer | traced |
| 6 | No AST node carries a source range | parser | traced |
| 7 | `string` → `Span<char>` emits a field that does not exist, C only | transform lowering | **fixed**, unstaged |
| 8 | `string` → `Span<char>` is unimplemented on JS: wrong length, wrong reads, slices do not parse | transform lowering | bounded |

## 1. Assignment through a reference-typed field of a value parameter

```ms
struct Cell { x: float32; }
interface Scene { cells: Cell[]; log: int32[]; }
struct Ref { scene: Scene; index: int32; }

function w(this n: Ref, v: float32): void {
	n.scene.cells[n.index].x = v;
}
```

- Measured: `cannot mutate value-type parameter 'n': value parameters are read-only views; copy it locally first`, on the C and the JS backend.
- Works:
  - The same body with `n: Ref` as a plain value parameter fails identically, so `this` is not the axis.
  - A **mutating method call** down the same path, `n.scene.log.push(1)`, is accepted and runs — `log.length` prints `1`. It reaches the caller's scene exactly as the rejected assignment would.
  - `function w(ref n: Ref, …)` with the same assignment is accepted and prints `5`.
  - One-line rebind is accepted and prints `5`:
    ```ms
    function w(this n: Ref, v: float32): void {
    	const s: Scene = n.scene;
    	s.cells[n.index].x = v;
    }
    ```
- Why it is a bug, not a rule: `n.scene` is an interface, i.e. a reference. Writing through it does not touch `n`'s storage — it touches the heap object `n.scene` points at, which is shared by design and which the caller reaches through its own copy of the same reference. The pass's own stated invariant (`paramMutationAnalysis.ms:124-126`) is that the diagnostic exists because "interior writes would reach the caller's storage"; a write past a reference hop does not. The rebind neighbour settles it: it has identical semantics and identical emitted effect, so the rule forbids nothing and costs one line per setter.
- Where:
  - `src/checker/paramMutationAnalysis.ms:80` raises the error.
  - `src/checker/paramMutationAnalysis.ms:139-147` — `getRootName` walks `MemberExpr.object` and `ArrayAccess.array` to the root identifier with no inspection of the type at any hop, so `n.scene.cells[i].x` reduces to `"n"`.
  - `src/checker/paramMutationAnalysis.ms:127-135` — `isValueAggregateParam` gates the check on the parameter being Array / SizedArray / Tuple / Struct, which is why `ref` is exempt.
  - `src/checker/paramMutationAnalysis.ms:275-282` — the `BinaryExpr` branch of `scanForMutation` refines `getRootName(d.left) == paramName` only with `d.left.kind != NodeKind.Identifier`. The `CallExpr` branch at `:360-373` does consult `md.object.nodeType` and requires `TypeKind.Array | TypeKind.SizedArray`, so the pass already type-checks one path and not the other.
- ~~Fix direction: stop `getRootName` at the first hop whose object type is a reference.~~ Implemented and measured at `fe27d196`: it changes nothing. The checker has already inserted a `HiddenDeref` at every reference hop, so the base a `MemberExpr` sees is the dereferenced struct (kind 18), never the `Ref`. The `Ref` (kind 27) is on the `HiddenDeref`'s operand — 144 of 144 derefs over a full compile.
- Nim verdict, **DIVERGE-UNINTENTIONAL**: `parampatterns.nim:277-285` `isAssignable` returns `arLValue` at `nkHiddenDeref` and at `nkHiddenAddr` and does not walk further; `getRootName` walked through both to the root symbol. `paper/NIM-REF.md` (moved from `docs/` in `53604840`) has no row for this pass or for lvalue-ness.
- Fix, one line, in the private worktree `/tmp/z_bug1_param` on `main` at `4700d72d`, **not landed**: `NodeKind.HiddenDeref | NodeKind.HiddenAddr => ""`. `HiddenAddr` is unreachable at this pass's position — both call sites (`orchestrator.ms:276`, `checkPass.ms:2792`) run before any transform, and no checker code creates one — so it follows Nim at no observable cost.
- What else the one line moves, all measured:
  - ABI. `getRootName` also feeds `sym.mutatedParams`, which gates by-pointer promotion. That gate is a recorded intentional divergence (`paper/NIM-REF.md:126`, Param passing: "track mutation via `mutatedParams`; unmutated struct params get `const T*`"; rationale in `LANG-STRUCT.md:301-307`). A write past a deref propagates without it, so such a param now takes Nim's size rule: small by value, large as `const T*`. Emitted `static void w(const Big* big, …) { ((*(*big).scene).tag = v); }` compiles and runs; `ref`/`out` params emit byte-identical C.
  - `readonly p: SomeInterface` then `p.tag = v` was refused as `cannot mutate readonly parameter` and now runs. Nim has no readonly parameter, and `paper/NIM-REF.md:167` records that "a `ref` parameter's pointee stays mutable"; deep read-only references are `Readonly<T>` views, a separate DIVERGE-INTENTIONAL mechanism checked in `checkExprPass.ms:78-173`. No code or test anywhere uses `readonly` as a parameter modifier.
- Still refused: `p.x = v`, `p.cells = [...]`, `this n` writing `n.index`, `readonly p` writing its own field. Guards `valueParamMutationCheck` (incl. `a[0] = 9` on a `Vec` param) and `arrayMutatorValueBinding` green on the candidate, with the check proven able to go red.
- Gates run on `4700d72d` with control and candidate both built `--gc=drc --danger` by the same builder: `msc test src/index.ms` 3713/3713 under drc and under orc; the two guards; the 20 probes; `src/test/fixedbugs/bug176ValueParamWriteThroughRef.ms` (renumbered from 173, which `main` has since used), 4 tests, red on control (4 refusals), green on the candidate. `fixedbugs/index.ms` is red on `main` itself (3 type errors); the candidate adds none — the only difference is the 4 bug176 refusals on control. New corpus program `780-paramWriteThroughRefField.ms`: the corpus had no program of this shape (`728-paramMutationLegal` writes through an interface param directly, not through a field of a value param). Emit-diff selector (`src/test/CLAUDE.md` §5.3) over all 214 corpus programs, control and candidate from one tree path: 211 emit byte-identical C for their own modules, all 63 std C files are identical, and the only program that changes is `780` (refused on control, builds on the candidate); sensitivity proven on `728`/`780` and on a synthetic C-only hash change. `704-macroExprHoist` and `762-bitSetMacro` fail identically on both binaries with pre-existing macro-body type errors, so the selector cannot speak for them. Lanes on `780`: parity 6/6 (c, orc, danger, js, esm, identical output) and SAN (ASan + DRC ledger) green. Guard lane: ALL GREEN, 327 cells, candidate under test. Every pre-land gate in the recompiler `CLAUDE.md` is green; what remains is landing.

## 2. Macro-emitted `StructDecl` cannot have user-declared field types

```ms
export struct Ident { index: int32; }
genUserStructField(0);
const h: HoldsStruct = { id: { index: 5 } };
```

where the macro emits `StructDecl { interfaceName: "HoldsStruct", interfaceFields: ["id"], interfaceFieldTypes: ["Ident"] }`.

- Measured: `Unresolved type 'HoldsStruct' - missing import?`. The struct does not register at all.
- Works:
  - The same emission with `interfaceFieldTypes: ["int32"]` registers and runs.
  - Wrapping the `StructDecl` in an `ExportDecl` changes nothing either way.
  - `Ident` is declared before the macro invocation, so declaration order is not the axis.
  - The same failure occurs when the field type is a user `interface` rather than a `struct`.
- Impact: the binder is `{ scene: Scene; id: NodeId; }`. Both field types are user-declared, so the central generated declaration of the design cannot be generated. Hand-declaring the binder structs and generating only their functions is the current shape of the probe.
- Where (unconfirmed): `src/checker/checkPass.ms:406-426` — `collectSplicedDecl` dispatches `NodeKind.StructDecl` to `collectStruct`. The collect pass that resolves field types walks the original `programStmts` before macros run (per the comment at `checkPass.ms:397-405`), so field-type resolution for a spliced struct is the suspect.

## 3. Compiler segfaults on certain macro-emitted `ExportDecl` splices

- Measured: `msc run` exits 139 (SIGSEGV) with no diagnostic, on a macro emitting an `ExportDecl`-wrapped extension `FunctionDecl` whose body returns a member of the receiver.
- Works: the same shape with two parameters, with a bare member return, with `createNodeAt` instead of raw object literals, and with two distinct functions in one splice, all compile and run.
- The exact discriminator between the crashing and the passing configuration is not yet isolated. A crash is a bug regardless of which one it is.

## 4. Macro-emitted decls vanish silently when composed

- Measured: a macro that emits 8 nodes (verified by `error()` reporting `out.length` at expansion time) produces no registered declarations. Every call site reports `Undefined variable` or `Property … does not exist`. No error and no warning is issued about the emission itself.
- Works, each tested alone: `ExportDecl`-wrapped `FunctionDecl`; `createNodeAt` construction; two emitted extensions in one splice; an extension on a receiver whose fields are user types; `MatchStmt` in the emitted body; a `VariableDecl` with a user-declared type in the emitted body; reading a module-level `string[][]` table and `split` at expansion time.
- Untested residue: the emitted body calling free functions declared in the *consuming* module (`payloadIndex`, `markDirty`), and a receiver struct with an `interface`-typed field.
- Worst property is the silence: a generated declaration that disappears without a diagnostic makes every macro-driven layer unverifiable by compiling it.

## 5. `msc fmt` drops `this`, producing a file that no longer compiles

```ms
struct Ref { index: int32; }

function shifted(this n: Ref, delta: int32): int32 {
	return n.index + delta;
}

function main(): int32 {
	const n: Ref = { index: 10 };
	console.log(n.shifted(5));
	return 0;
}
process.exit(main());
```

- Measured: `msc run` prints `15`. After `msc fmt` on the same file, the receiver is printed as `function shifted(n: Ref, delta: int32)` and `msc run` fails with a type error. The formatter silently converts every extension function into a plain function.
- Also lost in the same round-trip, in decreasing severity: float literals are narrowed (`setX(0.0)` → `setX(0)`, `setScale(2.0)` → `setScale(2)`); blank lines between statements are deleted; leading tabs become two spaces, which contradicts the indentation of every `.ms` file in `void/`.
- Works: comments survive in every position tested — trailing, leading-line, and `/** */` doc blocks. Trivia is carried; it is the declaration syntax that is lost.
- Where: `src/compiler/fmt/`.
- Why it matters beyond formatting: the intended editor model is that `.ms` source is the only source of truth, with an editor mutating the AST and writing the file back. Any write-back path through the printer converts the entire binder design — which is extension functions — into non-compiling code.
- Fix direction: print the receiver. Then add the two property tests that would have caught this: `fmt(fmt(x)) == fmt(x)`, and `run(x) == run(fmt(x))` over every `.ms` in `void/`, `neon/` and this repo.

## 6. No AST node carries a source range

- Measured: in `src/parser/`, `makeLocRange` has **0** call sites and `makeLoc` has 22. `makeLoc` sets `endLine` and `endColumn` to `0`, documented as "unknown" at `std/meta/node.ms:345-346`. `SourceLocation` has the fields; nothing fills them.
- Consequence: a tool cannot replace the text of one node. Any AST-driven edit must reprint the whole file, which makes the printer's total correctness a hard requirement forever — bug 5 is one instance of that class — and turns a single property edit into a whole-file diff.
- With ranges, an editor changes a literal by splicing bytes over that node's range; hand-written code elsewhere in the file is untouched, and the printer only has to render the small subtree that actually changed.
- Fix direction: populate ranges in the parser (the 22 `makeLoc` sites) and have the lexer report token end positions. Mechanical, bounded.

## 7. `string` → `Span<char>` emits a field that does not exist, C only

**Not blocking Void, and fixed anyway** — the patch is two lines and the bug sat on a path that could not have had users, because every route through it died. Found incidentally while probing `Span` for the columnar scene; Void needs `Span<T>` over `Vec<T>`, never over a string.

```ms
function main(): int32 {
	const txt = "hello";
	const chars: Span<char> = txt;
	console.log(chars.length as int32);
	return 0;
}
process.exit(main());
```

- Measured before the fix, on msc 0.2.54: **every** route from a string to a `Span<char>` failed identically with `error: no member named 'data' in 'msString'` — the declaration above, a string literal meeting a `Span<char>` parameter, a slice `txt[1..4]`, an empty string, and an element read. Not one of the five worked, so the feature was not partly broken; it was absent on C.
- Works: every other source of a `Span` — `Vec<T>`, `Array<T>` / `T[]`, and a sized `T[N]` — coerces and runs on C, including writing through the span and slicing with `a[lo..hi]`.
- The checker is not at fault: `src/checker/compat.ms:348-352` and `:526-529` deliberately admit `string`/`StringLiteral` → `Span<char>`, so the acceptance is intended and only the lowering was wrong.
- Root cause: `src/transform/lowering/spanLower.ms` emitted `{ data: str.data, len: str.len }`. `msString` is `{ int64_t len; msStrPayload* p; }` (`runtime/core/string.h:29-33`) and the bytes live in the payload, `msStrPayload { int64_t cap; char data[]; }` (`:23-27`), so only `len` was on the struct it was read from. The slice arm carried a comment claiming `nativeLower` rewrites `.data` to `.p->data` for strings; that rewrite (`src/transform/native/nativeLower.ms:277-280`) covers `TypeKind.Array` alone, so the comment described a rewrite that never ran.
- Fix, at recompiler `ba16897a`: take the pointer the way the `Array` arm two branches above already does — `msArrDataOr0(str.p)` (`runtime/core/array.h:210`, an untyped macro that yields NULL when `p` is NULL, which is exactly the empty string). Two sites: the coercion arm and the `lowerRangeAccess` string arm. Length still comes from `len`, never from `cap`, which carries flag bits (`MS_STRLIT_FLAG`, `MS_ASCII_CHECKED` at `:38-41`).
- Verified on the patched compiler: all five routes above, plus `for..of` over the span, a slice of a slice, a heap-built string (`"ab" + "cdc"`), and UTF-8 (`"héllo"` gives 6, matching `byteLength` — `Span<char>` is a byte view). Green on both `--gc=drc` and `--gc=orc`. The compiler suite is 3705/3705 with the patch, unchanged from before it, and the `Vec`/`Array`/`T[N]` span probe prints the same ten values as on stock msc.
- Guard: `src/test/fixedbugs/bug167StringToSpan.ms`, six tests, proven red on stock msc 0.2.54 and green on the patched binary.
- Nim verdict, traced after the fix was already written: **SAME**. `genOpenArrayConv`'s `tyString` arm (`compiler/ccgexprs.nim:316-333`) emits `Field0 = cIfExpr(dataFieldAccessor(s), dataField(s), NimNil)` and `Field1 = lenExpr(s)`, where `dataFieldAccessor` is `(s).p` and `dataField` is `(s).p->data` (`compiler/cgen.nim:488-495`) — character for character what `msArrDataOr0(str.p)` expands to. Nim emits the *same* expression for `tySequence` (`:304-310`), so sharing one accessor between the array and the string arm is Nim's own shape, not a convenient reuse of a macro whose name says `Arr`. What we had before was the shape of the `tyArray` arm (`Field0 = ra`, the object itself) applied to a string.
- **What the fix opens up, and does not close.** Writing through the span was impossible before (nothing compiled); now it compiles, and writing through a span over a *literal* is `SIGBUS` (exit 138) because the bytes are in read-only memory. Over a heap-built string it works and writes through (`"hel" + "lo"`, `span[0] = 'J'` → the string reads `Jello`). Nim has the guard we lack, in two pieces: `lfPrepareForMutation`, a flag on the destination meaning "this location is about to be written", which gates a `nimPrepareStrMutationV2` COW call — its comment at `ccgexprs.nim:1331-1333` says in as many words that calling it unconditionally "would SIGSEGV on write to read-only memory" — and the `etyp.kind in {tyVar}` gate on the openArray conversion itself (`:317`), which is how Nim keeps a writable view from ever being taken over an immutable string. Verdict for this half: **DIVERGE-INCOMPLETE**. The runtime prerequisite is already in place — `msStringPrepareMutation(msString*)` at `runtime/core/string.h:152`, the twin of `nimPrepareStrMutationV2` — so the model is followable; what is missing is the compiler-side notion of a read-only span, which is an arc, not a hunk.

## 8. `string` → `Span<char>` is unimplemented on JS: wrong length, wrong reads, slices do not parse

Discovered while fixing 7. The two backends disagree on what a span over a string *is*, which makes any use of it a determinism hazard — the shape `sim/determinism.ms` exists to catch.

- Measured on the patched compiler, same eight probes as entry 7:
  - `"héllo"` → span length is **5 on JS, 6 on C**. JS lowers the coercion to `const chars = txt;` and reads `String.prototype.length`, i.e. UTF-16 code units; C gives the byte count. ASCII strings agree by accident.
  - `chars[1]` on `"hello"` prints **0 on JS, 101 on C**. JS indexes the string, gets the one-character string `"e"`, and `| 0` turns it into `0`. Every element read through a string-backed span on JS is 0.
  - `txt[1..4]` **does not parse**: the emitted JS is `const mid = txt[(1 .. 4)];` → `SyntaxError: Unexpected token '.'`. The range operator survives into the output, so no string slice reaches a span on JS at all.
- Not a regression from the entry-7 fix: all three were measured on stock msc 0.2.54 first and are unchanged by it. What the fix changed is the consequence — before, C also refused, so nothing could diverge.
- Fix direction: lower `string` → `Span<char>` on JS the way the C side now does, to a byte view, not to the string object — and lower the range operator on that path. Until then the honest alternative is to reject the coercion on JS in the checker rather than accept it and answer differently.
