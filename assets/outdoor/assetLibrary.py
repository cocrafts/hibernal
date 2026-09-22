import json
import math
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PALETTE = {
    "soil": "464652", "earth": "6d5655", "ledge": "57515b",
    "grass": "77765f", "grassTip": "929078", "fern": "879b90",
    "stone": "77747b", "stoneTop": "91877c", "stoneChip": "686574",
    "rock": "727789", "bark": "493d43", "barkLight": "66504c",
    "cutWood": "b69571", "leaf": "425f61", "leafLight": "617c71",
    "coal": "302b37", "flame": "ff9b38", "core": "fff0a5", "ember": "ffc76c",
}


def prism(outline, height, side, top=None, heights=None):
    count = len(outline)
    vertices = [(x, y, 0) for x, y in outline]
    vertices += [(x, y, heights[i] if heights else height) for i, (x, y) in enumerate(outline)]
    faces = [list(reversed(range(count))), list(range(count, count * 2))]
    materials = [side, top or side]
    for i in range(count):
        j = (i + 1) % count
        faces.append([i, j, j + count, i + count])
        materials.append(side)
    return {"vertices": vertices, "faces": faces, "materials": materials}


def box(width, depth, height, side, top=None, chip=0):
    x, y = width / 2, depth / 2
    outline = [(-x, -y), (x - chip, -y), (x, -y + chip), (x, y), (-x, y)] if chip else [(-x, -y), (x, -y), (x, y), (-x, y)]
    return prism(outline, height, side, top)


def combine(parts):
    result = {"vertices": [], "faces": [], "materials": []}
    for part in parts:
        offset = len(result["vertices"])
        result["vertices"].extend(part["vertices"])
        result["faces"].extend([[i + offset for i in face] for face in part["faces"]])
        result["materials"].extend(part["materials"])
    return result


