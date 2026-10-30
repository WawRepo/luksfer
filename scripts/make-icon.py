#!/usr/bin/env python3
"""Draw Luksfer's app icon and write every file macOS needs.

Run from anywhere (needs Python 3 with Pillow; iconutil and actool come with macOS / Xcode):

    python3 scripts/make-icon.py            # write the icon files into Resources/
    python3 scripts/make-icon.py --preview  # also write a contact sheet of all sizes
    python3 scripts/make-icon.py --check    # also compile the icon files with actool

Writes, inside the repo:
    Resources/AppIcon.icns                         built by iconutil from a full .iconset
    Resources/Assets.xcassets/Contents.json
    Resources/Assets.xcassets/AppIcon.appiconset/  every mac size as PNG + Contents.json
    Resources/AppIcon.icon/                        Icon Composer bundle (macOS 26 Liquid Glass)

Temporary files (the .iconset, the preview, the actool output) go to ~/Library/Caches/luksfer-dev/icon/.

The design: a window seen head-on. The rounded square is an orange window frame; a mullion with
a handle splits the glass into two tall panes (Luksfer's two panes) with one sky behind them. Shapes
are drawn at 4x and scaled down with LANCZOS. The 16 and 32 px images use a simpler drawing
whose edges sit on whole pixels, so they stay sharp.
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parent.parent
RESOURCES = REPO / "Resources"
SCRATCH = Path.home() / "Library" / "Caches" / "luksfer-dev" / "icon"

GRID = 1024.0  # all geometry is in units of the 1024 x 1024 master
SUPERSAMPLE = 4

# ---------------------------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------------------------

# One corner of Apple's "continuous corner" rounded rectangle (the squircle), as cubic Bezier
# segments in units of the corner radius. X is measured in from the right edge, Y down from the
# top edge; the corner runs from the top edge (Y = 0) to the right edge (X = 0).
_K = 1.52866483
_CORNER = [
    ((_K, 0.0), (1.08849323, 0.0), (0.86840689, 0.0), (0.66993427, 0.06549600)),
    ((0.66993427, 0.06549600),) + ((0.63149399, 0.07491100),) * 3,
    ((0.63149399, 0.07491100), (0.37282392, 0.16905899), (0.16906013, 0.37282401), (0.07491100, 0.63149399)),
    ((0.07491100, 0.63149399),) * 3 + ((0.06549600, 0.66993427),),
    ((0.06549600, 0.66993427), (0.0, 0.86840689), (0.0, 1.08849323), (0.0, _K)),
]


def _corner_points(steps: int = 40) -> list[tuple[float, float]]:
    pts = [_CORNER[0][0]]
    for p0, p1, p2, p3 in _CORNER:
        for i in range(1, steps + 1):
            t = i / steps
            u = 1 - t
            pts.append(tuple(u * u * u * p0[j] + 3 * u * u * t * p1[j] + 3 * u * t * t * p2[j] + t * t * t * p3[j]
                             for j in (0, 1)))
    return pts


_CORNER_PTS = _corner_points()


def rrect(box, radii) -> list[tuple[float, float]]:
    """Polygon for a continuous-corner rounded rectangle.

    radii is one number or (top-left, top-right, bottom-right, bottom-left)."""
    x0, y0, x1, y1 = box
    if not isinstance(radii, (tuple, list)):
        radii = (radii,) * 4
    limit = min(x1 - x0, y1 - y0) / 2 / _K
    tl, tr, br, bl = (min(r, limit) for r in radii)
    c = _CORNER_PTS
    pts: list[tuple[float, float]] = []
    pts += [(x1 - X * tr, y0 + Y * tr) for X, Y in c] if tr > 0 else [(x1, y0)]
    pts += [(x1 - X * br, y1 - Y * br) for X, Y in reversed(c)] if br > 0 else [(x1, y1)]
    pts += [(x0 + X * bl, y1 - Y * bl) for X, Y in c] if bl > 0 else [(x0, y1)]
    pts += [(x0 + X * tl, y0 + Y * tl) for X, Y in reversed(c)] if tl > 0 else [(x0, y0)]
    return pts


def ellipse(cx, cy, rx, ry, steps=96) -> list[tuple[float, float]]:
    return [(cx + rx * math.cos(2 * math.pi * i / steps), cy + ry * math.sin(2 * math.pi * i / steps))
            for i in range(steps)]


class Geo:
    """Where the body, frame opening and mullion sit on the 1024 grid.

    With `pixels`, the edges snap to the pixel grid of an image that many pixels wide, and the
    frame and mullion stay at least one pixel thick."""

    BODY_HALF = 412.0    # 824 x 824 body, 100 px margin (macOS Big Sur+ icon grid)
    BODY_R = 185.0
    SIDE = 84.0          # frame width at the sides and top
    BOTTOM = 96.0        # the bottom rail is a little heavier, like a real window
    MULL_HALF = 26.0
    PANE_R = 14.0        # corner radius of the pane corners next to the mullion

    def __init__(self, pixels: int | None = None):
        body_half, side, bottom, mull_half = self.BODY_HALF, self.SIDE, self.BOTTOM, self.MULL_HALF
        if pixels is not None:
            step = GRID / pixels
            body_half, side, bottom, mull_half = (max(step, round(v / step) * step)
                                                  for v in (body_half, side, bottom, mull_half))
        c = self.c = GRID / 2
        self.body = (c - body_half, c - body_half, c + body_half, c + body_half)
        self.opening = (self.body[0] + side, self.body[1] + side, self.body[2] - side, self.body[3] - bottom)
        self.mull_half = mull_half
        self.inner_r = self.BODY_R - side

    def panes(self, grow: float = 0.0):
        """The two panes as polygons, optionally grown outwards by `grow`."""
        ox0, oy0, ox1, oy1 = self.opening
        c, m, g, r, s = self.c, self.mull_half, grow, self.inner_r + grow, self.PANE_R + grow
        return (rrect((ox0 - g, oy0 - g, c - m + g, oy1 + g), (r, s, s, r)),
                rrect((c + m - g, oy0 - g, ox1 + g, oy1 + g), (s, r, r, s)))


# ---------------------------------------------------------------------------------------------
# Painting helpers (pure Pillow, no numpy)
# ---------------------------------------------------------------------------------------------

def _hex(c: str, alpha: int = 255):
    c = c.lstrip("#")
    return (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16), alpha)


def _stop_color(stops, t):
    t = max(0.0, min(1.0, t))
    for (ta, ca), (tb, cb) in zip(stops, stops[1:]):
        if t <= tb:
            f = 0 if tb == ta else (t - ta) / (tb - ta)
            return tuple(round(ca[i] + (cb[i] - ca[i]) * f) for i in range(4))
    return stops[-1][1]


class Canvas:
    """An RGBA image that takes coordinates in 1024-grid units.

    `view` is the (x, y, size) square of the grid that fills the image; the default is the whole
    1024 grid."""

    def __init__(self, pixels: int, view=(0.0, 0.0, GRID)):
        self.n = pixels
        self.vx, self.vy, size = view
        self.k = pixels / size
        self.img = Image.new("RGBA", (pixels, pixels), (0, 0, 0, 0))

    def _xy(self, x, y):
        return ((x - self.vx) * self.k, (y - self.vy) * self.k)

    # masks ------------------------------------------------------------------------------------
    def mask(self, *polys) -> Image.Image:
        m = Image.new("L", (self.n, self.n), 0)
        d = ImageDraw.Draw(m)
        for pts in polys:
            d.polygon([self._xy(x, y) for x, y in pts], fill=255)
        return m

    def blur(self, m: Image.Image, radius: float) -> Image.Image:
        return m.filter(ImageFilter.GaussianBlur(radius * self.k))

    def shift(self, m: Image.Image, dx: float, dy: float) -> Image.Image:
        out = Image.new(m.mode, m.size, 0)
        out.paste(m, (round(dx * self.k), round(dy * self.k)))
        return out

    def glow(self, cx, cy, radius, gamma=2.2) -> Image.Image:
        """Round soft spot: 255 at the centre, 0 at `radius`."""
        size = round(2 * radius * self.k)
        # radial_gradient is the distance from the centre: 128 at the edge of its 256 box.
        spot = Image.radial_gradient("L").resize((size, size), Image.BILINEAR)
        spot = spot.point(lambda v: round(255 * max(0.0, 1 - v / 128) ** gamma))
        m = Image.new("L", (self.n, self.n), 0)
        x, y = self._xy(cx - radius, cy - radius)
        m.paste(spot, (round(x), round(y)))
        return m

    @staticmethod
    def clip(m: Image.Image, *others: Image.Image) -> Image.Image:
        for o in others:
            m = ImageChops.multiply(m, o)
        return m

    # paints -----------------------------------------------------------------------------------
    def vgrad(self, y0: float, y1: float, stops) -> Image.Image:
        """Full-image vertical gradient; stops are (t, rgba), t from 0 at y0 to 1 at y1."""
        strip = Image.new("RGBA", (1, self.n))
        strip.putdata([_stop_color(stops, ((j + 0.5) / self.k + self.vy - y0) / (y1 - y0))
                       for j in range(self.n)])
        return strip.resize((self.n, self.n), Image.NEAREST)

    def fill(self, m: Image.Image, paint, opacity: float = 1.0) -> None:
        """Paint a colour or an RGBA image through mask `m`."""
        if isinstance(paint, tuple):
            layer = Image.new("RGBA", (self.n, self.n), paint[:3] + (255,))
            alpha = m
        else:
            layer = paint.copy()
            alpha = ImageChops.multiply(paint.getchannel("A"), m)
        if opacity < 1:
            alpha = alpha.point(lambda v: round(v * opacity))
        layer.putalpha(alpha)
        self.img.alpha_composite(layer)

    def screen(self, m: Image.Image, color, opacity: float = 1.0) -> None:
        """Lighten with a 'screen' blend: clean light, unlike a grey-ish white overlay."""
        lit = ImageChops.screen(self.img.convert("RGB"), Image.new("RGB", self.img.size, color[:3])).convert("RGBA")
        lit.putalpha(self.img.getchannel("A"))
        if opacity < 1:
            m = m.point(lambda v: round(v * opacity))
        self.img = Image.composite(lit, self.img, m)


# ---------------------------------------------------------------------------------------------
# The icon
# ---------------------------------------------------------------------------------------------

FRAME = [(0.00, _hex("FFB257")), (0.55, _hex("FB8C3A")), (1.00, _hex("EE6526"))]
FRAME_EDGE = _hex("B9501A")
SKY = [
    (0.00, _hex("1556D4")),
    (0.45, _hex("3F8FF3")),
    (0.78, _hex("8FCBFF")),
    (0.93, _hex("DDF0FF")),
    (1.00, _hex("FFE9C7")),
]
WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)


def paint_shadow(cv: Canvas, g: Geo) -> None:
    """Drop shadow inside the margin: a wide soft one and a tight contact one."""
    body = cv.mask(rrect(g.body, g.BODY_R))
    cv.fill(cv.blur(cv.shift(body, 0, 12), 22), BLACK, 0.30)
    cv.fill(cv.blur(cv.shift(body, 0, 3), 4), BLACK, 0.18)


def paint_frame(cv: Canvas, g: Geo, simple: bool) -> None:
    """The window frame: the whole body, lit from above, with a darker rim around the glass."""
    body = cv.mask(rrect(g.body, g.BODY_R))
    cv.fill(body, cv.vgrad(g.body[1], g.body[3], FRAME))
    if not simple:
        cv.fill(cv.blur(cv.mask(*g.panes(7)), 2), FRAME_EDGE, 0.55)
        top_edge = ImageChops.subtract(body, cv.shift(body, 0, 6))
        cv.fill(cv.blur(top_edge, 2), WHITE, 0.5)


def paint_glass(cv: Canvas, g: Geo, simple: bool) -> None:
    """Sky behind both panes; in the detailed drawing also sun, clouds and a glass sheen."""
    ox0, oy0, ox1, oy1 = g.opening
    glass = cv.mask(*g.panes())
    cv.fill(glass, cv.vgrad(oy0, oy1, SKY))

    if not simple:
        cv.screen(cv.clip(cv.glow(740, 292, 280), glass), _hex("FFF3D6"), 0.9)

        # A thin wisp up high, and a low bank of soft cloud that passes behind the mullion:
        # one sky seen through two panes.
        wisp = cv.mask(ellipse(330, 380, 110, 22), ellipse(390, 366, 70, 26))
        cv.fill(cv.clip(cv.blur(wisp, 10), glass), WHITE, 0.55)
        bank = cv.mask(ellipse(330, 760, 150, 52), ellipse(470, 728, 120, 70), ellipse(600, 752, 140, 56),
                       ellipse(740, 772, 130, 44), ellipse(250, 800, 120, 40), ellipse(520, 800, 330, 44))
        cv.fill(cv.clip(cv.blur(bank, 9), glass),
                cv.vgrad(660, 840, [(0, _hex("FFFFFF")), (1, _hex("FFF1DC"))]), 0.92)

        # Glass sheen: two diagonal light bands.
        for (a, b), opacity in (((600, 700), 0.14), ((760, 800), 0.10)):
            band = cv.mask([(ox0 - 40, a), (a, oy0 - 40), (b, oy0 - 40), (ox0 - 40, b)])
            cv.fill(cv.clip(cv.blur(band, 3), glass), WHITE, opacity)

    # Inner shadow along the top and left of each pane: the glass sits back in the frame.
    inner = cv.clip(cv.blur(ImageChops.invert(cv.shift(glass, 5, 14)), 12), glass)
    cv.fill(inner, (6, 30, 80, 255), 0.35)


def paint_handle(cv: Canvas, g: Geo, shadow: bool = True) -> None:
    """The window handle on the mullion, lever pointing down (closed)."""
    c, (_, oy0, _, oy1) = g.c, g.opening
    hy = (oy0 + oy1) / 2 - 20
    hm = cv.mask(rrect((c - 21, hy - 46, c + 21, hy + 58), 21), rrect((c - 12, hy - 4, c + 12, hy + 128), 12))
    if shadow:
        cv.fill(cv.blur(cv.shift(hm, 3, 7), 5), BLACK, 0.30)
    cv.fill(hm, cv.vgrad(hy - 46, hy + 128, [(0, _hex("FFFFFF")), (1, _hex("D9DEE6"))]))
    cv.fill(cv.mask(ellipse(c, hy, 19, 19)), cv.vgrad(hy - 19, hy + 19, [(0, _hex("F4F6F9")), (1, _hex("C3CAD5"))]))


def draw(pixels: int, simple: bool = False) -> Image.Image:
    """The icon at `pixels` x `pixels`. `simple` drops the small details and snaps to pixels."""
    g = Geo(pixels if simple else None)
    cv = Canvas(pixels * max(SUPERSAMPLE, 1024 // pixels))
    paint_shadow(cv, g)
    paint_frame(cv, g, simple)
    paint_glass(cv, g, simple)
    if not simple:
        paint_handle(cv, g)
    return cv.img.resize((pixels, pixels), Image.LANCZOS)


# ---------------------------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------------------------

# (point size, scale) for every image a macOS app icon has.
MAC_SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def file_name(points: int, scale: int) -> str:
    return f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"


def render_all() -> dict[int, Image.Image]:
    """Every pixel size needed, keyed by pixels."""
    master = draw(1024)
    images = {1024: master, 64: draw(64)}
    for px in (16, 32):
        images[px] = draw(px, simple=True)
    for px in (128, 256, 512):
        images[px] = master.resize((px, px), Image.LANCZOS)
    return images


def _png_kwargs() -> dict:
    """Tag the PNGs as sRGB when Pillow has LittleCMS (it normally does)."""
    try:
        from PIL import ImageCms
        return {"icc_profile": ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()}
    except Exception:  # noqa: BLE001 - untagged PNGs are read as sRGB anyway
        return {}


def write_icon_files(images: dict[int, Image.Image]) -> None:
    kw = _png_kwargs()

    # Asset catalog.
    catalog = RESOURCES / "Assets.xcassets"
    appiconset = catalog / "AppIcon.appiconset"
    if appiconset.exists():
        shutil.rmtree(appiconset)
    appiconset.mkdir(parents=True)
    info = {"author": "xcode", "version": 1}
    (catalog / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
    entries = []
    for points, scale in MAC_SIZES:
        name = file_name(points, scale)
        images[points * scale].save(appiconset / name, **kw)
        entries.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
    (appiconset / "Contents.json").write_text(json.dumps({"images": entries, "info": info}, indent=2) + "\n")

    # .icns, built by iconutil from an .iconset in the scratch folder.
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for points, scale in MAC_SIZES:
            images[points * scale].save(iconset / file_name(points, scale), **kw)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(RESOURCES / "AppIcon.icns")], check=True)


def _srgb(rgba) -> str:
    return "srgb:" + ",".join(f"{v / 255:.5f}" for v in rgba)


def write_icon_composer_bundle() -> None:
    """AppIcon.icon for macOS 26 (Liquid Glass): orange fill, then the glass and the handle as layers.

    Icon Composer layers cover the whole 1024 canvas and the system masks them to its own shape,
    so the layers are drawn with the body (not the margin) filling the image."""
    bundle = RESOURCES / "AppIcon.icon"
    if bundle.exists():
        shutil.rmtree(bundle)
    (bundle / "Assets").mkdir(parents=True)
    g = Geo()
    view = (g.body[0], g.body[1], g.body[2] - g.body[0])
    layers = {}
    for name, paint in (("handle", lambda cv: paint_handle(cv, g, shadow=False)),
                        ("glass", lambda cv: paint_glass(cv, g, simple=False))):
        cv = Canvas(1024 * SUPERSAMPLE, view)
        paint(cv)
        cv.img.resize((1024, 1024), Image.LANCZOS).save(bundle / "Assets" / f"{name}.png", **_png_kwargs())
        layers[name] = {"image-name": f"{name}.png", "name": name}
    doc = {
        "fill": {
            "linear-gradient": [_srgb(FRAME[0][1]), _srgb(FRAME[-1][1])],
            "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}},
        },
        "groups": [
            {"layers": [layers["handle"]], "shadow": {"kind": "neutral", "opacity": 0.5},
             "translucency": {"enabled": False, "value": 0.5}},
            {"layers": [layers["glass"]], "shadow": {"kind": "neutral", "opacity": 0.5},
             "translucency": {"enabled": False, "value": 0.5}},
        ],
        "supported-platforms": {"squares": ["macOS"]},
    }
    (bundle / "icon.json").write_text(json.dumps(doc, indent=2) + "\n")


def check_with_actool() -> None:
    """Compile the asset catalog and the Icon Composer bundle the way Xcode would, one at a time.

    Each must produce Assets.car and AppIcon.icns, or the script exits with an error. (Given both
    at once, actool picks AppIcon.icon and ignores the hand-tuned AppIcon.appiconset.)"""
    for source in ("Assets.xcassets", "AppIcon.icon"):
        out = SCRATCH / "actool" / source
        if out.exists():
            shutil.rmtree(out)
        out.mkdir(parents=True)
        cmd = ["xcrun", "actool", str(RESOURCES / source), "--compile", str(out),
               "--platform", "macosx", "--minimum-deployment-target", "15.0", "--app-icon", "AppIcon",
               "--output-partial-info-plist", str(out / "partial.plist"),
               "--errors", "--warnings", "--notices", "--output-format", "human-readable-text"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        produced = sorted(p.name for p in out.iterdir())
        notes = [line for line in result.stdout.splitlines() if line and not line.startswith(("/*", str(out)))]
        print(f"actool {source}: exit {result.returncode}, produced {', '.join(produced)}")
        for line in notes:
            print("   ", line)
        if result.returncode != 0 or notes or not {"Assets.car", "AppIcon.icns"} <= set(produced):
            sys.exit(f"actool check failed for {source}")


def write_preview(images: dict[int, Image.Image]) -> Path:
    """Contact sheet: every size at 1:1 plus 16/32/64 zoomed, on a light and a dark background."""
    sizes = [16, 32, 64, 128, 256, 512]
    zoom = [(16, 8), (32, 4), (64, 2)]
    pad = 24
    row_h = 512 + 2 * pad
    width = pad + sum(px + pad for px in sizes) + sum(px * z + pad for px, z in zoom)
    sheet = Image.new("RGBA", (width, 2 * row_h))
    for row, bg in enumerate(((236, 236, 238, 255), (30, 30, 34, 255))):
        tile = Image.new("RGBA", (width, row_h), bg)
        x = pad
        for px in sizes:
            tile.alpha_composite(images[px], (x, row_h - pad - px))
            x += px + pad
        for px, z in zoom:
            big = images[px].resize((px * z, px * z), Image.NEAREST)
            tile.alpha_composite(big, (x, row_h - pad - px * z))
            x += px * z + pad
        sheet.alpha_composite(tile, (0, row * row_h))
    path = SCRATCH / "preview.png"
    SCRATCH.mkdir(parents=True, exist_ok=True)
    sheet.save(path)
    images[1024].save(SCRATCH / "master-1024.png")
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--preview", action="store_true", help="write a contact sheet to the scratch folder")
    ap.add_argument("--check", action="store_true", help="compile the icon files with actool")
    args = ap.parse_args()

    images = render_all()
    write_icon_files(images)
    write_icon_composer_bundle()
    for name in ("AppIcon.icns", "Assets.xcassets", "AppIcon.icon"):
        print("wrote", RESOURCES / name)
    if args.preview:
        print("preview:", write_preview(images))
    if args.check:
        check_with_actool()
    return 0


if __name__ == "__main__":
    sys.exit(main())
