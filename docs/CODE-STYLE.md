# MetaScript code style

How to write MetaScript that reads as MetaScript, not as TypeScript with integer types. Every rule here was run against `msc 0.2.54` (C backend, plus JS and `--os=solana` where noted) on 2026-09-12; the protocol and serialization section (§15) on 2026-09-13, re-run on recompiler HEAD `b07a547f`; `BitSet` (§4) re-run on 2026-09-15 against the installed `msc 0.2.54`, C and JS; the array kinds in §5 measured 2026-09-15 on C, `--release`; the pointer and view kinds in §5 (`Borrow<T>` and its neighbours) measured 2026-09-15 against recompiler `main` `b707175d` built from source, C and JS. Where the language docs and the compiler disagree, the compiler wins and the disagreement is listed in §13. Re-run the probe before trusting a claim that is older than the compiler you hold.

This file is project-agnostic. Copy it into any MetaScript repo; project-specific constraints go in that repo's `CLAUDE.md`.

## 0. The six habits

1. **`match` when a value picks one of several cases; `if` for conditions.** Enum members, literal values and small tables read best as `match`. Guards, early returns, thresholds and clamps stay `if`. Never `switch`.
2. **Fail with `Result<T, E>`, not sentinels, booleans, or `out` flags.** A function that can fail returns `Result`. Callers `try` it. Errors are `enum`s, not strings, unless the error is for a human.
3. **Loop with `for..of`, then indexed `for`, then `while`.** `while` only when the loop has no natural sequence (converge, drain, scan until a condition).
4. **Values by default: `struct`, `enum`, `BitSet<E>`, `Vec<T>`, sized integers.** Reach for `interface`/`class`/`T[]` only when you need sharing or identity. Pass arrays as `Span<T>`. Never bare `number`.
5. **Say the width.** `int32` for index, count, id, small stat; `int64`/`uint64` for money, time, hashes; `as` at every narrowing and at every signed/unsigned boundary.
6. **One `await`, three tools.** `async` for I/O, `spawn` for CPU work in parallel, `actor` for a long-lived stateful service. Shared mutable state is `Locked<T>` or it does not exist (§12).

## 1. Match

```ms
function tierCost(tier: Tier, level: int32): uint64 {
	return match (tier) {
		Tier.Small => 8,
		Tier.Medium | Tier.Large when level > 20 => 30,
		Tier.Medium => 15,
		_ => 21,
	};
}
```

Use `match` when it is the better read, not by reflex:

| Situation | Write | Why |
|---|---|---|
| An enum or a literal picks the result (`Tier.Small => 8`, `KEYSTONE_PACIFIST => …`) | `match` | reads as a table; enum matches are exhaustiveness-checked |
| Several discrete values plus one or two guarded exceptions on the same scrutinee | `match` | the guard sits next to the case it refines |
| Every arm is `_ when …` (thresholds, ranges, a clamp) | `if` or a named helper | a guard-only `match` is an `if` chain with extra syntax and no exhaustiveness check |
| A precondition that exits early (`if (x == 0) { return y; }`) | `if` | a guard, not a dispatch |
| Two outcomes | ternary or `if` | a two-arm `match` adds nothing |

```ms
function clampInt32(value: int32, low: int32, high: int32): int32 {   // not: match (v) { _ when v > high => … }
	if (value < low) { return low; }
	if (value > high) { return high; }
	return value;
}
```

- Cost is not a reason either way: a guard `match`, the equivalent `if` chain and a nested ternary compile to the same instructions (`cmp`/`csel`, no branch) under `clang -O2` (measured on the C shapes the backend emits). `Math.min`/`Math.max` are generic (`min<T>(this typeof Math, a: T, b: T): T`): an `int32` or `uint64` pair stays integer, no `as`; mixing `int32` with a `float64` literal widens to `float64`. Clamp with them instead of a ternary.
- `_` is the wildcard. `|` joins alternatives. `when` guards read the **scrutinee variable**, not a binding: write `_ when n < 0`, never `x when x < 0` (bare identifiers in patterns are an error today).
- Expression arms `=> value` return implicitly. Block arms `=> { … }` need an explicit `return` (or are statements in a statement `match`).
- Enum matches are exhaustiveness-checked: cover every member or add `_`.
- Works on: enums, integers (including `uint64`), strings, booleans, `"a".code` char codes.
- Does **not** parse: struct destructuring `{ x: 0 }`, tuple patterns `[a, b]`, ranges `0..9`. Match on one value and guard the rest.
- `try`, `break`, `continue` and C-style `for` inside arms all work now (older notes say otherwise).
- A bare struct literal as an arm value is read as a block (`=> { x: 1 }`); parenthesize it: `=> ({ ...s, might: s.might + 1 })` (C, JS, `--os=solana` build). `unreachable` is not an arm value either: put it in an `if` before the match.

Anti-pattern:

```ms
if (tier == Tier.Small) { return 8; }
else if (tier == Tier.Medium) { return 15; }
else { return 21; }
```

## 2. Result and try

```ms
enum StakeError {
	Shielded,
	EmptyHarvest,
	Broke,
}

function stakeFor(harvest: uint64, burrow: uint64, shielded: boolean): Result<uint64, StakeError> {
	if (shielded) { return Result.err(StakeError.Shielded); }
	if (harvest == 0) { return Result.err(StakeError.EmptyHarvest); }
	const cap = harvest / 2;
	return cap <= burrow ? Result.ok(cap) : Result.err(StakeError.Broke);
}

function plan(h: uint64, b: uint64): Result<int32, StakeError> {
	const stake = try stakeFor(h, b, false);
	return Result.ok(stake > 100 ? 2 : 1);
}

const stake = try stakeFor(h, b, false) catch 0;
if (r.ok) { use(r.value); } else { use(r.error); }
```

