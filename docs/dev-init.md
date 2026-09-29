# Kingdom — Developer Brief

## Product Intent

**Kingdom** is an iOS augmented reality app for scientists, educators, and technically curious users to visualize animals at **true physical scale** using printed reference cards.

The core experience is simple:

> Point an iPhone or iPad at a Kingdom card and see a scientifically appropriate 3D animal appear life-sized above it.

The app should support **multiple cards in the same camera view**, allowing users to compare animals side-by-side at correct relative scale.

Initial target animals:

- C57BL/6J mouse
- Sprague Dawley rat
- American red squirrel (*Tamiasciurus hudsonicus*)
- Eastern gray squirrel (*Sciurus carolinensis*)
- Eastern fox squirrel (*Sciurus niger*)

The app should be built as a platform that can eventually expand across animal taxa.

---

## Primary MVP Goals

### 1. Marker-based AR animal placement

Each physical Kingdom card identifies a specific animal.

When the app recognizes the card:

- place the correct 3D animal on or immediately above the card
- preserve true-to-life physical scale
- preserve stable 6-DOF pose relative to the card
- allow the user to walk around and inspect the animal
- continue rendering smoothly if the marker is briefly occluded

The animal does **not** need to be animated for MVP.

Static, high-quality, correctly scaled 3D models are sufficient.

---

### 2. Multi-animal visualization

The app should detect and render multiple Kingdom cards simultaneously.

Example:

- C57BL/6J mouse card
- Sprague Dawley rat card
- Eastern gray squirrel card

All three animals should appear at the same time and at their correct relative physical scale.

This comparative-scale capability is a key part of the product.

---

## Recommended Technical Stack

Native iOS implementation preferred.

### Core technologies

- Swift
- SwiftUI
- ARKit
- RealityKit

Use RealityKit for:

- USDZ asset loading
- entity placement
- anchors
- lighting
- transforms
- simple interaction

---

## Marker Strategy

The marker system should be abstracted so it can change later.

For MVP, prefer one of the following:

1. ARKit tracked reference images
2. AprilTag-style fiducials
3. QR-assisted identification with image tracking

The visual card should remain attractive and should not feel like an industrial robotics marker.

Long-term preference:

- branded Kingdom animal card
- animal name
- scientific name
- optional thumbnail/image
- small machine-readable marker
- optional QR code for web fallback

The app should not require the marker to remain visible continuously once ARKit has established a stable world pose.

---

## Card Model

Each card should map to one animal asset and associated metadata.

Example:

```json
{
  "id": "c57bl6j",
  "displayName": "C57BL/6J",
  "scientificName": "Mus musculus",
  "asset": "C57BL6J.usdz",
  "scale": 1.0,
  "defaultMass_g": 22,
  "notes": "Adult laboratory mouse"
}
```

The `scale` value should preserve real-world dimensions.

Where possible, 3D assets should already be authored at correct physical scale in meters.

---

## 3D Asset Requirements

Preferred source formats:

- `.blend`
- `.fbx`
- `.glb` / `.gltf`

Runtime iOS format:

- `.usdz`

### Target characteristics

- approximately 30k–80k triangles for MVP
- PBR materials
- 2K textures preferred
- albedo/base color
- normal map
- roughness map where useful
- no strand-based fur rendering
- fur represented using texture, normals, or lightweight cards
- sensible UV layout
- neutral natural pose
- feet aligned to ground plane
- physically correct real-world scale

Rigging is optional for MVP.

Animation is not required.

---

## Scientific Accuracy

The product should prioritize scientific recognizability over stylization.

Important distinctions include:

- C57BL/6J should look like a black laboratory mouse
- Sprague Dawley should look like an albino laboratory rat
- red, gray, and fox squirrels should be represented as the correct North American species
- body proportions should be species-appropriate
- relative physical scale should be correct

Avoid generic "mouse", "rat", or "squirrel" marketplace assets where strain/species differences are visually obvious.

---

## MVP User Flow

### Launch

1. User opens Kingdom.
2. App requests camera permission.
3. User sees a simple AR camera view.
4. Minimal onboarding explains:
   - place one or more Kingdom cards on a surface
   - point camera at cards
   - move device slowly until animals appear

### Recognition

When a card is detected:

1. identify animal ID
2. create an anchor
3. load corresponding USDZ asset
4. apply canonical scale
5. place animal relative to card
6. maintain tracking

### Interaction

For MVP:

- tap animal to select
- selected animal can display a compact metadata sheet
- optional reset/re-localize button
- optional toggle for labels

No complex gesture system is required initially.

