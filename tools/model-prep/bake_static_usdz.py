#!/usr/bin/env python3
"""Bake a rigged (UsdSkel) USDZ into a static mesh USDZ.

RealityKit reports visualBounds from a skinned mesh's unskinned geometry, which can differ from
what it renders (e.g. rotated 90 degrees). Kingdom sizes animals from those bounds, so rigged
assets must be baked to static geometry before bundling. One animation frame (default time 0) or
the rest pose is baked; animations are dropped.

Usage:
    tools/tag-gen/.venv/bin/python tools/model-prep/bake_static_usdz.py IN.usdz OUT.usdz
"""

import argparse
import shutil
import tempfile
import zipfile
from pathlib import Path

from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdSkel, UsdUtils


def bake(source: Path, destination: Path, time: float = 0.0, rest_pose: bool = False):
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        with zipfile.ZipFile(source) as archive:
            archive.extractall(work)
        roots = [p for p in work.iterdir() if p.suffix in (".usdc", ".usda", ".usd")]
        if len(roots) != 1:
            raise SystemExit("Expected one root layer in %s, found %s" % (source, roots))
        layer_path = roots[0]
        stage = Usd.Stage.Open(str(layer_path))

        # Some exporters author skel:animationSource on meshes, where UsdSkel ignores it; it is only
        # honored on the Skeleton (or an ancestor). Move it there, or drop it to use the rest pose.
        for prim in stage.Traverse():
            binding = UsdSkel.BindingAPI(prim)
            source_rel = binding.GetAnimationSourceRel()
            if not source_rel or prim.IsA(UsdSkel.Skeleton):
                continue
            targets = source_rel.GetTargets()
            skeleton_targets = binding.GetSkeletonRel().GetTargets() if binding.GetSkeletonRel() else []
            prim.RemoveProperty(source_rel.GetName())
            if rest_pose or not targets:
                continue
            for skeleton_path in skeleton_targets:
                skeleton = stage.GetPrimAtPath(skeleton_path)
                skeleton_binding = UsdSkel.BindingAPI.Apply(skeleton)
                skeleton_binding.CreateAnimationSourceRel().SetTargets(targets[:1])

        skinned = [p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh) and p.HasAPI(UsdSkel.BindingAPI)]
        if not skinned:
            raise SystemExit("%s has no skinned meshes; nothing to bake" % source)

        if not UsdSkel.BakeSkinning(stage.Traverse(), Gf.Interval(time, time)):
            raise SystemExit("UsdSkel.BakeSkinning failed")

        for prim in skinned:
            # Move baked samples to default values so the mesh is fully static.
            for name in ("points", "normals", "extent"):
                attr = prim.GetAttribute(name)
                if attr and attr.GetNumTimeSamples():
                    value = attr.Get(attr.GetTimeSamples()[0])
                    attr.Clear()
                    attr.Set(value)
            for prop in list(prim.GetPropertyNames()):
                if prop.startswith("skel:") or prop.startswith("primvars:skel:"):
                    prim.RemoveProperty(prop)
            schemas = prim.GetAppliedSchemas()
            if "SkelBindingAPI" in schemas:
                prim.RemoveAPI(UsdSkel.BindingAPI)

        for prim in list(stage.Traverse()):
            if prim.IsA(UsdSkel.Skeleton) or prim.IsA(UsdSkel.Animation):
                stage.RemovePrim(prim.GetPath())
        for prim in list(stage.Traverse()):
            if prim.IsA(UsdSkel.Root):
                prim.SetTypeName("Xform")

        for prim in stage.Traverse():
            if prim.GetRelationship("material:binding") and not prim.HasAPI(UsdShade.MaterialBindingAPI):
                UsdShade.MaterialBindingAPI.Apply(prim)

        stage.ClearMetadata("startTimeCode")
        stage.ClearMetadata("endTimeCode")
        stage.GetRootLayer().Save()

        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            destination.unlink()
        if not UsdUtils.CreateNewARKitUsdzPackage(Sdf.AssetPath(str(layer_path)), str(destination)):
            raise SystemExit("Failed to write %s" % destination)

    check = Usd.Stage.Open(str(destination))
    leftovers = [p.GetPath() for p in check.Traverse() if p.IsA(UsdSkel.Skeleton) or p.HasAPI(UsdSkel.BindingAPI)]
    if leftovers:
        raise SystemExit("Skeleton data remains: %s" % leftovers)
    bounds = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_]).ComputeWorldBound(check.GetPseudoRoot()).ComputeAlignedRange()
    print("Wrote %s  (%d skinned meshes baked)  world extent %s" % (destination, len(skinned), bounds.GetSize()))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--time", type=float, default=0.0, help="animation time code to bake (default 0)")
    parser.add_argument("--rest-pose", action="store_true", help="bake the skeleton rest pose instead of an animation frame")
    args = parser.parse_args()
    bake(args.source.resolve(), args.destination.resolve(), args.time, args.rest_pose)


if __name__ == "__main__":
    main()