- `Result.ok(...)` / `Result.err(...)` infer `T`/`E` from the declared return type. In a bare `const r = Result.ok(5)` there is nothing to infer from: annotate `const r: Result<int32, string>`.
- `.value` is only readable after `if (r.ok)`; `.error` after the else. The checker enforces it.
- `try` is an early return; use it inside loops freely. `try … catch fallback` substitutes.
- No `Option<T>`, no `T?`. Nullable is `T | null` with `if (x !== null)`. `??` works on scalars and strings but not on interface types; `?.` does not work. For a typed slot that starts empty, `null as unknown as T`.
- `Result` is a tagged union with no allocation: it links and runs under `--os=solana` (verified).
- There are no `Ok()`/`Err()` free functions and no `throw`-based style.
- No `Result<void, E>`: `Result.ok()` without an argument is a type error. Return what the caller needs next, e.g. `allocate(this t: Tree, …): Result<Tree, AllocError>` hands back the grown tree.
- `try f();` as a bare statement does not parse (the error points at the next `}`); bind it: `const _left = try f();`.
- `Result` values do not compare: `r == w` is a C compile error and always false on JS. Test by narrowing.

Anti-pattern: returning `-1`, returning `boolean` plus an `out` value, `if (!ok) { console.log(...); return; }` chains.

## 3. Loops

```ms
for (const pet of pets) { … }                       // arrays, Vec, Span, BitSet<E>
for (let i = 0; i < n; i++) { … }                    // index needed, or integer range
for (const k of m) { use(k, m.get(k)); }            // Map: keys (toItems protocol, §15)
m.forEach((v: int32, k: string): void => { … });
while (hp > 0 && round < MAX) { … }                  // condition-driven only
```

- No range literal and no std `range()`. A generator `function* range(n)` works on the host but allocates, so it is not for on-chain code. For integer ranges the indexed `for` is the idiom.
- `for..of` over a **string** and over a **fixed array `T[N]`** fail in C codegen; index-loop those. That includes a `T[N]` struct field and one reached through `Ptr<T>`; `.length` on it fails the same way, so loop to the literal size. Over `Map` iterate directly (keys), or `values()`/`forEach`; `for (const [k, v] of m)` compiles and yields garbage. Any type becomes iterable with a `toItems` extension (§15).
- No labeled loops. Restructure or use a flag.
- `int32[]` has no `map`/`filter`/`reduce`/`forEach`/`sort(cmp)`; write the loop. `splice` on `int32[]` crashes at runtime.

Anti-pattern: `let i = 0; while (i < xs.length) { …; i += 1; }`.

## 4. Enums and BitSet

```ms
enum Region { // ordinal, never hand-numbered
	Worker,
	Fighter,
	Survivor,
}

enum Mod {
	Overtime,
	Scavenger,
	ThickHide,
	Pacifist,
	GlassCannon,
	Cannibal,
}

const mods: BitSet<Mod> = Mod.ThickHide | Mod.Pacifist;
if (mods.has(Mod.Pacifist)) { … }
const next = mods.incl(Mod.Cannibal).excl(Mod.ThickHide);
const none = 0 as BitSet<Mod>;                        // empty set, there is no literal
let s = none.incl(Mod.Overtime);                      // single-member set
s = s | Mod.Scavenger;                                // `|=` does not parse
const kept = mods.intersection(next);                 // or mods & next
const lost = mods.difference(next);                   // no operator
if (lost.isSubsetOf(mods) && lost.size() == 1) { … }
for (const m of mods) { … }                           // ThickHide, Pacifist: ordinal order
const text = mods.toString();                         // "{ThickHide, Pacifist}"
```

- `BitSet<E>` replaces `int32` flag fields and `(flags & F) != 0`. Repr follows the member count: `uint8` ≤ 8, `uint16` ≤ 16, `uint32` ≤ 32, `uint64` ≤ 64, then a byte array up to 65536 members (`sizeof` 1, 2, 8, 13 for 6, 15, 40, 100 members).
- The whole surface is methods that return a new set or a value; none mutates. `has`, `incl`, `excl`, `isEmpty`, `size`; `union`, `intersection`, `symmetricDifference` (shorthand `|` `&` `^`, a bare member joins from either side), `difference` (no operator); `isSubsetOf`, `isSupersetOf`, `isDisjointFrom`; `toItems`, `toString`; `hash` on C only (it is what makes a set a `HashMap` key). `==`/`!=` compare two sets of the same enum.
- `for (const m of s)` visits the members in ordinal order on every band. It goes through `toItems`, which allocates, as does `toString`: keep both out of on-chain code.
- An integer mask converts in one cast: `(mask as uint8) as BitSet<Mod>` at the band's width; back with `m as uint32`.
- Text is `s.toString()` (`{ThickHide, Pacifist}`, `{}` when empty), right inside a template, `+` and `+=`. `` `${s}` ``, `"x " + s` and `String(s)` are a C compile error and print the raw word on JS; `console.log(s)` prints `<BitSet>` on C.
- Never `Mod.X as BitSet<Mod>`: it compiles and reads the ordinal as the mask (`Mod.Scavenger` becomes `{Overtime}`). `const s: BitSet<Mod> = Mod.X` is a type error; write `(0 as BitSet<Mod>).incl(Mod.X)`. `& ~Mod.X` and `~s` are type errors: use `.excl` or `.difference`. `s <= t` and `s == Mod.X` are rejected: use `isSubsetOf` and `has`.
- The chain lane was not re-run on 2026-09-15: every `--os=solana` build on the installed runtime, a known-good probe included, stops at `#include <time.h>` in `runtime/manual.h`.
- An enum is an `int32_t` in emitted C and `enum E: uint8 { … }` does not parse. A fixed-width layout (an on-chain account) stores the `uint8` and exposes the enum through a view extension.
- Cast enum ↔ integer explicitly: `r as int32`, `1 as Region`. Arithmetic on a bare enum prints garbage.
- `r.toString()` and `String(r)` give the member name on both backends; `"" + r` and `` `${r}` `` give the name on C but the ordinal on JS, so call `.toString()`. A `toString` extension on an enum is honored only by an explicit `r.toString()` (§15). Other extension functions on enums are called as `label(r)`, not `r.label()`.

## 5. Structs, interfaces, classes

