"""Ready for Launch's Earth map (#82): writes games/games/ready_for_launch/earth_map.png, an
equirectangular day map (RGB) with clouds in its alpha, for shaders/rfl_earth.gdshader.

Everything here is original and deterministic: the continents are rough outlines typed by hand
as (longitude, latitude) lists below (no map data, no imagery), roughened into natural coasts with
filtered noise; the land's colours come from latitude, a few hand-placed desert and forest
regions and noise; the clouds are warped noise with spiral storms. Needs numpy and scipy:

    python games/tools/art/make_earth_map.py
"""
import os
import struct
import zlib

import numpy as np
from scipy import ndimage

W, H = 2048, 1024
SS = 2  # the mask is drawn this much finer, then filtered down
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "games", "ready_for_launch", "earth_map.png")

LAND = {
    "north_america": [(-168, 66), (-162, 70), (-156, 71), (-141, 70), (-128, 70), (-115, 68), (-108, 68), (-95, 68),
        (-94, 72), (-85, 70), (-82, 68), (-87, 64), (-93, 61), (-94, 58), (-88, 57), (-82, 55), (-80, 51), (-79, 54),
        (-77, 57), (-78, 62), (-72, 62), (-66, 59), (-60, 55), (-56, 52), (-60, 50), (-65, 49), (-60, 47), (-64, 45),
        (-67, 45), (-70, 43), (-71, 41), (-74, 40), (-76, 37), (-76, 35), (-81, 31), (-80, 26), (-81, 25), (-83, 29),
        (-85, 30), (-90, 29), (-94, 29), (-97, 27), (-98, 22), (-96, 19), (-91, 18), (-90, 21), (-87, 21), (-88, 16),
        (-84, 15), (-83, 11), (-80, 9), (-77, 8), (-80, 7), (-85, 10), (-92, 14), (-96, 16), (-105, 20), (-109, 26),
        (-113, 31), (-110, 23), (-115, 29), (-117, 33), (-121, 35), (-124, 40), (-124, 47), (-128, 51), (-133, 56),
        (-140, 60), (-148, 60), (-152, 59), (-158, 56), (-165, 54), (-160, 59), (-166, 62)],
    "greenland": [(-73, 78), (-60, 82), (-30, 84), (-18, 80), (-20, 72), (-32, 68), (-42, 62), (-45, 60), (-52, 65),
        (-55, 70), (-60, 76)],
    "baffin": [(-80, 73), (-68, 70), (-62, 66), (-70, 63), (-78, 65), (-88, 71)],
    "ellesmere": [(-90, 77), (-70, 83), (-62, 82), (-78, 76)],
    "victoria": [(-118, 73), (-105, 73), (-102, 69), (-115, 69)],
    "cuba": [(-85, 22), (-80, 23), (-74, 20), (-78, 20)],
    "hispaniola": [(-74, 19.5), (-68.5, 18.5), (-72, 18)],
    "south_america": [(-77, 8), (-72, 12), (-62, 10.5), (-52, 5), (-50, 0), (-44, -2), (-35, -6), (-35, -9), (-39, -15),
        (-41, -22), (-48, -26), (-53, -33), (-58, -35), (-57, -38), (-63, -41), (-65, -45), (-68, -50), (-68, -54),
        (-72, -53), (-75, -48), (-73, -40), (-71, -30), (-70, -18), (-76, -14), (-81, -6), (-80, 0), (-78, 3)],
    "africa": [(-6, 35), (10, 37), (11, 33), (20, 32), (25, 31.5), (32, 31), (34, 28), (37, 21), (39, 15), (43, 11),
        (51, 12), (48, 5), (42, -1), (39, -6), (40, -15), (35, -20), (35, -24), (32, -29), (27, -34), (20, -35),
        (18, -33), (15, -27), (12, -17), (13, -8), (9, -1), (9, 4), (4, 6), (-4, 5), (-8, 4), (-13, 8), (-17, 14),
        (-17, 21), (-13, 27), (-10, 31)],
    "madagascar": [(49, -12), (50, -16), (47, -25), (44, -25), (44, -18)],
    "eurasia": [(-9, 37), (-9, 43), (-2, 43.5), (-1, 46), (-5, 48), (2, 51), (8, 54), (8, 57), (11, 56), (11, 54), (20, 55),
        (21, 59), (29, 60), (23, 60), (21, 63), (25, 65), (22, 66), (17, 62), (18, 59), (13, 55.5), (11, 59), (6, 58),
        (5, 62), (14, 68), (25, 71), (40, 67), (44, 68), (60, 69), (68, 72), (80, 73), (105, 77), (113, 74), (130, 71),
        (160, 70), (180, 69), (180, 65), (178, 62), (165, 60), (163, 56), (156, 51), (156, 58), (143, 59), (135, 54),
        (141, 50), (135, 44), (130, 42), (128, 39), (129, 35), (126, 34), (125, 38), (121, 40), (118, 38), (122, 37),
        (120, 32), (122, 29), (117, 23), (110, 21), (106, 19), (109, 13), (105, 9), (100, 13), (103, 2), (101, 3),
        (98, 9), (97, 16), (94, 17), (91, 22), (87, 21), (80, 15), (80, 10), (77.5, 8), (73, 18), (72, 21), (67, 25),
        (61, 25), (57, 26), (52, 28), (48, 30), (51, 25), (56, 25), (59, 22), (55, 17), (45, 13), (43, 13), (39, 21),
        (35, 28), (34, 31), (36, 36), (30, 36), (27, 37), (26, 40), (23, 40), (23, 37), (20, 40), (13, 45), (19, 42),
        (16, 41), (18, 40), (16, 38), (15, 40), (12, 42), (9, 44), (3, 43), (0, 39), (-2, 37), (-6, 36)],
    "britain": [(-5, 50), (1, 51), (1, 53), (-2, 56), (-3, 58.5), (-6, 58), (-5, 54)],
    "ireland": [(-10, 52), (-6, 52), (-6, 55), (-9, 55)],
    "iceland": [(-24, 65), (-14, 66), (-14, 64), (-22, 63.5)],
    "japan": [(130, 31), (132, 34), (136, 36), (141, 41), (142, 45), (145, 44), (141, 38), (140, 35), (135, 33)],
    "taiwan": [(120, 23), (122, 25), (121, 22)],
    "philippines": [(120, 18), (122, 18), (125, 8), (122, 7), (120, 14)],
    "sumatra": [(95, 5), (104, -3), (106, -6), (101, -3)],
    "java": [(105, -6), (115, -8), (106, -8)],
    "borneo": [(109, 1), (117, 7), (119, 1), (116, -4), (110, -3)],
    "sulawesi": [(120, 1), (125, 1), (122, -5), (119, -4)],
    "new_guinea": [(131, -1), (141, -3), (148, -7), (150, -10), (141, -9), (134, -4)],
    "australia": [(114, -22), (122, -18), (130, -12), (136, -12), (136, -15), (141, -17), (142, -11), (146, -19),
        (153, -26), (151, -34), (146, -39), (140, -38), (135, -34), (130, -32), (124, -33), (115, -34)],
    "tasmania": [(145, -41), (148, -41), (147, -43.5)],
    "new_zealand_n": [(173, -35), (178, -38), (175, -41), (174, -39)],
    "new_zealand_s": [(167, -46), (171, -46), (174, -42), (172, -41)],
    "sri_lanka": [(80, 9.5), (82, 7), (80.5, 6)],
    "novaya_zemlya": [(52, 71), (56, 75), (68, 77), (60, 73)],
    "svalbard": [(12, 78), (25, 80), (22, 77)],
    "antarctica": [(-180, -90), (180, -90), (180, -78), (165, -72), (140, -66), (100, -66), (60, -67), (30, -69), (0, -70),
        (-30, -76), (-60, -75), (-60, -64), (-70, -70), (-100, -73), (-150, -76), (-180, -78)],
}
WATER = {
    "black_sea": [(28, 42), (31, 46), (37, 45), (41, 42), (35, 42), (30, 41)],
    "caspian": [(47, 45), (53, 46), (54, 38), (50, 37), (49, 41)],
    "great_lakes": [(-88, 47), (-80, 46), (-82, 42), (-87, 42)],
}
## (longitude, latitude, radius in degrees, strength): dry regions, and green ones with a minus.
DRY = [(10, 23, 22, 1.0), (30, 22, 14, 1.0), (45, 23, 12, 1.0), (65, 30, 10, 0.7), (100, 42, 14, 0.8), (134, -25, 14, 0.9),
       (-110, 33, 10, 0.7), (20, -24, 9, 0.7), (-69, -30, 6, 0.6), (-68, -46, 6, 0.5), (80, 40, 8, 0.6)]
