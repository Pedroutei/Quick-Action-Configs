"""Looks for an Infestation cloud on the Fallout 76 map.

Called by InfestationHop.ahk after each map drag:
    python cloudscan.py <left> <top> <width> <height> [--save-all]

Grabs the game window area of the screen and checks it for a big patch of smooth,
warm dark grey (the cloud), ignoring the fixed on-screen panels.

Exit code 2 = cloud found, 0 = no cloud, 1 = error. The largest patch is printed.
Screenshots with a cloud are saved to cloudshots/ so the detector can be tuned.
"""
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageGrab

BLOCK = 40            # grid square size (at 1920x1080)
MIN_CLOUD_BLOCKS = 12 # patch size that counts as a cloud (clouds seen: 21 and 24; no-cloud maps: 4 at most)

# Fixed map-screen panels (1920x1080 coordinates): x0, y0, x1, y1
MASKS = [
    (40, 30, 150, 78),      # Z) MENU
    (45, 85, 388, 195),     # C.A.M.P. slots
    (45, 775, 388, 995),    # world activity
    (1275, 85, 1875, 540),  # challenges
    (1750, 30, 1875, 78),   # C) SOCIAL
    (1095, 30, 1250, 165),  # season icon
    (250, 1000, 1840, 1080),# key hints / atoms
    (1735, 860, 1905, 990), # weight / caps
    (1880, 0, 1920, 15),    # fps counter
]

SHOT_DIR = Path(__file__).with_name("cloudshots")


def cloud_blocks(a, gh, gw):
    """Grid squares whose typical (median) colour is the cloud's: dark, nearly colourless
    grey, blue a touch lower than red/green, red >= green. Using the median ignores map
    icons, roads and rivers drawn over the cloud. The Ash Heap is less green than blue and
    the dark olive map edges have green above red, so they don't match."""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    blocks = lambda m: np.median(m[:gh * BLOCK, :gw * BLOCK]
                                 .reshape(gh, BLOCK, gw, BLOCK).transpose(0, 2, 1, 3)
                                 .reshape(gh, gw, BLOCK * BLOCK), 2)
    br, sat = blocks(a.mean(2)), blocks(a.max(2) - a.min(2))
    rb, gb, rg = blocks(r - b), blocks(g - b), blocks(r - g)
    return ((br > 28) & (br < 70) & (sat <= 6)
            & (rb >= 0) & (rb <= 9) & (gb >= 0) & (gb <= 6) & (rg >= 0) & (rg <= 3))


def largest_patch(img):
    a = np.asarray(img.convert("RGB").resize((1920, 1080))).astype(np.int16)
    valid = np.ones(a.shape[:2], bool)
    for x0, y0, x1, y1 in MASKS:
        valid[y0:y1, x0:x1] = False

    gh, gw = 1080 // BLOCK, 1920 // BLOCK
    grid = (cloud_blocks(a, gh, gw)
            & (valid[:gh * BLOCK, :gw * BLOCK].reshape(gh, BLOCK, gw, BLOCK).mean((1, 3)) >= 0.9))

    best, best_at = 0, (0, 0)
    seen = np.zeros_like(grid)
    for j in range(gh):
        for i in range(gw):
            if not grid[j, i] or seen[j, i]:
                continue
            stack, n = [(j, i)], 0
            seen[j, i] = True
            while stack:
                y, x = stack.pop()
                n += 1
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < gh and 0 <= xx < gw and grid[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        stack.append((yy, xx))
            if n > best:
                best, best_at = n, (i * BLOCK, j * BLOCK)
    return best, best_at


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    save_all = "--save-all" in sys.argv
    if len(args) == 4:
        left, top, w, h = map(int, args)
        img = ImageGrab.grab(bbox=(left, top, left + w, top + h), all_screens=True)
    elif len(args) == 1:
        img = Image.open(args[0])   # test on a saved screenshot
    else:
        print(__doc__)
        return 1

    size, (x, y) = largest_patch(img)
    found = size >= MIN_CLOUD_BLOCKS
    print(f"{'CLOUD' if found else 'NONE'} patch={size} at={x},{y}")

    if (found or save_all) and len(args) == 4:
        SHOT_DIR.mkdir(exist_ok=True)
        tag = "cloud" if found else "none"
        img.save(SHOT_DIR / f"{time.strftime('%Y%m%d_%H%M%S')}_{tag}_{size}.png")
    return 2 if found else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # never crash the AHK loop
        print("ERROR", e)
        sys.exit(1)
