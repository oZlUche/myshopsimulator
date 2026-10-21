#!/usr/bin/env python3
"""高清版精灵（assets/sprites_hd/）：以标清设计为底，放大两倍后再补细节 —— 圆头、眼睛高光、领口、袖口、裤线、
发丝、流苏、地砖的砖缝与色差、路面骨料、草叶。每张图正好是标清的 2 倍大，锚点也翻倍，游戏里共用标清的元数据与坐标，
只是 Iso.S = 2、每个标清单位画 1 个屏幕像素（Iso.PX = 2 不变）。
由 gen_sprites.py 一起调用：python3 tools/pixelart/gen_sprites.py
"""
import math
import os
import random

from PIL import Image

import gen_equipment
import gen_sprites as sd
from gen_sprites import LIT, SHADE, DEEP, Layer, outline_of, HAIR_STYLES, FRAMES, DIRS

S = 2
FW, FH = sd.FW * S, sd.FH * S
TW, TH = sd.TW * S, sd.TH * S

FIXED = {
    "face": {1: (42, 34, 48, 255), 2: (150, 140, 160, 255), 3: (200, 140, 110, 255), 4: (222, 186, 156, 255), 5: (120, 92, 76, 255)},
    "shoes": {1: (58, 44, 50, 255), 2: (40, 30, 36, 255), 3: (84, 66, 72, 255)},
    "outline": {LIT: (20, 18, 26, 150)},
}


# ---------------------------------------------------------------- 人物

def head_circle(bob):
    """高清的头：直径 24 的圆，占 x 12..35、y 4..27（标清 6..17、2..13 的两倍）。"""
    m = Layer(FW, FH)
    cx, cy, r = 24.0, 16.0 + bob, 12.0
    for y in range(FH):
        for x in range(FW):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                m.put(x, y, LIT)
    return m


def refine_body(L, frame, back):
    """在放大两倍的标清图层上补高清细节。L 是 {层名: Layer}（已放大）。"""
    bob = -S if frame in (1, 3) else 0
    head_sd = sd.head_mask().upscale(S).shift(0, bob)
    head_hd = head_circle(bob)
    # 皮肤：换成圆头，右侧两级阴影，下巴一圈阴影
    skin = Layer(FW, FH)
    for (x, y), v in L["skin"].px.items():
        if (x, y) not in head_sd:
            skin.put(x, y, v)
    for (x, y) in head_hd.px:
        v = LIT
        if x >= 33:
            v = 200
        elif x >= 30:
            v = 215
        if y >= 16 + bob + 10:
            v = min(v, 215)
        skin.put(x, y, v)
    L["skin"] = skin
    # 脸：眼睛 3×4 带高光、眉毛、鼻尖、两像素的嘴
    face = Layer(FW, FH)
    if not back:
        for ex in (21, 28):
            for dy in range(4):
                for dx in range(3):
                    face.put(ex + dx, 16 + bob + dy, 1)
            face.put(ex, 16 + bob, 2)
            face.put(ex + 1, 16 + bob, 2)
            face.put(ex, 17 + bob, 2)
            for dx in range(3):
                face.put(ex + dx, 13 + bob, 5)
        face.put(25, 20 + bob, 4)
        face.put(26, 22 + bob, 3)
        face.put(27, 22 + bob, 3)
    L["face"] = face
    # 上衣：左侧一列高光、右侧两级阴影、V 领、腰带、袖口
    top = Layer(FW, FH)
    for (x, y), v in L["top"].px.items():
        top.put(x, y, v)
    t0 = 30 + bob
    for y in range(t0, t0 + 16):
        for x in range(14, 34):
            if (x, y) not in top:
                continue
            v = 240
            if x <= 15:
                v = 255
            elif x >= 32:
                v = 160
            elif x >= 30:
                v = 190
            if y >= t0 + 14:
                v = 170 if y == t0 + 14 else 140
            top.put(x, y, v)
    if not back:
        for i, (a, b) in enumerate([(20, 27), (21, 26), (22, 25), (23, 24)]):
            for x in range(a, b + 1):
                top.put(x, t0 + i, DEEP)
    else:
        for y in range(t0, t0 + 3):
            for x in range(22, 26):
                top.put(x, y, SHADE)
    swing = S if frame == 1 else (-S if frame == 3 else 0)
    la, ra = t0 - swing, t0 + swing
    for y in range(la + 12, la + 14):
        for x in range(10, 14):
            top.put(x, y, 205)
    for y in range(ra + 12, ra + 14):
        for x in range(34, 38):
            top.put(x, y, 150)
    L["top"] = top
    # 裤子：外侧一条亮线、内侧一条暗线
    bottom = Layer(FW, FH)
    for (x, y), v in L["bottom"].px.items():
        bottom.put(x, y, v)
    cols = sorted({x for (x, y) in bottom.px})
    if cols:
        legs = []
        run = [cols[0]]
        for x in cols[1:]:
            if x == run[-1] + 1:
                run.append(x)
            else:
                legs.append(run)
                run = [x]
        legs.append(run)
        for leg in legs:
            lx, rx = leg[0], leg[-1]
            for (x, y), v in list(bottom.px.items()):
                if lx <= x <= rx:
                    nv = 240 if v == LIT else v
                    if x == lx + 1 and v == LIT:
                        nv = 255
                    if x == rx:
                        nv = min(nv, 170)
                    bottom.put(x, y, nv)
    L["bottom"] = bottom
    # 鞋：鞋底一行更深，鞋面一行高光
    shoes = Layer(FW, FH)
    rows = sorted({y for (x, y) in L["shoes"].px})
    for (x, y), v in L["shoes"].px.items():
        nv = v
        if y == rows[-1] or (len(rows) > 2 and y == rows[-1] - 1 and False):
            nv = 2
        shoes.put(x, y, nv)
    L["shoes"] = shoes
    # 围巾：底边做成流苏
    scarf = Layer(FW, FH)
    rows = sorted({y for (x, y) in L["scarf"].px})
    for (x, y), v in L["scarf"].px.items():
        if v == DEEP and (x % 2 == 1):
            continue
        scarf.put(x, y, v)
    L["scarf"] = scarf
    return L


