# UI KIT — Hibernal

> Reusable art inventory, not an app navigation plan. Keep the Pet scene, diary and actions together on one outer Home surface; interactions stay inline or in anchored overlays, not Settings or other app pages. Legacy usage names below describe kit contexts, not separate screens. The current composition is `homeFrame` in `native/hud/home.ms`.
>
> Prompt for generating the art with an image model: `UI-KIT-PROMPT.md`.
>
> **Out of scope:** claim/onboarding, the full death and inheritance screen, fight replay, widget, notification, live wallpaper.

---

## 0. Style constraints

| Item | Value |
|---|---|
| Platform | Android, Solana Seeker, portrait |
| Frame | 360 × 800 logical px, rendered at 3× (1080 × 2400) |
| Safe areas | top 24 px, bottom 16 px |
| Grid | 8 px, side margin 16 px |
| Touch targets | ≥ 48 × 48 (exception: skill-tree nodes) |
| Font | Silkscreen, only at 8 px and 16 px so it stays crisp. In-game text is English. |
| Panels | "Tro tàn" / charred wood: burnt-paper or plank panels, thick (≈ 4 px) ash/charred rim with ember spots. **Panel interiors stay calm and readable**; no busy texture behind text. |
| Frames | Three weights. **Heavy** (full charred-wood frame with ember spots): status card, Feed / Talk, SignButtons, sheets, modals, dock. **Badge** (the reference's own 40 × 40 charred badge frames, `badgeFrame` in `kitbashFrame.py`; thinner rim, few embers): gear and other icon-button boxes, the 40 × 40 Badges (user, 2026-10-02). **Light** (thin 1–2 px charred rim, no ember spots, no glow): sync chip, tooltip. **None**: toast (dark semi-transparent strip, light text), Chips, Bars, HeartPips, Balances, list rows, section headers (they sit inside panels; no frame inside a frame). The campfire must stay the strongest fire on screen. |
| Hearts | full heart = chunky outlined heart with highlight; lost heart = grey **cracked** heart (not an empty outline) |
| Buttons | hybrid. **Framed** (small charred-wood frame, a mini version of the panel, ember underline kept as accent): Feed / Talk on Home, every SignButton, the confirm button in modals. **Frameless** (text + glowing ember underline): text links, icon buttons, secondary buttons inside panels or sheets (e.g. Cancel). The ember underline glows evenly along its length, with no bright dot or spark at the end. Reason: no hover on mobile, so shape must show what is tappable, and Feed / Talk float over the scene with no panel behind them. |
| Mood | fragile, fear of loss. The HUD floats over the scene and does **not** change with the pet's state. |
| Layering | the scene fills the screen; the HUD is small floating panels, never edge-to-edge bars on Home. Keep the middle band (y ≈ 200–560) clear. |

---

## 0b. How heavy frames are made (decided 2026-10-02)

- The HUD layer renders at **device resolution** (3 device px per logical px), not at the 1x logical grid of the scene. The scene keeps its 360 x 800 pixel look; the HUD keeps the detail of the style reference.
- Heavy frames are **not 9-slice textures**. Each one starts from a **whole frame of the reference** (`styleReference.png`: Status Card, Info Panel or Popup Menu, the text-free ones with the thickest rims) and is resized by cutting out or repeating plank spans at the darkest rim joints, then its interior is repainted as dark planks (`spliceFrame` in `kitbashFrame.py`). A **seed per panel** picks the base and the splice points, so panels differ but stay stable between frames, and any size works. Build once, cache the texture, rebuild only on resize. (The earlier parts-library mode, `frame()`, gave thinner, holed rims and is kept only for reference.)
- Ember spots sit on the rim line only, over wood, never on the interior or outside the frame.
- Prototype and reference implementation: `art/ui-kit/tools/kitbashFrame.py`; Home preview: `art/ui-kit/tools/renderHomeHd.py` → `assets/ui/preview/homeHd.png`. Light frames, icons, chips and bars still come from `assets/ui/hud.png`.
- The level-plate fit generated 179 × 280 px; an exact-footprint supplied-sheet crop
  generated 207 × 280 px and was inspected on Seeker. The person rejected that result:
  it still did not match the original assembled junction. Exact resizing alone is not
  a design-match gate. If revisited, compare the contiguous original level frame,
  three lights and XP-bar join rather than stretching isolated pieces to guess the overlap.

## 0c. Press colour and feedback (decided 2026-10-10)

- **Orange marks a press that changes the Pet on chain**: an empty owner shop slot (5, 6) and CLAIM. Every other press stays blue: `< NAME >`, the toggles, the log arrow, neighbour visits. A player reads orange as "this costs a signature". The orange pieces are hue turns of the blue ones, made by `ORANGE` / `orangePieces` in `art/hud/cutHud.py`; a new on-chain press adds its piece there instead of a hand-painted copy.
- **A held press fades** instead of swapping art, like React Native's TouchableOpacity: `pressedLook` / `plainLook` in `native/hud/kit.ms`. A press that should look tappable calls them around its own drawing.
- **The HP bar over the Pet's head sits on the scene's texel grid**, not the HUD's, so it reads as part of the pixel scene while HUD text stays sharp (`HUD_PIXEL` is 0). `projectPetHead` in `native/scene/campfireScene.ms` passes the texel size; `PET_HEAD_TOP` was measured at level 7 only.

## A. Shared components

| # | Component | Variants / states | Used in |
|---|---|---|---|
| 1 | **Button** | framed primary (mini 9-slice charred-wood frame + ember underline), frameless secondary (text + ember underline), text link with `›`, destructive, icon button (gear, back, copy, `‹ ›`, Recenter). States: normal / pressed / disabled | everywhere |
| 2 | **SignButton** (extends framed Button) | idle (wallet glyph + label) / waiting (spinner, `Wallet…`) / confirmed (`✓ Done`, ~2 s) / failed (`! Retry`) / disabled | Feed, Shop, persona change, session key |
| 3 | **Panel** (9-slice) | card, alert card (heavy rim + tint), dashed card (empty / locked / dead) | status card, Digest day summary, Shop cards, talent, item tiles, Block cells |
| 4 | **Sheet** | half height (≈ 420 px), full height, content height; drag handle; dimmed scene behind | Feed, Talk, stat breakdown, item, tree node, purchase confirm |
| 5 | **Modal** | dialog (title, text, 2 buttons: frameless Cancel + framed confirm) / full screen | disconnect confirm, talent reveal |
| 6 | **Banner** | "Confirm in your wallet" + what is being signed | any wallet wait |
| 7 | **Toast** | normal / error. One line, one at a time, queued, never stacked | app-wide |
| 8 | **Tooltip** | one line, beside its anchor | badges, explanations |
| 9 | **Reason pill** | normal / alert | under the status card, Digest bad-night card, disabled Feed |
| 10 | **Chip** | outline / filled / dashed, plus rarity colours (Common, Rare, Epic, Legendary, Mythic) | statuses (Shield, Growth, Insured, Fading), Wild, Rage `⚑`, rarity, start path, `counted`, sync |
| 11 | **Badge** | 40 × 40 square (icon + short number), unread dot, count badge on a tab | Home badge column, dock, Tree tab, Digest |
| 12 | **HeartPips** | full / cracked; 1 row, 2 rows, or collapsed `♥ 17/20` (max hearts up to ~20) | Home, Feed, Block, My Pet, pet header |
| 13 | **Bar** | progress (XP, age, wear, stats), bipolar with centre tick (bonding −127…+127), with hatched zones | Home, My Pet, Talk, Block |
| 14 | **Balance / value** | icon + right-aligned number; signed delta coloured by sign (`+280`, `−310`) | status card, Block, Digest, Shop |
| 15 | **Segmented control / Tabs** | segment (one active, filled), tab with count badge | Threat / Loot / Weak, Pet / Tree |
| 16 | **Toggle** | off / on / pending (waiting for signature) / disabled | Settings |
| 17 | **Radio row** | selected / unselected / `current` tag | persona |
| 18 | **List row** | 48 px or 56 px; `icon · text · value ›`; states: selected (inverted), destructive, locked (greyed) | Settings, Digest, Block list, stat rows, Feed portions |
| 19 | **Section header + Divider** | group header with date at right, day divider, `New since 23:10`, `Seen` | Digest, Talk, Settings, My Pet |
| 20 | **Loading** | spinner, skeleton bars, sync chip (`Syncing…` / `Offline · 3 min ago`) | app-wide |
| 21 | **Empty / locked state** | dashed box + icon + one line | empty Digest, hidden talent, empty gear slot, dead slot, not attackable |
| 22 | **Icon set** (~25, one style) | heart, cracked heart, harvest ⚠, burrow lock, Winter snowflake, shield, growth ↗, insured ✚, fading ⧖, rage ⚑, skull ☠, wallet, gear, copy, back, `‹ ›`, send, lock, unread dot, worked, ate, level up, gear bought/sold, fight won/lost, gift | app-wide |

---

## B. Patterns (composed from §A, no new art)

| Pattern | Built from |
|---|---|
| Status card (Home) | Panel + HeartPips + Balance ×2 + Bar. Expanded form adds Chips. Alert form = alert Panel + Reason pill |
| Badge column (Home) | Badge ×4 (4th becomes `+N` on overflow) + Tooltip |
| Product card (Feed, Shop) | Panel + text + price + SignButton |
| Item / gear tile | Panel + rarity Chip + wear Bar; empty slot = Empty state |
| Neighbour entry (Block) | list layout = List row; grid layout = small Panel |
| Pet header (My Pet) | small portrait + text + HeartPips |
| Digest event line / fight log line | List row + unread dot + signed Balance |
| Stat comparison them / you | two-column List row |
| Day summary (Digest) | Panel + 3-column grid of signed Balances; bad night = alert Panel + Reason pill |
| Dead pet card (Home) | Panel replacing the status card + text link |

---

## C. Context-specific components

| Context | Component |
|---|---|
| Block | **Odds block**: win %, expected loot, max loot, bar chart of fight length over 1–6 rounds; states computing / not attackable |
| Talk | **Chat bubbles**: owner right (filled), pet left with small avatar; **input field + Send** |
| My Pet | **Lineage timeline**: vertical, one entry per generation |
| Tree | **Skill nodes**: small circle, notable large circle, keystone hexagon, each allocated / reachable / locked; connecting lines (normal, thick when allocated); legend row |
| Talent reveal | **Flip card** (back with `?`, face with kind, grade, multiplier) + grade ladder Common → Mythic |

---

## D. Build order

Icon set → Panel → Button → Chip / Badge → HeartPips → Bar → List row → Sheet.

These are kit assembly dependencies, not a screen-by-screen build plan. Reuse them within the scene-backed Home rather than introducing separate pages.
