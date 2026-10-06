"""Make the Android launcher icon from appIcon.png into android/app/src/main/res.

The adaptive icon's foreground is the whole picture at 108 dp; the launcher's mask shows its middle
72 dp, so the legacy and round icons are that middle part. Run from the repo root:
uv run --with pillow python art/app/makeAppIcon.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

SOURCE = Path("art/app/appIcon.png")
RES = Path("android/app/src/main/res")
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}
ADAPTIVE_DP = 108
LEGACY_DP = 48
VISIBLE_SHARE = 72 / 108


def main():
    picture = Image.open(SOURCE).convert("RGBA")
    margin = round(picture.width * (1 - VISIBLE_SHARE) / 2)
    visible = picture.crop((margin, margin, picture.width - margin, picture.height - margin))
    for density, scale in DENSITIES.items():
        folder = RES / ("mipmap-" + density)
        folder.mkdir(parents=True, exist_ok=True)
        adaptive = round(ADAPTIVE_DP * scale)
        picture.resize((adaptive, adaptive), Image.LANCZOS).save(folder / "ic_launcher_foreground.png")
        legacy = round(LEGACY_DP * scale)
        square = visible.resize((legacy, legacy), Image.LANCZOS)
        square.save(folder / "ic_launcher.png")
        mask = Image.new("L", (legacy, legacy))
        ImageDraw.Draw(mask).ellipse((0, 0, legacy - 1, legacy - 1), fill=255)
        round_icon = Image.new("RGBA", (legacy, legacy))
        round_icon.paste(square, (0, 0), mask)
        round_icon.save(folder / "ic_launcher_round.png")


if __name__ == "__main__":
    main()
