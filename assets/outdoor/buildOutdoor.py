import bpy
import math
import random
from mathutils import Vector

SCENE_NAME = "OutdoorCampfire"
LIBRARY_NAME = "OutdoorLibrary"
SEED = 220926


def linearColor(hexColor):
    channels = [int(hexColor[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4 for c in channels) + (1,)


def collection(name, scene):
    result = bpy.data.collections.new(name)
    scene.collection.children.link(result)
    return result


def placeCoordinates(x, y, z=0):
    return (.83205 * x - .5547 * y, .5547 * x + .83205 * y, z)


def aimAt(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


def inPolygon(x, y, polygon):
    inside = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        ax, ay = polygon[i]
        bx, by = polygon[j]
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            inside = not inside
        j = i
    return inside


def buildGeometry(catalog):
    if bpy.data.scenes.get(SCENE_NAME) or bpy.data.scenes.get(LIBRARY_NAME):
        raise RuntimeError("Outdoor scenes already exist. Edit them in place; rebuilding requires explicitly removing the generated scenes first.")
    scene = bpy.data.scenes.new(SCENE_NAME)
    library = bpy.data.scenes.new(LIBRARY_NAME)
    scene["purpose"] = "Reference-driven modular outdoor art study; not an integrated game scene"
    scene["seed"] = SEED
    scene["atlasKind"] = "Design sheets, not UV textures"
    scene["reference"] = "User-supplied t3ssel8r campfire clearing, three orbit views"
    scene["libraryScene"] = LIBRARY_NAME
    scene["builder"] = "assets/outdoor/buildOutdoor.py"
    library["purpose"] = "All 22 reusable components, with trees kept outside the reference composition"
    groups = {name: collection(name, scene) for name in ("Terrain", "Ruins", "GrassPatches", "GroundDetails", "CampfireWood", "FirePreview", "Lighting", "Cameras")}
    masters = collection("ComponentLibrary", library)
    materials = {}
    for name, hexColor in catalog["palette"].items():
        material = bpy.data.materials.new("Outdoor_" + name)
        material.diffuse_color = linearColor(hexColor)
        material.use_nodes = True
        material.use_backface_culling = False
        shader = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        shader.inputs["Base Color"].default_value = linearColor(hexColor)
        shader.inputs["Roughness"].default_value = .94
        shader.inputs["Specular IOR Level"].default_value = .16
        if name in ("flame", "core", "ember"):
            shader.inputs["Emission Color"].default_value = linearColor(hexColor)
            shader.inputs["Emission Strength"].default_value = {"flame": 3, "core": 5, "ember": 4}[name]
        materials[name] = material
    meshes = {}
    for index, asset in enumerate(catalog["assets"]):
        mesh = bpy.data.meshes.new("Outdoor_" + asset["id"])
        mesh.from_pydata(asset["vertices"], [], asset["faces"])
        mesh.update()
        used = list(dict.fromkeys(asset["materials"]))
        for name in used:
            mesh.materials.append(materials[name])
        for polygon, materialName in zip(mesh.polygons, asset["materials"]):
            polygon.material_index = used.index(materialName)
            polygon.use_smooth = False
        mesh["assetId"] = asset["id"]
        mesh["triangleCount"] = asset["triangles"]
        master = bpy.data.objects.new(asset["id"], mesh)
        masters.objects.link(master)
        master.location = ((index % 6 - 2.5) * 3.5, (index // 6) * 4, 0)
        master["assetId"] = asset["id"]
        master["role"] = asset["role"]
        master["atlas"] = "//atlases/" + asset["id"] + ".png"
        master.asset_mark()
        master.asset_data.description = asset["role"]
        meshes[asset["id"]] = mesh

    def instance(assetId, name, group, xy, z=0, scale=(1, 1, 1), rotation=0):
        obj = bpy.data.objects.new(name, meshes[assetId])
        groups[group].objects.link(obj)
        obj.location = placeCoordinates(xy[0], xy[1], z)
        obj.scale = scale
        obj.rotation_euler.z = rotation
        obj["assetId"] = assetId
        return obj

    instance("groundTile", "groundFoundation", "Terrain", (0, 0), -.1, (120, 120, 1.25))
    patchData = [(-.1, .4, 1.75, 1.55), (-2, 1.3, 1.7, 1.15), (1.6, .8, 1.6, 1.25), (-3.8, -.5, 1.8, 1), (-4.7, -3.8, 1.7, .9), (4.5, 1, 1.4, .8)]
    for i, (x, y, sx, sy) in enumerate(patchData):
        instance("clearingPatch", "soilPatch_%02d" % i, "Terrain", (x, y), .001 + i * .001, (sx, sy, .4), i * .41)
    pillarData = [(-2.7, 2.1, 4.25, 1), (-4.15, -.4, 3.65, .92), (-2.5, -2.65, 2.5, 1.05), (.3, 3.15, 2.25, .95), (3.5, .5, 3.2, 1), (-6.1, 6.2, 2.45, 1), (-7.4, 4.6, 1.6, .85), (5.8, 6.8, 3.5, .9)]
    blockers = []
    for i, (x, y, height, width) in enumerate(pillarData):
        assetId = "pillarTall" if height > 2.8 else "pillarShort"
        baseHeight = 4.2 if assetId == "pillarTall" else 2.2
        instance(assetId, "ruinPillar_%02d" % i, "Ruins", (x, y), 0, (width, width, height / baseHeight))
        blockers.append((x, y, .66 * width))
    slabData = [(-6.1, -2.8, 1.3, 0), (4.5, 1.7, .85, .03), (-6.1, 5.4, .9, .08), (7, 5.6, 1.05, .1), (6.2, 4.65, .55, 0)]
    for i, (x, y, scale, angle) in enumerate(slabData):
        instance("stoneSlab", "fallenSlab_%02d" % i, "Ruins", (x, y), 0, (scale, scale, 1), angle)
        blockers.append((x, y, 1.2 * scale))
    for i in range(4):
        instance("stoneStep", "stairTread_%02d" % i, "Ruins", (3.05 + i * .56, -2.35 - i * .75), 0, (1, 1, (1.05 - i * .2) / .28))
        blockers.append((3.05 + i * .56, -2.35 - i * .75, .8))
    for i, (x, y) in enumerate([(-8, 5), (7.7, 7.3), (-8.4, -1.3)]):
        instance("groundLedge", "perimeterLedge_%02d" % i, "Terrain", (x, y), -.15, (1.2, 1.7, .6), i * .15)

    polygons = [
        [(-4.1, 2.4), (-2.9, 3.4), (-1.2, 3.1), (.2, 3.8), (2.1, 3.15), (2.8, 1.3), (3.55, .6), (3, -.8), (1.7, -1.8), (.5, -1.6), (-.8, -1.25), (-2.1, -1.5), (-3.7, -.3)],
        [(-5.5, 5), (-4.5, 4.4), (-4.05, 2.3), (-3.9, .5), (-4.4, -.8), (-5.3, -.2), (-5, 1.8), (-6.3, 3.5)],
        [(-6, -3.5), (-4.4, -3.1), (-3.4, -2.6), (-2.8, -3), (-3, -4.5), (-4.25, -5.1), (-5.8, -4.7)],
        [(2.8, .2), (4.6, 1.25), (5.8, .9), (6.1, -.2), (4.8, -.8), (3.8, -1.4)],
        [(-7.5, 6), (-6.2, 6.4), (-5.8, 7.7), (-7.4, 7.4)],
    ]
    rng = random.Random(SEED)
    grassCount = 0
    for patchIndex, polygon in enumerate(polygons):
        patchRoot = bpy.data.objects.new("grassPatch_%02d" % patchIndex, None)
        groups["GrassPatches"].objects.link(patchRoot)
        patchRoot["seed"] = SEED + patchIndex
        patchRoot["role"] = "Move or hide the entire grass patch through this parent"
        minimumX, maximumX = min(p[0] for p in polygon), max(p[0] for p in polygon)
        minimumY, maximumY = min(p[1] for p in polygon), max(p[1] for p in polygon)
        attempts = int((maximumX - minimumX) * (maximumY - minimumY) * 42)
        for attempt in range(attempts):
            x, y = rng.uniform(minimumX, maximumX), rng.uniform(minimumY, maximumY)
            if not inPolygon(x + .12 * math.sin(y * 9), y + .12 * math.sin(x * 8), polygon):
                continue
            if math.hypot(x, y) < .78 or any(math.hypot(x - bx, y - by) < radius for bx, by, radius in blockers):
                continue
            assetId = "grassTall" if rng.random() < .18 else "grassTuft"
            scale = rng.uniform(.72, 1.3)
            obj = instance(assetId, "grass_%04d" % grassCount, "GrassPatches", (x, y), .01, (scale, scale, rng.uniform(.7, 1.08)), rng.uniform(0, math.tau))
            obj.parent = patchRoot
            grassCount += 1
    for i, (x, y) in enumerate([(-7, -5), (-6.5, -5.8), (-5.5, -6), (-1.8, -6.1), (2.1, -5.7), (6.6, -4), (6.8, .1), (-6.7, 1.2), (-4.9, 5.2), (1, 5.5), (5.3, 3.1), (-8, -.6), (.4, -3.5), (7.6, 1.7), (-.7, 6.9), (3.1, 7)]):
        instance("broadleafSprig", "sprig_%02d" % i, "GroundDetails", (x, y), 0, (.75, .75, .75), rng.uniform(0, math.tau))
    for i, (x, y, scale) in enumerate([(-5.3, 2.8, .55), (5.2, 3.3, .6), (-7, -3.2, .35), (6.2, -2.1, .4), (-3, 5.8, .5)]):
        instance("rockMedium", "looseRock_%02d" % i, "GroundDetails", (x, y), 0, (scale, scale, scale), rng.uniform(0, math.tau))
    for i in range(9):
        angle = i * math.tau / 9
        instance("rockSmall", "hearthStone_%02d" % i, "CampfireWood", (math.cos(angle) * .68, math.sin(angle) * .68), .01, (1.1, 1.1, .7), angle)
    for i in range(4):
        angle = math.pi / 4 + i * math.tau / 4
        bottom = Vector(placeCoordinates(math.cos(angle) * .82, math.sin(angle) * .82, .1))
        top = Vector(placeCoordinates(math.cos(angle) * .1, math.sin(angle) * .1, 1.38))
        log = instance("splitFirewood", "teepeeLog_%02d" % i, "CampfireWood", (0, 0))
        log.location = bottom
        log.rotation_euler = (top - bottom).to_track_quat('Z', 'Y').to_euler()
        log.scale = (.9, .9, (top - bottom).length / 1.2)
    for i in range(3):
        log = instance("firewoodLog", "spareLog_%02d" % i, "CampfireWood", (-1.05 - i * .17, .6 + (i % 2) * .15), .13 + (i // 2) * .18, (.85, .85, .75))
        log.rotation_euler = (math.pi / 2, .12, -.8)
    for i in range(3):
        tongue = instance("flameTongue", "flameOuter_%02d" % i, "FirePreview", (0, 0), .08, (.78, .78, .78), i * math.pi / 3)
        core = instance("fireCore", "flameCore_%02d" % i, "FirePreview", (0, -.08), .06, (1, 1, 1), i * math.pi / 3 + .2)
        for obj in (tongue, core):
            obj["previewOnly"] = True
            baseScale = obj.scale.copy()
            for frame in range(1, 122, 8):
                obj.scale = (baseScale.x * rng.uniform(.83, 1.13), baseScale.y, baseScale.z * rng.uniform(.72, 1.15))
                obj.keyframe_insert(data_path="scale", frame=frame)
    for i in range(20):
        obj = instance("ember", "ember_%02d" % i, "FirePreview", (0, 0), .3, rotation=rng.uniform(0, math.tau))
        obj["previewOnly"] = True
        start = 1 + i * 5
        x, y = rng.uniform(-.35, .35), rng.uniform(-.25, .25)
        for frame, height, scale in [(start - 1, .3, 0), (start, .4, .5), (start + 16, 1.35, 1), (start + 36, 2.5, .65), (start + 44, 3, 0)]:
            obj.location = placeCoordinates(x + (height - .3) * .13, y, height)
            obj.scale = (scale, scale, scale)
            obj.keyframe_insert(data_path="location", frame=frame)
            obj.keyframe_insert(data_path="scale", frame=frame)
    scene.frame_start, scene.frame_end = 1, 120
    scene.render.fps = 24
    scene.frame_set(48)
    bpy.context.window.scene = scene
    print("Built", len(meshes), "shared component meshes;", grassCount, "grass instances;", len(scene.objects), "scene objects")
    return scene


def setupPreview(scene):
    world = bpy.data.worlds.new("OutdoorNight")
    world.use_nodes = True
    background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    background.inputs["Color"].default_value = (.015, .018, .06, 1)
    background.inputs["Strength"].default_value = .2
    scene.world = world
    scene.render.resolution_x, scene.render.resolution_y = 480, 270
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.eevee.taa_render_samples = 64


def addLightingAndCameras(scene):
    lights = scene.collection.children["Lighting"]
    cameras = scene.collection.children["Cameras"]

    def light(name, kind, position, energy, color, radius):
        data = bpy.data.lights.new(name, kind)
        obj = bpy.data.objects.new(name, data)
        lights.objects.link(obj)
        obj.location = position
        data.energy, data.color = energy, color
        if kind == "POINT":
            data.shadow_soft_size = radius
        elif kind == "AREA":
            data.size = radius
            aimAt(obj, (0, 0, 0))
        elif kind == "SUN":
            data.angle = radius
            aimAt(obj, (0, 0, 0))
        return obj

    fire = light("fireKey", "POINT", (0, 0, 1.4), 2300, (1, .34, .13), .25)
    for frame, energy in [(1, 1100), (15, 1250), (29, 1080), (42, 1180), (55, 1120), (68, 1280), (81, 1090), (95, 1190), (109, 1130), (120, 1100)]:
        fire.data.energy = energy * 2
        fire.data.keyframe_insert(data_path="energy", frame=frame)
    light("moonRim", "SUN", (-6, -4, 10), 2.2, (.28, .38, .75), .14)
    light("nightFill", "AREA", (2, -4, 10), 1250, (.23, .32, .65), 15)
    for name, position in [("cameraMain", (12, -18, 16)), ("cameraOrbitLeft", (-17, -13, 16)), ("cameraOrbitBack", (-13, 17, 16))]:
        data = bpy.data.cameras.new(name)
        obj = bpy.data.objects.new(name, data)
        cameras.objects.link(obj)
        obj.location = position
        aimAt(obj, (0, 0, .8))
        data.type = "ORTHO"
        data.ortho_scale = 20.4
        data.lens = 48
        data.clip_end = 300
        obj["purpose"] = "Orbit check of true 3D composition, not a billboard set"
    scene.camera = bpy.data.objects["cameraMain"]
    scene.frame_set(48)
    for area in bpy.context.screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.region_3d.view_perspective = "CAMERA"
            area.spaces.active.overlay.show_overlays = False
    print("Preview lighting and three orthographic cameras ready")


def setupBloom(scene):
    group = bpy.data.node_groups.new("OutdoorPixelPreview", "CompositorNodeTree")
    group.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    source = group.nodes.new("CompositorNodeRLayers")
    source.scene = scene
    source.location = (-280, 0)
    bloom = group.nodes.new("CompositorNodeGlare")
    bloom.inputs["Type"].default_value = "Fog Glow"
    bloom.inputs["Threshold"].default_value = 1.3
    bloom.inputs["Strength"].default_value = .3
    bloom.inputs["Size"].default_value = .35
    bloom.location = (0, 0)
    output = group.nodes.new("NodeGroupOutput")
    output.location = (240, 0)
    group.links.new(source.outputs["Image"], bloom.inputs["Image"])
    group.links.new(bloom.outputs["Image"], output.inputs["Image"])
    scene.compositing_node_group = group
    scene.render.use_compositing = True
    scene["previewPipeline"] = "480x270 EEVEE + restrained Fog Glow; nearest-neighbor enlargement outside Blender"