WET = [(-60, -5, 16, 1.0), (22, 0, 12, 1.0), (110, 2, 16, 0.9), (-85, 40, 14, 0.5), (15, 50, 16, 0.5), (110, 30, 12, 0.5)]


def noise(shape, beta, seed):
    """Periodic noise with a 1/f^beta spectrum, 0-1: it wraps in longitude with no seam."""
    rng = np.random.default_rng(seed)
    fy = np.fft.fftfreq(shape[0])[:, None]
    fx = np.fft.rfftfreq(shape[1])[None, :]
    f = np.sqrt(fy * fy + fx * fx)
    f[0, 0] = 1.0
    spec = (rng.normal(size=f.shape) + 1j * rng.normal(size=f.shape)) / f ** (beta / 2.0)
    spec[0, 0] = 0.0
    x = np.fft.irfft2(spec, s=shape)
    x -= x.min()
    return x / x.max()


def stretch(x):
    """Rescales to 0-1 by rank-like percentiles, so thresholds below mean the same at any seed."""
    lo, hi = np.percentile(x, [1, 99])
    return np.clip((x - lo) / (hi - lo), 0.0, 1.0)


def fill(mask, poly, value, w, h):
    """Even-odd scanline fill of a (lon, lat) polygon into `mask`."""
    pts = np.array(poly, dtype=float)
    xs = (pts[:, 0] + 180.0) / 360.0 * w
    ys = (90.0 - pts[:, 1]) / 180.0 * h
    x2, y2 = np.roll(xs, -1), np.roll(ys, -1)
    for row in range(max(int(ys.min()), 0), min(int(ys.max()) + 1, h)):
        y = row + 0.5
        hit = ((ys <= y) & (y2 > y)) | ((y2 <= y) & (ys > y))
        if not hit.any():
            continue
        cross = np.sort(xs[hit] + (y - ys[hit]) / (y2[hit] - ys[hit]) * (x2[hit] - xs[hit]))
        for a, b in zip(cross[0::2], cross[1::2]):
            mask[row, max(int(a), 0):min(int(b) + 1, w)] = value


