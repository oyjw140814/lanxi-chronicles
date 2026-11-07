#!/usr/bin/env python3
"""岚汐纪 original procedural asset kit for Houdini 20.5+.

Run with Houdini's hython, not the system Python:
  hython generate_assets.py --output ./generated --seed 42 --size 80
This script creates a HIP scene, per-asset BGeo, LODs and simple collision meshes.
--export-glb also tries the installed glTF SOP exporter, failing visibly if unsupported.
No third-party assets, Houdini Engine, or proprietary game data are used.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path

# Self-contained source stored in Python SOPs, so the resulting HIP can reopen alone.
GEOMETRY_SOURCE = r'''
import hou, math, random
node = hou.pwd()
geo = node.geometry()
geo.clear()
geo.addAttrib(hou.attribType.Point, "Cd", (1.0, 1.0, 1.0))
geo.addAttrib(hou.attribType.Prim, "name", "")
rng = random.Random(SEED)

def polygon(vertices, color, part):
    primitive = geo.createPolygon()
    for vertex in vertices:
        point = geo.createPoint()
        point.setPosition(hou.Vector3(vertex))
        point.setAttribValue("Cd", color)
        primitive.addVertex(point)
    primitive.setAttribValue("name", part)

def box(pos, size, color, part):
    x,y,z = pos
    a,b,c = [n/2.0 for n in size]
    pts = [(x-a,y-b,z-c),(x+a,y-b,z-c),(x+a,y+b,z-c),(x-a,y+b,z-c),
           (x-a,y-b,z+c),(x+a,y-b,z+c),(x+a,y+b,z+c),(x-a,y+b,z+c)]
    for indices in [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2),(0,1,5,4)]:
        polygon([pts[i] for i in indices],color,part)

def tube(pos, bottom, top, height, color, part, sides=12):
    x,y,z = pos
    rings = []
    for h,radius in [(-height/2,bottom),(height/2,top)]:
        rings.append([(x+math.sin(i*math.tau/sides)*radius,y+h,z+math.cos(i*math.tau/sides)*radius) for i in range(sides)])
    polygon(list(reversed(rings[0])),color,part)
    polygon(rings[1],color,part)
    for i in range(sides):
        j=(i+1)%sides
        polygon([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],color,part)

def crystal(pos,r,h,color,part):
    tube(pos,r,0.001,h,color,part,5)

stone = (0.72,0.68,0.53) if TEAM == 0 else (0.61,0.43,0.34)
light = (0.92,0.83,0.63) if TEAM == 0 else (0.86,0.64,0.45)
roof = (0.09,0.40,0.37) if TEAM == 0 else (0.50,0.16,0.13)
metal = (0.66,0.40,0.20) if TEAM == 0 else (0.24,0.23,0.26)
glow = (0.30,0.84,0.65) if TEAM == 0 else (1.0,0.45,0.16)
wood = (0.27,0.23,0.16)

if KIND in ('heart','house','barracks','tower'):
    radius = {'heart':2.65,'house':1.55,'barracks':2.10,'tower':1.25}[KIND]
    tube((0,.12,0),radius+.18,radius+.18,.24,metal,'foundation_trim')
    tube((0,.31,0),radius+.08,radius,.18,light,'foundation')
    if KIND == 'heart':
        tube((0,1.20,0),2.18,2.05,1.60,stone,'hall')
        tube((0,2.08,0),2.90,2.80,.13,metal,'roof_rim')
        tube((0,2.67,0),2.85,1.02,1.12,roof,'canopy',12 if TEAM == 0 else 6)
        for i in range(8):
            a=i*math.tau/8
            x,z=math.sin(a)*2.07,math.cos(a)*2.07
            tube((x,1.25,z),.10,.085,1.7,light,'column',6)
        tube((0,3.25,0),1.06,1.06,.17,metal,'lantern_floor',10)
        for i in range(4):
            a=i*math.tau/4+math.pi/4
            tube((math.sin(a)*.72,3.89,math.cos(a)*.72),.065,.05,1.3,light,'lantern_column',6)
        crystal((0,3.98,0),.42,1.25,glow,'tide_core')
        tube((0,4.72,0),1.18,.10,.68,roof,'lantern_roof',10 if TEAM == 0 else 6)
        box((0,1.05,2.13),(.94,1.30,.13),wood,'door')
        for i in range(3):
            box((0,.10+i*.12,2.90-i*.25),(1.4,.13,.40),light,'step')
    elif KIND == 'house':
        tube((0,1.02,0),1.25,1.14,1.3,stone,'walls',8)
        tube((0,1.74,0),1.52,1.52,.13,metal,'roof_trim',8)
        tube((0,2.36,0),1.62,.13,1.13,roof,'sail_roof',8 if TEAM == 0 else 4)
        box((0,.87,1.18),(.51,.94,.12),wood,'door')
        tube((.73,2.35,-.3),.18,.18,.77,stone,'chimney',6)
        tube((.73,2.75,-.3),.24,.24,.12,metal,'chimney_cap',6)
    elif KIND == 'barracks':
        box((0,1.15,0),(3.65,1.5,2.55),stone,'hall')
        box((0,1.94,0),(3.95,.14,2.82),metal,'eaves')
        # Ridge roof built as explicit faces with a long jade silhouette.
        pts=[(-2.1,1.99,-1.57),(0,3.02,-1.57),(2.1,1.99,-1.57),(-2.1,1.99,1.57),(0,3.02,1.57),(2.1,1.99,1.57)]
        for face in [(0,3,4,1),(1,4,5,2),(0,1,2),(3,5,4)]:
            polygon([pts[i] for i in face],roof,'sail_roof')
        box((0,3.05,0),(.12,.12,3.3),metal,'ridge')
        box((0,1.05,1.3),(.93,1.3,.12),wood,'door')
        for side in [-1,1]:
            box((side*1.73,1.15,1.3),(.15,1.65,.18),light,'buttress')
    else:
        tube((0,1.98,0),.9,.65,3.15,stone,'tower',8)
        tube((0,3.66,0),1.25,1.25,.2,metal,'parapet_floor',8)
        for i in range(6):
            a=i*math.tau/6
            box((math.sin(a),3.94,math.cos(a)),(.3,.44,.3),light,'merlon')
        tube((0,4.81,0),.95,.10,.62,roof,'watch_roof',8 if TEAM == 0 else 6)
        crystal((0,5.30,0),.13,.32,glow,'beacon')
elif KIND == 'tree':
    height=3.0+rng.random()*.6
    tube((0,height*.34,0),.21,.09,height*.68,wood,'trunk',7)
    for i in range(3):
        a=i*math.tau/3
        tube((math.sin(a)*.28,height*.75+i*.17,math.cos(a)*.28),1.0-i*.16,.24,1.35-i*.12,(.22+i*.045,.43+i*.05,.32+i*.025),'canopy',8)
elif KIND == 'ore':
    tube((0,.22,0),.77,.57,.45,(.34,.43,.43),'stone',7)
    for i in range(5):
        a=i*math.tau/5
        height=.8+(i%3)*.25
        crystal((math.sin(a)*.43,height*.5,math.cos(a)*.43),.23,height,(.40,.72,.63),'crystal')
elif KIND == 'berry':
    for i in range(4):
        a=i*math.tau/4
        x,z=math.sin(a)*.30,math.cos(a)*.30
        tube((x,.4,z),.35,.16,.65,(.22,.43,.29),'leaves',7)
        tube((x+.08,.72,z),.11,.07,.15,(.88,.49,.22),'fruit',6)
elif KIND == 'terrain':
    cells=max(20,int(SIZE/2))
    step=SIZE/cells
    for z in range(cells):
        for x in range(cells):
            color=(.33+.035*math.sin(x*.3),.49+.03*math.cos(z*.2),.35)
            # Flat gameplay surface, originating at (0,0,0), 0..SIZE on X/Z.
            polygon([(x*step,0,z*step),((x+1)*step,0,z*step),((x+1)*step,0,(z+1)*step),(x*step,0,(z+1)*step)],color,'terrain')
'''


def build_asset(hou, parent, kind, team, seed, size, output):
    geo = parent.createNode("geo", f"{kind}_team{team}")
    for child in geo.children():
        child.destroy()
    source = geo.createNode("python", "PARAMETRIC_SOURCE")
    parameters = f"SEED={seed}\nSIZE={size!r}\nTEAM={team}\nKIND={kind!r}\n"
    source.parm("python").set(parameters + GEOMETRY_SOURCE)
    normal = geo.createNode("normal", "NORMALS")
    normal.setInput(0, source)
    lod0 = geo.createNode("null", "OUT_LOD0")
    lod0.setInput(0, normal)
    lod0.setDisplayFlag(True)
    lod0.setRenderFlag(True)
    source.cook(force=True)
    errors = source.errors()
    if errors:
        raise RuntimeError(f"{source.path()}: {errors}")
    lod0.geometry().saveToFile(str(output / f"{kind}_team{team}_lod0.bgeo.sc"))
    # PolyReduce parameters vary between Houdini builds; reduction setup is inspected.
    reduce_types = [n for n in hou.sopNodeTypeCategory().nodeTypes() if n == "polyreduce::2.0" or n == "polyreduce"]
    lods = [lod0]
    if reduce_types and kind != "terrain":
        for level, percentage in [(1, 55), (2, 28)]:
            reduce = geo.createNode(reduce_types[0], f"REDUCE_LOD{level}")
            reduce.setInput(0, normal)
            parm = reduce.parm("percentage") or reduce.parm("percent")
            if parm is None:
                reduce.destroy()
                continue
            parm.set(percentage)
            lod = geo.createNode("null", f"OUT_LOD{level}")
            lod.setInput(0, reduce)
            lod.geometry().saveToFile(str(output / f"{kind}_team{team}_lod{level}.bgeo.sc"))
            lods.append(lod)
    radius = {"heart":2.8,"house":1.6,"barracks":2.1,"tower":1.25,"tree":.65,"ore":.85,"berry":.65}.get(kind)
    if radius:
        collision = geo.createNode("tube", "COLLISION_CYLINDER")
        collision.parmTuple("rad").set((radius, radius))
        collision.parm("height").set(1.0)
        collision.parmTuple("t").set((0,.5,0))
        collider = geo.createNode("null", "OUT_COLLISION")
        collider.setInput(0, collision)
    geo.layoutChildren()
    return geo, lods


def export_glb(hou, geometry_node, source, filename):
    node_types = hou.sopNodeTypeCategory().nodeTypes()
    available = sorted(name for name in node_types if name.split("::")[0] == "rop_gltf")
    if not available:
        raise RuntimeError("This Houdini build has no glTF ROP SOP. Export OUT_LOD0 using File > Export > glTF, or install a supported Houdini build.")
    exporter = geometry_node.createNode(available[-1], "EXPORT_GLB")
    exporter.setInput(0, source)
    path_parm = next((exporter.parm(name) for name in ("file","filename","sopoutput","output") if exporter.parm(name)), None)
    if path_parm is None:
        labels = [(p.name(), p.description()) for p in exporter.parms()]
        raise RuntimeError(f"Unknown glTF output parameters: {labels}")
    path_parm.set(str(filename))
    execute = exporter.parm("execute")
    if execute is not None:
        execute.pressButton()
    elif hasattr(exporter, "render"):
        exporter.render()
    else:
        raise RuntimeError(f"Cannot execute {exporter.path()}; configure and render it in Houdini UI.")
    if not filename.is_file() or filename.stat().st_size == 0:
        raise RuntimeError(f"Exporter did not produce {filename}. Check license and exporter diagnostics.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("generated"))
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--size", type=float, default=80)
    parser.add_argument("--export-glb", action="store_true")
    args = parser.parse_args()
    if args.size <= 0 or args.size > 512:
        parser.error("--size must be in (0, 512]")
    try:
        import hou
    except ImportError as exc:
        raise SystemExit("Run this script with Houdini's hython. The system Python has no hou module.") from exc
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    obj = hou.node("/obj")
    # Keep existing scenes intact: create a uniquely named subnet, never clear the scene.
    kit = obj.createNode("subnet", "lanxi_original_kit", force_valid_node_name=True)
    records = []
    export_errors = []
    for kind in ("heart","house","barracks","tower","tree","ore","berry","terrain"):
        for team in ([0,1] if kind in ("heart","house","barracks","tower") else [0]):
            node, lods = build_asset(hou, kit, kind, team, args.seed, args.size, output)
            node.setPosition(hou.Vector2(len(records)%4*4, -(len(records)//4)*3))
            records.append({"kind":kind,"team":team,"node":node.path(),"lods":[n.name() for n in lods]})
            if args.export_glb:
                for index, lod in enumerate(lods):
                    try:
                        export_glb(hou,node,lod,output/f"{kind}_team{team}_lod{index}.glb")
                    except Exception as exc:
                        export_errors.append(str(exc))
    # The license determines whether Houdini saves .hip, .hiplc or .hipnc.
    scene_file = output / "lanxi_asset_kit.hip"
    hou.hipFile.save(str(scene_file))
    manifest = {"project":"岚汐纪","seed":args.seed,"size_m":args.size,"axis":"+Y up, -Z forward","origin":"ground centre; terrain uses southwest (0,0)","units":"metres","houdini_version":hou.applicationVersionString(),"license":str(hou.licenseCategory()),"assets":records,"export_errors":export_errors}
    (output/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    print(f"Created {len(records)} original assets at {output}")
    if export_errors:
        raise SystemExit("Scene and BGeo saved; GLB export had errors:\n"+"\n".join(export_errors))


if __name__ == "__main__":
    main()
