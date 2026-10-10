"""Cut gearIconSheet.png into the twelve gear icons native/hud/gearIcons.ms picks by slot and stat.

The sheet is a 4 x 3 grid on transparency. Each icon is trimmed to its alpha, centred on a square
canvas and resized to the hotbar's 31 design units at the Seeker's 1200 / 360 pixels per unit.
Writes only its own gearIcon*.png files. Run from the repo root: python3 art/hud/cutGearIcons.py
"""

from pathlib import Path

from PIL import Image

SHEET = Path("art/hud/gearIconSheet.png")
OUT = Path("assets/hud/pieces")
DENSITY = 1200.0 / 360.0
ICON_DESIGN_SIZE = 31.0
COLUMNS = 4
ROWS = 3
ALPHA_FLOOR = 20

# Grid cells, left to right and top to bottom, named slot then stat (gearIcons.ms GEAR_ICON_NAMES).
CELLS = [
    "gearIconHandsGrit", "gearIconBodyMight", "gearIconHeadForage", "gearIconHeadMight",
    "gearIconHandsMight", "gearIconHandsForage", "gearIconFeetGrit", "gearIconBodyGrit",
    "gearIconFeetForage", "gearIconBodyForage", "gearIconFeetMight", "gearIconHeadGrit",
]


def main():
    sheet = Image.open(SHEET).convert("RGBA")
    assert sheet.size == (1448, 1086), "Gear icon sheet size changed; review the grid."
    cell_width = sheet.width / COLUMNS
    cell_height = sheet.height / ROWS
    side = round(ICON_DESIGN_SIZE * DENSITY)
    for index, name in enumerate(CELLS):
        column, row = index % COLUMNS, index // COLUMNS
        cell = sheet.crop((round(column * cell_width), round(row * cell_height),
            round((column + 1) * cell_width), round((row + 1) * cell_height)))
        cell.putalpha(cell.getchannel("A").point(lambda value: value if value > ALPHA_FLOOR else 0))
        bounds = cell.getbbox()
        assert bounds, f"{name}: empty cell"
        icon = cell.crop(bounds)
        square = Image.new("RGBA", (max(icon.size),) * 2, (0, 0, 0, 0))
        square.paste(icon, ((square.width - icon.width) // 2, (square.height - icon.height) // 2))
        square.resize((side, side), Image.LANCZOS).save(OUT / f"{name}.png")


if __name__ == "__main__":
    main()
