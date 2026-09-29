"""Decimate a static USDZ with Blender and write a lighter USDZ.

Heavy scans (millions of vertices) bloat the app bundle and cost frame time on device. This keeps
materials/UVs and collapses geometry to a target vertex budget. The source file is not modified.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
        --python tools/model-prep/decimate_usdz_blender.py -- IN.usdz OUT.usdz [--target-vertices 300000]

Blender's output is Z-up with materials outside the default prim; run finalize_usdz.py on it next.
"""

import argparse
import sys

import bmesh
import bpy


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("destination")
    parser.add_argument("--target-vertices", type=int, default=300_000)
    args = parser.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=args.source)

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    print("Imported %d vertices" % sum(len(o.data.vertices) for o in meshes))

    # Scans exported via glTF often store unwelded triangles, which the collapse decimator cannot
    # simplify. Weld coincident vertices first; UVs live on face corners and are preserved.
    for obj in meshes:
        mesh = bmesh.new()
        mesh.from_mesh(obj.data)
        bmesh.ops.remove_doubles(mesh, verts=mesh.verts, dist=1e-6)
        mesh.to_mesh(obj.data)
        mesh.free()

    total = sum(len(o.data.vertices) for o in meshes)
    ratio = min(1.0, args.target_vertices / max(total, 1))
    print("Decimating %d meshes, %d vertices, ratio %.4f" % (len(meshes), total, ratio))

    if ratio < 1.0:
        for obj in meshes:
            modifier = obj.modifiers.new(name="Decimate", type="DECIMATE")
            modifier.decimate_type = "COLLAPSE"
            modifier.ratio = ratio
            modifier.use_collapse_triangulate = True
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.modifier_apply(modifier=modifier.name)

    after = sum(len(o.data.vertices) for o in meshes)
    print("Result vertices: %d" % after)

    bpy.ops.wm.usd_export(
        filepath=args.destination,
        selected_objects_only=False,
        export_materials=True,
        export_uvmaps=True,
        export_normals=True,
        export_animation=False,
        generate_preview_surface=True,
        export_textures=True,
        overwrite_textures=True,
    )
    print("Wrote %s" % args.destination)


main()
