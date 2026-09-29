#!/usr/bin/env python3
"""Generate laser-etch artwork for 2" circular Kingdom tags.

Reads the app's AnimalCatalog.json (marker IDs, names, tag size) and the vendored tag36h11
codebook, then writes per-animal SVG / DXF / PLT / PDF / PNG / BMP files to tags/.

All geometry is built once as closed polygons in millimeters (origin at tag center, +y up)
and every output format is written from that single model. Filled regions are the areas to
etch (dark gray on white tags); fill uses the even-odd rule.

Usage:
    tools/tag-gen/.venv/bin/python tools/tag-gen/generate_tags.py [--edge-ring] [--only c57bl6j]
"""

import argparse
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import ezdxf
from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from PIL import Image, ImageChops, ImageOps

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "app/iOS/Kingdom/Kingdom/Resources/AnimalCatalog.json"
TAG36H11_C = ROOT / "app/iOS/Kingdom/Packages/AprilTagKit/Sources/CAprilTag/tag36h11.c"
FIXTURES = ROOT / "app/iOS/Kingdom/Packages/AprilTagKit/Tests/AprilTagKitTests/Fixtures"
FONT_REGULAR = ROOT / "brand/fonts/PlusJakartaSans-Variable.ttf"
FONT_ITALIC = ROOT / "brand/fonts/PlusJakartaSans-Italic-Variable.ttf"
LOGO = ROOT / "brand/kingdom_logo.png"
OUT = ROOT / "tags"

TAG_DIAMETER_MM = 50.8
TAG_RADIUS_MM = TAG_DIAMETER_MM / 2

# Text ring layout (mm). Kept inside r = 24 to leave ~1.4 mm of edge tolerance.
TOP_BASELINE_R = 20.0
TOP_CAP_HEIGHT = 2.4
TOP_TRACKING = 0.28
TOP_MAX_SPAN_DEG = 124.0
BOTTOM_BASELINE_R = 22.6
BOTTOM_CAP_HEIGHT = 2.3
BOTTOM_TRACKING = 0.12
BOTTOM_MAX_SPAN_DEG = 104.0
LOGO_SIZE_MM = 5.2
LOGO_CENTER_R = 18.9
EDGE_RING_R = 24.7
EDGE_RING_WIDTH = 0.3
FLATTEN_STEP_MM = 0.04

PNG_DPI = 1200
FIXTURE_DPI = 300


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

def signed_area(poly):
    area = 0.0
    for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1]):
        area += x1 * y2 - x2 * y1
    return area / 2


def transform(poly, angle=0.0, dx=0.0, dy=0.0, scale=1.0):
    c, s = math.cos(angle), math.sin(angle)
    return [((x * c - y * s) * scale + dx, (x * s + y * c) * scale + dy) for x, y in poly]


def circle(radius, segments=720):
    return [(radius * math.cos(2 * math.pi * i / segments), radius * math.sin(2 * math.pi * i / segments)) for i in range(segments)]


# ---------------------------------------------------------------------------
# tag36h11
# ---------------------------------------------------------------------------

def load_tag36h11():
    source = TAG36H11_C.read_text()

    def array(name):
        match = re.search(r"%s\[\d*\]\s*=\s*\{([^}]*)\}" % name, source)
        if not match:
            sys.exit("Could not parse %s from %s" % (name, TAG36H11_C))
        return match.group(1)

    codes = [int(v, 16) for v in re.findall(r"0x[0-9a-fA-F]+", array("codedata"))]

    def field(name):
        return int(re.search(r"tf->%s\s*=\s*(\d+)" % name, source).group(1))

    def bits(name):
        values = {int(i): int(v) for i, v in re.findall(r"tf->%s\[(\d+)\]\s*=\s*(-?\d+)" % name, source)}
        return [values[i] for i in range(field("nbits"))]

    bit_x = bits("bit_x")
    bit_y = bits("bit_y")
    if len(codes) != field("ncodes"):
        sys.exit("Parsed %d codes, expected %d" % (len(codes), field("ncodes")))

    return {
        "codes": codes,
        "bit_x": bit_x,
        "bit_y": bit_y,
        "nbits": field("nbits"),
        "width_at_border": field("width_at_border"),
        "total_width": field("total_width"),
    }