def rings(levels, sides, material, cap=None, seed=0):
    rng = random.Random(seed)
    radii = [rng.uniform(.85, 1.12) for _ in range(sides)]
    vertices = []
    for radiusX, radiusY, z, shiftX, shiftY in levels:
        for i in range(sides):
            angle = math.tau * i / sides
            vertices.append((shiftX + math.cos(angle) * radiusX * radii[i], shiftY + math.sin(angle) * radiusY * radii[i], z))
    faces = [list(reversed(range(sides)))]
    materials = [material]
    for level in range(len(levels) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            faces.append([level * sides + i, level * sides + j, (level + 1) * sides + j, (level + 1) * sides + i])
            materials.append(material)
    faces.append(list(range((len(levels) - 1) * sides, len(levels) * sides)))
    materials.append(cap or material)
    return {"vertices": vertices, "faces": faces, "materials": materials}


def grass(count, height, spread, seed):
    rng = random.Random(seed)
    vertices, faces, materials = [], [], []
    for i in range(count):
        angle = math.tau * i / count + rng.uniform(-.4, .4)
        x, y = rng.uniform(-spread, spread), rng.uniform(-spread, spread)
        width = rng.uniform(.035, .07)
        h = height * rng.uniform(.6, 1.1)
        dx, dy = math.cos(angle), math.sin(angle)
        base = len(vertices)
        vertices += [(x - dy * width, y + dx * width, 0), (x + dy * width, y - dx * width, 0), (x + dx * .09 + dy * width * .4, y + dy * .09 - dx * width * .4, h * .62), (x + dx * .09 - dy * width * .4, y + dy * .09 + dx * width * .4, h * .62), (x + dx * .19, y + dy * .19, h)]
        faces += [[base, base + 1, base + 2, base + 3], [base + 3, base + 2, base + 4]]
        materials += ["grass", "grassTip"]
    return {"vertices": vertices, "faces": faces, "materials": materials}


def fern():
    vertices, faces = [], []
    for i in range(5):
        angle = i * math.tau / 5
        dx, dy = math.cos(angle), math.sin(angle)
        start = len(vertices)
        vertices.extend([(0, 0, 0), (dx * .22 - dy * .07, dy * .22 + dx * .07, .2), (dx * .33, dy * .33, .48), (dx * .22 + dy * .07, dy * .22 - dx * .07, .2)])
        faces.append([start, start + 1, start + 2, start + 3])
    return {"vertices": vertices, "faces": faces, "materials": ["fern"] * len(faces)}


def flame(width, height, material):
    silhouette = [(-.45, 0), (-.5, .2), (-.26, .5), (-.21, .3), (.02, .74), (-.04, 1), (.3, .71), (.21, .49), (.45, .35), (.4, .09), (.14, 0)]
    vertices = [(x * width, 0, z * height) for x, z in reversed(silhouette)]
    return {"vertices": vertices, "faces": [list(range(len(vertices)))], "materials": [material]}


def makeAssets():
    assets = []

    def add(name, family, mesh, role):
        vertices = mesh["vertices"]
        dimensions = [round(max(v[i] for v in vertices) - min(v[i] for v in vertices), 3) for i in range(3)]
        assets.append({"id": name, "family": family, "role": role, "dimensions": dimensions, "triangles": sum(len(f) - 2 for f in mesh["faces"]), **mesh})

    add("groundTile", "terrain", box(2, 2, .08, "soil"), "Flat contiguous ground; pivot at underside")
    outline = [(math.cos(i * math.tau / 11) * (1 + .1 * math.sin(i * 2)), math.sin(i * math.tau / 11) * (.82 + .07 * math.cos(i))) for i in range(11)]
    add("clearingPatch", "terrain", prism(outline, .025, "earth"), "Irregular bare-earth insert; overlap below grass")
    add("groundLedge", "terrain", box(2.3, 1.4, .5, "ledge", "soil", .28), "Raised perimeter ledge, not a floating island rim")
    add("grassTuft", "grass", grass(5, .34, .12, 11), "Small tuft; rotate and instance in coherent patches")
    add("grassTall", "grass", grass(7, .6, .14, 23), "Tall broken silhouette for patch edges")
    add("broadleafSprig", "grass", fern(), "Sparse pale punctuation outside dense grass")
    add("pillarTall", "ruins", box(1.05, 1.05, 4.2, "stone", "stoneTop"), "Unbeveled square monolith; reference silhouette")
    add("pillarShort", "ruins", box(1.12, 1.04, 2.2, "stone", "stoneTop"), "Short monolith; independent height variation")
    add("stoneSlab", "ruins", box(2, 1.3, .5, "stone", "stoneTop", .12), "Low plinth or fallen block")
    add("stoneStep", "ruins", box(2.2, .76, .28, "stone", "stoneTop"), "Single stair tread; build staircase by instances")
    for name, dimensions, sides, seed in [("rockLarge", (1.2, .85, .85), 7, 5), ("rockMedium", (.65, .5, .45), 6, 8), ("rockSmall", (.3, .25, .19), 5, 12)]:
        x, y, z = dimensions
        add(name, "rocks", rings([(x / 2, y / 2, 0, 0, 0), (x * .52, y * .48, z * .48, 0, 0), (x * .28, y * .27, z, x * .08, 0)], sides, "rock", "stoneTop", seed), "Faceted loose stone; no smooth shading")
    add("treeTrunk", "trees", rings([(.32, .3, 0, 0, 0), (.21, .2, .4, 0, 0), (.16, .15, 2.3, .12, .02), (.09, .09, 3.2, .25, .02)], 6, "bark", "cutWood", 4), "Library-only trunk; not present in reference clearing")
    add("treeBranch", "trees", rings([(.13, .12, 0, 0, 0), (.085, .08, .75, .16, 0), (.035, .035, 1.4, .42, .05)], 5, "bark", "barkLight", 2), "Separate branch for tree assembly")
    add("treeCrown", "trees", rings([(.65, .6, 0, 0, 0), (1.15, .95, .45, 0, 0), (.72, .65, 1.15, .12, 0), (.15, .18, 1.5, .1, 0)], 7, "leaf", "leafLight", 3), "Angular foliage cluster; library only")
    add("firewoodLog", "wood", rings([(.13, .13, 0, 0, 0), (.12, .12, 1.55, .035, 0)], 6, "bark", "cutWood", 3), "One intact log; local +Z length, base pivot")
    add("splitFirewood", "wood", prism([(-.17, -.09), (.17, -.09), (.11, .06), (-.1, .1)], 1.2, "barkLight", "cutWood"), "One split billet; assemble stack or teepee")
    add("treeStump", "wood", rings([(.4, .36, 0, 0, 0), (.28, .27, .18, 0, 0), (.25, .25, .56, .01, 0)], 7, "bark", "cutWood", 6), "Independent stump; library only")
    add("fireCore", "fire", flame(.62, .72, "core"), "Small bright inner card; crossed assembly")
    add("flameTongue", "fire", flame(.8, 1.35, "flame"), "Outer flame card; animate scale and rotation")
    add("ember", "fire", {"vertices": [(-.035, 0, .04), (0, 0, 0), (.025, 0, .035), (0, 0, .09)], "faces": [[0, 1, 2, 3]], "materials": ["ember"]}, "Tiny rising particle card; lifetime via keyed scale")
    return assets


def writeCatalog():
    catalog = {"units": "meters", "up": "Z", "pivot": "ground or attachment base", "palette": PALETTE, "assets": makeAssets()}
    (ROOT / "assetCatalog.json").write_text(json.dumps(catalog, indent=2) + "\n")
    return catalog


def drawAtlases(catalog):
    from PIL import Image, ImageDraw, ImageFont

    output = ROOT / "atlases"
    output.mkdir(exist_ok=True)
    fontPath = "/System/Library/Fonts/Menlo.ttc"
    font = ImageFont.truetype(fontPath, 17)
    small = ImageFont.truetype(fontPath, 13)
    heading = ImageFont.truetype(fontPath, 25)
    palette = {name: tuple(bytes.fromhex(color)) for name, color in PALETTE.items()}
    views = [("FRONT / -Y", (0, -1, .001)), ("SIDE / +X", (1, 0, .001)), ("TOP / +Z", (0, -.001, 1)), ("ASSEMBLY / 3D", (1.25, -1.7, 1.3))]

    def project(asset, view, rect, image):
        vx, vy, vz = view
        magnitude = math.sqrt(vx * vx + vy * vy + vz * vz)
        normal = (vx / magnitude, vy / magnitude, vz / magnitude)
        horizontalLength = math.hypot(vx, vy)
        right = (-vy / horizontalLength, vx / horizontalLength, 0)
        up = (-normal[2] * right[1], normal[2] * right[0], normal[0] * right[1] - normal[1] * right[0])
        points = [(sum(v[i] * right[i] for i in range(3)), sum(v[i] * up[i] for i in range(3)), sum(v[i] * normal[i] for i in range(3))) for v in asset["vertices"]]
        left, top, width, height = rect
        minX, maxX = min(p[0] for p in points), max(p[0] for p in points)
        minY, maxY = min(p[1] for p in points), max(p[1] for p in points)
        scale = min((width - 48) / max(maxX - minX, .1), (height - 56) / max(maxY - minY, .1))
        coords = [(left + width / 2 + (x - (minX + maxX) / 2) * scale, top + height / 2 - (y - (minY + maxY) / 2) * scale) for x, y, z in points]
        draw = ImageDraw.Draw(image)
        ordered = sorted(enumerate(asset["faces"]), key=lambda item: sum(points[i][2] for i in item[1]) / len(item[1]))
        for index, face in ordered:
            a, b, c = [asset["vertices"][i] for i in face[:3]]
            ab, ac = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
            n = (ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0])
            length = math.sqrt(sum(x * x for x in n)) or 1
            shade = .72 + .28 * abs(sum(n[i] / length * (-.35, -.45, .82)[i] for i in range(3)))
            if asset["family"] == "fire":
                shade = 1
            color = tuple(int(channel * shade) for channel in palette[asset["materials"][index]]) + (255,)
            draw.polygon([coords[i] for i in face], fill=color)
        originX = left + width / 2 - (minX + maxX) / 2 * scale
        originY = top + height / 2 + (minY + maxY) / 2 * scale
        draw.line([(originX - 5, originY), (originX + 5, originY)], fill="#d98969", width=1)
        draw.line([(originX, originY - 5), (originX, originY + 5)], fill="#d98969", width=1)

    for asset in catalog["assets"]:
        image = Image.new("RGBA", (1280, 460))
        draw = ImageDraw.Draw(image)
        draw.text((24, 18), asset["id"], fill="#d6d8e0", font=heading)
        dimensions = " x ".join(f"{v:g}" for v in asset["dimensions"])
        draw.text((24, 54), f"{asset['family']}  /  {dimensions} m  /  {asset['triangles']} triangles", fill="#969fac", font=small)
        for i, (label, view) in enumerate(views):
            project(asset, view, (i * 320, 87, 320, 302), image)
            draw.text((i * 320 + 24, 394), label, fill="#969fac", font=small)
        draw.text((24, 430), asset["role"], fill="#969fac", font=small)
        image.save(output / f"{asset['id']}.png")

    families = list(dict.fromkeys(asset["family"] for asset in catalog["assets"]))
    for family in families:
        members = [a for a in catalog["assets"] if a["family"] == family]
        sheet = Image.new("RGBA", (1280, 460 * len(members)))
        for i, asset in enumerate(members):
            with Image.open(output / f"{asset['id']}.png") as image:
                sheet.alpha_composite(image, (0, i * 460))
        sheet.save(output / f"{family}Atlas.png")

    overview = Image.new("RGB", (1600, 1360), "#181c29")
    draw = ImageDraw.Draw(overview)
    draw.text((36, 26), "HIBERNAL / OUTDOOR COMPONENT LIBRARY", font=heading, fill="#e0e1e5")
    draw.text((36, 65), "22 independent pieces  |  shape sheets, not UV textures  |  + marks attachment pivot", font=font, fill="#9ca6b5")
    for index, asset in enumerate(catalog["assets"]):
        x, y = 30 + index % 6 * 262, 108 + index // 6 * 300
        draw.rectangle((x, y, x + 250, y + 280), fill="#222736")
        project(asset, views[-1][1], (x, y + 4, 250, 222), overview)
        draw.text((x + 12, y + 237), asset["id"], font=small, fill="#d6d8e0")
        draw.text((x + 12, y + 258), f"{asset['family']} / {asset['triangles']} tris", font=small, fill="#99a2b1")
    draw.text((36, 1330), "Reference structure: square ruins + irregular grass ribbons + small teepee fire. Trees remain library-only.", font=small, fill="#9ca6b5")
    overview.save(output / "componentOverview.png")
    print(f"Atlas: {len(catalog['assets'])} individual sheets, {len(families)} family atlases, one overview")


if __name__ == "__main__":
    drawAtlases(writeCatalog())
