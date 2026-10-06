"""Cut hotbarSheet.png, statBarsSheet.png, shopSheet.png, toggleSheet.png and buttonSheet.png into
the pieces native/hud/hotbar.ms, statBars.ms, shopPopup.ms, toggles.ms, actionButton.ms and
banners.ms draw.

Every piece is resized to the design size those files give it, at the Seeker's 1200 / 360 pixels
per design unit, so it draws 1:1 there. Run from the repo root: python3 art/hud/cutHud.py
"""

from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageOps

SHEET = Path("art/hud/hotbarSheet.png")
STAT_SHEET = Path("art/hud/statBarsSheet.png")
ICONS = Path("assets/hud/kit/icons")
OUT = Path("assets/hud/pieces")
DENSITY = 1200.0 / 360.0

# Source boxes (left, top, right, bottom) in hotbarSheet.png, and the design size to fit into.
FITTED = {
    "levelPlate": ((34, 68, 346, 555), (62.0, 84.0)),
    "slot": ((669, 377, 907, 604), (39.5, 38.8)),
    "plusSlot": ((938, 377, 1182, 604), (39.5, 38.8)),
    "endCap": ((1297, 68, 1431, 542), (24.0, 75.0)),
    "hatch": ((875, 1010, 950, 1064), (10.5, 9.5)),
    "dot": ((314, 1020, 355, 1057), (3.4, 3.4)),
    "sword": ((61, 753, 303, 997), (31.0, 31.0)),
    "pistol": ((355, 781, 556, 993), (31.0, 31.0)),
    "shotgun": ((597, 770, 828, 992), (31.0, 31.0)),
    "core": ((892, 773, 1095, 976), (31.0, 31.0)),
    "rifle": ((1129, 771, 1409, 998), (31.0, 31.0)),
}

# Drawn at exactly this size: the sheet's slot-number plate is flatter than the mockup's tabs.
EXACT = {
    "tab": ((712, 1012, 840, 1063), (23.0, 13.0)),
}

# The XP frame is the sheet's empty bar, longer than drawn: its two ends keep their shape and
# the middle stretches.
XP_FRAME_BOX = (423, 86, 1187, 162)
XP_FRAME_END = 44
XP_FRAME_SIZE = (259.0, 13.0)

# The sheet has no panel behind the bar: a translucent fill with the sheet's long glow line
# along its top and bottom edges.
GLOW_LINE_BOX = (397, 1024, 588, 1051)
PANEL_SIZE = (265.0, 64.0)
PANEL_FILL = (34, 96, 178, 96)


def pixels(size):
    return (round(size[0] * DENSITY), round(size[1] * DENSITY))


def fitted(piece, size):
    width, height = pixels(size)
    scale = min(width / piece.width, height / piece.height)
    return piece.resize((max(1, round(piece.width * scale)), max(1, round(piece.height * scale))), Image.LANCZOS)


def stretched(piece, size, end):
    width, height = pixels(size)
    scale = height / piece.height
    cap = round(end * scale)
    scaled = piece.resize((round(piece.width * scale), height), Image.LANCZOS)
    out = Image.new("RGBA", (width, height))
    out.paste(scaled.crop((0, 0, cap, height)), (0, 0))
    middle = scaled.crop((cap, 0, scaled.width - cap, height)).resize((width - 2 * cap, height), Image.LANCZOS)
    out.paste(middle, (cap, 0))
    out.paste(scaled.crop((scaled.width - cap, 0, scaled.width, height)), (width - cap, 0))
    return out


def panel(glow):
    width, height = pixels(PANEL_SIZE)
    out = Image.new("RGBA", (width, height), PANEL_FILL)
    line = glow.resize((width, max(1, round(glow.height * width / glow.width / 4))), Image.LANCZOS)
    out.alpha_composite(line, (0, 0))
    out.alpha_composite(line, (0, height - line.height))
    return out