```ms
struct Combatant { might: int32; grit: int32; hearts: int32; mods: BitSet<Mod>; }

function fightHp(this c: Combatant): int32 { return 100 + 4 * c.grit; }   // c.fightHp()
function heal(ref c: Combatant, n: int32): void { c.hearts += n; }        // caller: heal(c, 1)
function plain(this typeof Combatant, might: int32, grit: int32): Combatant {   // Combatant.plain(8, 5)
	return { might: might, grit: grit, hearts: 5, mods: noMods() };
}
function asCombatant(this s: Stats, hearts: int32): Combatant {           // s.asCombatant(5)
	return { might: s.might, grit: s.grit, hearts: hearts, mods: s.mods };
}
const glass: Stats = { ...s, maxHearts: 2, mods: s.mods.incl(Mod.GlassCannon) };
function split(amount: uint64): [uint64, uint64] { return [amount / 20, amount - amount / 20]; }
const [protocol, winner] = split(999);
```

- `struct` is a value: assignment copies, `==` compares structurally, no methods inside the body. Methods are extension functions `function f(this self: T)`, called `v.f()`.
- **Receiver rule.** A function whose first argument is the struct it is about becomes an instance extension: `a.fight(d, seed)`, `d.lootFor(stake, harvest)`, `p.scoreTarget(…)`. Pure arithmetic on scalars (`levelCost(level)`, `splitmix(x)`) and anything whose natural receiver is an `enum` (dot-call unsupported) stay free functions. A bare primitive that carries meaning gets a one-field struct so it can have methods: `struct Tree { bits: uint64; }` with `t.has(id)`, `t.withNode(id)`, `Stats.fromTree(t)`. Private helpers follow the same rule.
- Constructors and other namespace-level functions are **static extensions** `function create(this typeof T, …)`, called `T.create(…)`. Verified on struct receivers across native, JS and `--os=solana`, and through an `export *` barrel. Not on `enum` receivers (`Property does not exist`). Exported static extensions need a name that is unique across receivers in the importing module: two exported `of` on different structs collide (only the first resolves), while the same pair in one file works.
- **No forwarding constructors.** A static extension that only copies its arguments into fields (`Persona.create(7000, 7000, 5000, 3)`) hides the field names; write the literal. Derive a struct from another with spread `{ ...s, might: s.might + 1 }` (C, JS, `--os=solana` build). A static extension earns its place when it computes or defaults something: `Combatant.plain` fills `mods`, `Stats.fromTree` walks the tree.
- Convention protocols (`toItems`, `toString`, `getDynamicField`, `as<Type>`) are extension functions with reserved names; §15 has the measured support matrix.
- A value parameter (`c: Combatant`, or `this c`) is a **read-only view**; writing to it is a compile error. To mutate the caller's struct take `ref`. `readonly` is an explicit local copy. `move` is an expression (`consume(move xs)`), not a parameter modifier.
- Returning a struct by value works on host and links on chain.
- Prefer a tuple return `[a, b]` for two results over `out` parameters; use `out` when the callee fills a large struct in place. A struct literal can be assigned directly to an `out` param or an existing `let`.
- `interface` = reference, refcounted, built from an object literal; `class` = `new`, methods, `implements`. Method **signatures** inside an `interface` do not parse; use a function-typed field.
- `distinct` types (`type Slot = distinct int32`) block implicit conversion both ways; arithmetic on them is a compiler crash today, so `as int32` first.

### Arrays: `Array<T>` (aka `T[]`), `Vec<T>`, `Span<T>` (measured 2026-09-15)

Three kinds, and the choice is about **ownership**, not speed. Speed follows from it.

| | What it is | Assignment | Owns the data |
|---|---|---|---|
| `T[]`, `Array<T>` | a **reference** to a heap array (`createRef(createArray(T))`) | aliases — two names, one array | yes, shared |
| `Vec<T>` | the array **value**; the descriptor lives inline in whatever holds it | **copies** | yes, exactly one owner |
| `Span<T>` | a **view**: pointer + length, no header | aliases the viewed memory | no |

`T[]` and `Array<T>` are the same type; the spelling is cosmetic.

```ms
const col: Vec<Item> = new Array(8);     // owned storage, one owner
const shared: Item[] = [];               // shared handle, aliases on assignment
const all: Span<Item> = col;             // view over the whole thing
const mid = col[2..5];                   // slice: elements 2, 3, 4 — end-exclusive
```

**Pick by ownership:**

- **`Vec<T>` for owned storage** — a field whose data belongs to exactly one structure and is never aliased. Columns of a scene, rows of a table, a buffer a system owns. This is the default for system-programming data.
- **`Array<T>` / `T[]` for shared handles** — two structures point at one array and both may write; you hand it out and keep using it; you need `T[] | null`; identity matters.
- **`Span<T>` for passing and slicing** — never stored as the owner, always a window onto someone else's memory.

**Why `Vec` is the default for owned data.** When the owner is itself a reference (an `interface`), `owner.col[i]` on an `Array<T>` costs two dependent loads — reference, then array header — while a `Vec<T>` descriptor sits inline in the owner, costing one. Measured on a 1M-element sweep through an `interface` field, 35 samples per variant, one process each with a warm-up pass: `Vec<T>` **0.64 ms** median against `Array<T>` **1.70 ms** and `T[]` **1.64 ms** — **2.6×**. A `Vec` field also carries no refcount, so a structure with thirteen `Vec` columns has thirteen fewer refcounted objects than the `Array` version.

**Hoisting buys nothing.** `const c = someArray;` before a loop measures the same as indexing through the owner (1.64 → 1.59 ms, inside the noise). Hoist for readability, never for speed.

**The copy trap.** Binding a `Vec` to a plain local copies it, and writes through the copy are silently discarded:

```ms
const hoisted = col;      // Vec: a COPY
hoisted[0] = 99;
console.log(col[0]);      // 10 — the write went nowhere

const view: Span<int32> = col;
view[0] = 77;
console.log(col[0]);      // 77 — a view writes through
```

The same line on an `Array<T>` writes through, because it aliases. Carrying the JS habit of "assign the array to a shorter name" into `Vec` code loses data with no diagnostic.

**Passing a `Vec` to a function.** A `Vec<T>` parameter is a copy, so the checker rejects writing to it (`cannot mutate value-type parameter`) — that error is a feature here, telling you the write would have gone nowhere. `Span<T>` is the parameter form that both compiles and writes through:

