"""Cut ownerShopSheet.png into the pieces native/hud/shopStrip.ms draws the SKR shop panel with.

Writes only its own ownerShop*.png files into assets/hud/pieces.
"""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / "art/hud/ownerShopSheet.png"
OUT = ROOT / "assets/hud/pieces"

# Filled shapes: the shape under the crop centre is kept, anything the crop clips from a neighbour is dropped.
PIECES = {
    "ownerShopTitle": (49, 15, 450, 115),
    "ownerShopClose": (458, 27, 537, 97),
    "ownerShopHeader": (15, 116, 736, 218),
    "ownerShopSectionBar": (782, 238, 991, 271),
    "ownerShopCard": (16, 307, 210, 489),
    "ownerShopCardInCart": (403, 307, 594, 489),
    "ownerShopCardDim": (597, 307, 790, 489),
    "ownerShopCardLocked": (795, 307, 988, 489),
    "ownerShopInsurance": (15, 546, 290, 758),
    "ownerShopComingSoon": (297, 546, 654, 758),
    "ownerShopCart": (15, 766, 556, 977),
    "ownerShopBuy": (364, 843, 534, 893),
    "ownerShopCancel": (668, 647, 820, 695),
    "ownerShopMinus": (572, 850, 641, 890),
    "ownerShopCornerTopLeft": (1006, 127, 1078, 234),
    "ownerShopCornerTopRight": (1090, 98, 1181, 234),
    "ownerShopCornerBottomLeft": (998, 1191, 1078, 1304),
    "ownerShopCornerBottomRight": (1100, 1191, 1181, 1304),
}

# What a crop catches of a neighbour that touches it, in crop coordinates.
CLEARED = {
    "ownerShopCornerBottomLeft": (58, 0, 80, 70),
}

# Notice bars: the cap with the glyph keeps its shape, the bar after it stretches to any width.
NOTICES = {
    "ownerShopOk": (719, 753, 986, 798),
    "ownerShopError": (719, 798, 986, 843),
    "ownerShopWarning": (719, 843, 986, 888),
    "ownerShopDead": (719, 888, 986, 932),
}
NOTICE_CAP = 50
NOTICE_BAR_FROM = 44

# Icons and line art: cut on alpha alone.
ICONS = {
    "ownerShopCoin": (16, 1137, 68, 1195),
    "ownerShopFoodIcon0": (77, 1137, 128, 1195),
    "ownerShopFoodIcon1": (199, 1137, 254, 1195),
    "ownerShopFoodIcon2": (134, 1137, 189, 1195),
    "ownerShopGrowthIcon0": (260, 1135, 317, 1200),
    "ownerShopGrowthIcon1": (323, 1135, 379, 1200),
    "ownerShopGrowthIcon2": (383, 1135, 440, 1200),
    "ownerShopInsuranceIcon": (452, 1136, 516, 1203),
    "ownerShopCartIcon": (526, 1143, 575, 1191),
    "ownerShopTruck": (592, 1146, 642, 1193),
    "ownerShopFork": (19, 1204, 62, 1258),
    "ownerShopHelix": (75, 1202, 125, 1259),
    "ownerShopShield": (142, 1204, 183, 1258),
    "ownerShopShirt": (197, 1208, 246, 1258),
}

# The cart's baked BUY button, in cart coordinates, is painted over with the plain panel below it;
# the panel draws its buttons itself.
CART_BUTTON = (343, 72, 525, 132)
CART_PLAIN_TOP = 134


def main():
    sheet = Image.open(SHEET).convert("RGBA")
    assert sheet.size == (1191, 1320), "Owner shop sheet size changed; review crop bounds."
    OUT.mkdir(parents=True, exist_ok=True)
    for name, bounds in PIECES.items():
        cropped = sheet.crop(bounds)
        alpha = cropped.getchannel("A")
        mask = alpha.point(lambda value: 255 if value > 20 else 0)
        seed = (cropped.width // 2, cropped.height // 2)
        if mask.getpixel(seed) != 255:
            seed = (cropped.width // 2, cropped.height - 6)
        assert mask.getpixel(seed) == 255, f"{name}: crop seed is transparent."
        ImageDraw.floodfill(mask, seed, 128)
        mask = mask.point(lambda value: 255 if value == 128 else 0)
        cropped.putalpha(ImageChops.multiply(alpha, mask))
        if name in CLEARED:
            cropped.paste((0, 0, 0, 0), CLEARED[name])
        if name == "ownerShopCart":
            left, top, right, bottom = CART_BUTTON
            cropped.paste(cropped.crop((left, CART_PLAIN_TOP, right, CART_PLAIN_TOP + bottom - top)), (left, top))
        cropped.save(OUT / f"{name}.png")
    for name, bounds in NOTICES.items():
        notice = sheet.crop(bounds)
        notice.crop((0, 0, NOTICE_CAP, notice.height)).save(OUT / f"{name}Cap.png")
        notice.crop((NOTICE_BAR_FROM, 0, notice.width, notice.height)).save(OUT / f"{name}Bar.png")
    for name, bounds in ICONS.items():
        icon = sheet.crop(bounds)
        icon.putalpha(icon.getchannel("A").point(lambda value: value if value > 20 else 0))
        icon.save(OUT / f"{name}.png")


if __name__ == "__main__":
    main()