def tag_grid(family, tag_id):
    """Returns total_width x total_width rows (row 0 = top); True = dark (etched) cell.

    Mirrors apriltag_to_image(): a white outer ring, a black border, data bits white when set.
    """
    total = family["total_width"]
    border = family["width_at_border"]
    start = (total - border) // 2
    grid = [[False] * total for _ in range(total)]
    for y in range(start, start + border):
        for x in range(start, start + border):
            grid[y][x] = True
    code = family["codes"][tag_id]
    nbits = family["nbits"]
    for i in range(nbits):
        if code & (1 << (nbits - i - 1)):
            grid[family["bit_y"][i] + start][family["bit_x"][i] + start] = False
    return grid


def grid_outlines(grid, cell, origin_x, origin_y):
    """Unions dark cells into closed outlines (outer CCW, holes CW), y up.

    Diagonally touching cells are kept as separate outlines.
    """
    rows = len(grid)
    cols = len(grid[0])

    def dark(r, c):
        return 0 <= r < rows and 0 <= c < cols and grid[r][c]

    # Vertex (i, j) = grid corner at column i, row j (row 0 at top). Edges keep dark on the left
    # when walking in y-up coordinates.
    edges = {}
    for r in range(rows):
        for c in range(cols):
            if not dark(r, c):
                continue
            if not dark(r + 1, c):
                edges.setdefault((c, r + 1), []).append((c + 1, r + 1))
            if not dark(r, c + 1):
                edges.setdefault((c + 1, r + 1), []).append((c + 1, r))
            if not dark(r - 1, c):
                edges.setdefault((c + 1, r), []).append((c, r))
            if not dark(r, c - 1):
                edges.setdefault((c, r), []).append((c, r + 1))

    def to_mm(v):
        return (origin_x + v[0] * cell, origin_y - v[1] * cell)

    loops = []
    while edges:
        start = next(iter(edges))
        loop = [start]
        prev = start
        current = edges[start].pop()
        if not edges[start]:
            del edges[start]
        while current != start:
            options = edges[current]
            if len(options) == 1:
                nxt = options.pop()
            else:
                # Prefer the left turn (in y-up space) so diagonal neighbors stay separate.
                incoming = (current[0] - prev[0], -(current[1] - prev[1]))

                def turn(v):
                    out = (v[0] - current[0], -(v[1] - current[1]))
                    return incoming[0] * out[1] - incoming[1] * out[0]

                nxt = max(options, key=turn)
                options.remove(nxt)
            if not options:
                del edges[current]
            loop.append(current)
            prev, current = current, nxt
        # Drop collinear points.
        pts = [to_mm(v) for v in loop]
        simplified = []
        n = len(pts)
        for i in range(n):
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
            if abs((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])) > 1e-9:
                simplified.append(b)
        loops.append(simplified)
    return loops


# ---------------------------------------------------------------------------
# Text
# ---------------------------------------------------------------------------

class FlattenPen(BasePen):
    def __init__(self, glyph_set, step):
        super().__init__(glyph_set)
        self.step = step
        self.contours = []
        self.current = []

    def _moveTo(self, pt):
        self.current = [pt]

    def _lineTo(self, pt):
        self.current.append(pt)

    def _curveToOne(self, p1, p2, p3):
        p0 = self.current[-1]
        n = self._segments(p0, p1, p2, p3)
        for i in range(1, n + 1):
            t = i / n
            mt = 1 - t
            self.current.append((
                mt ** 3 * p0[0] + 3 * mt * mt * t * p1[0] + 3 * mt * t * t * p2[0] + t ** 3 * p3[0],
                mt ** 3 * p0[1] + 3 * mt * mt * t * p1[1] + 3 * mt * t * t * p2[1] + t ** 3 * p3[1],
            ))

    def _qCurveToOne(self, p1, p2):
        p0 = self.current[-1]
        n = self._segments(p0, p1, p2)
        for i in range(1, n + 1):
            t = i / n
            mt = 1 - t
            self.current.append((
                mt * mt * p0[0] + 2 * mt * t * p1[0] + t * t * p2[0],
                mt * mt * p0[1] + 2 * mt * t * p1[1] + t * t * p2[1],
            ))

    def _closePath(self):
        if len(self.current) > 2:
            if self.current[0] == self.current[-1]:
                self.current.pop()
            self.contours.append(self.current)
        self.current = []

    _endPath = _closePath

    def _segments(self, *pts):
        length = sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))
        return max(2, int(math.ceil(length / self.step)))


