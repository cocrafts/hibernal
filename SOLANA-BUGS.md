# Compiler bugs blocking on-chain MetaScript

Found while designing `std/solana` primitives. Extension methods are the core of that API, so these are fixed in the compiler, not worked around.

Every entry was reproduced on recompiler `main` at `b707175d` (compiler built from that commit in a private worktree) on the C and JS backends, with passing neighbours to bound the trigger, and compared against a Nim 2.2.2 twin that was compiled and run. File and line references are to `b707175d`.

Re-run on `main` at `ba16897a` (2026-09-16), in a private worktree: every entry gave the same result, except #16, which was not re-run. #5, #6, #7 and #15 were measured on `ba16897a`, and their file and line references are to that commit. #18 was found on 2026-09-16 while tracing #1, and was measured on `01c86b5f`.

Re-run on `main` at `d101b611` (2026-09-17, 40 commits past `ba16897a`), compiler built from a clean private worktree (`/tmp/hib-bugs/wt-tip/msc`, repros in `/tmp/hib-bugs/r/`), C and JS, `--os=solana` for #6: every open entry reproduces with the same output, except #5, whose C case is fixed on this tip (a same-module 32-byte struct now prints `1`) while JS still fails on every struct. #1 stays green (`5` on C and JS); #18 stays red until its fix lands. The entry-file `const LIMIT` in #6 also fails the Solana link, so the "scalar `const` in the entry file folds" row of `docs/ROADMAP.md` R12 and `~/metascript/docs/CODE-STYLE.md` §11 is stale.

Re-run on `main` at `f8a913e5` (2026-09-17 evening, 13 commits past `d101b611`), compiler built from a clean private worktree (`/tmp/hib-bugs/wt-tip2/msc2`; the bootstrap binary has to sit inside the new worktree, because `msc` reads `std/` next to itself): the 24 host repros give the same output on C and JS as on `d101b611`, and #6 fails the same link. #19 was found on this tip while tracing #6.

Entries are in execution order, grouped by the compiler change they share. A group lands only after the groups above it. `Status` means:

- **landed** — fixed on `main`, with the commits named in the entry.
- **fixed, not landed** — fix written and every gate green in a private worktree; waiting on approval to land.
- **open** — reproduced, not fixed.

Re-measured 2026-09-22 on installed `d757c7e1`: nothing below has landed except #1. Blockers are parked on inbox cards `~/metascript/.inbox/compiler/2026-09-22-*.md`, claimed by recompiler worktrees `wt/solana-const-fold` (#6 and a dead-`if` crash) and `wt/std-solana` (the rest, card `~/metascript/.wt/std-solana.md`).