def warp(field, dx, dy):
    """Samples `field` at each pixel moved by (dx, dy), wrapping in longitude."""
    h, w = field.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    return ndimage.map_coordinates(field, [np.clip(yy + dy, 0, h - 1), (xx + dx) % w], order=1, mode="grid-wrap")


def region(lon, lat, spots):
    out = np.zeros_like(lon)
    for x, y, r, s in spots:
        d = np.minimum(np.abs(lon - x), 360.0 - np.abs(lon - x))
        out = np.maximum(out, s * np.exp(-(d * d + (lat - y) ** 2) / (r * r)))
    return out


def clouds(lon, lat):
    h, w = lon.shape
    base = noise((h, w), 3.0, 4)
    dx = (noise((h, w), 3.2, 5) - 0.5) * 240.0
    dy = (noise((h, w), 3.2, 6) - 0.5) * 120.0
    field = warp(base, dx, dy)
    # Spiral storms: twist the field round a few centres, tightest in the middle.
    rng = np.random.default_rng(8)
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    for k in range(14):
        cy = (90.0 - rng.choice([-52, -44, -30, 18, 26, 44, 52, 58]) + rng.uniform(-5, 5)) / 180.0 * h
        cx = rng.uniform(0, w)
        ddx = (xx - cx + w / 2) % w - w / 2
        ddy = yy - cy
        d = np.sqrt(ddx * ddx + ddy * ddy)
        size = rng.uniform(60, 130)
        twist = 3.2 * np.exp(-d / size) * (1.0 if cy < h / 2 else -1.0)
        c, s = np.cos(twist), np.sin(twist)
        field = warp(field, (ddx * c - ddy * s) - ddx, (ddx * s + ddy * c) - ddy)
    field = stretch(field)
    fine = stretch(noise((h, w), 1.9, 7))
    field = field * 0.8 + fine * 0.2
    # Bands: the tropics' line of cloud and the storm tracks, clear subtropics.
    a = np.abs(lat)
    band = (0.26 * np.exp(-((lat - 5.0) / 9.0) ** 2) + 0.34 * np.exp(-((a - 52.0) / 15.0) ** 2)
            - 0.16 * np.exp(-((a - 25.0) / 9.0) ** 2))
    return np.clip((field + band - 0.66) / 0.2, 0.0, 1.0) ** 0.8