class OutlineFont:
    def __init__(self, path, weight):
        font = TTFont(str(path))
        # Variable-font glyphs often overlap contours; even-odd fills and laser hatching need them merged.
        self.font = instancer.instantiateVariableFont(font, {"wght": weight}, overlap=instancer.OverlapMode.REMOVE)
        self.glyph_set = self.font.getGlyphSet()
        self.cmap = self.font.getBestCmap()
        self.units_per_em = self.font["head"].unitsPerEm
        self.cap_height = getattr(self.font["OS/2"], "sCapHeight", 0) or self.units_per_em * 0.7

    def glyph(self, char, cap_height_mm):
        """Returns (contours in mm with baseline at y = 0, advance in mm)."""
        scale = cap_height_mm / self.cap_height
        name = self.cmap.get(ord(char))
        if name is None:
            name = ".notdef"
        pen = FlattenPen(self.glyph_set, FLATTEN_STEP_MM / scale)
        self.glyph_set[name].draw(pen)
        contours = [[(x * scale, y * scale) for x, y in contour] for contour in pen.contours]
        advance = self.glyph_set[name].width * scale
        return contours, advance


def text_on_arc(text, font, cap_height, tracking, radius, center_deg, max_span_deg, upright_outward):
    """Lays text along a circle. Top text reads clockwise with glyphs pointing outward;
    bottom text reads counterclockwise with glyphs pointing inward, so both read upright."""
    size = cap_height
    while True:
        glyphs = [font.glyph(ch, size) for ch in text]
        advances = [adv for _, adv in glyphs]
        total = sum(advances) + tracking * (len(text) - 1)
        span = math.degrees(total / radius)
        if span <= max_span_deg or size < 1.4:
            break
        size *= 0.96
        tracking *= 0.96

    polygons = []
    cursor = 0.0
    for (contours, advance), ch in zip(glyphs, text):
        mid = cursor + advance / 2
        offset = (mid - total / 2) / radius
        if upright_outward:
            angle = math.radians(center_deg) - offset
            rotation = angle - math.pi / 2
        else:
            angle = math.radians(center_deg) + offset
            rotation = angle + math.pi / 2
        px, py = radius * math.cos(angle), radius * math.sin(angle)
        for contour in contours:
            local = [(x - advance / 2, y) for x, y in contour]
            polygons.append(transform(local, rotation, px, py))
        cursor += advance + tracking
    return polygons, size


# ---------------------------------------------------------------------------
# Logo
# ---------------------------------------------------------------------------

def trace_logo():
    if shutil.which("potrace") is None:
        sys.exit("potrace not found. Install it with: brew install potrace")
    image = Image.open(LOGO).convert("RGBA")
    alpha = image.split()[3]
    ink = ImageChops.multiply(alpha, ImageOps.invert(image.convert("L")))
    mask = ImageOps.invert(ink).point(lambda v: 255 if v > 127 else 0).convert("1")
    with tempfile.TemporaryDirectory() as tmp:
        pbm = Path(tmp) / "logo.pbm"
        geojson = Path(tmp) / "logo.geojson"
        mask.save(pbm)
        subprocess.run(["potrace", "-b", "geojson", "-a", "1", "-O", "0.1", str(pbm), "-o", str(geojson)], check=True)
        data = json.loads(geojson.read_text())

    rings = []
    for feature in data["features"]:
        geometry = feature["geometry"]
        polys = geometry["coordinates"] if geometry["type"] == "Polygon" else [r for p in geometry["coordinates"] for r in p]
        for ring in polys:
            pts = [tuple(p) for p in ring]
            if pts[0] == pts[-1]:
                pts.pop()
            rings.append(pts)

    xs = [x for ring in rings for x, _ in ring]
    ys = [y for ring in rings for _, y in ring]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    extent = max(max(xs) - min(xs), max(ys) - min(ys))
    return [[((x - cx) / extent, (y - cy) / extent) for x, y in ring] for ring in rings]


# ---------------------------------------------------------------------------
# Tag assembly
# ---------------------------------------------------------------------------

