from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / "art/hud/itemShopSheet.png"
OUT = ROOT / "assets/hud/pieces"

PIECES = {
    "itemCard": (20, 80, 548, 597),
    "shopStrip": (17, 723, 1105, 944),
}


def main():
    sheet = Image.open(SHEET).convert("RGBA")
    assert sheet.size == (1122, 1402), "Item shop sheet size changed; review crop bounds."
    OUT.mkdir(parents=True, exist_ok=True)
    for name, bounds in PIECES.items():
        cropped = sheet.crop(bounds)
        alpha = cropped.getchannel("A")
        mask = alpha.point(lambda value: 255 if value else 0)
        seed = (cropped.width // 2, cropped.height // 2)
        assert mask.getpixel(seed) == 255, f"{name}: crop seed is transparent."
        ImageDraw.floodfill(mask, seed, 128)
        mask = mask.point(lambda value: 255 if value == 128 else 0)
        cropped.putalpha(ImageChops.multiply(alpha, mask))
        minimum, maximum = cropped.getchannel("A").getextrema()
        assert minimum == 0 and maximum > 0, f"{name}: crop lost transparency or content."
        cropped.save(OUT / f"{name}.png")
        print(f"{name}: {cropped.width}x{cropped.height}")


if __name__ == "__main__":
    main()