def main():
    w, h = W * SS, H * SS
    mask = np.zeros((h, w), dtype=np.float32)
    for poly in LAND.values():
        fill(mask, poly, 1.0, w, h)
    for poly in WATER.values():
        fill(mask, poly, 0.0, w, h)
    # Natural coasts: push the outlines about with noise, at two scales.
    amp = 11.0 * SS
    mask = warp(mask, (noise((h, w), 2.2, 1) - 0.5) * amp * 2.0, (noise((h, w), 2.2, 2) - 0.5) * amp * 2.0)
    mask = ndimage.zoom(ndimage.gaussian_filter(mask, SS * 0.8, mode=("nearest", "wrap")), 1.0 / SS, order=1)[:H, :W]
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    lon = (xx + 0.5) / W * 360.0 - 180.0
    lat = 90.0 - (yy + 0.5) / H * 180.0
    land = np.clip((mask - 0.42) / 0.16, 0.0, 1.0)
    grain = stretch(noise((H, W), 2.0, 3))
    rock = stretch(noise((H, W), 1.6, 9))
    a = np.abs(lat)

    def col(hexcode):
        return np.array([int(hexcode[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])

    def mix(x, y, t):
        return x * (1.0 - t[..., None]) + y * t[..., None]

    # The sea: deep, lighter over the shelves round the coasts.
    shelf = np.clip(ndimage.gaussian_filter(mask, 7.0, mode=("nearest", "wrap")) * 2.4, 0.0, 1.0)
    sea = mix(np.broadcast_to(col("0a2c63"), (H, W, 3)), np.broadcast_to(col("1b6fa6"), (H, W, 3)), shelf ** 1.6)
    # The land: forest, grass, desert, tundra, rock; ice at the poles.
    dry = np.clip(region(lon, lat, DRY) + (grain - 0.5) * 0.5 - region(lon, lat, WET) * 0.8, 0.0, 1.0)
    wet = np.clip(region(lon, lat, WET) + (grain - 0.5) * 0.3, 0.0, 1.0)
    ground = mix(np.broadcast_to(col("5f8a45"), (H, W, 3)), np.broadcast_to(col("1f5a2e"), (H, W, 3)), wet)
    ground = mix(ground, np.broadcast_to(col("d2b277"), (H, W, 3)), np.clip(dry * 1.5, 0.0, 1.0))
    ground = mix(ground, np.broadcast_to(col("7c7a62"), (H, W, 3)), np.clip((a - 56.0) / 12.0, 0.0, 1.0) * 0.85)
    ground = mix(ground, np.broadcast_to(col("6e5f4d"), (H, W, 3)), np.clip((rock - 0.72) / 0.2, 0.0, 1.0) * 0.6)
    ice_land = np.clip((a - 72.0 + (grain - 0.5) * 12.0) / 4.0, 0.0, 1.0)
    greenland = np.zeros((H, W), dtype=np.float32)
    fill(greenland, LAND["greenland"], 1.0, W, H)
    ice_land = np.maximum(ice_land, ndimage.gaussian_filter(greenland, 3.0))
    ground = mix(ground, np.broadcast_to(col("eef3f6"), (H, W, 3)), ice_land)
    surface = mix(sea, ground, land)
    pack = np.clip((a - 76.0 + (grain - 0.5) * 16.0) / 5.0, 0.0, 1.0) * (lat > 0)
    surface = mix(surface, np.broadcast_to(col("e6eef3"), (H, W, 3)), pack)
    rgba = np.dstack([surface, clouds(lon, lat)])
    data = (np.clip(rgba, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    raw = b"".join(b"\0" + data[row].tobytes() for row in range(H))

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(OUT, "wb") as f:
        f.write(png)
    print(f"{os.path.normpath(OUT)}: {len(png) / 1024:.0f} KB")


if __name__ == "__main__":
    main()