# One stat bar, laid out as the sheet's assembled rows (pieces matched into the blue row), then
# mirrored for the top-right corner: badge and plug on the right, the fill growing leftwards.
# Positions are sheet pixels in a STAT_CANVAS box; statBars.ms scales them by STAT_WIDTH / 612.
STAT_CANVAS = (612, 173)
STAT_WIDTH = 70.0
STAT_FRAME = ((507, 843, 932, 938), (186, 44))
STAT_PLUG = ((186, 856, 292, 960), (0, 40))
STAT_BADGE = (304, 824, 478, 992)
STAT_FILL_END = 40
STAT_FILLS = {
    "Blue": (220, 1055, 571, 1111),
    "Red": (220, 1115, 571, 1172),
    "Green": (220, 1175, 571, 1232),
    "Orange": (220, 1235, 571, 1292),
}
STAT_ICONS = {"heart": 8.0, "gift": 8.0, "growth": 8.0}


def statScale():
    return STAT_WIDTH / STAT_CANVAS[0]


def scaledBy(piece, scale):
    return piece.resize((max(1, round(piece.width * scale * DENSITY)), max(1, round(piece.height * scale * DENSITY))),
        Image.LANCZOS)


def statPieces(sheet):
    scale = statScale()
    frame = Image.new("RGBA", STAT_CANVAS)
    for box, at in (STAT_FRAME, STAT_PLUG):
        frame.alpha_composite(sheet.crop(box), at)
    scaledBy(ImageOps.mirror(frame), scale).save(OUT / "statFrame.png")
    scaledBy(ImageOps.mirror(sheet.crop(STAT_BADGE)), scale).save(OUT / "statBadge.png")
    for colour, box in STAT_FILLS.items():
        fill = ImageOps.mirror(sheet.crop(box))
        scaledBy(fill.crop((0, 0, STAT_FILL_END, fill.height)), scale).save(OUT / ("statFill" + colour + "End.png"))
        middle = fill.width // 2
        scaledBy(fill.crop((middle, 0, middle + 8, fill.height)), scale).save(OUT / ("statFill" + colour + "Body.png"))