def build_tag(animal, marker_id, tag_size_mm, family, fonts, logo, edge_ring):
    cells = family["total_width"]
    border = family["width_at_border"]
    cell = tag_size_mm / border
    half = cells * cell / 2
    layers = {
        "TAG": grid_outlines(tag_grid(family, marker_id), cell, -half, half),
        "TEXT": [],
        "LOGO": [],
    }

    top_text = animal["displayName"].upper()
    top, top_size = text_on_arc(top_text, fonts["bold"], TOP_CAP_HEIGHT, TOP_TRACKING, TOP_BASELINE_R, 90, TOP_MAX_SPAN_DEG, True)
    layers["TEXT"].extend(top)

    bottom_text = animal.get("scientificName") or ""
    if bottom_text:
        bottom, _ = text_on_arc(bottom_text, fonts["italic"], BOTTOM_CAP_HEIGHT, BOTTOM_TRACKING, BOTTOM_BASELINE_R, 270, BOTTOM_MAX_SPAN_DEG, False)
        layers["TEXT"].extend(bottom)

    for side in (-1, 1):
        layers["LOGO"].extend(transform(ring, 0, side * LOGO_CENTER_R, 0, LOGO_SIZE_MM) for ring in logo)

    if edge_ring:
        layers["EDGE_RING"] = [circle(EDGE_RING_R + EDGE_RING_WIDTH / 2), list(reversed(circle(EDGE_RING_R - EDGE_RING_WIDTH / 2)))]

    return layers, {"cell_mm": cell, "top_cap_height_mm": top_size}


# ---------------------------------------------------------------------------
# Writers
# ---------------------------------------------------------------------------

def svg_path(polys):
    parts = []
    for poly in polys:
        pts = " ".join("%.4f,%.4f" % (x, -y) for x, y in poly)
        parts.append("M%sZ" % pts)
    return " ".join(parts)


def write_svg(path, layers, title, outline=False):
    r = TAG_RADIUS_MM
    body = []
    for name, polys in layers.items():
        body.append('  <path id="%s" fill="#000" fill-rule="evenodd" d="%s"/>' % (name.lower(), svg_path(polys)))
    if outline:
        body.append('  <circle id="outline" cx="0" cy="0" r="%.4f" fill="none" stroke="#c8c8c8" stroke-width="0.1"/>' % r)
    path.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" width="%.1fmm" height="%.1fmm" viewBox="%.4f %.4f %.4f %.4f">\n'
        "  <title>%s</title>\n%s\n</svg>\n" % (TAG_DIAMETER_MM, TAG_DIAMETER_MM, -r, -r, 2 * r, 2 * r, title, "\n".join(body))
    )


def write_dxf(path, layers, include_outline=False):
    doc = ezdxf.new("R12")
    msp = doc.modelspace()
    colors = {"TAG": 7, "TEXT": 7, "LOGO": 7, "EDGE_RING": 7, "OUTLINE": 8}
    for name in list(layers) + (["OUTLINE"] if include_outline else []):
        doc.layers.add(name, color=colors.get(name, 7))
    for name, polys in layers.items():
        for poly in polys:
            msp.add_polyline2d(poly, close=True, dxfattribs={"layer": name})
    if include_outline:
        msp.add_circle((0, 0), TAG_RADIUS_MM, dxfattribs={"layer": "OUTLINE"})
    doc.saveas(path)


def write_plt(path, layers):
    """HPGL with 40 plotter units per mm, origin at the tag center."""
    lines = ["IN;", "SP1;"]
    for polys in layers.values():
        for poly in polys:
            pts = [(round(x * 40), round(y * 40)) for x, y in poly]
            pts.append(pts[0])
            lines.append("PU%d,%d;" % pts[0])
            lines.append("PD" + ",".join("%d,%d" % p for p in pts[1:]) + ";")
    lines.append("PU;SP0;")
    path.write_text("\n".join(lines) + "\n")


def inkscape(svg, out, *args):
    subprocess.run(["inkscape", str(svg), "--export-filename=%s" % out, *args], check=True, capture_output=True)