---

## Metadata Panel

A tapped animal should eventually support:

- common name
- scientific name
- strain or stock
- sex
- age
- body mass
- source/model provenance
- notes
- scale indicator

Not all fields need to be populated in MVP.

The data model should support them.

---

## Visual Design Direction

Brand: **Kingdom**

Tagline:

**Animals in real scale**

Desired visual character:

- scientific
- modern
- geometric
- restrained
- not childish
- not overly clinical
- not limited visually to rodents

Current logo exploration uses:

- geometric animal forms
- a stylized `K`
- black/white initially
- possible future earth-tone palette

The app UI should stay visually quiet so the AR animals remain the focus.

---

## AR Scene Behavior

### Placement

Animals should appear naturally grounded on the card/surface.

Avoid:

- floating above the surface
- sinking through the card
- visibly incorrect orientation

### Scale

Scale accuracy is critical.

Use ARKit world units directly:

- `1.0 RealityKit meter = 1 meter`

Do not scale animals to fit the screen.

A mouse should appear small.

A squirrel should appear much larger.

Future large animals should be allowed to extend well beyond the physical card.

The card identifies and anchors the animal; it does not define the animal's footprint.

---

## Multi-Marker Requirements

Architecture should assume multiple active tracked cards.

Suggested object model:

```swift
AnimalInstance
- id
- speciesID
- anchor
- entity
- cardID
- trackingState
```

Avoid a global singleton animal.

Each detected marker should create an independent instance.

The system should safely handle:

- 1 animal
- 2 animals
- 3–5 animals simultaneously

MVP performance target should prioritize stable tracking and rendering over very high asset complexity.

---

## Asset Loading

Prefer a reusable animal asset manager.

Example responsibilities:

```swift
AnimalAssetManager
- preload frequently used assets
- load USDZ by animal ID
- cache loaded RealityKit entities
- clone entities for repeated cards
- apply canonical transforms
```

Do not tightly couple marker recognition directly to filenames.

Use an intermediate metadata/configuration layer.

---

## Suggested Project Structure

```text
Kingdom/
├── App/
├── AR/
│   ├── ARSessionManager.swift
│   ├── MarkerTracker.swift
│   └── AnimalAnchorManager.swift
├── Models/
│   ├── AnimalDefinition.swift
│   └── AnimalInstance.swift
├── Services/
│   └── AnimalAssetManager.swift
├── Views/
│   ├── ARViewContainer.swift
│   ├── AnimalInfoView.swift
│   └── OnboardingView.swift
├── Resources/
│   ├── Animals/
│   ├── Markers/
│   └── AnimalCatalog.json
└── Branding/
```

---

## Initial Animal Catalog

Suggested stable IDs:

```text
c57bl6j
sprague_dawley
red_squirrel
gray_squirrel
fox_squirrel
```

Do not use display names as primary identifiers.

---

## MVP Success Criteria

The MVP is successful if a user can:

1. launch the app
2. place a C57BL/6J card on a table
3. point the camera at it
4. see a stable, correctly scaled 3D mouse
5. walk around the table while the animal remains anchored
6. add a Sprague Dawley card
7. see both animals simultaneously
8. immediately understand their relative physical size

The experience should feel fast and almost magical, not like a technical AR demo.

---

## Non-Goals for MVP

Do not prioritize yet:

- animation
- locomotion
- behavioral simulation
- skeletal overlays
- internal anatomy
- physics
- animal-to-animal interaction
- cloud accounts
- user-generated animals
- Android support
- collaborative/shared AR sessions
- complex gamification

---

## Future Directions

The architecture should leave room for:

### Scientific visualization

- skeleton overlays
- brain overlays
- transparent skin
- anatomical structures
- implant/device placement
- measurement tools
- body-length annotations
- sex differences
- age variants
- weight variants

### Behavioral visualization

- walking
- grooming
- rearing
- feeding
- species-specific behaviors

### Experimental visualization

Potential future models could show:

- head-mounted devices
- neural implants
- optical fibers
- telemetry systems
- collars
- behavioral apparatus
- experimental enclosures

### Expanded taxa

Kingdom should eventually support:

- mammals
- birds
- fish
- reptiles
- amphibians
- insects
- potentially plants or other biological specimens

The name should therefore not be treated as rodent-specific.

---

## Product Principle

The defining feature of Kingdom is not simply:

> "A 3D animal appears from a card."

The defining experience is:

> **Scientifically recognizable animals appearing at their true physical scale, with multiple specimens visible together for immediate spatial comparison.**

That principle should guide technical and design decisions throughout development.
