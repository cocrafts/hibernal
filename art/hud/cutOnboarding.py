from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / "art/hud/onboardingSheet.png"
OUT = ROOT / "assets/hud/pieces"

PIECES = {
    "onboardingCreate": (18, 700, 726, 898),
    "onboardingName": (10, 405, 698, 533),
    "onboardingPrevious": (20, 539, 198, 698),
    "onboardingNext": (216, 538, 387, 698),
    "onboardingHologram": (642, 130, 1122, 690),
    "onboardingWallet": (740, 800, 1108, 895),
}
# A dead Pet's onboarding shows these in grey, saved as <name>Dead.
DEAD_GREY = ["onboardingHologram", "onboardingName"]


def main():
    sheet = Image.open(SHEET).convert("RGBA")
    assert sheet.size == (1122, 1402), "Onboarding sheet size changed; review crop bounds."
    OUT.mkdir(parents=True, exist_ok=True)
    for name, bounds in PIECES.items():
        cropped = sheet.crop(bounds)
        alpha = cropped.getchannel("A")
        if name == "onboardingHologram":
            ImageDraw.Draw(alpha).rectangle((0, 0, 62, 403), fill=0)
        mask = alpha.point(lambda value: 255 if value else 0)
        seed = (cropped.width // 2, cropped.height // 2)
        assert mask.getpixel(seed) == 255, f"{name}: crop seed is transparent."
        ImageDraw.floodfill(mask, seed, 128)
        mask = mask.point(lambda value: 255 if value == 128 else 0)
        cropped.putalpha(ImageChops.multiply(alpha, mask))
        minimum, maximum = cropped.getchannel("A").getextrema()
        assert minimum == 0 and maximum > 0, f"{name}: crop lost transparency or content."
        cropped.save(OUT / f"{name}.png")
        if name in DEAD_GREY:
            grey = ImageOps.grayscale(cropped).convert("RGBA")
            grey.putalpha(cropped.getchannel("A"))
            grey.save(OUT / f"{name}Dead.png")
        print(f"{name}: {cropped.width}x{cropped.height}")


if __name__ == "__main__":
    main()