def refine_hair(h, style, back, bob):
    """放大后的头发贴合圆头：去掉圆外的角，前额加几缕参差，顶上一道高光。"""
    head_sd = sd.head_mask().upscale(S).shift(0, bob)
    head_hd = head_circle(bob)
    out = Layer(FW, FH)
    for (x, y), v in h.px.items():
        if (x, y) in head_sd and (x, y) not in head_hd:
            continue
        nv = 235 if v == LIT else v
        out.put(x, y, nv)
    # 高光：头顶偏左两行
    for y in (6 + bob, 7 + bob):
        for x in range(16, 24):
            if (x, y) in out:
                out.put(x, y, 255)
    if style != "cap":
        for x in range(26, 30):
            if (x, 9 + bob) in out:
                out.put(x, 9 + bob, 225)
    # 刘海参差：正面在发际线上每隔 4 列挖一个像素；背面不用
    if not back and style != "cap":
        for x in range(14, 34, 4):
            ys = [y for (xx, y) in out.px if xx == x and y <= 16 + bob]
            if not ys:
                continue
            yb = max(ys)
            below = (x, yb + 1)
            if below not in out and below in head_hd:
                del out.px[(x, yb)]
    return out


def build_person():
    sheets = {k: Image.new("LA", (FW * FRAMES, FH * DIRS), (0, 0)) for k in ["skin", "top", "bottom", "scarf"]}
    sheets["face"] = Image.new("RGBA", (FW * FRAMES, FH * DIRS), (0, 0, 0, 0))
    sheets["shoes"] = Image.new("RGBA", (FW * FRAMES, FH * DIRS), (0, 0, 0, 0))
    hair = Image.new("LA", (FW * FRAMES, FH * DIRS * len(HAIR_STYLES)), (0, 0))
    outline = Image.new("RGBA", (FW * FRAMES, FH * DIRS * len(HAIR_STYLES)), (0, 0, 0, 0))
    for d in range(DIRS):
        back = d >= 2
        mirror = d in (1, 3)
        for f in range(FRAMES):
            L0, bob = sd.body_frame(f, back)
            L = {k: v.upscale(S) for k, v in L0.items()}
            L = refine_body(L, f, back)
            hairs = {}
            for s in HAIR_STYLES:
                h0 = (sd.hair_back(s) if back else sd.hair_front(s)).shift(0, bob).upscale(S)
                hairs[s] = refine_hair(h0, s, back, bob * S)
            outlines = {s: outline_of(list(L.values()) + [hairs[s]]) for s in HAIR_STYLES}
            if mirror:
                L = {k: v.mirror() for k, v in L.items()}
                hairs = {s: h.mirror() for s, h in hairs.items()}
                outlines = {s: o.mirror() for s, o in outlines.items()}
            ox, oy = f * FW, d * FH
            for k, l in L.items():
                for (x, y), v in l.px.items():
                    if k in FIXED:
                        sheets[k].putpixel((ox + x, oy + y), FIXED[k][v])
                    else:
                        sheets[k].putpixel((ox + x, oy + y), (v, 255))
            for i, s in enumerate(HAIR_STYLES):
                for (x, y), v in hairs[s].px.items():
                    hair.putpixel((ox + x, oy + i * FH * DIRS + y), (v, 255))
                for (x, y), v in outlines[s].px.items():
                    outline.putpixel((ox + x, oy + i * FH * DIRS + y), FIXED["outline"][LIT])
    sheets["hair"] = hair
    sheets["outline"] = outline
    return sheets