```ms
function propagate(local: Span<Transform>, world: Span<Transform>, n: int32): void { … }
propagate(scene.local, scene.world, n);          // Vec → Span coerces implicitly
```

**What a `Span` can do.** `.length`, indexing for read and write, `for..of`, slicing a slice, being returned from a function, and being a struct field — all measured, all writing through to the original:

```ms
struct Window { view: Span<Item>; base: int32; }

function windowOf(col: Span<Item>, from: int32, count: int32): Window {
	return { view: col[from..from + count], base: from };
}
```

`Vec<T>`, `Array<T>`, `T[N]` and `string` all coerce implicitly to `Span<T>` (`Span<char>` for a string). Use a `Span` window instead of passing `(array, offset, count)` and doing the index arithmetic by hand — the bounds travel with the view.

A `Span<char>` over a string is a view of **bytes**: `"héllo"` gives 6, matching `.byteLength`, not the 5 you would count on screen. Native gained that only at recompiler `ba16897a`; JS still lowers the coercion to the string object itself, so it answers 5, reads every element as `0`, and refuses `s[a..b]` outright. Until that lands, a `Span<char>` over a string is native-only — keep it out of anything that has to agree across the two backends, `sim/determinism.ms` above all.

All three allocate, so none of this belongs in on-chain code (§11).

### Pointers and views: `Borrow<T>` and its neighbours (measured 2026-09-15)

Seven kinds give access to memory that someone else owns. Pick by what the receiver may do with it and how long it may hold it.

| Kind | What it is | Emitted C | Writes | May outlive the call |
|---|---|---|---|---|
| value parameter `v: T` | read-only view of the caller's value | `const T*` when `T` is over 24 bytes, a copy otherwise | compile error | no |
| `ref v: T`, `out v: T` | the caller's location | `T*` | reach the caller | no |
| `Span<T>` | pointer + length over an array | a struct; an `extern` parameter becomes `(T*, int64_t)` | reach the array | as a field, by contract only |
| `Borrow<T>` | read-only pointer that owns nothing | `const T*` | compile error | no (design below) |
| `Ptr<T>` | raw, untraced pointer | `T*` | yes | yes; you own the lifetime |
| `Readonly<T>` | deep read-only view of a reference or array | not measured | compile error | yes (§12) |
| `Cursor<T>` | non-owning link to a `class`/`interface` value; accepts `null` | not measured | not measured | yes; nothing tracks it |

What to use, today:

- **Read a struct:** a value parameter. Structs over 24 bytes already go by pointer (`readBig(const Big* big)`); a `Borrow<T>` parameter emits identical C and adds nothing.
- **Change the caller's struct:** `ref`. A generic `ref box: Box<T>` does not bind `T` on `b707175d` (`cannot instantiate: 'T'`, even as `put<int32>(box, 5)`); a compiler fix is pending.
- **Hand array data to C for one call:** an `extern` parameter `data: Borrow<T>` called with `arr[0]`. C receives `&arr[0]` as `const T*`, from a `let` or a `const` array alike. `import { f } from "x.h"` maps a `const` pointer to a scalar (`const float*`) to `Borrow<float32>` for you; a pointer to a struct maps to `Ptr<S>`. The C side may read or copy during the call and must not keep the pointer. When the C side takes `(const T*, int64_t count)`, an `extern` `Span<T>` parameter works too.
- **Overlay a struct on raw memory** (account data, a mapped buffer): `address as Ptr<T>`; writes land in place. `Ptr<T>` does not accept `arr[0]`, and there is no address-of operator.
- **Read big structs in a hot loop:** index and read the field. `bigs[i].a` emits `msArrayAccess(…).a` with no struct copy; `for (const big of bigs)` copies every element (next table).
- **Share with a spawned task:** `Readonly<T>` (§12).

Copies that `Borrow<T>` is meant to remove (emitted C, debug and `--danger`):

| Code | Emitted C |
|---|---|
| `for (const big of bigs)` | `big = msArrayAccess(bigs, i)` into a `Big` local, every iteration |
| `const first = bigs[0]` | a struct copy |
| `map.get(k)` with a struct value | a copy into `Maybe_Big` |

Do not write (measured on `b707175d`):

- `const item: Borrow<Big> = arr[0]` (the `LANG.md` example): C compile error; JS makes a copy. Nothing checks its lifetime.
- a `Borrow<Big>` return type: C compile error.
- `extern function f(ref data: float32, …)` called with `arr[0]`: C compile error; the call passes the address of a temporary copy.
- `let cur: Ptr<Tok> = arena[0]` (`LANG.md`): C compile error.
- `items[0]` on a `ref items: Array<int32>` parameter: C compile error. `items.push(x)` through it works.

#### `Borrow<T>` design (target, not implemented)

`Borrow<T>` is a read-only pointer that owns nothing. The language proves its lifetime by where it may appear, never by annotations. It is legal in exactly three places.

1. **Return type, borrowing from the first parameter.**

   ```ms
   function fighterAt(this account: Account, index: int32): Borrow<Fighter> {
   	return account.fighters[index];
   }
   const power = account.fighterAt(2).power;      // const Fighter*, no copy
   ```

   The returned expression must be a path (field, index, dereference) rooted in the first parameter, which is then passed by pointer. Returning a local, a temporary or another parameter is a compile error.

2. **`for..of` bindings over value elements, inferred.**

   ```ms
   for (const fighter of account.fighters) { total += fighter.power; }   // const Fighter* per iteration
   ```

   No new syntax. The binding is already read-only, so only the emitted C changes; JS is unchanged.

3. **`extern` parameters, address taken at the call.**

   ```ms
   extern function uploadVertices(data: Borrow<float32>, byteCount: int32): uint32;
   uploadVertices(vertices[0], (vertices.length as int32) * 4);
   ```

   The pointer is valid for the call only. This is the language's form of an address-of operator for C interop.

Rejected with a diagnostic once the design lands:

- a `Borrow<T>` parameter on a non-`extern` function: use a value parameter;
- `Borrow<T>` locals, fields, array elements and globals: nothing checks that the source outlives them. Revisit with escape analysis.

A borrowing `Map.get` and a mutable borrow are not part of this design.

## 6. Numbers