| # | Group | Bug | Kind | Depends on | Status |
|---|---|---|---|---|---|
| 1 | A | Generic parameter under `ref`, `out`, `Borrow` or `Cursor` does not bind `T` | unification and substitution gap | — | **landed** `9565b257` + `48d9f015` |
| 18 | A | A generic `distinct` instance as a plain parameter never matches its argument | argument checked before its type parameters are bound | — | **fixed, not landed** |
| 2 | A | Indexing a `ref` array parameter fails in C | native lowering | — | open |
| 3 | A | `try` does not check the error type | checker type rule | 12 (instance part, fixed with it) | **fixed, not landed** |
| 4 | A | `.length` and `for..of` on a fixed array `T[N]` fail in C | native lowering | — | **fixed, not landed** |
| 5 | A | `==` on structs fails for every struct in JS (the C case over 24 bytes is fixed on `d101b611`) | hook generation on the JS backend | — | open (JS only) |
| 6 | A | Module `const` does not link on Solana | codegen of module bindings | — | scalars **landed** `8be46044..e5f0ec68`; aggregates open (after #8) |
| 7 | A | Type mismatch message drops type arguments | diagnostic | — | open |
| 8 | A | `const` bindings and value parameters are writable | missing assignability check (soundness) | — | open |
| 9 | B | Macro called with method syntax | macro dispatch | B core | open |
| 10 | B | `this x: Ptr<T>` receiver is never found | checker receiver matching | B core | open |
| 11 | B | `this ref` receiver: does not parse, and the receiver skips every `Var` rule | parser gap, JS lowering order, receiver outside argument checks | 1 (landed), 8, B core | open |
| 12 | C | Extensions on enums, instance and static | checker member-access gate | B core (instance), C core (static) | open |
| 13 | C | `T.f()` inside a generic | generic instantiation scope | C core | open |
| 14 | C | Same-name static extensions across modules | export registry | C core | open |
| 15 | D | Struct fields private to their module | missing feature; field modifiers crash C codegen | — | open |
| 16 | D | `@borrow` for `distinct` types | missing feature | B, C | open |
| 17 | E | `Borrow<T>` locals and returns fail in C, `for..of` copies, no lifetime check | half-implemented feature, not blocking | — | open |
| 19 | A | A 64-bit integer literal expression folds through a double | constant folding on doubles; literal typed `int32` regardless of context | — | open |
| 20 | A | Two structs of the same shape are assignable in the checker and distinct in C | structural assignability against nominal C types | — | open |

Where this stands on 2026-09-17: 1 landed, 1 fixed and waiting to land, 16 open. Group A is the only group in progress; nothing in B, C or D has been started. Next in execution order is #2.

## A. Standalone fixes

These nine do not depend on the method-call rewrite, so each lands and is verified on its own. #8 is the largest and changes behaviour: `const` becomes deep on value structs. It goes last in the group, right before group B relies on it, and its verification includes the self-host build and `std`.

### 1. Generic parameter under `ref`, `out`, `Borrow` or `Cursor` does not bind `T`

```ms
struct Box<T> { value: T; }
function put<T>(ref box: Box<T>, v: T): void { box.value = v; }
let box: Box<int32> = { value: 1 };
put(box, 5);
```

- Measured, identical on C and JS:
  - `put(box, 5)`: `cannot instantiate: 'T' — annotate the destination type or pass an explicit type argument`.
  - The explicit `put<int32>(box, 5)` fails the same way. So do `ref x: T`, `out box: Box<T>`, a `ref` parameter that is the only place `T` appears, `b: Borrow<T>` and `c: Cursor<T>`.
  - As a `this ref` receiver (#11 probe), `box.put(5)` instead emits a call to `Box_put__int32_u0`, which clang reports as undeclared.
- Works: `peek<T>(this box: Box<T>)`, a value parameter `pick<T>(box: Box<T>, v: T)`, `put<T>(box: Ptr<Box<T>>, v: T)`, `Readonly<T[]>`, and every shape above without generics.
- Where (`src/checker/types.ms`):
  - `unifyTypeInner` (:2705) has no arm for `Var`, `Borrow` or `Cursor`, so those formals never produce a binding.
  - `substituteTypeInner` (:2455) and `substituteAllParams` (:2540) end in `_ => t` with no `Var` or `Cursor` arm. An explicit binding is never written inside the wrapper either, so the formal check in `inferGenericReturn` (`src/checker/callResolve.ms:1706`) still sees `T`.
- Reference:
  - `typeRel` `of tyVar:` and `of tyLent:` (`sigmatch.nim:1433-1445`) relate `f.base` with the argument, or base with base when the argument has the same wrapper.
  - `replaceTypeVarsTAux` (`semtypinst.nim:763-779`) substitutes through the children of every type in its default arm, so no wrapper kind is skipped.
  - Twin: `put[int32](box, 5)`, `setTo(n, 5)` on `var T`, `bump(box)` then `peekValue(box)`, `fill(other, 9)` on `out`, `first(items)` on `var seq[T]` print `5 5 5 9 4`.
- Verdict: DIVERGE-UNINTENTIONAL. NIM-REF has no row that allows skipping these kinds. It is the same whitelist-instead-of-default-arm shape as the "Generic alias instantiation" row, which fixed body kinds only.
- Fix, in a private worktree off `b707175d`:
  - `unifyTypeInner`: one arm for `Var`, `Borrow` and `Cursor` that unifies the base with the argument, or base with base when the argument has the same kind.
  - `substituteTypeInner` and `substituteAllParams`: `Var` and `Cursor` arms that rebuild the wrapper around the substituted base. `Borrow` already had one.
  - Regression test `src/test/fixedbugs/bug170GenericVarParam.ms`: red on `b707175d` with `cannot instantiate` at every call, green on the patched build (5/5).
  - A build with only the `Var` arms fixed `ref`/`out` and still failed `Borrow<T>` and `Cursor<T>`, which is why those arms are in the same change.
- Verified on the patched build (`--danger`):
  - Every shape above prints the Nim value on C and JS.
  - `msc test src/index.ms`: 180 files, 3705/3705.
  - Self-host fixpoint: gen2 builds gen3, and 0 of 309 emitted `.c` files differ.
  - `src/test/guard/run.sh`: 312 ok, 4 failures (`structuralMaybeHookNaming` and `unionMemberEquality`, drc and orc). Both fail with the same clang errors on `b707175d` (a `Maybe_…` equality hook called with a pointer against a by-value prototype), so they predate this fix.
  - Program corpus: 1180 pass, 17 fail, 6 xfail. All 17 fail the same way on `b707175d`: `704-macroExprHoist` and `762-bitSetMacro` do not build on any lane (same macro-body errors), and `619`, `628`, `630`, `711`, `773`, `775` fail at runtime on `js`/`esm` only.
  - Sanitizer corpus lane: 202 pass, 8 fail, all present on `b707175d` too. Five union programs (`253`, `254`, `258`, `259`, `260`) report the same ledger imbalance, `704` and `762` do not build, and `410-awaitStructSpawnStored` hangs with an identical main-thread stack on both compilers (`msWaitFor` → `msPoolHelpOne` → `msSpawnWorkerRun` → `msCompletionQueuePushOwned` blocked in `write`).
  - Hibernal `rules/` 328/328; the four `sim/determinism.ms` digests match `b707175d`, native and JS.
- Landed on `main` (2026-09-16): `9565b257` fix(checker) and `48d9f015` test(checker), on top of `fe27d196`.
  - Re-verified on `fe27d196`: the test is red on the unpatched build and green on the patched one (5/5); `msc test src/index.ms` 3705/3705.
  - Emitted C for the 210 corpus programs is identical between the two builds (208 build, `704` and `762` fail the same way on both).

### 18. A generic `distinct` instance as a plain parameter never matches its argument

```ms
type Wrap<T> = distinct T;
function peel<T>(w: Wrap<T>): T { return w as T; }
const a = 5 as Wrap<int32>;
peel(a);
```

- Measured, identical on C and JS: `error: Argument type mismatch in 'peel' arg 0: got Wrap<int32>, expected Wrap<T>`. An explicit `peel<int32>(a)` fails the same way. So do `type Thunk<T> = distinct (() => T)`, `type Boxed<T> = distinct Box<T>`, and a `distinct` alias reached through a second alias.
- Works: a non-nominal generic parameter (`Box<T>`), the same `distinct` passed as an object literal, a `this` receiver, and every shape above without `distinct`.
- Where (`src/checker/callResolve.ms:1243-1350`): the argument loop compares `argTypes[pi]` against `paramType = calleeType.typeChildren[pi]`, the *declared* formal, and errors at :1343. On-demand instantiation runs only at :1392, so the comparison sees an unbound `T`. Non-nominal generics survive it because `isAssignable` lets anything match a `GenericParam` (`src/checker/compat.ms:375-378`); `isNominalType` (:49-53) is true for a `GenericInstance` over a `Distinct`, which forces `sameType(int32, T)` and fails.
- Reference: `typeRel` `of tyGenericInst:` (`sigmatch.nim:1691-1735`) relates the type arguments through `c.bindings`, so Nim binds while it matches, never before. Twin: `peel`, `call`, `unbox` and `pair` over the same four shapes print `5 7 9`.
- Verdict: DIVERGE-UNINTENTIONAL. The loop already carried the Nim-shaped exception, but narrowed to `d.arguments[pi].kind == NodeKind.ObjectLiteral` — a symptom patch for one spelling of the same bug. `tryInstantiateGenericCallee`'s own loop has the general guard: `if (formalT == null || hasGenericParams(formalT) || isUnresolvedType(formalT)) continue;`.
- Fix, in a private worktree off `01c86b5f`: drop the `ObjectLiteral` narrowing, so an argument is skipped whenever its formal still has generic parameters.
  - Regression test `src/test/fixedbugs/bug175GenericDistinctParam.ms`: red on the unpatched build, green on the patched one (15/297). Numbered 175 because `main` took 174 on 2026-09-17.
  - `msc test src/index.ms` 180/180 files, 3708/3708 tests.
  - Emitted C for the 211 corpus programs is identical between the two builds (209 build, `704` and `762` fail the same way on both).
  - Re-applied on `f8a913e5` (2026-09-17, `/tmp/hib-bugs/wt-land18`); the test is now `bug179GenericDistinctParam.ms`, because `main` took 175–177 and another session holds 178. Gates on that tip, all in the private worktree:
    - the test is red on the unpatched build (six `Argument type mismatch … expected Wrap179<T>` errors) and green on the patched one;
    - self-host fixpoint: gen2 and gen3 emit 313 C files, 0 differ;
    - `msc test src/index.ms` 180/180 files, 3717/3717 tests;
    - `src/test/guard/run.sh` ALL GREEN, 332 probes (the four reds of `b707175d` are gone on this tip);
    - corpus 1189 pass, 30 fail, 6 xfail: the 17 known cells (`704` and `762` on every lane, `619`, `628`, `630`, `711`, `773`, `775` on `js`/`esm`) plus 13 cell timeouts (`255`, `256`, `259`, `260`, `624`, `410`) taken while the machine ran at load 120. Re-run alone, the first five pass 6/6 cells on the patched build; `410-awaitStructSpawnStored` hangs on one cell on the patched build and on one cell on the unpatched build, the intermittent hang already recorded under #1;
    - sanitizer lane 206 pass, 8 fail, the same eight as under #1 (`253`, `254`, `258`, `259`, `260` ledger, `704`, `762` build, `410` hang);
    - Hibernal `msc test rules/index.ms` 349/349, and the seven `sim/determinism.ms` digests are identical on native, JS and the unpatched compiler.
  - Not landed: waiting on approval to commit.

### 2. Indexing a `ref` array parameter fails in C

```ms
function first(ref items: Array<int32>): int32 { return items[0]; }
let items: Array<int32> = [4, 5];
first(items);
```

- Measured:
  - C: clang `member reference type 'int32_tArray *' (aka 'struct int32_tArray *') is a pointer; did you mean to use '->'?` inside `msArrayAccess`. JS prints `4`.
  - The generic `ref items: Array<T>` fails the same way once #1 is fixed.
- Works: a value parameter `items: Array<int32>` prints `4`. `items.push(6)` through the `ref` parameter prints `3` on both backends.
- Where:
  - The parameter types are right: the value parameter is `int32_tArray* items`, the `ref` parameter `int32_tArray** items`, and the call passes `&(items_1_)`. Both bodies read `msArrayAccess((*items), 0)`. The macro (`runtime/core/system.h:490`) takes the array struct (`(a).len`, `(a).p`), so the `ref` body is one dereference short.
  - `insertVarParamDerefs` (`src/transform/native/varParamDeref.ms`, run at `src/compiler/compile.ms:1434`) wraps the parameter in one `HiddenDeref`. `lowerNativeAccess` runs later (`compile.ms:1452`); its `unwrapRefArrayRecv` (`src/transform/native/nativeLower.ms:27`) adds the array dereference only when the receiver type is `Ref<Array>`. Which step loses the second dereference is not pinned yet.
- Not traced against Nim yet.

### 3. `try` does not check the error type

```ms
enum AccountError {
	MissingSigner,
	WrongOwner,
}
enum PetError {
	Account,
	Dead,
}
function load(): Result<uint64, AccountError> { return Result.err(AccountError.WrongOwner); }
function feed(): Result<uint64, PetError> {
	const value = try load();
	return Result.ok(value);
}
```

- Measured: it compiles, and the error from `feed()` prints `Dead` on C and JS: ordinal 1 of `AccountError` is read as `PetError`. When `E` is a struct instead, the checker passes and clang fails with `assigning to 'ProgramFailure…' from incompatible type 'PetError…'`.
- Where: `checkTryExpr` (`src/checker/callResolve.ms`) returns the ok type and never compares the argument's `E` with the enclosing function's return type.
- Reference: none in Nim core; `Result` and `try` are MetaScript constructs. The invariant is ordinary return checking: `try x` means `if (!x.ok) return Result.err(x.error)`, and that return must type-check like a written one.
- Fix direction: at the `try` site, check `E` against the error type of the enclosing function's `Result`, including inside `Promise<Result<T, E>>`.
- Fix, in a private worktree off `f8a913e5` (`/tmp/hib-bugs/wt-fix3`), repros in `/tmp/hib-bugs/t3/`:
  - `checkTryErrorPropagation` (`src/checker/callResolve.ms`): `try x` without `catch` is checked like the `return Result.err(x.error)` it stands for. The same error type passes. A different one converts through the existing `as<Type>` coercion protocol (`trySynthesizeAsCoercion`, `src/checker/fit.ms`); the checked conversion is carried on the node in a new `TryExprData.errorConversion` field, over a `$tryError` placeholder that `makeErrorCheck` (`src/transform/desugar/resultDesugar.ms`) replaces with `$result.error`. Anything else is a type error at the `try`, naming the extension to declare.
  - Also an error now, where clang used to fail: `try` without `catch` in a function that does not return `Result`, and at module level.
  - Measured on C and JS: enum errors convert (`Generic`, where the unpatched build printed `Stake`), struct errors convert (`1007`), the same `E` still propagates (`Locked`), the entry's repro reports `'try' returns an error of type AccountError, but 'feed' returns errors of type PetError; declare an 'asPetError(this error: AccountError): PetError' extension, or handle the error with 'catch'`. The compiler's own 312 modules pass the new rule (gen2 builds).
  - The conversion is a synthesized method call, so an enum error needed the instance half of #12: `checkMemberExpr` now lets a property that is not a member of the enum, on an enum value, fall through to the extension lookup, as `tryReadingTypeField`'s `tyEnum` arm does (`semexprs.nim:1533-1545`, nil when the identifier is not a member). `mood.label()` and `Mood.Angry.label()` print `1 1` on C and JS like the twin; `mood.bogus()` and `Mood.Bogus` keep their diagnostics. The static half of #12 (`Mood.fromByte(1)`) stays open in C core.
  - Regression tests `bug182TryErrorType.ms` (5) and `bug183EnumInstanceExtension.ms` (2): green on the patched build; on the unpatched one `bug183` does not type-check and three of the five `bug182` tests fail.
  - Gates on `f8a913e5` (2026-09-18): self-host fixpoint 313 C files, 0 differ; `msc test src/index.ms` 180/180 files, 3717/3717 (the first run was red on `childTableGuard` until the new field was added to the macro bridge); guard ALL GREEN, 332 probes; corpus 1197 pass, 22 fail, 6 xfail — the 17 known cells plus five timeouts of the threading programs `410` and `419`, whose emitted C is byte-identical to the unpatched compiler's; sanitizer lane 207 pass, 7 fail, all among the known eight; Hibernal rules suite green, seven digests identical on native, JS and the unpatched compiler. Not landed: waiting on approval to commit.


### 4. `.length` and `for..of` on a fixed array `T[N]` fail in C

```ms
struct Fighter { power: int64; health: int64; bornSlot: uint64; kills: int64; }
struct Account { count: uint8; fighters: Fighter[4]; }
const account = address as Ptr<Account>;
for (const fighter of account.fighters) { total = total + fighter.power; }
```

- Blocks on-chain code: an account overlay with a fixed array field cannot use `for..of` or `.length`, the loop idiom from `~/metascript/docs/CODE-STYLE.md` §3.
- Measured on C:
  - `for..of` over `account.fighters` through `Ptr<Account>`: clang `no member named 'len' in 'struct msSizedArray_Fighter…'`.
  - The same on a value struct field and on a local `const fighters: Fighter[4]`.
  - `account.fighters.length`: the same clang error.
  - JS runs: on a value struct field the loop prints `10` and `.length` prints `4` (`ba16897a`).
- Works: `for (let i = 0; i < 4; i++) { total = total + account.fighters[i].power; }` through the same overlay prints `9`.
- Where:
  - `lowerNativeAccess` rewrites `.length` to `.len` for `Array`, `SizedArray` and `Span` alike (`src/transform/native/nativeLower.ms:249-252`).
  - A fixed array is emitted as `struct msSizedArray_<T>_<N> { T data[N]; }` (`src/codegen/c/types.ms:1478-1495`), with no `len` field. Element access already passes the size as a constant (`msSizedArrayAccess(a, i, n)`, `runtime/core/system.h:503`).
  - `for..of` lowering reads `$iter.length` (`src/transform/lowering/forOfLower.ms:142`), so it inherits the error.
- Reference: `len` of an `array[N, T]` folds to the constant `N` (`semfold.nim:139`, `of mLengthArray`). Twin: `for fighter in account.fighters` through `ptr Account`, then `account.fighters.len`, prints `9 4`.
- Fix direction: `.length` on a `SizedArray` lowers to the integer literal of its `typeValue`, the way the reference folds `mLengthArray`; `for..of` then needs no change.
- Fix, in a private worktree off `f8a913e5` (`/tmp/hib-bugs/wt-fix4`): exactly that, in `rewriteMemberExpr` (`src/transform/native/nativeLower.ms`); the reference folds it whatever the argument is (`semfold.nim:684-687`). Measured: both repros print `9 4` and `8 4` on C; regression test `bug181FixedArrayLength.ms` is green on the patched build and red on the unpatched one (five clang `no member named 'len'` errors); self-host fixpoint 313 C files, 0 differ; `msc test src/index.ms` 180/180 files, 3717/3717; guard ALL GREEN, 332 probes; corpus 1200 pass, 19 fail, 6 xfail (the 17 known cells and two timeouts of `419-leakSendMovedArgAsync`); sanitizer lane 206 pass, 8 fail (seven of the known eight and a timeout of `405-lockedSharedCounter`); Hibernal rules suite green, seven digests identical on native, JS and the unpatched compiler. The C this build emits for `419` and for `405` is byte-identical to the unpatched compiler's, so those hangs are not this change: `405`, `410` and `419` are the corpus's threading programs and hang intermittently on this tip with either compiler. Not landed: waiting on approval to commit.

### 5. `==` on structs fails over 24 bytes in C, and for every struct in JS

```ms
struct Key { a: uint64; b: uint64; c: uint64; d: uint64; }
const owner: Key = { a: 1, b: 2, c: 3, d: 4 };
const signer: Key = { a: 1, b: 2, c: 3, d: 4 };
if (owner == signer) { … }
```

- Blocks on-chain code: a public key is 32 bytes, and every owner or signer check compares two of them.
- Measured on `ba16897a`:
  - C, a 32-byte struct declared in the same module: clang `passing 'WideKey *' to parameter of incompatible type 'WideKey'`, then `conflicting types for 'WideKeyEq'`.
  - JS, every struct, 16 bytes included: `ReferenceError: SmallKeyEq is not defined`.
  - On `b707175d` the imported 32-byte case failed in C with the same clang error.
  - On `d101b611` the same-module 32-byte case builds and prints `1` for `==` and `1` for `!=` on C, so only the JS failure is left.
- Works:
  - C, a 16-byte struct in the same module: `==` and `!=` print `11`.
  - C, a 32-byte struct imported from another module: `111`, since `ffdcb753` ("derive the Eq hook prototype from the parameter ABI").
- Where:
  - `lowerOperators` runs for both backends (`src/transform/index.ms:155`). On a value struct it rewrites `a == b` to a call `<Type>Eq(a, b)` and registers the type for generation (`src/transform/lowering/operatorLower.ms:158-163`).
  - The `Eq` body is generated by `liftDestructors`, which runs only when `!jsBackend` (`src/transform/index.ms:193`). JS calls a function that is never emitted.
  - C: since `ffdcb753` the prototype takes its pointer choice from the `hookptr:` type-cache entry that `genObjectType` writes (`src/codegen/c/types.ms`), and the call passes `&a` for a struct over 24 bytes. In the same-module case the prototype still takes the struct by value. Why is not traced.
- Reference: object `==` is the generic `proc ==*[T: tuple|object](x, y: T): bool` (`lib/system.nim:2056`). Twin: a 16-byte object, a 32-byte object from another module and a 32-byte local object print `1111` on C and JS.

### 6. Module `const` does not link on Solana

Scalars landed `8be46044..e5f0ec68` (arc `wt/solana-const-fold`, 2026-09-23), with the dead-`if` crash below. Re-measured 2026-09-24 on installed `cce059c8`: `tools/rulesProbe.ms` builds a 17 KB `.so` and `tools/fightProbe.ms` a 68 KB `.so` with `--os=solana`; `msc test rules/index.ms` 353/353; the seven `sim/determinism.ms` digests are identical on native and JS; a module `const` of struct type fails at compile time with `FREESTANDING E02` at the binding. Aggregate consts in `.rodata` stay open behind #8. The history below is the trace and the first fix.

```ms
import { DAMAGE } from "./knobs";
const LIMIT: uint64 = 9;
function main(): int32 {
	if (LIMIT == 9 && DAMAGE == 3) { … }
	return 0;
}
main();
```

- Blocked on-chain code until the scalar fix landed: `rules/` keeps its tuning knobs as `export const`, so `fight`, `emission` and `tree` could not link. This is R12 in `docs/SOLANA.md` and `docs/ROADMAP.md`.
- Measured on `ba16897a` with `--os=solana`. Each of these fails at the link with `ld.lld: error: relocation refers to a symbol in a discarded section`, naming the constant and the module's `Init000`:
  - a literal `const LIMIT: uint64 = 9` in the entry file;
  - `const START: uint64 = seed()` in the entry file;
  - `export const DAMAGE: int32 = 3` and `MIN_STAKE` imported from another module;
  - Hibernal `tools/rulesProbe.ms`.
- Works:
  - The same values as locals inside `main()` build a `.so`.
  - On the host every form runs: `24 5000009` on C and JS.
- Where: `genGlobalVar` (`src/codegen/c/declarations.ms:633`) emits every module binding as a C global. A literal initializer becomes an initialized global (`<type> NAME = <literal>;`, `:684-700`); any other initializer is assigned in the module's `Init000`. The link discards the section that holds them while `Init000` still refers to it.
- Reference: a `const` symbol is replaced by its value at each use (`getConstExpr`, `of skConst` → `copyTree(s.astdef)`, `semfold.nim:604-625`), so no storage is emitted for it.
- Fix direction: fold a module `const` whose initializer is a compile-time constant into its uses, as the reference does. Under `--os=solana`, a module binding that still needs storage or runtime initialization is a compile error at the binding instead of a link error.

- Re-traced on `f8a913e5` (2026-09-17) with `/trace-nim`; repro matrix in `/tmp/hib-bugs/t6/`.
  - Boundary: under `--os=solana` every module binding that optimised code still reads fails the link — `const` or `let`, scalar, struct or `T[N]`, literal or computed initializer, entry file or imported. The same value as a local links. An entry-file `const` whose only read is dead after clang's optimiser links by accident, which is where "entry-file scalar const folds" in `docs/ROADMAP.md` R12 came from.
  - Mechanism: `genGlobalVar` emits a writable C global (`.data`, or `.bss` plus an assignment in `Init000` when the initializer is not a literal); the SBF link script discards `.data*` and `.bss*`.
  - Reference: a scalar `skConst` is inlined where it is used (`semSym`, `semexprs.nim:1386-1394` → `inlineConst`; `getConstExpr`, `semfold.nim:604-625`), an `skEnumField` folds to its position (`semfold.nim:597-603`), an aggregate const is emitted once as `static NIM_CONST` data (`genConstDefinition`, `ccgexprs.nim:3489`), and only `let`/`var` get storage. Integer folding is exact: a signed result out of range is not folded (`foldAdd`/`foldSub`/`foldMul`, `semfold.nim:65-100`), an unsigned one wraps to its width (`maskBytes`, `:258-275`).
  - Verdict: DIVERGE-INCOMPLETE. The comptime tier already inlines a module const through its defining AST (`src/codegen/raiser/expressions.ms:336-346`, `paper/NIM-REF.md` row "Readonly static fields at comptime", SAME); the runtime tier never did, and its fold table runs on doubles.
- Fix, in a private worktree off `f8a913e5` (`/tmp/hib-bugs/wt-fix6`):
  - Scalars (`src/transform/coercion/constantFolding.ms`): an identifier bound to a module `const` of integer, float or boolean type folds to the value of its initializer, through chains of consts, across modules, through `as intN` and through an enum member under `as intN`. Integer operands fold in their own width, by the reference rules above. Measured: entry literal, imported const, `LOG2_ONE / 8` chains and `(StakeLevel.Whole as int32) + 1` link; `tools/rulesProbe.ms` builds a 14 KB `.so`; `msc test rules/index.ms` 349/349; the seven `sim/determinism.ms` digests are identical on native, JS and the unpatched compiler.
  - Diagnostic (`src/checker/freestanding.ms`, reported from `src/compiler/compile.ms` after DCE): under `--os=solana` a module `let`, or a module `const` whose initializer is still not a literal, that DCE keeps is a compile error at the binding (FREESTANDING E02) instead of a link error. Measured on module `let`, `const START = seed()`, a struct const and a `T[N]` const.
  - Regression test `src/test/fixedbugs/bug180ModuleConstFold.ms`; its emitted-C assertion is red on the unpatched build.
  - Found by the guard lane (`positionalNewJs`): folding a boolean module const exposed a crash that the unpatched compiler already has on the literal spelling, `const skipped = false && tally(new Pt(1, 2));` (exit 139). `eliminateDeadBranch` (`src/transform/analysis/dce.ms`) returned a null `alternate` for `if (false)`, assuming the parser always supplies an else block, while lowering passes build `makeIf(…, null, …)`. Fixed in the same worktree (an `if (false)` with no else becomes an empty block), regression test `bug184DeadBranchWithoutElse.ms`. Also found by the suite: the first version refused to fold `-9223372036854775808`; and a JS codegen unit test that expected `const x = 1; x;` to keep the identifier now uses `let`.
  - Found after the first full gate, while diffing emitted C for corpus program `419`: the integer arm of the unary fold wrapped a literal that did not fit the type the checker gave it, so `value < -9007199254740992` became `value < 0` and `-1 < -9007199254740992` folded to `true`. No lane caught it (inside the compiler it only turned `-1` into `-1.0`). Fixed by folding in the integer domain only when the literal fits (`literalFitsWidth`), a case added to `bug180`; the gate is re-running. A corpus-wide emitted-C diff against the unpatched compiler (214 programs, 36 differing files, `/tmp/hib-bugs/emitdiff6/`) was then read in full: 123 line pairs are a const name replaced by exactly its declared value, and the other 23 are correct folds (`128 | 1` → `129`, `(uint64_t)(-1)` → `18446744073709551615ULL`, `7.5 % 2.0` → `1.5`, `300 as uint8` → `44`, `static const t = 1` → `1`, a dead `if (3 != 3)` removed, and the `Init000` and `extern` of modules whose consts all fold).
  - Gates on `f8a913e5` with the final code (2026-09-18, third run): self-host fixpoint 313 C files, 0 differ; `msc test src/index.ms` 180/180 files, 3717/3717; `bug180` (5) and `bug184` (2) green standalone; guard ALL GREEN, 332 probes; corpus 1199 pass, 20 fail, 6 xfail — the 17 known cells plus timeouts of `405 [orc]`, `419 [orc]` and `419 [danger]`; sanitizer lane 206 pass, 8 fail — seven of the known eight plus a timeout of `405`; Hibernal rules suite green, seven digests identical on native, JS and the unpatched compiler. The #4 and #3 builds, whose C for `405` and `419` is byte-identical to the unpatched compiler's, hang on the same cells at the same rate, so these timeouts are the tip's intermittent threading hangs, not this change. Not landed: waiting on approval to commit.
  - Gates BEFORE that last fix, kept for reference: self-host fixpoint 313 C files, 0 differ; `msc test src/index.ms` 180/180 files, 3717/3717; `bug180` (4) and `bug184` (2) green standalone; guard ALL GREEN, 332 probes; corpus 1200 pass, 19 fail, 6 xfail — the 17 known cells, the known `410` hang, and one timeout of `419-leakSendMovedArgAsync [danger]` that three re-runs of all its cells did not reproduce on the patched or the unpatched compiler; sanitizer lane 207 pass, 7 fail, all among the known eight; Hibernal rules suite green and the seven digests identical on native, JS and the unpatched compiler. These numbers predate the `literalFitsWidth` fix.
  - Open part: a `const` of struct, `T[N]` or string type belongs in `.rodata` as the reference does. It waits on #8, because a `const` struct is still writable today and a program that writes one would fault once the storage is read-only. `Pubkey` constants in `std/solana` need it; `rules/` does not.

### 7. Type mismatch message drops type arguments

```ms
struct Pda<T> { address: uint64; }
function feed(pda: Pda<Pet>): uint64 { return pda.address; }
const block: Pda<Block> = { address: 5 };
feed(block);
```

- Measured on `ba16897a`, C and JS: `Argument type mismatch in 'feed' arg 0: got Pda, expected Pda`. Rejecting the call is right; the message cannot tell the two types apart.
- Why it matters on chain: the account type travels as a type argument (`Pda<Pet>`), so this is the message a developer gets for passing the wrong account.
- Where (not traced): the message uses `typeDisplayName` (`src/checker/callResolve.ms:1343`). `typeDisplayNameInner` prints type arguments only for a `GenericInstance` (`src/checker/types.ms:3238-3245`) and otherwise falls back to `typeNameOf` (`:3248`).
- Reference: the twin reports `[1] blockPda: Pda[n.Block]` against `proc feed(pda: Pda[Pet]): uint64`.
- Fix direction: print the type arguments of an instantiated generic struct in mismatch messages.

### 8. `const` bindings and value parameters are writable

```ms
struct Pet { hunger: uint16; bornSlot: uint64; }
const pet: Pet = { hunger: 10, bornSlot: 1 };
pet.hunger = 5;
pet = { hunger: 99, bornSlot: 0 };
const count: uint64 = 1;
count = 2;
```

- Decision (2026-09-15): `const` on a value struct is deep.
  - Neither the binding nor any field or element may be written, directly or through `ref`/`out`.
  - A struct is a MetaScript value type with no TypeScript counterpart, so TypeScript's binding-only `const` does not constrain it. The rule is the one an ordinary compiler for value types enforces.
  - Reference types (`interface`, `class`) and `Ptr<T>` keep writes through the reference legal, because the memory written is not the binding.
- Measured on `b707175d`:

| Code | C | JS | Nim twin (`let`) |
|---|---|---|---|
| `const x: uint64 = 1; x = 2` (also unannotated, and a module-level `const`) | accepted, prints 2 | accepted, throws at runtime | `'x' cannot be assigned to` |
| `const pet: Pet; pet = { … }` | accepted, 99 | throws at runtime | same error |
| `const pet: Pet; pet.hunger = 5` | accepted, 5 | 5 | `'a.hunger' cannot be assigned to` |
| `const pets: Pet[2]; pets[1].hunger = 5` | accepted, 5 | 5 | `'pets[1].hunger' cannot be assigned to` |
| `const pet: Pet; feed(pet, 3)` with `ref pet: Pet` | accepted, 7 | 7 | `expression 'pet' is immutable, not 'var'` |
| `const x: uint64; bump(x)` with `ref n: uint64` | accepted, 2 | 2 | same error |
| `const pets: Pet[2]; feed(pets[1], 3)` | accepted, 17 | 17 | same error |
| `feed(pet, 3)` inside `outer(pet: Big)`, struct over 24 bytes | caller mutated: `7 7` | caller intact: `7 10` | same error |

- Works:
  - `let b = a; b.hunger = 5` copies: `10 5` on C, JS and Nim.
  - A direct field write on a value parameter is rejected (`cannot mutate value-type parameter`).
  - A literal passed to `ref` is rejected.
  - `const u: IPet; u.hunger = 5` on an interface is legal and stays legal.
- The `Big` case:
  - `outer` receives `const Big*`, because it is big and its own body does not write it. The call hands that pointer to `feed(Big* pet)`, and the C cast drops `const`.
  - The backends disagree: C writes the caller's memory, JS does not.
- Where:
  - No assignability check exists. Assignment checking in `checkExprPass.ms:495-525` covers only read-only properties, actor `pid` and `string.length`. `git log -S` finds no const-reassignment diagnostic in the history.
  - The `Var` argument check (`callResolve.ms:1371-1380`) is syntactic: any Identifier, MemberExpr or ArrayAccess passes, whatever its root binding. Its message also says "out parameter" for a `ref` formal.
  - `paramMutationAnalysis.ms:80` rejects writes to a value parameter inside its own body. It does not stop the parameter from being passed to a `ref` or `out` formal.
- Reference: one relation, `isAssignable` (`parampatterns.nim:224`), classifies an expression by its root.
  - A `skLet`, or an `skParam` that is not `var`, is `arAddressableConst`.
  - `nkDotExpr` and `nkBracketExpr` recurse to the root, unless the base is `ptr`, `ref` or `var`, which gives `arLValue`.
  - The same relation serves assignment (`semAsgn`, `semexprs.nim:2026`, error at `:2102`) and `var` formals (`isLValue`, `sigmatch.nim:2334`, used at `:2917`).
- MetaScript rules the port keeps:
  - Assigning a parameter is legal (TS compatibility): `docs/NIM-REF.md` row "Assignment to a parameter", DIVERGE-INTENTIONAL, lowered to a shadow local by `paramReassignLower`. A scalar value parameter passed to `ref` therefore stays legal (measured: `outer` returns 2, caller keeps 1).
  - A value-type struct parameter is a read-only view (`6831fedd`), so it is not assignable through `ref` or `out`.
- Fix direction:
  - Port `isAssignable` as one root-based relation. Call it from both the assignment check and the `Var` formal check, replacing the node-kind test at `callResolve.ms:1371`.
  - Roots:
    - a `const` binding is not assignable, including fields and elements of a value type;
    - a `let` binding is assignable;
    - a value-type struct parameter is not assignable;
    - a scalar parameter is assignable;
    - anything under a `Ptr`, `Ref` or `Var` base is assignable;
    - an rvalue is not assignable.
  - Name the root in diagnostics, for example `'pet.hunger' cannot be assigned to: 'pet' is const`. Say `ref` or `out` according to the formal.
  - Record the deep `const` rule for value structs in `docs/LANG.md` and `docs/LANG-STRUCT.md`, and add a `docs/NIM-REF.md` row (SAME as `let`).


### 19. A 64-bit integer literal expression folds through a double

```ms
const folded: uint64 = 18446744073709551615 / 3;
const small: uint64 = 9000000000000000000 / 7;
```

- Measured on `f8a913e5`: C prints `6148914691236517000` and `1285714285714285800`, JS prints `6148914691236516864n` and `1285714285714285824n`. The exact values are `6148914691236517205` and `1285714285714285714`; the same division on `uint64` variables, or on two `uint64` consts, is exact on both backends.
- Where: `foldBinary` (`src/transform/coercion/constantFolding.ms`) folds two number literals on doubles, guarded only by `fitsDouble` on each operand, so an inexact quotient or product is baked in. The checker types both literals `int32` whatever the annotation says, so the expression is an `int32` division converted to `uint64` afterwards.
- Reference: a literal takes its type from its value and its context, and `semfold.nim` folds integers in `Int128` by the type of the expression.
- Not fixed by #6: its integer fold applies only when the operands fit the type the checker gave them, so this case still takes the double path. The fix is in literal typing.
- Does not block the design: `rules/` reaches its 64-bit knobs through typed consts (`100000 * HBRN_UNIT`), which #6 folds exactly.

### 20. Two structs of the same shape are assignable in the checker and distinct in C

```ms
struct StakeFailure { code: int32; }
struct ProgramFailure { code: int32; }
function widen(failure: StakeFailure): ProgramFailure { return failure; }
```

- Measured on `f8a913e5`: the checker accepts it; C fails in clang (`assigning to 'ProgramFailure…' from incompatible type 'StakeFailure…'`); JS prints `7`. Repro `/tmp/hib-bugs/r/b21_sameShapeStructs.ms`.
- Found through #3: with two same-shaped error structs `try` sees no mismatch, so no conversion runs and clang fails.
- Reference: object types are nominal; the twin is a type mismatch.
- Not traced yet. Proof types in `std/solana` are `distinct`, so they do not depend on it.

## B. A method call is an ordinary call

B core is one change in `checkCallExprInner` (`src/checker/callResolve.ms:701`), for a callee `x.f`:
1. Check `x` only.
2. Look up a field, enum member, module export or function-typed field, without reporting an error.
3. On a miss, rewrite the call in place to `f(x, a…)` and send it down the existing identifier path: macro dispatch, overloads, argument fit, and the `Var` check from #8.

- Only functions with a `this` receiver are candidates. Class and actor methods stay where they are for now.
- Reference: `semIndirectOp` → `semFieldAccess(efIsDotCall)` → `builtinFieldAccess` returning nil → `dotTransformation` (`semexprs.nim:1134-1146`, `:1670-1702`).
- Check with a Nim twin before landing: a local name that shadows the routine name (`const key = pet.key()`). Candidates must be collected across scopes.
- B core alone closes #9 and #10. #11 adds the `this ref` syntax on top.

### 9. Macro called with method syntax

```ms
export macro fieldCount(receiver: Node): Node { … getTypeArg() … }
account.fieldCount<Pet>();
account.one();
```

- Measured: `Property 'fieldCount' does not exist on type 'Account'`, and the same for `one`, on C and JS.
- Works: `fieldCount<Pet>(account)` prints `2`; `one(account)` prints `1`.
- Where: `checkCallExprInner` (`src/checker/callResolve.ms:746-767`) takes the macro path only when `d.callee.kind == NodeKind.Identifier`. A MemberExpr callee goes to `checkMemberExpr`, which never looks for `SymbolKind.Macro`.
- Reference: `dotTransformation` builds an `nkDotCall`, and overload resolution includes `skMacro` and `skTemplate` (`semexprs.nim:1039`, `:1042`). Twin: `account.fieldCount(Pet)` prints `2`.
- Fix direction: at a call site whose callee is `receiver.name`, when there is no field, method or extension of that name and `name` resolves to a macro, rewrite it to a macro invocation with the receiver as the first argument, keeping the call's type argument. Do this only at call sites, not on plain member reads.


### 10. `Ptr<T>` receiver

```ms
function feed(this pet: Ptr<Pet>, portions: uint16): uint16 {
	pet.hunger = pet.hunger - portions;
	return pet.hunger;
}
const pet = allocate(16) as Ptr<Pet>;
pet.feed(3);
```

- Measured: `Property 'feed' does not exist on type 'Pet'. Available: hunger, bornSlot`.
- Works:
  - The same function called as `feed(pet, 3)` prints `7`.
  - A free function taking `Ptr<Pet>` prints `7`.
  - An extension on `Pet` called through a `Ptr<Pet>` prints `10`; C emits `hungerOf(*(pet))`.
- Where:
  - `src/checker/context.ms:935-944`: `receiverBaseName` stores the receiver as `"Ptr"`.
  - At the call site `typeNameOf` strips `Ptr` and yields `"Pet"`, so `isReceiverMatch` fails at the nominal-name check (`context.ms:716-721`).
  - The `HiddenDeref` retry at `callResolve.ms:3440` only covers Array, SizedArray and Span.
- Reference:
  - `builtinFieldAccess` skips `tyPtr` only for field lookup.
  - `dotTransformation` undoes the hidden derefs before overload resolution, so `proc feed(pet: ptr Pet)` matches `pet.feed(3)`. Twin prints `7`.
- Divergence, now settled by measurement:
  - MetaScript accepts a `Pet` extension called on a `Ptr<Pet>` and derefs. Nim rejects it (type mismatch).
  - With a `this ref` receiver the same auto-deref miscompiles (#11: `feed_u0(&(pet_1_), 3)`).
  - Align with Nim:
    - A `Ptr<T>` receiver matches `this x: Ptr<T>`.
    - A `T` extension needs an explicit deref, as `p[].feed(3)` does in Nim.
  - Writing through `this x: Ptr<T>` needs no `ref`, because a field write through a pointer is an lvalue (`nkDotExpr` over `tyPtr` in `parampatterns.nim:249-252`). This covers account overlays.
- Fix direction: B core. `pet.feed(3)` becomes `feed(pet, 3)`, which already matches `Ptr<Pet>` (it prints `7` today). Do not add a structural `Ptr` case to `isReceiverMatch`; that resolver is deleted after group C.
- Needed with it: an explicit dereference spelling. After this change a `T` extension called on a `Ptr<T>` needs one, as `p[]` is in the reference, and `docs/` has none today. Field reads and writes through a `Ptr<T>` stay implicit.


### 11. `this ref` receiver

```ms
struct Pet { hunger: uint16; bornSlot: uint64; }
function feed(this ref pet: Pet, portions: uint16): void { pet.hunger = pet.hunger - portions; }
let pet: Pet = { hunger: 10, bornSlot: 1 };
pet.feed(3);
```

- Why it is needed:
  - Value parameters have been read-only views since `6831fedd` (2026-08-23). `paramMutationAnalysis.ms:80` reports `cannot mutate value-type parameter 'pet'`, so `this pet: Pet` cannot mutate.
  - That leaves `ref` as the only mutating receiver for a struct.
  - `docs/LANG.md` "Struct Parameter Passing" and `docs/LANG-STRUCT.md` "Parameter Modifiers" ("Redundant for structs (default already propagates)") are stale.
- Measured on `b707175d`:
  - `this ref pet: Pet` and `ref this pet: Pet` both give `Parse: Expected '{' at line 2`, on C and JS.
  - A method named `ref` (`function ref(this pet: uint64)`, `x.ref()`) prints `4` and must keep working.
- Measured with a probe parser patch, in a private worktree only. The `this` branch accepts `ref`, and `applyExtensionFlags` strips `ref:` from the receiver name. Parsing turns out to be the small part: the receiver then skips every rule a `Var` argument gets.

| Case | C | JS | Nim twin |
|---|---|---|---|
| `let pet; pet.feed(3)` | 7 | crash: `pet[0][pet[1]]` | 7 |
| `feed(pet, 3)`, free call | 7 | 7 | 7 |
| `let x: uint64; x.bump()` | 2 | crash | — |
| `holder.pet.feed(3)` / `pets[1].feed(3)` | 7 / 17 | crash | 7 |
| cross-module / `ref` calling `ref` | 7 / 8 | crash | — |
| `const pet; pet.feed(3)` | accepted, 7 | crash | `expression 'pet' is immutable, not 'var'` |
| `makePet().feed(3)` | accepted | crash | same error |
| `pet.feed(3)` inside `outer(pet: Pet)` | accepted, write lost (10) | crash | same error |
| `Ptr<Pet>` receiver | UBSan: `member access within misaligned address` | crash | type mismatch; `p[].feed(3)` prints 7 |
| `box.put(5)` on `Box<T>` | clang: undeclared `Box_put__int32_u0` | crash | 5 |

- Where:
  - Parser:
    - `src/parser/util.ms:247-277`: the `this` branch reads the next token as the receiver name, so `this ref` takes `ref` as the name.
    - With `ref this`, the `ref` check at `:237` fails `isIdentLike` on `this`.
    - `applyExtensionFlags` (`declaration.ms:157-164`) only knows a leading `this:`, and it writes the name into the `ext:` flag.
  - JS:
    - `lowerJsVarParam` (`src/transform/index.ms:122`) runs before `lowerExtensionMethod` (`:139`). The receiver is not an argument yet, so it is never boxed.
    - Emitted code: `feed_u0(pet, 3)` for `pet.feed(3)`, against `feed_u0([pet, 0], 3)` for `feed(pet, 3)`.
  - Receiver lvalue:
    - The `Var` check (`callResolve.ms:1371-1380`) loops only over `d.arguments`.
    - As a result `makePet().feed(3)` is accepted while `feed(makePet(), 3)` is rejected.
    - The binding-level holes are #8.
  - `Ptr` receiver:
    - Member lookup sees through `Ptr` (`typeNameOf` strips it), but the argument passed is still the pointer variable.
    - C emits `feed_u0(&(pet_1_), 3)` with `pet_1_` of type `Pet*`, so the callee writes into the stack slot that holds the pointer.
  - Generic receiver: see #1.
    - Unification fails, and `isReceiverMatch` falls back to the name check (`context.ms:700-721`).
    - The call is then emitted for an instance that was never created.
- Reference:
  - `dotTransformation` (`semexprs.nim:1670-1691`) makes the receiver argument 0.
    - The `var` formal check in `matchesAux` (`sigmatch.nim:2911-2918`, `isLValue` at `:2334`) therefore applies to the receiver like to any other argument.
  - `docs/NIM-REF.md` already records this as SAME in the row "Method receiver spelled on `this`": receiver mutability is the first parameter's mode.
- Fix direction:
  - Land this together with, or after, the dot-call rewrite (`x.f(a)` becomes `f(x, a)` in the checker). The receiver then goes through the same steps as any argument:
    - argument fit;
    - the `Var` check (#8);
    - `lowerJsVarParam`.
  - A `Ptr<T>` receiver against `this ref x: T` then becomes the same type mismatch that `feed(ptr, 3)` already reports.
  - Syntax: one spelling, `this ref name: T`.
    - `this` opens the receiver slot and the rest is an ordinary parameter, like `this typeof X`.
    - `ref this` gets a pointed parse error.
  - Update the editor grammars:
    - tree-sitter `this_parameter`, and `parameter`, which has no `ref`, `out` or `readonly` at all;
    - the tmLanguage receiver regex.


## C. Static extensions are type receivers

C core has four parts:
- `this typeof X` becomes a type-level receiver, matched by type identity. Emit still drops it.
- An enum counts as type-level access.
- Each generic parameter name is bound to its concrete type in the instantiation scope.
- Same-name statics become overloads of one symbol that bare calls filter out, so export and import walk the overloads.

References:
- `typedesc` receiver matching: `sigmatch.nim:2133`.
- Generic parameter binding: `instantiateGenericParamList` and `addDecl` (`seminst.nim:37-50`, `:516-517`).
- Import: `importSymbol` walks every routine of a name.

Closing step after this group, to remove the second resolver:
- Delete the extension block in `checkCallExprInner`, `resolveExtensionOverloadCall`, the name path of `isReceiverMatch`, and the extension fallback in `checkMemberExpr`.
- Make `extensionMethodLower` a no-op for calls the checker already rewrote, and update the raiser (`codegen/raiser/expressions.ms:814-822`).
- The registry stays only as an index, for LSP completion and the protocol hooks (`toString`, `toItems`, `getDynamicField`, `onDestroy`).

### 12. Extensions on enums

```ms
enum Mood {
	Calm,
	Angry,
}
function label(this mood: Mood): uint8 { return (mood as int32) as uint8; }
function fromByte(this typeof Mood, value: uint8): Mood { return (value as int32) as Mood; }
mood.label();
Mood.fromByte(1);
```

- Measured: `Property 'label' does not exist on type 'Mood'. Available: Calm, Angry`, and the same for `fromByte`, on C and JS.
- Works:
  - `label(mood)` and `label(Mood.Angry)` print `1`.
  - `mood.toString()` prints `Angry`.
  - A struct static `Pet.make(4)` works.
- Where:
  - `src/checker/callResolve.ms:2963-2976`: any `.prop` on an Enum-typed object is rewritten as a member access (only `toString` is exempt), and a missing member is an error on the spot. The extension lookup is never reached.
  - `isTypeLevelAccess` (`callResolve.ms:328-340`) does not list `SymbolKind.Enum`.
- Reference:
  - The `tyEnum` arm of `tryReadingTypeField` (`semexprs.nim:1529-1545`) returns nil when the identifier is not a member.
  - `semFieldAccess` (`:1693-1702`) then applies `dotTransformation`.
  - Twin: `mood.label()` and `Mood.Angry.label()` print `1 1`; `Mood.fromByte(1)` with `typedesc[Mood]` prints `Angry`.
- Fix direction:
  - Rewrite to the enum member only when the member exists; otherwise fall through to the extension lookup.
  - Treat an enum as type-level access for static extensions.
  - Widen an enum-literal receiver (`Mood.Angry.label()`) to its enum when matching.


### 13. `T.f()` inside a generic

```ms
function accountKind(this typeof Pet): uint8 { return 2; }
function accountKind(this typeof Block): uint8 { return 1; }
function kindOf<T>(): uint8 { return T.accountKind(); }
kindOf<Pet>();
```

- Measured: `Undefined variable 'T'`, on C and JS.
- Works:
  - An instance extension on a generic value, `sample.accountKind()`, prints `2 1`.
  - `T` inside annotations (`const copy: T`) works.
  - `Pda.atAddress<Pet>(5)` works.
- Where: `instantiateGenericFunction` (`src/checker/instantiate.ms`) substitutes type variables only inside types and annotation strings (`typeArg`, `sizeofType`). No symbol named `T` is in scope when the body is re-checked, so the identifier lookup in `checkExprPass.ms:428` fails.
- Reference: `instantiateGenericParamList` (`seminst.nim:37-50`) creates an `skType` symbol for each generic parameter, bound to the concrete type. `generateInstance` adds it with `addDecl` (`seminst.nim:516-517`) after `fillMixinScope`. Twin prints `2 1`.
- Fix direction: bind each generic parameter name to its concrete type in the instantiation scope, and let static-extension lookup see through that binding.


### 14. Same-name static extensions across modules

```ms
// lib.ms
export struct Pet { hunger: uint16; }
export struct Block { id: uint32; }
export function create(this typeof Pet): Pet { return { hunger: 7 }; }
export function create(this typeof Block): Block { return { id: 9 }; }
// main.ms
import { Pet, Block, create } from "./lib";
Block.create();
```

- Measured: `Property 'create' does not exist on type 'Block'. Available: id`, on C and JS. `Pet.create()` works.
- Works:
  - The same pair in one file prints `7 9`.
  - A single exported static prints `7`.
  - Same-name instance extensions across modules (`pet.key()`, `block.key()`) print `7 9`.
- Where:
  - `collectExports` (`src/checker/context.ms:359-371`) walks the extension registry and skips any symbol whose name is already exported. Statics are not module-scope symbols, so they never join `sym.overloads`, and the second static never gets an export entry.
  - The import side is first-name-only as well: `findExportedSymbol` (`context.ms:160-167`) and the dedup in `collectImport` (`collectPass.ms:1051-1052`).
- Reference: `importSymbol` (`importer.nim`) walks every routine with that name (`initModuleIter`/`nextModuleIter`) and imports each one. Twin prints `7 9`.
- Fix direction: carry every same-name static extension, and mixed static/instance ones, as overloads of a single export entry.


## D. New features

#15 does not depend on the method-call rewrite and can land any time. #16 comes last because the borrowed routine is looked up the way a call to the base type resolves, and that needs the single resolution path from groups B and C. In Nim, `searchForBorrowProc` (`semcall.nim:1053`) builds `fn(x, y)` with the distinct parameters replaced by their base types and runs `semOverloadedCall` on it.

### 15. Struct fields private to their module

```ms
// auth.ms
export struct Signer { key: uint64; }
export function verifySigner(key: uint64, isSigner: boolean): Result<Signer, AuthError> { … }
// program.ms
const fake: Signer = { key: 99 };
spend(fake);
```

- Why on chain: a proof type such as `Signer` is only safe if the module that checks the account is the only one that can create it. Today any module can.
- Measured on `ba16897a`, same on `b707175d`:
  - Plain field: the literal from another module is accepted, `99` on C and JS.
  - `private key: uint64` or `readonly key: uint64`: C fails with `internal: unresolved type (kind=48) reached codegen` in the declaring module, even for a program that only calls `verifySigner`. JS accepts both the forged literal (`99`) and the honest call (`7`).
  - `let fake: Signer;` without an initializer: C prints `0`; JS throws at `signer.key`.
  - `distinct`: `account as Signer` from another module prints `99`. The reference allows that conversion too, so `distinct` is not a proof.
- Where (not traced): struct bodies are parsed by `parseInterfaceBody` (`src/parser/statements/declaration.ms:788`). The modifier passes the parser and the checker without an error, and the declaring module then fails in C codegen.
- Reference: a field without the export marker is invisible outside its module, and naming it in an object constructor is rejected (`semConstrField`, `semobjconstr.nim:85-87`). Twin: `Signer(key: 99)` from another module fails with `the field 'key' is not accessible.`; `verify(Account(key: 7), true)` prints `7`; `default(Signer)` still builds a zeroed value (`0`), so a proof must not accept a zeroed value as valid.
- Fix direction:
  - `private` on a struct field, the spelling classes already use. Outside the declaring module the field cannot be named in a literal, a read or a write.
  - Until then, the parser rejects a field modifier instead of letting it reach codegen.

### 16. `@borrow` for `distinct` types

```ms
struct Account { address: uint64; }
type Signer = distinct Account;
function key(this account: Account): uint64 { return account.address; }
signer.key();
```

- Measured: `Property 'key' does not exist on type 'Signer'`. `(signer as Account).key()` works.
- This is by design: Nim does not inherit procs through `distinct` either (the twin without borrow is a type mismatch). Nim shares them with `proc key(signer: Signer): uint64 {.borrow.}` (twin prints `7`), via `semBorrow` (`semstmts.nim:1968`) and `searchForBorrowProc` (`semcall.nim:1053`). Field access needs ``{.borrow: `.`.}``.
- MetaScript has no borrow mechanism; `borrow` is only a reserved word. User decorators are not allowed on functions because that position is reserved for compiler intrinsics, which is where a `@borrow` intrinsic belongs.
- Fix direction: add `@borrow` on a body-less function declaration, resolved the way `semBorrow` does it, and add a `docs/NIM-REF.md` row.

## E. Not blocking

Found while tracing `Borrow<T>`. On-chain code does not need these: read structs through value parameters, overlay account data with `Ptr<T>`, index hot loops. They can wait. The design they point at is in `~/metascript/docs/CODE-STYLE.md` §5, "`Borrow<T>` design".

### 17. `Borrow<T>` is half implemented

- Measured on `b707175d`:
  - `const item: Borrow<Big> = data[0]` (the `LANG.md` example): C declares `const Big* item` and assigns the element value without `&`, clang error. JS runs and copies: after `data[0].a = 9`, `item.a` prints `1`.
  - A `Borrow<Big>` return type (`return items[0]`): clang error.
  - Returning a `Borrow` of a local is not rejected by the checker.
  - No lifetime check exists. `LANG.md` says the analyzer manages it, but no analyzer commit has ever referenced `TypeKind.Borrow`.
  - `for (const big of bigs)` copies every element (`Big big_1_ = msArrayAccess(...)`, debug and `--danger`). `const first = bigs[0]` and `Map.get` on a struct value copy too.
- Works: an `extern` parameter `data: Borrow<float32>` called with `arr[0]` from a `let` or `const` array; a `Borrow<Big>` parameter, which emits the same `const Big*` as a plain value parameter.
- Same area:
  - `extern function f(ref data: float32, …)` called with `arr[0]` passes the address of a temporary copy (`sumRef(&_clit5_, 3)`), clang error.
  - `let cur: Ptr<Tok> = arena[0]` (`LANG.md`): clang error.
- Reference: `lent T` is illegal as a parameter (`typeallowed.nim:74`), legal as a return type borrowing from the first parameter, and yielded by `items` (`system/iterators.nim:247`), which emits `big = &bigs.p->data[i]`. A `lent` local needs the experimental views checker. Twin: `addr verts[0]` into `ptr cfloat`, an `openArray` wrapper and a `lent Big` getter print `7.0 7.0 5`.
- Fix direction: the three legal positions and two rejections in `~/metascript/docs/CODE-STYLE.md` §5.

## Checked, not reproduced

- `try` inside a call argument emitted `/* unsupported expression: kind=TryExpr */` on 2026-09-13, in `tools/counterProbe.ms` built with the uncommitted Solana compiler. On `ba16897a` these print the expected values on C and JS: `double(try load(ok))` (`14 Wrong`), `double(try load(ok)) + 1` (`15 Wrong`), `Result.ok(try load(ok))` (`7 Wrong`), and `try` in a `match` arm block (`8 Wrong`). The `match` arm form also builds with `--os=solana`. Recheck when `std/solana` is rebuilt.
