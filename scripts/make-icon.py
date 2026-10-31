#!/usr/bin/env python3
"""Build Luksfer's app icon and logo from the branding image and write every file macOS needs.

Run from anywhere (needs Python 3 with Pillow; iconutil and actool come with macOS / Xcode):

    python3 scripts/make-icon.py            # write the icon files into Resources/ and the logo
    python3 scripts/make-icon.py --preview  # also write a contact sheet of all sizes
    python3 scripts/make-icon.py --check    # also compile the icon files with actool

Reads docs/brand/luksfer-branding.png: the icon (a glass block on a dark rounded square) on the
left, the logo (a small block and the word "luksfer") on the right.

Writes, inside the repo:
    Resources/AppIcon.icns                         built by iconutil from a full .iconset
    Resources/Assets.xcassets/Contents.json
    Resources/Assets.xcassets/AppIcon.appiconset/  every mac size as PNG + Contents.json
    Resources/AppIcon.icon/                        Icon Composer bundle (macOS 26 Liquid Glass)
    docs/brand/logo.png                            the logo, for the README

Temporary files (the .iconset, the preview, the actool output) go to ~/Library/Caches/luksfer-dev/icon/.

The icon art is a square cut from the source around the glass block, so the block fills about 80% of
the icon (in the source it fills about 66%, which looks small next to other icons). Its dark parts are
lightened, most at the top, so the tile's edge shows in a dark Dock. The art is scaled to the 824 x 824
body of the macOS icon grid and masked to Apple's continuous-corner shape, with the usual soft drop
shadow in the margin.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parent.parent
RESOURCES = REPO / "Resources"
SOURCE = REPO / "docs" / "brand" / "luksfer-branding.png"
LOGO = REPO / "docs" / "brand" / "logo.png"
SCRATCH = Path.home() / "Library" / "Caches" / "luksfer-dev" / "icon"

# Measured in the source image: the centre and size of the glass block (with its glow) inside the
# icon's rounded square, and the logo box (left, top, right, bottom) with some dark background.
BLOCK_CENTER = (374.5, 486.0)
BLOCK_SIZE = 269.0
BLOCK_FILL = 0.80  # how much of the icon the block fills
LIFT = 0.5  # how far the darkest pixels move toward LIFT_COLOR at the top (half that at the bottom)
LIFT_COLOR = (96, 116, 148)
LOGO_BOX = (680, 345, 1450, 625)
LOGO_RADIUS = 28

GRID = 1024.0  # all geometry is in units of the 1024 x 1024 master
SUPERSAMPLE = 4
BODY = (100.0, 100.0, 924.0, 924.0)  # 824 x 824 body, 100 px margin (macOS Big Sur+ icon grid)
BODY_R = 185.0

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


def mask(pixels: int, box, radius) -> Image.Image:
    """Antialiased mask of a continuous-corner rectangle given in grid units."""
    big = pixels * SUPERSAMPLE
    k = big / GRID
    m = Image.new("L", (big, big), 0)
    ImageDraw.Draw(m).polygon([(x * k, y * k) for x, y in rrect(box, radius)], fill=255)
    return m.resize((pixels, pixels), Image.LANCZOS)


# ---------------------------------------------------------------------------------------------
# The icon
# ---------------------------------------------------------------------------------------------

def source() -> Image.Image:
    return Image.open(SOURCE).convert("RGB")


def icon_art(pixels: int) -> Image.Image:
    """The square around the block, scaled to `pixels` x `pixels` and lightened, without a mask."""
    cx, cy = BLOCK_CENTER
    half = BLOCK_SIZE / BLOCK_FILL / 2
    art = source().crop((round(cx - half), round(cy - half), round(cx + half), round(cy + half)))
    art = art.resize((pixels, pixels), Image.LANCZOS)
    # A soft top light: the darker the pixel and the higher up, the more it moves toward LIFT_COLOR.
    dark = art.convert("L").point(lambda v: round(255 * max(0.0, 1 - v / 110) ** 1.5))
    ramp = Image.linear_gradient("L").resize((pixels, pixels)).point(lambda v: round(255 - v * 0.55))
    amount = ImageChops.multiply(dark, ramp).point(lambda v: round(v * LIFT))
    return Image.composite(Image.new("RGB", art.size, LIFT_COLOR), art, amount)


def draw(pixels: int) -> Image.Image:
    """The icon at `pixels` x `pixels`: shadow, then the art masked to the body."""
    k = pixels / GRID
    img = Image.new("RGBA", (pixels, pixels), (0, 0, 0, 0))
    body = mask(pixels, BODY, BODY_R)

    # Drop shadow inside the margin: a wide soft one and a tight contact one.
    for dy, blur, opacity in ((12, 22, 0.30), (3, 4, 0.18)):
        shifted = Image.new("L", body.size, 0)
        shifted.paste(body, (0, round(dy * k)))
        alpha = shifted.filter(ImageFilter.GaussianBlur(blur * k)).point(lambda v: round(v * opacity))
        shadow = Image.new("RGBA", body.size, (0, 0, 0, 255))
        shadow.putalpha(alpha)
        img.alpha_composite(shadow)

    side = round((BODY[2] - BODY[0]) * k)
    art = Image.new("RGBA", (pixels, pixels), (0, 0, 0, 0))
    art.paste(icon_art(side).convert("RGBA"), (round(BODY[0] * k), round(BODY[1] * k)))
    art.putalpha(body)
    img.alpha_composite(art)
    # The source is about 400 px wide, so the large sizes are scaled up: sharpen a little.
    return img.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))


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
    images = {1024: master}
    for px in (16, 32, 64, 128, 256, 512):
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


def _srgb(rgb) -> str:
    return "srgb:" + ",".join(f"{v / 255:.5f}" for v in rgb) + ",1.00000"


def write_icon_composer_bundle() -> None:
    """AppIcon.icon for macOS 26 (Liquid Glass): the icon square as one full-bleed layer.

    Icon Composer layers cover the whole 1024 canvas and the system masks them to its own shape,
    so the layer is the art without a mask or shadow. The fill is the colour along the art's
    bottom edge, for any pixel the system's shape shows outside the layer."""
    bundle = RESOURCES / "AppIcon.icon"
    if bundle.exists():
        shutil.rmtree(bundle)
    (bundle / "Assets").mkdir(parents=True)
    art = icon_art(1024)
    art.save(bundle / "Assets" / "block.png", **_png_kwargs())
    average = art.crop((256, 960, 768, 1024)).resize((1, 1), Image.BOX).getpixel((0, 0))
    doc = {
        "fill": {"solid": _srgb(average)},
        "groups": [
            {"layers": [{"image-name": "block.png", "name": "block"}],
             "shadow": {"kind": "neutral", "opacity": 0.5},
             "translucency": {"enabled": False, "value": 0.5}},
        ],
        "supported-platforms": {"squares": ["macOS"]},
    }
    (bundle / "icon.json").write_text(json.dumps(doc, indent=2) + "\n")


def write_logo() -> None:
    """The logo on its dark background, with rounded corners so it sits well on light pages too."""
    logo = source().crop(LOGO_BOX).convert("RGBA")
    w, h = logo.size
    m = Image.new("L", (w * SUPERSAMPLE, h * SUPERSAMPLE), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * SUPERSAMPLE - 1, h * SUPERSAMPLE - 1),
                                        LOGO_RADIUS * SUPERSAMPLE, fill=255)
    logo.putalpha(m.resize((w, h), Image.LANCZOS))
    logo.save(LOGO, optimize=True, **_png_kwargs())


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
    write_logo()
    for name in ("AppIcon.icns", "Assets.xcassets", "AppIcon.icon"):
        print("wrote", RESOURCES / name)
    print("wrote", LOGO)
    if args.preview:
        print("preview:", write_preview(images))
    if args.check:
        check_with_actool()
    return 0


if __name__ == "__main__":
    sys.exit(main())