| Use | Type |
|---|---|
| index, length, count, id, level, stat, percentage, bps | `int32` |
| lamports, token base units, epochs, timestamps, hashes, seeds | `uint64` |
| signed money math (EV, deltas) | `int64` |
| genuinely fractional | `float64` |
| never | `number` |

- Integer `/` truncates; `%` follows C (negative results for negative dividends). Bind operands to typed variables: a literal-only `7 / 2` is `3` on C and `3.5` on JS.
- `int32 + uint64` widens silently to `uint64`; a negative `int32` becomes a huge unsigned. Cast on purpose: `u + (n as uint64)`.
- `uint64` wraps. `int32` overflow **panics in debug** and wraps in `--release`/`--danger`. `int64 → int32` conversion is range-checked at runtime. An unannotated literal that does not fit `int32` is silently wrapped; annotate it.
- `>>>` is not implemented; `<<`/`>>` on `uint64` are fine.
- Float → int is an explicit `as int32` (truncates); implicit narrowing is an error.
- `enum as uint64` is not lowered on the JS backend (the value stays a Number and the next BigInt op throws). Widen through `int32` first: `(k as int32) as uint64`.

## 7. Strings and chars

- Strings are values with copy-on-write; `s += x` is the string builder. `slice`/`substring` need **both** arguments.
- `"a".code` is the compile-time code of a single-character literal (multi-char silently gives the first). `'A'` is a one-character `string`, not a `char`.
- `String(x)` for any integer width; template literals work. Never `String(v)` on a type that defines `toString` (C compile error); use `v.toString()` (§15).
- Strings and `String(uint64)` allocate: keep them out of on-chain code and hot paths.

## 8. Compile-time and conditional code

```ms
const TABLE_SIZE = @comptime { return 4 * 1024; };
@comptime function sq(n: int32): int32 { return n * n; }

when (solana) { … } else when (js) { … } else { … }
```

- `when (flag)` gates whole declarations. Flags: `c`, `js`, os names (`macos`, `solana`, `bare`, …), `debug`, `testBuild`, and `-d:name` from the command line. Under `--os=solana` gate on `solana`, not `manual`.
- `@emit("...")` injects raw backend text; `macro`/`quote` for AST macros, invoked as bare calls.
- `build.ms` `alias`, `searchPaths`, `define` are not wired; use relative imports and `-d:` flags.

## 9. Modules and entry points

- Named exports only. `export * from "./x"` barrels in `index.ms`. No `export default` (its import form does not parse). No non-exported symbol is visible outside its file.
- Relative paths only. Backend-specific files: `x.cms` wins on C, `x.jms` on JS, `x.ms` fallback.
- Nothing calls `main()`. Host tools end with `process.exit(main());`. A file that is both a CLI and a test target ends with `when (!testBuild) { process.exit(main()); }`. Chain builds end with bare `main();`.
- Circular imports work with a warning; avoid them anyway.

## 10. Tests

```ms
test "loot caps at k times stake" {
	const d: Combatant = { might: 5, grit: 10, hearts: 5, mods: Mod.Overtime | Mod.Overtime };
	assert lootFor(100, 1000000, d, 0) == 135;
}
```

- Tests sit in the same file as the code, top level, with the `assert` keyword (`expect` does not exist). `assert` outside a test block is an error. Tests inside a function are silently dropped.
- Setup helpers are ordinary module functions.
- `msc test file.ms` runs the file's import graph, std included (about 2 s of prelude tests). Test bodies are type-checked in every build even though they are stripped from the binary.
- A `Result` is tested by narrowing: `assert r.ok; if (r.ok) { assert r.value == 2; }`.

## 11. Host vs freestanding vs on-chain

| | host (`msc run`) | `--gc=manual` / `--os=bare` | `--os=solana` |
|---|---|---|---|
| `struct`, `enum`, `BitSet`, sized ints, `Result`, `match`, `defer`, `out`/`ref`, tuple return, local `const` | yes | yes | yes (linked and run) |
| `async`/`await`/`spawn`/actors | yes | compile error E01 | compile error E01 |
| `T[]`, `Vec`, `Map`, `Set`, generators, `interface`/`class`, string building | yes | arena | **link error** (`_ms_arena`) |
| module-scope `let`, non-scalar `const`, any `const` in a module other than the entry file (even if only used in that file) | yes | yes | **link error** (discarded section) |
| scalar `const` in the entry file | yes | yes | folds, links |
| `String(uint64)`, `process.exit()` | yes | yes | links, aborts at run time |

Rule for a module that must run on chain: scalars in, scalars out, structs by value or `out`, no module-scope state, nothing that allocates. Module `const`s in library files are the host idiom and currently wait on a compiler fix for the chain lane (recompiler R12); do not contort library code around it.

## 12. Concurrency

```ms
async function fetchPet(id: int32): Promise<Result<Pet, RpcError>> { … }   // I/O
const pet = try await fetchPet(7);                                          // unwrap both layers
const [a, b] = await Promise.all([fetchPet(1), fetchPet(2)]);               // concurrent I/O
await main();                                                               // async entry

const hs: Promise<int32>[] = [];
for (let i = 0; i < 4; i++) { const k = i; hs.push(spawn(() => monteCarlo(k))); }   // CPU, real threads
const results = await Promise.all(hs);                                      // join once, after the loop
spawn(() => consume(buf), { move: [buf] });                                 // hand ownership over
await spawn(() => slow(), { timeout: 30 });                                 // deadline

actor Ledger {
	private balances: Map<string, uint64> = new Map<string, uint64>();
	credit(who: string, n: uint64): void { … }        // void method = SEND, returns at once
	balance(who: string): uint64 { … }                // typed method = CALL, `await l.balance(x)`
}
const l = new Ledger();
l.credit("a", 5);
const b = await l.balance("a");

const cfg: Arc<Config> = new Arc({ epochs: 120 });                          // immutable share
const hits: Locked<Counter> = new Locked({ n: 0 });                          // the only shared-mutable form
lockedUpdate(hits, (v: Counter): Counter => { return { n: v.n + 1 }; });    // short, pure, no await inside
```

Rules the checker enforces (all verified as compile errors):