# ---------------------------------------------------------------- 地面

def iso_inside(x, y):
    if not (0 <= x < TW and 0 <= y < TH):
        return False
    r = y if y < TH // 2 else TH - 1 - y
    half = 2 * r + 1
    return TW // 2 - half <= x < TW // 2 + half


def tile_uv(x, y):
    cx, cy = x + 0.5 - TW / 2, y + 0.5 - TH / 2
    return (cx / (TW / 2) + cy / (TH / 2) + 1) / 2, (-cx / (TW / 2) + cy / (TH / 2) + 1) / 2


def shade(c, k):
    return tuple(max(0, min(255, int(v * (1 + k)))) for v in c)


def ground_tile(kind, variant, rng):
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    pal = {
        "pavement": [(150, 142, 128), (128, 120, 108), (160, 152, 138), (118, 110, 100)],
        "road": [(92, 90, 101), (84, 82, 93), (102, 100, 112), (70, 68, 78)],
        "grass": [(66, 94, 60), (78, 110, 68), (56, 82, 52), (48, 70, 46)],
        "lot": [(60, 63, 53), (53, 56, 47), (68, 71, 60), (46, 49, 41)],
        "concrete": [(118, 117, 112), (108, 107, 102), (128, 127, 121), (96, 95, 90)],
        "wood": [(178, 140, 98), (156, 118, 78), (196, 160, 118), (112, 80, 52)],
        "tile": [(190, 184, 172), (176, 170, 158), (204, 198, 186), (140, 134, 124)],
    }[kind]
    slab_tone = {(a, b): rng.uniform(-0.04, 0.04) for a in range(2) for b in range(2)}
    # 水泥地：一格一块大板带伸缩缝；花色 1 多一块两层的淡污渍和一道带分叉的裂缝
    stain_in, stain_out, crack = set(), set(), set()
    if kind == "concrete" and variant == 1:
        cx, cy = rng.randrange(14, TW - 14), rng.randrange(7, TH - 7)
        for dy in range(-5, 6):
            for dx in range(-9, 10):
                d = (dx / 9.5) ** 2 + (dy / 5.5) ** 2
                if d < 1:
                    (stain_in if d < 0.45 else stain_out).add((cx + dx, cy + dy))
        x, y = rng.randrange(16, TW - 28), rng.randrange(8, TH - 8)
        for n in range(14):
            crack.add((x, y))
            if n == 6:
                bx, by = x, y
                for _ in range(5):
                    bx += 1
                    by += rng.choice((-1, -1, 0))
                    crack.add((bx, by))
            x += 1
            y += rng.choice((-1, 0, 0, 1))
    # 木地板：同标清的布局（4 块板沿 gx 铺），多一条板边倒角亮线、两道木纹、板头亮边
    planks = []
    if kind == "wood":
        for i in range(4):
            planks.append({
                "tone": rng.uniform(-0.03, 0.03),
                "seam": 0.0 if rng.random() < 0.5 else rng.uniform(0.3, 0.7),
                "grain": [(i / 4 + rng.uniform(0.07, 0.2), rng.uniform(0.0, 0.45), rng.uniform(0.55, 1.0)) for _ in range(2)],
            })
    blades = set()
    if kind == "grass":
        for _ in range(26):
            blades.add((rng.randrange(TW), rng.randrange(TH)))
    pebbles = set()
    if kind == "lot":
        for _ in range(10):
            pebbles.add((rng.randrange(TW), rng.randrange(TH)))
    for y in range(TH):
        for x in range(TW):
            if not iso_inside(x, y):
                continue
            u, v = tile_uv(x, y)
            r = rng.random()
            c = pal[0]
            if kind == "pavement":
                if u < 0.035 or v < 0.035:
                    c = pal[3]
                elif abs(u - 0.5) < 0.018 or abs(v - 0.5) < 0.018:
                    c = pal[1]
                else:
                    c = shade(pal[0], slab_tone[(int(u * 2), int(v * 2))])
                    if r < 0.03:
                        c = pal[2]
                    elif r < 0.05:
                        c = pal[1]
                    # 砖缝旁边一条亮边，像有点倒角
                    if (0.035 <= u < 0.06) or (0.035 <= v < 0.06):
                        c = shade(c, 0.05)
            elif kind == "road":
                c = pal[2] if r < 0.015 else (pal[1] if r < 0.09 else (pal[3] if r < 0.1 else pal[0]))
            elif kind == "grass":
                c = pal[1] if r < 0.12 else (pal[2] if r < 0.2 else (pal[3] if r < 0.23 else pal[0]))
                if (x, y) in blades or (x, y + 1) in blades:
                    c = (92, 128, 76)
                if r > 0.997:
                    c = rng.choice([(222, 96, 116), (242, 222, 120), (232, 232, 242)])
            elif kind == "concrete":
                c = pal[2] if r < 0.02 else (pal[1] if r < 0.08 else (pal[3] if r < 0.09 else pal[0]))
                if u < 0.035 or v < 0.035:
                    c = pal[1]                                   # 伸缩缝
                elif (0.035 <= u < 0.06) or (0.035 <= v < 0.06):
                    c = shade(c, 0.04)                           # 缝边一点倒角
                elif r >= 0.09:
                    if (x, y) in stain_in:
                        c = shade(pal[0], -0.07)
                    elif (x, y) in stain_out:
                        c = shade(pal[0], -0.04)
                if (x, y) in crack:
                    c = pal[3]
                elif (x, y - 1) in crack:
                    c = shade(c, 0.05)                           # 裂缝下沿一点亮边
            elif kind == "tile":
                if u < 0.035 or v < 0.035 or abs(u - 0.5) < 0.018 or abs(v - 0.5) < 0.018:
                    c = pal[3]
                else:
                    c = shade(pal[0], slab_tone[(int(u * 2), int(v * 2))] * 0.5)
                    uu, vv = u % 0.5, v % 0.5
                    if 0.035 <= uu < 0.095 and 0.035 <= vv < 0.095:
                        c = pal[2]                               # 左上角高光
                    elif (0.035 <= uu < 0.06) or (0.035 <= vv < 0.06):
                        c = shade(c, 0.04)                       # 砖边倒角
                    elif r < 0.02:
                        c = pal[1]
            elif kind == "wood":
                i = min(3, int(v * 4))
                pk = planks[i]
                c = shade(pal[0], pk["tone"])
                dv = v if i == 0 else v - i / 4
                if (v < 0.035 if i == 0 else abs(dv) < 0.018):
                    c = pal[3]                                   # 板缝
                elif (u < 0.035 if pk["seam"] == 0.0 else abs(u - pk["seam"]) < 0.018):
                    c = pal[3]                                   # 板头接缝
                elif any(abs(v - g[0]) < 0.018 and g[1] < u < g[2] for g in pk["grain"]):
                    c = pal[1]                                   # 木纹
                else:
                    if 0.018 <= dv < 0.05:
                        c = shade(c, 0.06)                       # 板边倒角亮线
                    if pk["seam"] > 0.0 and 0.018 <= u - pk["seam"] < 0.05:
                        c = shade(c, 0.05)                       # 板头亮边
                    if r < 0.03:
                        c = pal[1]
                    elif r < 0.045:
                        c = pal[2]
            else:
                c = pal[1] if r < 0.1 else (pal[2] if r < 0.13 else (pal[3] if r < 0.16 else pal[0]))
                if (x, y) in pebbles or (x - 1, y) in pebbles:
                    c = (84, 86, 76)
            img.putpixel((x, y), c + (255,))
    return img


