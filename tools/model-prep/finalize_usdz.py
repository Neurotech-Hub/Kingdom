#!/usr/bin/env python3
"""Bring a static USDZ in line with ARKit/usdchecker conventions before bundling it in Kingdom.

- Applies MaterialBindingAPI wherever material:binding is authored without it (Sketchfab exports).
- Moves root prims other than the default prim beneath it (Blender writes /_materials at the root).
- Rotates Z-up stages (Blender) to Y-up.
- Optionally restores the original texture files by name (Blender re-encodes JPEGs).

Geometry is not otherwise changed. Usage:
    tools/tag-gen/.venv/bin/python tools/model-prep/finalize_usdz.py IN.usdz OUT.usdz \
        [--textures-from ORIGINAL.usdz]
"""

import argparse
import tempfile
import zipfile
from pathlib import Path

from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils


def retarget(layer: Sdf.Layer, old_prefix: Sdf.Path, new_prefix: Sdf.Path):
    def fix(paths):
        return [p.ReplacePrefix(old_prefix, new_prefix) for p in paths]

    def visit(path):
        spec = layer.GetObjectAtPath(path)
        if isinstance(spec, Sdf.RelationshipSpec):
            items = list(spec.targetPathList.GetAddedOrExplicitItems())
            if any(p.HasPrefix(old_prefix) for p in items):
                spec.targetPathList.explicitItems = fix(items)
        elif isinstance(spec, Sdf.AttributeSpec):
            items = list(spec.connectionPathList.GetAddedOrExplicitItems())
            if any(p.HasPrefix(old_prefix) for p in items):
                spec.connectionPathList.explicitItems = fix(items)

    layer.Traverse(Sdf.Path.absoluteRootPath, visit)


def finalize(source: Path, destination: Path, textures_from: Path = None):
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        with zipfile.ZipFile(source) as archive:
            archive.extractall(work)
        roots = [p for p in work.iterdir() if p.suffix in (".usdc", ".usda", ".usd")]
        if len(roots) != 1:
            raise SystemExit("Expected one root layer in %s, found %s" % (source, roots))

        if textures_from:
            with zipfile.ZipFile(textures_from) as archive:
                originals = {Path(n).name: n for n in archive.namelist()
                             if n.lower().endswith((".png", ".jpg", ".jpeg"))}
                for exported in work.rglob("*"):
                    if exported.name in originals:
                        exported.write_bytes(archive.read(originals[exported.name]))
                        print("Restored original texture %s" % exported.name)

        stage = Usd.Stage.Open(str(roots[0]))
        layer = stage.GetRootLayer()
        default_prim = stage.GetDefaultPrim()
        if not default_prim:
            raise SystemExit("%s has no default prim" % source)

        for prim in list(stage.GetPseudoRoot().GetChildren()):
            if prim == default_prim:
                continue
            new_path = default_prim.GetPath().AppendChild(prim.GetName())
            Sdf.CopySpec(layer, prim.GetPath(), layer, new_path)
            retarget(layer, prim.GetPath(), new_path)
            edit = Sdf.BatchNamespaceEdit()
            edit.Add(Sdf.NamespaceEdit.Remove(prim.GetPath()))
            if not layer.Apply(edit):
                raise SystemExit("Could not remove %s" % prim.GetPath())
            print("Moved %s under %s" % (prim.GetPath(), default_prim.GetPath()))

        if UsdGeom.GetStageUpAxis(stage) == UsdGeom.Tokens.z:
            xformable = UsdGeom.Xformable(default_prim)
            local = xformable.GetLocalTransformation()
            z_up_to_y_up = Gf.Matrix4d().SetRotate(Gf.Rotation(Gf.Vec3d(1, 0, 0), -90))
            xformable.ClearXformOpOrder()
            xformable.AddTransformOp().Set(local * z_up_to_y_up)
            UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
            print("Converted Z-up stage to Y-up")

        applied = 0
        for prim in stage.Traverse():
            if prim.GetRelationship("material:binding") and not prim.HasAPI(UsdShade.MaterialBindingAPI):
                UsdShade.MaterialBindingAPI.Apply(prim)
                applied += 1
        if applied:
            print("Applied MaterialBindingAPI to %d prims" % applied)

        layer.Save()
        UsdUtils.CreateNewARKitUsdzPackage(Sdf.AssetPath(str(roots[0])), str(destination))
        print("Wrote %s" % destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--textures-from", type=Path, help="Original USDZ whose texture files should be restored")
    args = parser.parse_args()
    finalize(args.source.resolve(), args.destination.resolve(),
             args.textures_from.resolve() if args.textures_from else None)


if __name__ == "__main__":
    main()
