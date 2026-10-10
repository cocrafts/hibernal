"""Cut hotbarSheet.png, statBarsSheet.png, shopSheet.png, toggleSheet.png and buttonSheet.png into
the pieces native/hud/hotbar.ms, statBars.ms, shopStrip.ms, toggles.ms, actionButton.ms and
banners.ms draw.

Every piece is resized to the design size those files give it, at the Seeker's 1200 / 360 pixels
per design unit, so it draws 1:1 there. Run from the repo root: python3 art/hud/cutHud.py
"""

from collections import deque
from pathlib import Path

from PIL import Image, ImageOps

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


def endCapFrame(piece):
    for x in range(26, 72):
        top = piece.getpixel((x, 42))
        bottom = piece.getpixel((x, 104))
        for y in range(43, 104):
            share = (y - 42) / 62
            piece.putpixel((x, y), tuple(round(a + (b - a) * share) for a, b in zip(top, bottom)))
    return piece


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


# Item icons from shopSheet.png, scaled as the shop panel that sheet was cut for.
SHOP_SHEET = Path("art/hud/shopSheet.png")
SHOP_OUTLINE = 1012
SHOP_SCALE = XP_FRAME_SIZE[0] / SHOP_OUTLINE
SHOP_ITEM_CANVAS = (118, 104)
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


def shopPieces(sheet):
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


# The banners are cut from the sheet's blue button. The yellow row's glow starts right under it,
# so the crop stops above that glow and the button's bottom rows fade out.
BUTTON_SHEET = Path("art/hud/buttonSheet.png")
BANNER_BUTTON = (7, 545, 285, 646)
BANNER_BUTTON_END = 70
BANNER_BUTTON_FADE = 8


# The banners on Home: the same blue button at banner height, cut into its chevron end, a strip of
# its body that stretches to the line's width and its pointed end.
BANNER_HEIGHT = 26.0
BANNER_STRIP = 8


def fadedButton(sheet, box):
    button = sheet.crop(box)
    alpha = button.getchannel("A")
    values = alpha.load()
    for row in range(BANNER_BUTTON_FADE):
        y = button.height - 1 - row
        for x in range(button.width):
            values[x, y] = values[x, y] * row // BANNER_BUTTON_FADE
    button.putalpha(alpha)
    return button


def bannerPieces(sheet):
    button = fadedButton(sheet, BANNER_BUTTON)
    height = round(BANNER_HEIGHT * DENSITY)
    scale = height / button.height
    scaled = button.resize((round(button.width * scale), height), Image.LANCZOS)
    end = round(BANNER_BUTTON_END * scale)
    middle = scaled.width // 2
    scaled.crop((0, 0, end, height)).save(OUT / "bannerStart.png")
    scaled.crop((middle, 0, middle + BANNER_STRIP, height)).save(OUT / "bannerBody.png")
    scaled.crop((scaled.width - end, 0, scaled.width, height)).save(OUT / "bannerEnd.png")


# A press that changes the Pet on chain is orange: these pieces are also saved hue-turned as <name>Orange.
ORANGE = ["plusSlot", "bannerStart", "bannerBody", "bannerEnd"]
ORANGE_HUE_TURN = -118


def orange(piece):
    hue, saturation, value = piece.convert("HSV").split()
    turned = Image.merge("HSV", (hue.point(lambda h: (h + ORANGE_HUE_TURN) % 256), saturation, value)).convert("RGBA")
    turned.putalpha(piece.getchannel("A"))
    return turned


# The sheet's item slot glows past the icon and the rarity rim: channels above its fill colour keep this share.
SLOT_FILL = (0, 57, 97)
SLOT_GLOW_KEPT = 0.4


def calmSlot(piece):
    *channels, alpha = piece.split()
    calmed = [channel.point(lambda value, fill=fill: round(fill + (value - fill) * SLOT_GLOW_KEPT) if value > fill else value)
        for channel, fill in zip(channels, SLOT_FILL)]
    return Image.merge("RGBA", (*calmed, alpha))


def orangePieces():
    for name in ORANGE:
        orange(Image.open(OUT / (name + ".png")).convert("RGBA")).save(OUT / (name + "Orange.png"))


def main():
    sheet = Image.open(SHEET).convert("RGBA")
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (box, size) in FITTED.items():
        part = sheet.crop(box)
        if name == "endCap":
            part = endCapFrame(part)
        if name == "slot":
            calmSlot(fitted(part, size)).save(OUT / (name + ".png"))
        elif name == "levelPlate":
            part.resize(pixels(size), Image.LANCZOS).save(OUT / (name + ".png"))
        else:
            fitted(part, size).save(OUT / (name + ".png"))
    for name, (box, size) in EXACT.items():
        sheet.crop(box).resize(pixels(size), Image.LANCZOS).save(OUT / (name + ".png"))
    stretched(sheet.crop(XP_FRAME_BOX), XP_FRAME_SIZE, XP_FRAME_END).save(OUT / "xpFrame.png")
    panel(sheet.crop(GLOW_LINE_BOX)).save(OUT / "panel.png")
    statPieces(Image.open(STAT_SHEET).convert("RGBA"))
    statIcons()
    shopPieces(Image.open(SHOP_SHEET).convert("RGBA"))
    togglePieces(Image.open(TOGGLE_SHEET).convert("RGBA"))
    bannerPieces(Image.open(BUTTON_SHEET).convert("RGBA"))
    orangePieces()


if __name__ == "__main__":
    main()
