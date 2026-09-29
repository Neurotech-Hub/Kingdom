# Kingdom

An iOS augmented-reality app that shows animals at true physical scale on small etched tags. Point an iPhone at a Kingdom tag and a 3D model of that animal appears on it; several tags in view give side-by-side size comparisons.

The app opens to a catalog of every animal (3D preview, scientific name, dimensions, tag number). The **Open AR viewer** button starts the camera, which recognizes each tag by its AprilTag and anchors the matching animal to it.

## Repository layout

| Path | Contents |
| --- | --- |
| `app/iOS/Kingdom/` | Xcode project (SwiftUI, ARKit, RealityKit, SceneKit) |
| `app/iOS/Kingdom/Packages/AprilTagKit/` | Local Swift package wrapping the vendored AprilRobotics `apriltag` C library |
| `tags/` | Laser-etch artwork for each tag (SVG, DXF, PLT, PDF, PNG, BMP) plus a full sheet |
| `tools/tag-gen/` | Generates `tags/` from the app catalog |
| `tools/model-prep/` | Scripts that turn source USDZ files into app-ready models |
| `tools/brand-gen/` | Renders the app icon and launch assets from the logo |
| `brand/` | Logo, identity artwork, and Plus Jakarta Sans fonts |
| `docs/dev-init.md` | Original product and developer brief |
| `models/` | Source models (not tracked; processed copies are bundled in the app) |

## Animals and tags

Each tag is a 2" circle with a tag36h11 AprilTag whose black square is 20.8 mm across.

| Tag | Animal | Bundled model |
| --- | --- | --- |
| 0 | C57BL/6J mouse | `c57bl6j_female_146d_22g.usdz` |
| 1 | Generic rat | `generic_rat.usdz` |
| 2 | American red squirrel | `red_squirrel.usdz` |
| 3 | Gray squirrel skull | `gray_squirrel_skull.usdz` |
| 4 | Eastern fox squirrel | `fox_squirrel.usdz` |
| 5 | Generic mouse | `generic_mouse.usdz` |

The catalog lives in `app/iOS/Kingdom/Kingdom/Resources/AnimalCatalog.json`. For each animal it holds the tag number, the display and scientific names, and the dimensions. It also sets how the model is sized: the fit length, the yaw offset (which way the nose points), and a `scale` correction factor, currently 1.5 while on-device scale is still being calibrated.

## Building the app

Requirements: Xcode 26 and an ARKit-capable iPhone running iOS 26.2 or later. The simulator runs the catalog screens but not the AR viewer.

1. Open `app/iOS/Kingdom/Kingdom.xcodeproj`.
2. Select the `Kingdom` scheme and your device, then build and run.

Notes:

- Debug builds print diagnostic lines (`[depth]`, `[projection]`, `[camera]`) to the console while tags are tracked.
- When running from Xcode, RealityKit can trip Metal API Validation with a `tonemapLUT` texture assertion. This comes from Apple's shader, not app code. Launch from the home screen, or turn off **Edit Scheme > Run > Diagnostics > Metal API Validation**.

Unit tests (catalog, asset normalization, AprilTag detection on the generated tags):

```sh
cd app/iOS/Kingdom
xcodebuild test -project Kingdom.xcodeproj -scheme Kingdom \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:KingdomTests
```

## Tools

All Python tools share one virtual environment:

```sh
python3 -m venv tools/tag-gen/.venv
tools/tag-gen/.venv/bin/pip install -r tools/tag-gen/requirements.txt usd-core
```

### Tag artwork

Requires `potrace` and `inkscape` (`brew install potrace inkscape`).

```sh
tools/tag-gen/.venv/bin/python tools/tag-gen/generate_tags.py [--only c57bl6j] [--edge-ring] [--no-fixtures]
```

This reads the catalog and writes `tags/<animal>/`. Unless `--no-fixtures` is passed, it also copies the rendered tags into AprilTagKit's test fixtures, so the detector tests cover the exact artwork being etched.

### Preparing a model

Every bundled model must be a static mesh that passes `usdchecker --arkit`:

1. **Rigged models:** bake to static geometry.
   ```sh
   tools/tag-gen/.venv/bin/python tools/model-prep/bake_static_usdz.py IN.usdz OUT.usdz [--time 0 | --rest-pose]
   ```
2. **Very heavy scans:** decimate with Blender, then finalize the result.
   ```sh
   /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
     --python tools/model-prep/decimate_usdz_blender.py -- IN.usdz DECIMATED.usdz --target-vertices 150000
   tools/tag-gen/.venv/bin/python tools/model-prep/finalize_usdz.py DECIMATED.usdz OUT.usdz --textures-from IN.usdz
   ```
   `finalize_usdz.py` also fixes missing `MaterialBindingAPI` schemas on other models.
3. Copy the result into `app/iOS/Kingdom/Kingdom/Resources/Animals/`, add or update its catalog entry, and regenerate the tags if tag numbers changed.

### App icon and launch assets

```sh
tools/tag-gen/.venv/bin/python tools/brand-gen/generate_app_assets.py
```