# A kit pixel-art icon as a white glyph, as in statBarsMockup.png.
def whiteGlyph(name, size):
    icon = Image.open(ICONS / (name + ".png")).convert("RGBA")
    white = Image.new("RGBA", icon.size, (255, 255, 255, 255))
    white.putalpha(icon.getchannel("A"))
    target = round(size * DENSITY)
    step = max(1, -(-target // max(icon.width, icon.height)))
    large = white.resize((icon.width * step, icon.height * step), Image.NEAREST)
    return fitted(large, (size, size))


def statIcons():
    for name, size in STAT_ICONS.items():
        whiteGlyph(name, size).save(OUT / ("stat" + name[0].upper() + name[1:] + ".png"))


# The shop over the hotbar, assembled from shopSheet.png's slices into shopMockup.jpg's layout,
# one part at a time: the hex body (nine-sliced, so its chamfers keep their size) is the panel's
# thin outline; the title strip keeps its two ends and stretches its plain middle; the top-left
# corner, close box, top-right bracket and side dots sit where the mockup has them. Positions are
# canvas pixels, the mockup's own pixels from the panel's top-left (mockup (321, 78)); the panel is
# taller than the mockup's (590, not 487) so it stands as tall over the hotbar, which is thicker
# here. The outline (canvas x 11 to 1023) is as wide as the hotbar's XP frame.
SHOP_SHEET = Path("art/hud/shopSheet.png")
# The panel is 50 pixels taller than the mockup's for the buttons, twice the mockup's height.
SHOP_CANVAS = (1030, 640)
SHOP_OUTLINE = 1012
SHOP_SCALE = XP_FRAME_SIZE[0] / SHOP_OUTLINE
# The body's top border is the line under the title and the close box; between it and the
# outline's top runs a dark band (the mockup's (1, 39, 86)). Short straight pieces of the body's
# own edges and of the title's top line bridge the outline where the body's corners turn in.
SHOP_BAND = ((16, 6, 1002, 62), (1, 39, 86, 255))
SHOP_BODY = ((118, 155, 1004, 538), (11, 59, 1016, 581), 60)
SHOP_TITLE = [
    ((142, 72, 600, 147), (11, 0, 458, 75)),
    ((600, 72, 670, 147), (469, 0, 185, 75)),
    ((670, 72, 921, 147), (654, 0, 251, 75)),
]
SHOP_OUTLINE_PARTS = [
    ((122, 300, 134, 360), (15, 62, 12, 50)),
    ((988, 300, 1000, 360), (1011, 62, 12, 60)),
    ((700, 76, 860, 86), (884, 2, 112, 10)),
    ((32, 72, 120, 159), (16, 4, 70, 70)),
    ((1006, 66, 1092, 148), (923, 8, 64, 62)),
    ((926, 70, 983, 152), (975, 0, 48, 70)),
    ((33, 266, 46, 366), (0, 190, 10, 80)),
    ((33, 266, 46, 366), (1020, 190, 10, 80)),
]
# Three projectors on the hotbar's edge under the panel: a cone from the middle, and a beam from
# each end up to the panel's bottom corners; a glow line along the edge. Each piece's bright tip
# sits on the canvas' bottom edge. The side beams are drawn at 1.7 times their sheet opacity, as
# bright as the mockup's.
SHOP_HOLOGRAM_CANVAS = (1030, 110)
SHOP_HOLOGRAM_PARTS = [
    ((182, 1207, 442, 1361), (265, 0, 500, 110)),
    ((58, 1206, 164, 1321), (4, 0, 62, 110), 1.7),
    ((456, 1212, 551, 1320), (964, 0, 62, 110), 1.7),
    ((569, 1218, 839, 1250), (40, 96, 950, 16)),
]
# Canvas pixels of the content pieces; shopPopup.ms places them.
SHOP_CELL_CANVAS = (172, 140)
SHOP_CELL_CORNER = 36
# The selection check, lifted off its cell by brightness so it draws over the item.
SHOP_CHECK_CANVAS = (40, 40)
# PURCHASE and CANCEL, nine-sliced so their chamfered ends keep their shape at any height.
SHOP_BUTTONS = {
    "shopPurchase": ((38, 905, 385, 982), (346, 100)),
    "shopCancel": ((405, 907, 745, 976), (343, 100)),
}
SHOP_BUTTON_CORNER = 30
SHOP_CHECK_FLOOR = 110
SHOP_ITEM_CANVAS = (118, 104)
SHOP_CART = ((207, 90, 252, 129), (35, 28))
# The price plate under a cell: the sheet's plate turned upside down (the mockup's has its
# chamfers at the bottom), its fill and rim darkened to the mockup's (0, 25, 55) and (0, 90, 150).
SHOP_TAG = ((374, 656, 578, 693), (152, 28))
SHOP_TAG_FILL_GREEN = 110
SHOP_TAG_FILL_SHADE = 0.45
SHOP_TAG_RIM_SHADE = 0.65
SHOP_CELLS = {
    "shopCell": (37, 741, 199, 875),
    "shopCellBright": (224, 738, 385, 879),
    "shopCellPlus": (580, 741, 736, 875),
    "shopCellDisabled": (757, 741, 911, 875),
}
SHOP_CHECK = ((404, 741, 560, 875), (100, 0, 156, 56))
SHOP_PLATES = {
    "shopBalance": ((597, 655, 814, 702), (145, 30)),
    "shopGem": ((798, 916, 848, 975), (22, 26)),
}
# Item icons: shop size from shopSheet.png, and hotbar size for those the hotbar sheet lacks.
SHOP_ITEMS = {
    "Sword": (22, 1014, 128, 1146),
    "Pistol": (128, 1032, 239, 1150),
    "Shotgun": (239, 1031, 370, 1153),
    "Core": (381, 1029, 507, 1147),
    "Medkit": (527, 1040, 638, 1146),
    "Battery": (659, 1036, 738, 1144),
    "Ammo": (762, 1047, 851, 1141),
    "Shield": (864, 1026, 963, 1138),
    "Drone": (972, 1033, 1091, 1139),
}
HOTBAR_ONLY_FROM_SHOP = ["Medkit", "Battery", "Ammo", "Shield", "Drone"]
HOTBAR_ITEM_SIZE = (31.0, 31.0)


def canvasPixels(size):
    return pixels((size[0] * SHOP_SCALE, size[1] * SHOP_SCALE))


# Corners kept at `corner` source pixels, edges and middle stretched to `size` source pixels.
def nineSliced(piece, size, corner):
    width, height = size
    source_width, source_height = piece.size
    out = Image.new("RGBA", size)
    columns = [(0, corner, 0, corner), (corner, source_width - corner, corner, width - corner),
        (source_width - corner, source_width, width - corner, width)]
    rows = [(0, corner, 0, corner), (corner, source_height - corner, corner, height - corner),
        (source_height - corner, source_height, height - corner, height)]
    for sx0, sx1, dx0, dx1 in columns:
        for sy0, sy1, dy0, dy1 in rows:
            tile = piece.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.LANCZOS)
            out.paste(tile, (dx0, dy0))
    return out


# The sheet's item icons overlap each other's boxes: keep only the largest opaque blob of a crop
# (and its faint glow), so a neighbour's edge does not come along.
def isolated(piece, threshold=24):
    alpha = piece.getchannel("A").load()
    width, height = piece.size
    label = [[-1] * width for _ in range(height)]
    sizes = []
    for y in range(height):
        for x in range(width):
            if label[y][x] >= 0 or alpha[x, y] <= threshold:
                continue
            index = len(sizes)
            queue = deque([(x, y)])
            label[y][x] = index
            count = 0
            while queue:
                cx, cy = queue.popleft()
                count += 1
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < width and 0 <= ny < height and label[ny][nx] < 0 and alpha[nx, ny] > threshold:
                        label[ny][nx] = index
                        queue.append((nx, ny))
            sizes.append(count)
    keep = sizes.index(max(sizes))
    out = piece.copy()
    pixels = out.load()
    for y in range(height):
        for x in range(width):
            if label[y][x] >= 0 and label[y][x] != keep:
                pixels[x, y] = (0, 0, 0, 0)
    return out


def placed(sheet, out, parts):
    for part in parts:
        box, (x, y, width, height) = part[0], part[1]
        piece = sheet.crop(box).resize((width, height), Image.LANCZOS)
        if len(part) > 2:
            gain = part[2]
            piece.putalpha(piece.getchannel("A").point(lambda v: min(255, round(v * gain))))
        out.alpha_composite(piece, (x, y))


def shopPieces(sheet):
    frame = Image.new("RGBA", SHOP_CANVAS)
    (x, y, width, height), colour = SHOP_BAND
    frame.alpha_composite(Image.new("RGBA", (width, height), colour), (x, y))
    box, (x, y, width, height), corner = SHOP_BODY
    frame.alpha_composite(nineSliced(sheet.crop(box), (width, height), corner), (x, y))
    placed(sheet, frame, SHOP_TITLE)
    placed(sheet, frame, SHOP_OUTLINE_PARTS)
    frame.resize(canvasPixels(SHOP_CANVAS), Image.LANCZOS).save(OUT / "shopFrame.png")
    hologram = Image.new("RGBA", SHOP_HOLOGRAM_CANVAS)
    placed(sheet, hologram, SHOP_HOLOGRAM_PARTS)
    hologram.resize(canvasPixels(SHOP_HOLOGRAM_CANVAS), Image.LANCZOS).save(OUT / "shopHologram.png")
    for name, box in SHOP_CELLS.items():
        if name == "shopCellBright":
            continue
        cell = nineSliced(sheet.crop(box), SHOP_CELL_CANVAS, SHOP_CELL_CORNER)
        cell.resize(canvasPixels(SHOP_CELL_CANVAS), Image.LANCZOS).save(OUT / (name + ".png"))
    selected = nineSliced(sheet.crop(SHOP_CELLS["shopCellBright"]), SHOP_CELL_CANVAS, SHOP_CELL_CORNER)
    selected.resize(canvasPixels(SHOP_CELL_CANVAS), Image.LANCZOS).save(OUT / "shopCellSelected.png")
    checkBox, checkArea = SHOP_CHECK
    raw = sheet.crop(checkBox).crop(checkArea)
    floor = SHOP_CHECK_FLOOR
    bright = raw.convert("L").point(lambda v: max(0, min(255, (v - floor) * 255 // (255 - floor))))
    check = Image.new("RGBA", raw.size, (255, 255, 255, 255))
    check.putalpha(ImageChops.multiply(bright, raw.getchannel("A")))
    check.resize(canvasPixels(SHOP_CHECK_CANVAS), Image.LANCZOS).save(OUT / "shopCheck.png")
    for name, (box, size) in SHOP_PLATES.items():
        sheet.crop(box).resize(canvasPixels(size), Image.LANCZOS).save(OUT / (name + ".png"))
    for name, (box, size) in SHOP_BUTTONS.items():
        button = nineSliced(sheet.crop(box), size, SHOP_BUTTON_CORNER)
        button.resize(canvasPixels(size), Image.LANCZOS).save(OUT / (name + ".png"))
    box, size = SHOP_TAG
    tag = ImageOps.flip(sheet.crop(box))
    pixels_ = tag.load()
    for y in range(tag.height):
        for x in range(tag.width):
            r, g, b, a = pixels_[x, y]
            shade = SHOP_TAG_FILL_SHADE if g < SHOP_TAG_FILL_GREEN else SHOP_TAG_RIM_SHADE
            pixels_[x, y] = (round(r * shade), round(g * shade), round(b * shade), a)
    tag.resize(canvasPixels(size), Image.LANCZOS).save(OUT / "shopTag.png")
    box, size = SHOP_CART
    cart = sheet.crop(box).convert("L").point(lambda v: max(0, min(255, (v - 120) * 255 // 100)))
    glyph = Image.new("RGBA", cart.size, (255, 255, 255, 255))
    glyph.putalpha(cart)
    glyph.resize(canvasPixels(size), Image.LANCZOS).save(OUT / "shopCart.png")
    for name, box in SHOP_ITEMS.items():
        icon = isolated(sheet.crop(box))
        width, height = canvasPixels(SHOP_ITEM_CANVAS)
        fitted(icon, (width / DENSITY, height / DENSITY)).save(OUT / ("shop" + name + ".png"))
        if name in HOTBAR_ONLY_FROM_SHOP:
            fitted(icon, HOTBAR_ITEM_SIZE).save(OUT / (name[0].lower() + name[1:] + ".png"))


# The toggle's four looks, one square crop round each box's centre so they share a footprint
# (the held one's glow reaches furthest).
TOGGLE_SHEET = Path("art/hud/toggleSheet.png")
TOGGLE_CROP = 360
TOGGLE_SIZE = (15.0, 15.0)
TOGGLE_CENTRES = {
    "toggleOff": (406, 387),
    "toggleOn": (848, 387),
    "toggleHeld": (406, 866),
    "toggleDisabled": (849, 868),
}


def togglePieces(sheet):
    half = TOGGLE_CROP // 2
    for name, (x, y) in TOGGLE_CENTRES.items():
        sheet.crop((x - half, y - half, x + half, y + half)).resize(pixels(TOGGLE_SIZE), Image.LANCZOS).save(OUT / (name + ".png"))


# SET AS WALLPAPER: the sheet's blue button and its glowing look (held), cropped round the same
# centre with room for the glow and stretched to the label's width with both ends kept. The yellow
# row's glow starts right under the blue's, so the crop stops above it and the halo fades out.
BUTTON_SHEET = Path("art/hud/buttonSheet.png")
WALLPAPER_BUTTONS = {
    "wallpaperButton": (7, 545, 285, 646),
    "wallpaperButtonHeld": (283, 545, 561, 646),
}
WALLPAPER_BUTTON_END = 70
WALLPAPER_BUTTON_FADE = 8
WALLPAPER_BUTTON_SIZE = (137.0, 30.0)


# The glyph after SET AS WALLPAPER on Home: the kit's house, as Settings' wallpaper row has.
WALLPAPER_GLYPH = ("home", 10.0)


# The banners on Home: the same blue button at banner height, cut into its chevron end, a strip of
# its body that stretches to the line's width and its pointed end.
BANNER_HEIGHT = 26.0
BANNER_STRIP = 8


def fadedButton(sheet, box):
    button = sheet.crop(box)
    alpha = button.getchannel("A")
    values = alpha.load()
    for row in range(WALLPAPER_BUTTON_FADE):
        y = button.height - 1 - row
        for x in range(button.width):
            values[x, y] = values[x, y] * row // WALLPAPER_BUTTON_FADE
    button.putalpha(alpha)
    return button


def buttonPieces(sheet):
    for name, box in WALLPAPER_BUTTONS.items():
        stretched(fadedButton(sheet, box), WALLPAPER_BUTTON_SIZE, WALLPAPER_BUTTON_END).save(OUT / (name + ".png"))


def bannerPieces(sheet):
    button = fadedButton(sheet, WALLPAPER_BUTTONS["wallpaperButton"])
    height = round(BANNER_HEIGHT * DENSITY)
    scale = height / button.height
    scaled = button.resize((round(button.width * scale), height), Image.LANCZOS)
    end = round(WALLPAPER_BUTTON_END * scale)
    middle = scaled.width // 2
    scaled.crop((0, 0, end, height)).save(OUT / "bannerStart.png")
    scaled.crop((middle, 0, middle + BANNER_STRIP, height)).save(OUT / "bannerBody.png")
    scaled.crop((scaled.width - end, 0, scaled.width, height)).save(OUT / "bannerEnd.png")


def main():
    sheet = Image.open(SHEET).convert("RGBA")
    OUT.mkdir(parents=True, exist_ok=True)
    for stale in OUT.glob("*.png"):
        stale.unlink()
    for name, (box, size) in FITTED.items():
        fitted(sheet.crop(box), size).save(OUT / (name + ".png"))
    for name, (box, size) in EXACT.items():
        sheet.crop(box).resize(pixels(size), Image.LANCZOS).save(OUT / (name + ".png"))
    stretched(sheet.crop(XP_FRAME_BOX), XP_FRAME_SIZE, XP_FRAME_END).save(OUT / "xpFrame.png")
    panel(sheet.crop(GLOW_LINE_BOX)).save(OUT / "panel.png")
    statPieces(Image.open(STAT_SHEET).convert("RGBA"))
    statIcons()
    shopPieces(Image.open(SHOP_SHEET).convert("RGBA"))
    togglePieces(Image.open(TOGGLE_SHEET).convert("RGBA"))
    buttonPieces(Image.open(BUTTON_SHEET).convert("RGBA"))
    whiteGlyph(*WALLPAPER_GLYPH).save(OUT / "wallpaperGlyph.png")
    bannerPieces(Image.open(BUTTON_SHEET).convert("RGBA"))


if __name__ == "__main__":
    main()