def kerb_tile(side):
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    for y in range(TH):
        for x in range(TW):
            if not iso_inside(x, y):
                continue
            u, v = tile_uv(x, y)
            d = v if side == "nw" else 1.0 - v
            if d < 0.03:
                img.putpixel((x, y), (200, 192, 178, 255))
            elif d < 0.11:
                img.putpixel((x, y), (184, 176, 162, 255))
            elif d < 0.2:
                img.putpixel((x, y), (112, 106, 96, 255) if d > 0.13 else (132, 126, 116, 255))
    return img


# ---------------------------------------------------------------- 小物件

def scarf_fold():
    """28×10：顶面 4 行（带折痕）、正面 4 行、阴影 2 行。"""
    img = Image.new("LA", (28, 10), (0, 0))
    for y in range(0, 4):
        x0 = 6 - y
        for x in range(x0, 26):
            v = 255 if x < 20 else 225
            if y in (2, 3) and x in (10, 11, 18, 19):
                v = 245
            img.putpixel((x, y), (v, 255))
    for y in range(4, 8):
        for x in range(2, 24):
            v = 205 if x < 18 else 160
            if y == 4:
                v = min(255, v + 15)
            if y == 7:
                v -= 20
            img.putpixel((x, y), (v, 255))
    img.putpixel((1, 5), (205, 255))
    img.putpixel((1, 6), (205, 255))
    img.putpixel((24, 6), (130, 255))
    img.putpixel((24, 7), (130, 255))
    for y in (8, 9):
        for x in range(2, 24):
            img.putpixel((x, y), (110 if y == 8 else 120, 255))
    return img