def write_rasters(svg, png_path, bmp_path):
    with tempfile.TemporaryDirectory() as tmp:
        raw = Path(tmp) / "raw.png"
        inkscape(svg, raw, "--export-dpi=%d" % PNG_DPI, "--export-background=#ffffff", "--export-background-opacity=1")
        gray = Image.open(raw).convert("L")
    gray.save(png_path, dpi=(PNG_DPI, PNG_DPI))
    gray.point(lambda v: 255 if v >= 128 else 0).convert("1").save(bmp_path, dpi=(PNG_DPI, PNG_DPI))
    return gray


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--edge-ring", action="store_true", help="add a thin etched ring near the tag edge")
    parser.add_argument("--only", help="generate a single animal ID")
    parser.add_argument("--no-fixtures", action="store_true", help="skip copying test fixtures into AprilTagKit")
    args = parser.parse_args()

    if shutil.which("inkscape") is None:
        sys.exit("inkscape not found. Install it with: brew install --cask inkscape")

    catalog = json.loads(CATALOG.read_text())
    if catalog["marker"]["family"] != "tag36h11":
        sys.exit("Only tag36h11 is supported")
    tag_size_mm = catalog["marker"]["tagSize_m"] * 1000
    animals = {a["id"]: a for a in catalog["animals"]}

    family = load_tag36h11()
    fonts = {"bold": OutlineFont(FONT_REGULAR, 700), "italic": OutlineFont(FONT_ITALIC, 500)}
    logo = trace_logo()

    OUT.mkdir(exist_ok=True)
    manifest = {}
    sheet = []
    for card in sorted(catalog["cards"], key=lambda c: c["markerID"]):
        animal = animals[card["animalID"]]
        if args.only and animal["id"] != args.only:
            continue
        marker_id = card["markerID"]
        layers, info = build_tag(animal, marker_id, tag_size_mm, family, fonts, logo, args.edge_ring)
        folder = OUT / animal["id"]
        folder.mkdir(exist_ok=True)
        stem = "%s_tag%d" % (animal["id"], marker_id)
        title = "Kingdom tag %d: %s" % (marker_id, animal["displayName"])

        svg = folder / (stem + ".svg")
        write_svg(svg, layers, title)
        write_dxf(folder / (stem + ".dxf"), layers)
        write_plt(folder / (stem + ".plt"), layers)
        inkscape(svg, folder / (stem + ".pdf"))
        gray = write_rasters(svg, folder / (stem + ".png"), folder / (stem + ".bmp"))

        if not args.no_fixtures:
            FIXTURES.mkdir(parents=True, exist_ok=True)
            side = round(TAG_DIAMETER_MM / 25.4 * FIXTURE_DPI)
            gray.resize((side, side), Image.LANCZOS).save(FIXTURES / (stem + ".png"))
            manifest[stem + ".png"] = marker_id

        sheet.append((stem, layers))
        print("%-16s tag %d  cell %.3f mm  black border %.2f mm  title cap %.2f mm -> %s"
              % (animal["id"], marker_id, info["cell_mm"], tag_size_mm, info["top_cap_height_mm"], folder.relative_to(ROOT)))

    write_dxf(OUT / "tag_outline_2in.dxf", {}, include_outline=True)
    write_sheet(sheet)

    if manifest and not args.no_fixtures:
        (FIXTURES / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def write_sheet(entries):
    """Proof sheet: all tags on one US Letter page, with light cut outlines."""
    if not entries:
        return
    pitch = 60.0
    columns = 3
    r = TAG_RADIUS_MM
    body = []
    for index, (stem, layers) in enumerate(entries):
        cx = 15 + r + (index % columns) * pitch
        cy = 20 + r + (index // columns) * pitch
        polys = [p for layer in layers.values() for p in layer]
        body.append('  <g transform="translate(%.3f %.3f)"><title>%s</title>' % (cx, cy, stem))
        body.append('    <path fill="#000" fill-rule="evenodd" d="%s"/>' % svg_path(polys))
        body.append('    <circle r="%.4f" fill="none" stroke="#c8c8c8" stroke-width="0.1"/>' % r)
        body.append("  </g>")
    svg = OUT / "kingdom_tags_sheet.svg"
    svg.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" width="215.9mm" height="279.4mm" viewBox="0 0 215.9 279.4">\n'
        "%s\n</svg>\n" % "\n".join(body)
    )
    inkscape(svg, OUT / "kingdom_tags_sheet.pdf")


if __name__ == "__main__":
    main()