- A `spawn` handle is affine and scope-bound: await it exactly once, in the scope that created it. Never return it, never drop it.
- A spawn thunk borrows what it captures as `Readonly<T>`: no writes, no `push`/`set`, no capturing a `let`. To mutate, `{ move: [x] }` (sole owner) or `Locked<T>`.
- Actor fields are private to the actor. A SEND may carry values, `move x`, or `Arc<T>`; a plain reference into a SEND is refused. An awaited CALL may borrow a reference.
- Actor methods are async by nature: writing `async` on one is an error. `await` inside them suspends the actor.
- Inside a spawn thunk you cannot call methods of `this` (the actor is suspended) and, today, cannot SEND to a captured actor either.
- `Arc<T>` pointee must be deep-immutable data; `Locked<T>` payload must be plain data (no string, array, reference). Writes through `Arc` are refused.
- `throw` inside a `Promise<Result<T, E>>` function is refused; return `Result.err`.

What you must know that the checker does not catch:

- `await` inside a loop body on a `spawn` is only a lint (E40): collect handles, then `Promise.all`.
- Never `await`, block, or do I/O inside a `lockedUpdate` callback.
- A never-awaited rejecting promise exits the process with status 1 at drain. `process.exit()` skips the drain.
- An uncaught `throw` inside a spawned task is **silent** today (exit 0), and a caught one arrives as `null`. Return `Result` from spawned tasks; do not throw.
- Cancellation is cooperative and only on timeout-fused spawns, at loop back-edges.
- A struct passed to an actor method is **moved out** on C (the caller's copy is zeroed) and copied on JS. Pass a fresh literal or a copy.
- Do not use: `new Promise(executor)` (compiler crash), `Promise.allSettled`/`Promise.any` (crash on C), `monitor`/`link` (hang, `onDown` fires twice), `std/actor/supervisor` (does not type-check). `.then` works but is not the idiom.
- JS backend: `async`/`await`, `Promise.all`, `spawn` values and actors all run, but `spawn` is serial, SEND is synchronous, `{ move }`/`{ timeout }` do not build, `Arc`/`Locked` do not exist. Concurrency semantics are C-only; treat the JS lane as a functional check.
- Freestanding: `async`/`spawn` are compile error E01; `actor` fails at C compile; `Arc`/`Locked` are accepted as no-op stubs. Nothing concurrent belongs in an on-chain module.

## 13. Where the docs and the compiler disagree (measured 2026-09-12)

| Doc says | Compiler does |
|---|---|
| `expect` is the test keyword | `assert` |
| bare identifier in a match arm binds the value | `Undefined variable` |
| struct/tuple/range patterns in `match` | parse error |
| `Ok(x)` / `Err(e)` | only `Result.ok` / `Result.err` |
| `try`/`for`/`break` in match arms fail | all work |
| no `indexOf`/`includes` on strings | both work |
| mutating a struct value param propagates | read-only view; use `ref` |
| `move v: T` parameter modifier | parse error; `move` is an expression |
| `'A'` is a `char` | it is a 1-char `string`; `char` has no `.code` |
| `for (const [k, v] of map)` | compiles, wrong output |
| `T[N]` `.length` / `for..of` | C compile error |
| `Span` slicing `a[1..3]` | C only; JS emits invalid code |
| `@comptime function` planned | works |
| `import from "./x.h"` NOT YET | works and auto-compiles `x.c` |
| `@include` auto-compiles the `.c` | it does not |
| `console.error`, `len`, `panic` in prelude | absent |
| `msc fmt --check` in CI | output is not idempotent (adds a blank line each pass) |
| `--help-defines --os=solana` shows `gc=orc` | gc is manual; gate on `solana` |
| `new Promise((resolve, reject) => …)` shipped | compiler crash `index -1 out of bounds` |
| unguarded `await` inside `Promise<Result>` is an error (V2) | not enforced |
| `async analyze(): Promise<T>` on an actor | rejected: actor methods are inherently async |
| value-type actor args are copied | struct is moved out on C, copied on JS |
| `monitor`/`link` + `stop` | hang; `onDown` fires twice |
| `Supervisor` from `std/actor/supervisor` | the std module fails its own type check |
| a spawned task's exception propagates to `await` | uncaught: silent exit 0; caught: `null` |
| SEND to an actor from inside a spawn thunk is fine (E64/E70) | refused as a write through `Readonly<T>` |
| `enum as uint64` behaves like C on JS | JS emits no BigInt conversion; `TypeError: Cannot mix BigInt` |
| struct literal as a `match` arm value | parsed as a block unless parenthesized: `=> ({ … })` works |
| `toString(this p: Struct)` overrides `String(p)` | C: `no member named 'toString'`; JS: `[object Object]` (a class *method* `toString` is honored on JS) |
| `"s" + struct` is an error; call `.toString()` | concat, template and `+=` insert the custom `toString` on C and JS; without one, C prints JSON and JS `[object Object]` |
| custom `toString` is used by `console.log` | C: yes; JS: ignored, prints the object |
| enum `+`/template gives the variant name | C: name; JS: ordinal |
| `const n: int32 = jsonValue` coerces via `asInt32` | type error; `const s: string = jsonValue` compiles, then C compile error / JS yields the object |
| a value that is not assignable to the target is a type error | not for `string` targets: struct, interface and `int32` into `string` pass the checker, then C compile error / JS raw value |
| `as<Type>` fires at variable initializers | primitive targets yes; struct targets (`asColor`) only at arguments and returns |
| `v as T` goes through `asT` | C compile error; JS keeps the raw value |
| `cborValueToStruct` decodes a struct | every field comes back zero/empty, no error, C and JS |
| typed JSON decode of an enum field | C correct; JS yields a BigInt: `==` false, `match` falls to `_` |
| `uint64` JSON field | values ≥ 2^63 encode as negative numbers |
| field decorators `@rename("_id")` (SERIALIZE.md §1) | parse error |
| `this typeof Enum` static extension | `Property does not exist on type` |
| `BitSet` `for..of` fails, `console.log(s)` prints `<BitSet>` (LANG-PRIMITIVE, 2026-09-12) | `for..of` works in ordinal order; `console.log(s)` is still `<BitSet>` on C (measured 2026-09-15) |
| a `BitSet` in `${s}` / `"x" + s` prints the set | C compile error; JS prints the raw word. Only `s.toString()` works |
| `const item: Borrow<T> = arr[0]` is a zero-copy pointer whose lifetime the analyzer checks (LANG.md) | C compile error, JS copy; no check exists (measured 2026-09-15) |
| value `for..of` bindings are passed by pointer (LANG.md) | one struct copy per iteration, debug and `--danger` |
| `let cur: Ptr<Tok> = arena[0]` (LANG.md) | C compile error |

## 14. Review checklist

- [ ] An `if/else if` chain that compares one value against enum members or literals is a `match`; a `match` whose every arm is `_ when …` is an `if` chain or a named helper.
- [ ] No `-1`/`false`/`out ok` failure signalling: `Result<T, E>` with an `enum` error.
- [ ] No `while` that is really a counted loop: `for`.
- [ ] No `int32` mask field: `BitSet<E>`. No `E.X as BitSet<E>`: `(0 as BitSet<E>).incl(E.X)`. No `${set}` or `String(set)`: `set.toString()`.
- [ ] No `number`. No unannotated literal wider than `int32`. `as` at every signed/unsigned meeting.
- [ ] No `class` for plain data: `struct`, extension functions, `this typeof T` constructors.
- [ ] Owned array data is `Vec<T>`, shared handles are `T[]`, parameters and slices are `Span<T>`. No `const local = someVec` (it copies and drops the writes); no `(array, offset, count)` triples where a `Span` window says it once.
- [ ] No constructor that only forwards its arguments: struct literal, or spread from an existing value.
- [ ] No abbreviated names that make the reader ask (`pwinBps`, `harvestD`, `attackEv`): spell them out unless the full name is unreasonably long.
- [ ] No line over 100 columns: one field, parameter or import per line with a trailing comma (§16).
- [ ] Predicates that gate an action return `Result<T, E>` with an `enum` error and the value the action produces, not `boolean`.
- [ ] Every function whose first argument is a struct is an extension on it; meaningful primitives are wrapped in a one-field struct.
- [ ] No compound bitwise assignment (`|=` `&=` `^=` `<<=` `>>=`): they do not parse.
- [ ] Tests in the same file, `assert`, helpers as functions.
- [ ] On-chain modules: nothing from row 3 or 4 of the §11 table.
- [ ] Every `spawn` handle awaited once via `Promise.all` after the loop; no `let` captured; mutation only through `{ move }` or `Locked<T>`.
- [ ] Spawned tasks return `Result`, never throw. No `await` inside `lockedUpdate`.
- [ ] Actor methods without `async`; SEND for fire-and-forget, CALL when a reply is needed; references into a SEND are `move`d or `Arc`.
- [ ] No `String(v)` on a type with a custom `toString`; enum text via `.toString()`.
- [ ] JSON: `JSON.parse<T>` result narrowed with `if (r.ok)`; no enum fields decoded on the JS lane; `JsonValue` read through explicit `asX()` accessors.
- [ ] No `cborValueToStruct`; decode CBOR with accessors.
- [ ] `as<Type>` only at declarations, assignments, arguments and returns; explicit `.asString()` for `string` targets and explicit `asT()` for struct targets in declarations; never `v as T`.
- [ ] Structs are read through value parameters, never `Borrow<T>` parameters. `Borrow<T>` appears only on `extern` parameters that take `arr[0]`; no `Borrow<T>` locals or return types until its design lands.
- [ ] Hot loops over structs larger than 24 bytes (on-chain compute) read `xs[i].field` by index instead of `for (const x of xs)`, until `for..of` borrows.

## 15. Protocols and serialization

A protocol is an extension function with a reserved name that the checker calls for you at a fixed syntax site. A type opts in by declaring the extension; a type without it stays strict. All of this allocates (arrays, strings, trees), so none of it belongs in on-chain code (§11).

### toItems: iteration

```ms
function toItems(this r: Span3): int32[] {
	const out: int32[] = [];
	for (let i = r.lo; i < r.hi; i++) { out.push(i); }
	return out;
}

for (const x of r) { … }              // rewritten to r.toItems()
for (const k of scores) { … }         // Map<K, V>: keys
for (const v of scores.values()) { … }
for (const name of names) { … }       // Set<T>: members
```

- Works on `struct`, `interface` and `class` receivers, returning scalar or struct arrays, with identical output on C and JS.

### toString: stringification

```ms
function toString(this p: Point): string { return `(${p.x},${p.y})`; }

const a = "at " + p;          // the checker inserts p.toString()
const b = `at ${p}`;
line += p;
const c = p.toString();
```

Measured per call site (struct, interface, class method and class extension behave alike unless noted):

| Site | Type with `toString` | Type without `toString` | Enum with a `toString` extension | Enum without |
|---|---|---|---|---|
| `"" + v`, `` `${v}` ``, `+=` | custom, C and JS | C: JSON `{"x":3}`; JS: `[object Object]` | C: compile error; JS: ordinal | C: name; JS: ordinal |
| `v.toString()` | custom | JSON, both | custom | name, both |
| `String(v)` | C: compile error; JS: `[object Object]` (class method: custom) | JSON, both | C: compile error; JS: ordinal | name, both |
| `console.log(v)` | C: custom; JS: object dump | debug dump | C: name; JS: ordinal | C: name; JS: ordinal |

- The one site that is right everywhere is an explicit `v.toString()`. Use it for enums, for `String`-like conversions, and for anything logged.
- Implicit insertion in `+`, template literals and `+=` is safe for struct, interface and class receivers that define `toString`.
- Never `String(v)` on a type with a custom `toString`.

### `as<Type>`: implicit coercion

```ms
interface Cell { raw: string; }
export function asInt32(this c: Cell): int32 { return parseCell(c.raw); }
export function asInt64(this c: Cell): int64 { … }
export function asString(this c: Cell): string { return c.raw; }
export function asMoney(this c: Cell): Money { … }

const id: int32 = cell;          // cell.asInt32()
const big: int64 = cell;         // cell.asInt64(): the return type must match the target exactly
charge(cell);                    // charge(m: Money) → cell.asMoney()
```

The name is `as` + the target type in PascalCase: `asInt32`, `asInt64`, `asUint64`, `asFloat64`, `asNumber`, `asBoolean`, `asString`, and `asColor` for a user type `Color` (all measured; `LANG.md` extends the pattern to every sized integer and `asFloat32`).

| Site | Primitive target | Struct target (`asColor`) |
|---|---|---|
| `const x: T = v`, `x = v` | yes | **no**: `Type 'Cell' is not assignable to type 'Color'` |
| function argument | yes | yes |
| `return v` | yes | yes |
| ternary branch, array literal element, struct literal field | yes | not measured |
| `v as T` | **no**: C compile error, JS keeps the raw object | not measured |
| `1 + v`, `v == 32` | no (operator error) | — |
| `if (v)` | no (object truthiness) | — |

- Measured identical on C and JS for every "yes" cell, for `int32`, `int64`, `uint64`, `float64`, `number`, `boolean` and `string` targets, and with `asInt32` and `asInt64` side by side (each target picks its own).
- A missing converter is a type error (`const f: float32 = cell` without `asFloat32`) for every target except `string` (next bullet).
- **`string` targets are unchecked.** A struct, interface or `int32` assigned to a `string` passes `msc check` with no `asString` in scope, then fails at C compile or keeps the raw value on JS. An enum is rejected; other source kinds were not measured. So a missing or misspelled `asString` is not caught: call `.asString()` / `.toString()` explicitly when the target is `string`.
- One step only: with `Cell.asMid()` and `Mid.asString()`, `const s: string = cell` does not chain (and, per the bullet above, is not reported either).
- Call the converter explicitly for struct targets in declarations, and never write `v as T` for a protocol conversion.

### `getDynamicField`: dynamic member access

```ms
export function getDynamicField(this r: Row, key: string): Cell { … }

const email: string = row.email;   // row.getDynamicField("email").asString()
const n: int32 = row.count;        // row.getDynamicField("count").asInt32()
const id = row.id;                 // a real field wins
```

- Fires for a member name that is not a real field, on C and JS; measured at declarations, where the result flows into `as<Type>`.
- `JsonValue` is the outlier: `const age: int32 = j.age` is a type error and `const s: string = j.name` hits the unchecked `string` hole. Read it through explicit accessors: `j.user.age.asInt32()`, `j.n.asNumber()`, `j.name.asString()`, `j.tags.at(0)`, `j.tags.length()`. `asString()` on a missing key returns an empty string, not an error.

### JSON

```ms
const text = JSON.stringify(pet);                 // prelude; T inferred
const r = JSON.parse<Pet>(text);                  // Result<Pet, string>
if (!r.ok) { return Result.err(LoadError.BadJson); }
const pet2 = r.value;

const v = JSON.parseValue(body);                  // Result<JsonValue, string>, schema unknown
if (v.ok) { const age = v.value.user.age.asInt32(); }
```

| Field or shape | C | JS |
|---|---|---|
| `int32`, `float64`, `boolean`, `string` (quotes, unicode), nested struct, `int32[]`, `Struct[]` | round-trip | round-trip |
| `int64`, `uint64` below 2^63 | round-trip | round-trip |
| `uint64` at or above 2^63 | encodes as a negative number | same |
| enum | encodes the ordinal, decodes correctly | decodes to a BigInt: `==` and `match` silently wrong |
| `T \| null` field | encode: compile error (read as a tagged union); decode: absent key → `null` | same |
| `class` value | encodes its fields | same |
| top-level array `JSON.parse<T[]>` | compile error: target must be a struct or interface | same |
| field decorators (`@rename`, `@skip`, `@default`) | parse error | same |

- Decode is strict: the error string names every bad or missing field (`field 'x': expected int, got string; field 'y': expected int, got null`). Unknown keys are ignored. A non-object top level and syntax errors are reported (`Unexpected end of input at position 5`).
- Field attributes do not parse, and `std/serialize/json` documents no per-type encode hook (not probed further): treat the struct shape as the wire shape and map to a dedicated wire struct when names or types must differ.
- Cross-lane data with enum fields: store the enum as `int32` in the wire struct and convert with `as`.

### CBOR

```ms
import { cborEncode, decode, getDynamicField, asString, asInt32, asBoolean, cborArrayOfInt32 } from "std/serialize/cbor";

const bytes = cborEncode(pet);                    // Buffer
const r = decode(bytes);                          // Result<CborValue, string>
if (r.ok) { const level = r.value.getDynamicField("level").asInt32(); }
```

- `cborEncode` compiles and emits bytes for structs with string, integer, boolean, enum, nested-struct and array fields on C and JS. An array field needs its element builder imported by the caller (`cborArrayOfInt32` for `int32[]`); without it: `Undefined variable 'cborArrayOfInt32'`.
- `decode` plus accessors round-trips `string`, `int32` and `boolean` fields on both backends (identical bytes on C and JS). Other field kinds through accessors were not measured.
- `cborValueToStruct(value, null as T | null)` compiles and returns a struct whose fields are all zero or empty, on both backends. Do not use it; read fields with accessors.

## 16. Formatting

Tabs, and no line wider than 100 columns (a tab counts as 4). When a construct does not fit, break it one element per line with a trailing comma:

```ms
import {
	Combatant,
	Stats,
} from "../rules/index";

export function lootFor(
	this d: Combatant,
	stake: uint64,
	harvestD: uint64,
	fightsInTodayD: int32,
): uint64 {
	return match (kind) {
		PersonaKind.Cautious => ({
			minWinChanceBps: 7000,
			reserveBps: 7000,
		}),
		_ => base,
	};
}

const bits = bit(regionNode(r, 2)) |
	bit(regionNode(r, 3));
const t = Tree.empty()
	.withNode(1)
	.withNode(9);
```

- Every form above parses and runs identically on C and JS: multi-line import braces, parameter lists and struct literals with trailing commas, a binary operator at the end of the line, a `.method()` chain with the dot leading the next line.
- Enums put one member per line with a trailing comma, however short, as `Region` and `Mod` in §4; measured identical ordinals, `match` and `BitSet` on C and JS.
- Break a long expression after its operator, not before: a line that starts with `^` or `|` was not measured.
- `msc fmt` is not idempotent (§13); format by hand.