def shadow():
    img = Image.new("RGBA", (32, 12), (0, 0, 0, 0))
    for y in range(12):
        for x in range(32):
            cx, cy = (x + 0.5 - 16) / 16, (y + 0.5 - 6) / 6
            rr = cx * cx + cy * cy
            if rr <= 0.7:
                img.putpixel((x, y), (0, 0, 0, 255))
            elif rr <= 1.0:
                img.putpixel((x, y), (0, 0, 0, 150))
    return img


def bubble(kind):
    img = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    W = (255, 255, 255, 255)
    K = (42, 34, 48, 255)
    for y in range(24):
        for x in range(24):
            cx, cy = x + 0.5 - 12, y + 0.5 - 10
            if cx * cx + cy * cy <= 10.5 * 10.5:
                img.putpixel((x, y), W)
    for p in [(6, 20), (5, 21), (4, 22), (5, 20), (6, 19)]:
        img.putpixel(p, W)
    for y in range(24):
        for x in range(24):
            if img.getpixel((x, y)) == W:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < 24 and 0 <= ny < 24 and img.getpixel((nx, ny))[3] == 0:
                        img.putpixel((nx, ny), K)
    if kind == "ask":
        pts = [(9, 6), (10, 5), (11, 5), (12, 5), (13, 6), (14, 7), (14, 8), (13, 9), (12, 10), (12, 11), (12, 12), (12, 15), (12, 16)]
        for p in pts:
            img.putpixel(p, K)
        img.putpixel((9, 7), K)
        img.putpixel((11, 10), K)
        img.putpixel((11, 15), K)
        img.putpixel((11, 16), K)
    elif kind == "haggle":
        B = (33, 110, 200, 255)
        pts = [(8, 4), (9, 5), (10, 6), (11, 7), (12, 8), (16, 4), (15, 5), (14, 6), (13, 7)] + \
              [(12, y) for y in range(9, 17)] + [(x, 10) for x in range(9, 16)] + [(x, 13) for x in range(9, 16)]
        for p in pts:
            img.putpixel(p, B)
            img.putpixel((p[0] + 1, p[1]), B)
    elif kind == "wait":
        G = (108, 192, 112, 255)
        for x in range(5, 19):
            for y in range(6, 13):
                img.putpixel((x, y), G if y not in (8, 11) else (150, 225, 150, 255))
            img.putpixel((x, 13), (70, 140, 80, 255))
            if x % 2:
                img.putpixel((x, 14), (70, 140, 80, 255))
    return img


# ---------------------------------------------------------------- 入口

def generate(out):
    os.makedirs(out, exist_ok=True)
    sd_dir = os.path.join(os.path.dirname(out.rstrip("/")), "sprites")

    def write(img, name):
        img.save(os.path.join(out, name + ".png"))
        ref = Image.open(os.path.join(sd_dir, name + ".png"))
        assert img.size == (ref.size[0] * S, ref.size[1] * S), (name, img.size, ref.size)

    sheets = build_person()
    for k, img in sheets.items():
        write(img, "person_" + k if k != "hair" else "hair")
    rng = random.Random(11)
    for kind in ["pavement", "road", "grass", "lot", "concrete", "wood", "tile"]:
        for v in range(2):
            write(ground_tile(kind, v, rng), "tile_%s_%d" % (kind, v))
    write(kerb_tile("nw"), "kerb_nw")
    write(kerb_tile("se"), "kerb_se")
    write(scarf_fold(), "scarf_fold")
    write(shadow(), "shadow")
    for k in ["ask", "haggle", "wait"]:
        write(bubble(k), "bubble_" + k)
    gen_equipment.generate(out, S=S)
    print("wrote HD sprites to", out)


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    generate(os.path.join(root, "assets", "sprites_hd"))
