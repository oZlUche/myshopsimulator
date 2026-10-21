#!/usr/bin/env python3
"""像素精灵生成器：把 assets/sprites/ 下的 PNG 画出来（01 §3.2 的开罗式斜 45° 视角）。

    python3 tools/pixelart/gen_sprites.py          # 生成全部精灵
    python3 tools/pixelart/gen_sprites.py preview  # 另外拼一张预览图到 /tmp/… 看效果

美术像素（art px）= 游戏里 Iso.PX 个屏幕像素（目前 2）。地面一格是 32×16 art px，人物一帧 24×32 art px。
人物按"图层"分别出图，每层都是灰度 + 透明：255 = 受光面、190 = 背光面、140 = 深阴影，游戏里按颜色乘上去（modulate）
就能换衣服、换发色，所以同一套帧适用于玩家、员工、客人、路人。
图层表（每张都是 4 列帧 × 4 行方向：0 右前、1 左前、2 右后、3 左后；1 和 3 是 0 和 2 的镜像）：
    person_outline  轮廓（固定深色）     person_skin  皮肤      person_top  上衣
    person_bottom   裤子                person_shoes 鞋        person_face  眼睛嘴（固定深色）
    person_scarf    围巾（可选配饰）      hair         发型，纵向按发型叠：第 s 个发型占第 s*4..s*4+3 行
换了 PNG 请同时改 scenes/view/iso.gd 里的尺寸常量。
"""
import os
import random
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites")

FW, FH = 24, 32          # 人物一帧
FRAMES = 4               # 站 / 迈左 / 站 / 迈右
DIRS = 4
HAIR_STYLES = ["short", "parted", "bob", "long", "ponytail", "bun", "cap"]
TW, TH = 32, 16          # 地面一格

LIT, SHADE, DEEP = 255, 190, 140


class Layer:
    """一帧里的一层：(x, y) -> 灰度值。"""

    def __init__(self):
        self.px = {}

    def put(self, x, y, v=LIT):
        if 0 <= x < FW and 0 <= y < FH:
            self.px[(x, y)] = v

    def rect(self, x0, y0, x1, y1, v=LIT):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, v)

    def shift(self, dx, dy):
        n = Layer()
        for (x, y), v in self.px.items():
            n.put(x + dx, y + dy, v)
        return n

    def mirror(self):
        n = Layer()
        for (x, y), v in self.px.items():
            n.put(FW - 1 - x, y, v)
        return n

    def minus(self, other):
        n = Layer()
        for k, v in self.px.items():
            if k not in other.px:
                n.px[k] = v
        return n


def head_mask():
    """圆圆的大头：12 宽 × 12 高，占 x 6..17、y 2..13。"""
    m = Layer()
    rows = {2: (9, 14), 3: (7, 16), 4: (6, 17), 5: (6, 17), 6: (6, 17), 7: (6, 17), 8: (6, 17),
            9: (6, 17), 10: (6, 17), 11: (7, 16), 12: (8, 15), 13: (10, 13)}
    for y, (a, b) in rows.items():
        m.rect(a, y, b, y)
    return m


def hair_front(style):
    """正面（脸朝镜头、朝右）的头发：盖住头顶和后脑（左侧）。"""
    h = Layer()
    head = head_mask()
    if style == "cap":
        # 鸭舌帽：帽体盖头顶，帽檐伸向朝向那边
        for (x, y), v in head.px.items():
            if y <= 6:
                h.put(x, y, LIT if x < 14 else SHADE)
        h.rect(12, 7, 19, 7, SHADE)
        h.rect(6, 7, 7, 10, SHADE)
        return h
    for (x, y), v in head.px.items():
        if y <= 5:
            h.put(x, y, LIT if x < 14 else SHADE)
    # 发丝高光：头顶偏左一道更亮（上色后仍比周围亮一点）
    for x in range(8, 12):
        h.put(x, 3, 255)
    if style == "short":
        h.rect(6, 6, 8, 6)
        h.rect(15, 6, 17, 6, SHADE)
        h.put(10, 6)
        h.put(13, 6, SHADE)   # 刘海参差
        h.rect(6, 7, 7, 9)
    elif style == "parted":
        h.rect(6, 6, 10, 6)
        h.rect(13, 6, 17, 6, SHADE)
        h.rect(6, 7, 8, 7)
        h.rect(6, 8, 7, 10)
        h.put(16, 7, SHADE)
        h.put(17, 7, SHADE)
    elif style == "bob":
        h.rect(6, 6, 9, 6)
        h.rect(14, 6, 17, 6, SHADE)
        h.rect(6, 7, 7, 12)
        h.rect(16, 7, 17, 12, SHADE)
        h.rect(7, 13, 8, 13)
        h.rect(15, 13, 16, 13, SHADE)
    elif style == "long":
        h.rect(6, 6, 9, 6)
        h.rect(14, 6, 17, 6, SHADE)
        h.rect(5, 7, 7, 18)
        h.rect(16, 7, 18, 18, SHADE)
        h.rect(5, 19, 6, 19, SHADE)
        h.rect(17, 19, 18, 19, DEEP)
    elif style == "ponytail":
        h.rect(6, 6, 8, 6)
        h.rect(15, 6, 17, 6, SHADE)
        h.rect(6, 7, 7, 9)
        h.rect(4, 7, 5, 13, SHADE)   # 马尾从后脑垂下来
        h.rect(4, 14, 4, 15, DEEP)
    elif style == "bun":
        h.rect(6, 6, 8, 6)
        h.rect(15, 6, 17, 6, SHADE)
        h.rect(6, 7, 7, 9)
        h.rect(7, 0, 10, 2)          # 头顶偏后一个发髻
        h.put(11, 1, SHADE)
    return h


def hair_back(style):
    """背面（背对镜头、朝右后）：整个后脑都是头发。"""
    h = Layer()
    head = head_mask()
    for (x, y), v in head.px.items():
        if y <= 11:
            h.put(x, y, LIT if x < 13 else SHADE)
    if style == "cap":
        h = Layer()
        for (x, y), v in head.px.items():
            if y <= 7:
                h.put(x, y, LIT if x < 13 else SHADE)
        h.rect(7, 8, 16, 8, DEEP)   # 帽子下沿
    elif style == "short":
        pass
    elif style == "parted":
        h.rect(8, 12, 15, 12)
    elif style == "bob":
        h.rect(7, 12, 16, 13)
        h.rect(8, 14, 15, 14, SHADE)
    elif style == "long":
        h.rect(7, 12, 16, 13)
        h.rect(6, 14, 17, 18, SHADE)
        h.rect(7, 19, 16, 19, DEEP)
    elif style == "ponytail":
        h.rect(8, 12, 15, 12)
        h.rect(10, 13, 13, 17, SHADE)
        h.rect(11, 18, 12, 19, DEEP)
    elif style == "bun":
        h.rect(9, 0, 14, 2)
        h.rect(10, 3, 13, 3, SHADE)
    return h


def body_frame(frame, back):
    """除头发外的所有层。frame 0/2 站着，1 迈左脚，3 迈右脚。朝右（+x）。"""
    L = {k: Layer() for k in ["skin", "top", "bottom", "shoes", "face", "scarf"]}
    bob = -1 if frame in (1, 3) else 0
    # 头
    head = head_mask()
    for (x, y), v in head.px.items():
        L["skin"].put(x, y + bob, LIT if x < 15 else 215)
    if not back:
        # 眼睛 2×2，左上角一点高光；嘴一个像素。face 层是固定颜色（见 FIXED）
        for (x, y) in [(11, 8), (10, 9), (11, 9), (15, 8), (14, 9), (15, 9)]:
            L["face"].put(x, y + bob, 1)
        L["face"].put(10, 8 + bob, 2)
        L["face"].put(14, 8 + bob, 2)
        L["face"].put(13, 11 + bob, 3)
    # 脖子
    L["skin"].rect(11, 14 + bob, 12, 14 + bob, SHADE)
    # 上衣 10 宽 × 8 高，右边两列背光，底下一行阴影，正面有个领口
    L["top"].rect(7, 15 + bob, 16, 22 + bob, LIT)
    L["top"].rect(15, 15 + bob, 16, 22 + bob, SHADE)
    if not back:
        L["top"].rect(10, 15 + bob, 13, 15 + bob, DEEP)
        L["top"].rect(11, 16 + bob, 12, 16 + bob, DEEP)
    else:
        L["top"].rect(11, 15 + bob, 12, 16 + bob, SHADE)
    # 手臂随步伐前后摆：迈左脚时右臂往前（画低一格）
    swing = 1 if frame == 1 else (-1 if frame == 3 else 0)
    la, ra = 15 + bob - swing, 15 + bob + swing
    L["top"].rect(5, la, 6, la + 6, 235)
    L["top"].rect(17, ra, 18, ra + 6, 170)
    L["top"].rect(7, 22 + bob, 16, 22 + bob, DEEP)   # 腰线
    L["skin"].rect(5, la + 7, 6, la + 7, LIT)
    L["skin"].rect(17, ra + 7, 18, ra + 7, 215)
    # 裤子与鞋：站着两条腿平放；迈步时一条腿抬起缩短，另一条往朝向那边跨
    if frame in (0, 2):
        L["bottom"].rect(8, 23, 10, 27, LIT)
        L["bottom"].rect(13, 23, 15, 27, SHADE)
        L["shoes"].rect(7, 28, 10, 29, 1)
        L["shoes"].rect(13, 28, 16, 29, 2)
    elif frame == 1:
        L["bottom"].rect(8, 22, 10, 25, LIT)      # 左腿抬起
        L["shoes"].rect(7, 26, 10, 27, 1)
        L["bottom"].rect(14, 23, 16, 27, SHADE)   # 右腿跨出
        L["shoes"].rect(14, 28, 17, 29, 2)
    else:
        L["bottom"].rect(7, 23, 9, 27, LIT)       # 左腿跨出
        L["shoes"].rect(6, 28, 9, 29, 1)
        L["bottom"].rect(13, 22, 15, 25, SHADE)   # 右腿抬起
        L["shoes"].rect(13, 26, 16, 27, 2)
    # 围巾（可选层）：绕脖子一圈，正面垂下一截
    if not back:
        L["scarf"].rect(9, 13 + bob, 15, 14 + bob, LIT)
        L["scarf"].rect(13, 15 + bob, 14, 19 + bob, SHADE)
        L["scarf"].rect(13, 20 + bob, 14, 20 + bob, DEEP)
    else:
        L["scarf"].rect(8, 13 + bob, 15, 14 + bob, LIT)
    return L, bob


def outline_of(layers):
    sil = set()
    for l in layers:
        sil |= set(l.px.keys())
    o = Layer()
    for (x, y) in sil:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            p = (x + dx, y + dy)
            if p not in sil:
                o.put(p[0], p[1], LIT)
    return o


# 固定颜色的层：像素值是"第几号颜色"，不随人换色
FIXED = {
    "face": {1: (42, 34, 48, 255), 2: (120, 110, 130, 255), 3: (200, 140, 110, 255)},   # 眼、眼高光、嘴
    "shoes": {1: (58, 44, 50, 255), 2: (40, 30, 36, 255)},
    "outline": {LIT: (20, 18, 26, 150)},
}


def build_person():
    """返回 {层名: Image}。可换色层是 LA，固定色层是 RGBA。outline 和 hair 一样按发型纵向叠（轮廓随发型变）。"""
    tint_layers = ["skin", "top", "bottom", "scarf"]
    sheets = {k: Image.new("LA", (FW * FRAMES, FH * DIRS), (0, 0)) for k in tint_layers}
    sheets["face"] = Image.new("RGBA", (FW * FRAMES, FH * DIRS), (0, 0, 0, 0))
    sheets["shoes"] = Image.new("RGBA", (FW * FRAMES, FH * DIRS), (0, 0, 0, 0))
    hair = Image.new("LA", (FW * FRAMES, FH * DIRS * len(HAIR_STYLES)), (0, 0))
    outline = Image.new("RGBA", (FW * FRAMES, FH * DIRS * len(HAIR_STYLES)), (0, 0, 0, 0))
    for d in range(DIRS):
        back = d >= 2
        mirror = d in (1, 3)
        for f in range(FRAMES):
            L, bob = body_frame(f, back)
            hairs = {s: (hair_back(s) if back else hair_front(s)).shift(0, bob) for s in HAIR_STYLES}
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
    """标准 2:1 像素菱形（32×16）：每行比上一行每边宽 2 个像素，相邻格子正好无缝拼接。"""
    if not (0 <= x < TW and 0 <= y < TH):
        return False
    r = y if y < TH // 2 else TH - 1 - y
    half = 2 * r + 1
    return TW // 2 - half <= x < TW // 2 + half


def tile_uv(x, y):
    """像素 → 格内坐标 (u, v)，u 沿 gx（右下），v 沿 gy（左下），都在 0..1。"""
    cx, cy = x + 0.5 - TW / 2, y + 0.5 - TH / 2
    return (cx / (TW / 2) + cy / (TH / 2) + 1) / 2, (-cx / (TW / 2) + cy / (TH / 2) + 1) / 2


def ground_tile(kind, variant, rng):
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    pal = {
        "pavement": [(150, 142, 128), (128, 120, 108), (160, 152, 138), (118, 110, 100)],
        "road": [(92, 90, 101), (84, 82, 93), (102, 100, 112), (70, 68, 78)],
        "grass": [(66, 94, 60), (78, 110, 68), (56, 82, 52), (48, 70, 46)],
        "lot": [(60, 63, 53), (53, 56, 47), (68, 71, 60), (46, 49, 41)],
    }[kind]
    for y in range(TH):
        for x in range(TW):
            if not iso_inside(x, y):
                continue
            u, v = tile_uv(x, y)
            r = rng.random()
            c = pal[0]
            if kind == "pavement":
                # 每格一块大地砖，靠左上两条边是砖缝（右下两条边由邻格提供），中间再分一道成 2×2 小砖
                if u < 0.07 or v < 0.07:
                    c = pal[3]
                elif abs(u - 0.5) < 0.035 or abs(v - 0.5) < 0.035:
                    c = pal[1]
                elif r < 0.03:
                    c = pal[2]
                elif r < 0.06:
                    c = pal[1]
            elif kind == "road":
                c = pal[2] if r < 0.02 else (pal[1] if r < 0.1 else (pal[3] if r < 0.115 else pal[0]))
            elif kind == "grass":
                c = pal[1] if r < 0.16 else (pal[2] if r < 0.24 else (pal[3] if r < 0.27 else pal[0]))
                if r > 0.994:
                    c = rng.choice([(222, 96, 116), (242, 222, 120), (232, 232, 242)])
            else:
                c = pal[1] if r < 0.15 else (pal[2] if r < 0.2 else (pal[3] if r < 0.24 else pal[0]))
            img.putpixel((x, y), c + (255,))
    return img


def kerb_tile(side):
    """路缘石：贴在人行道格子靠街那条边上的一条石沿，浅色顶、深色立面。side = 'nw'（左上边）或 'se'（右下边）。"""
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    for y in range(TH):
        for x in range(TW):
            if not iso_inside(x, y):
                continue
            u, v = tile_uv(x, y)
            d = v if side == "nw" else 1.0 - v     # 到那条边的距离（格的 0..1）
            if d < 0.11:
                img.putpixel((x, y), (184, 176, 162, 255))
            elif d < 0.2:
                img.putpixel((x, y), (112, 106, 96, 255))
    return img


# ---------------------------------------------------------------- 小物件

def scarf_fold():
    """叠好的一份围巾：从斜上方看到的一小块扁平的布（14 宽 × 5 高）——顶面亮、朝镜头的侧面原色、右侧背光。
    灰度 + 透明，游戏里按 SKU 颜色上色；一叠就是几份错开 2 个像素往上摞。"""
    img = Image.new("LA", (14, 5), (0, 0))
    # 顶面（平行四边形，往右上错一格）
    for x in range(3, 13):
        img.putpixel((x, 0), (255, 255))
    for x in range(2, 13):
        img.putpixel((x, 1), (255 if x < 10 else 225, 255))
    img.putpixel((5, 1), (240, 255))
    img.putpixel((9, 1), (240, 255))   # 折痕
    # 正面厚度两行，右端背光
    for x in range(1, 12):
        img.putpixel((x, 2), (205 if x < 9 else 160, 255))
        img.putpixel((x, 3), (185 if x < 9 else 145, 255))
    img.putpixel((0, 2), (205, 255))
    img.putpixel((12, 3), (130, 255))
    # 底下一行阴影
    for x in range(1, 12):
        img.putpixel((x, 4), (110, 255))
    return img


def shadow():
    img = Image.new("RGBA", (16, 6), (0, 0, 0, 0))
    for y in range(6):
        for x in range(16):
            cx, cy = (x + 0.5 - 8) / 8, (y + 0.5 - 3) / 3
            if cx * cx + cy * cy <= 1.0:
                img.putpixel((x, y), (0, 0, 0, 255))
    return img


def bubble(kind):
    """客人头顶的气泡：12×12，白底描边，里面一个图标。"""
    img = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    W = (255, 255, 255, 255)
    K = (42, 34, 48, 255)
    for y in range(12):
        for x in range(12):
            cx, cy = x + 0.5 - 6, y + 0.5 - 5
            if cx * cx + cy * cy <= 5.5 * 5.5:
                img.putpixel((x, y), W)
    for y in range(12):
        for x in range(12):
            if img.getpixel((x, y)) == W:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < 12 and 0 <= ny < 12 and img.getpixel((nx, ny))[3] == 0:
                        img.putpixel((nx, ny), K)
    img.putpixel((3, 10), K)
    img.putpixel((2, 11), K)   # 气泡尾巴
    if kind == "ask":
        for p in [(4, 3), (5, 2), (6, 2), (7, 3), (7, 4), (6, 5), (6, 6), (6, 8)]:
            img.putpixel(p, K)
    elif kind == "haggle":
        B = (33, 110, 200, 255)
        for p in [(4, 2), (8, 2), (5, 3), (7, 3), (6, 4), (6, 5), (6, 6), (6, 7), (6, 8), (4, 5), (8, 5), (4, 7), (8, 7)]:
            img.putpixel(p, B)
    elif kind == "wait":
        # 一条小围巾
        for x in range(3, 10):
            for y in range(3, 6):
                img.putpixel((x, y), (108, 192, 112, 255))
            img.putpixel((x, 6), (70, 140, 80, 255))
        for x in (4, 7):
            img.putpixel((x, 4), (160, 230, 160, 255))
    return img


def write(img, name):
    path = os.path.join(OUT, name + ".png")
    img.save(path)
    return path


def generate():
    os.makedirs(OUT, exist_ok=True)
    sheets = build_person()
    for k, img in sheets.items():
        write(img, "person_" + k if k != "hair" else "hair")
    rng = random.Random(7)
    for kind in ["pavement", "road", "grass", "lot"]:
        for v in range(2):
            write(ground_tile(kind, v, rng), "tile_%s_%d" % (kind, v))
    write(kerb_tile("nw"), "kerb_nw")
    write(kerb_tile("se"), "kerb_se")
    write(scarf_fold(), "scarf_fold")
    write(shadow(), "shadow")
    for k in ["ask", "haggle", "wait"]:
        write(bubble(k), "bubble_" + k)
    print("wrote sprites to", OUT)


# ---------------------------------------------------------------- 预览（不进游戏，只是看效果）

def tint(img, color, alpha=1.0):
    """LA 图按颜色上色；RGBA 图只乘 alpha。"""
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    if img.mode == "RGBA":
        for y in range(img.size[1]):
            for x in range(img.size[0]):
                r, g, b, a = img.getpixel((x, y))
                if a:
                    out.putpixel((x, y), (r, g, b, int(a * alpha)))
        return out
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            v, a = img.getpixel((x, y))
            if a:
                out.putpixel((x, y), (color[0] * v // 255, color[1] * v // 255, color[2] * v // 255, int(a * alpha)))
    return out


def hexc(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


class Preview:
    def __init__(self):
        self.sheets = {k: Image.open(os.path.join(OUT, "person_%s.png" % k)) for k in ["outline", "skin", "top", "bottom", "shoes", "face", "scarf"]}
        self.hair = Image.open(os.path.join(OUT, "hair.png"))
        self.tiles = {k: [Image.open(os.path.join(OUT, "tile_%s_%d.png" % (k, v))) for v in range(2)] for k in ["pavement", "road", "grass", "lot"]}
        self.kerb = {s: Image.open(os.path.join(OUT, "kerb_%s.png" % s)) for s in ("nw", "se")}
        self.fold = Image.open(os.path.join(OUT, "scarf_fold.png"))
        self.sh = Image.open(os.path.join(OUT, "shadow.png"))
        self.bubbles = {k: Image.open(os.path.join(OUT, "bubble_%s.png" % k)) for k in ["ask", "haggle", "wait"]}

    def person(self, canvas, foot, top, bottom, hcol, style, d, f, scarf=None, alpha=1.0):
        pos = (foot[0] - FW // 2, foot[1] - 30)
        canvas.alpha_composite(tint(self.sh, None, 0.3), (foot[0] - 8, foot[1] - 3))
        box = (f * FW, d * FH, f * FW + FW, d * FH + FH)
        si = HAIR_STYLES.index(style)
        hb = (f * FW, (si * DIRS + d) * FH, f * FW + FW, (si * DIRS + d) * FH + FH)
        canvas.alpha_composite(tint(self.sheets["outline"].crop(hb), None, alpha), pos)
        canvas.alpha_composite(tint(self.sheets["skin"].crop(box), hexc("#f0d2b0"), alpha), pos)
        canvas.alpha_composite(tint(self.sheets["top"].crop(box), top, alpha), pos)
        canvas.alpha_composite(tint(self.sheets["bottom"].crop(box), bottom, alpha), pos)
        canvas.alpha_composite(tint(self.sheets["shoes"].crop(box), None, alpha), pos)
        canvas.alpha_composite(tint(self.hair.crop(hb), hcol, alpha), pos)
        canvas.alpha_composite(tint(self.sheets["face"].crop(box), None, alpha), pos)
        if scarf:
            canvas.alpha_composite(tint(self.sheets["scarf"].crop(box), scarf, alpha), pos)


def preview(path):
    from PIL import ImageDraw
    P = Preview()
    cols, rows = 9, 6
    W, H = (cols + rows) * TW // 2 + 8, (cols + rows) * TH // 2 + 48
    canvas = Image.new("RGBA", (W, H), (20, 21, 29, 255))
    ox, oy = rows * TW // 2 + 4, 36

    def to_screen(gx, gy):
        return ox + int((gx - gy) * TW / 2), oy + int((gx + gy) * TH / 2)

    for gx in range(cols):
        for gy in range(rows):
            kind = "road" if gy < 2 else ("pavement" if gy < 5 else "grass")
            p = to_screen(gx, gy)
            canvas.alpha_composite(P.tiles[kind][(gx * 7 + gy * 13) % 2], (p[0] - TW // 2, p[1]))
            if gy == 2:
                canvas.alpha_composite(P.kerb["nw"], (p[0] - TW // 2, p[1]))
    outfits = [("#c85a3c", "#2a2026"), ("#3c7ac8", "#6a4a2a"), ("#5aa05a", "#1a1a1a"), ("#9a5ac8", "#8a6a4a"),
               ("#d8a03c", "#4a3020"), ("#4a8a8a", "#b0a090"), ("#c8c0b0", "#2a2026"), ("#6a6a7a", "#4a3020")]
    pants = ["#3a3a4a", "#5a4a3a", "#2a3a5a", "#6a6a6a"]
    for i in range(6):
        top, hc = outfits[i]
        P.person(canvas, to_screen(0.6 + i * 1.5, 0.4 + (i % 2) * 1.0), hexc(top), hexc(pants[i % 4]), hexc(hc), HAIR_STYLES[i % len(HAIR_STYLES)], i % 4, i % 4)
    for i, (style, kind) in enumerate(zip(["bob", "long", "cap", "bun"], ["ask", "haggle", "wait", None])):
        top, hc = outfits[(i + 3) % 8]
        foot = to_screen(2.2 + i * 1.4, 2.35 - 0.6 * (i % 2))
        P.person(canvas, foot, hexc(top), hexc(pants[(i + 1) % 4]), hexc(hc), style, 1 if i % 2 else 0, 0, scarf=hexc("#c0392b") if i == 3 else None)
        if kind:
            canvas.alpha_composite(P.bubbles[kind], (foot[0] + 7, foot[1] - 38))
    # 摊桌：腿 + 木板 + 桌布 + 叠好的围巾（游戏里由 Iso.draw_stall_table 画，这里只是示意）
    dr = ImageDraw.Draw(canvas)
    g0, g1, g2, g3 = to_screen(2.6, 2.9), to_screen(6.4, 2.9), to_screen(6.4, 3.6), to_screen(2.6, 3.6)
    H14 = 12
    for lx, ly in [g3, g2, g1, g0]:
        dr.rectangle([lx - 1, ly - H14, lx, ly], fill=(60, 42, 28))
    dr.polygon([g3, g2, (g2[0], g2[1] - H14), (g3[0], g3[1] - H14)], fill=(122, 90, 58))
    dr.polygon([g2, g1, (g1[0], g1[1] - H14), (g2[0], g2[1] - H14)], fill=(88, 64, 40))
    dr.polygon([(g0[0], g0[1] - H14), (g1[0], g1[1] - H14), (g2[0], g2[1] - H14), (g3[0], g3[1] - H14)], fill=(168, 134, 90))
    cloth = (156, 60, 60)
    dr.polygon([(g0[0], g0[1] - H14), (g1[0], g1[1] - H14), (g2[0], g2[1] - H14), (g3[0], g3[1] - H14)], fill=cloth)
    dr.polygon([(g3[0], g3[1] - H14), (g2[0], g2[1] - H14), (g2[0], g2[1] - H14 + 5), (g3[0], g3[1] - H14 + 5)], fill=(130, 48, 48))
    dr.polygon([(g2[0], g2[1] - H14), (g1[0], g1[1] - H14), (g1[0], g1[1] - H14 + 5), (g2[0], g2[1] - H14 + 5)], fill=(104, 38, 38))
    for j, col in enumerate(["#c0392b", "#22315a", "#e6d5b8", "#7d3c98"]):
        base = to_screen(3.0 + j * 0.9, 3.15)
        for i in range(3 - (j % 2)):
            canvas.alpha_composite(tint(P.fold, hexc(col)), (base[0] - 7 + ((i * 7) % 3 - 1), base[1] - H14 - 4 - i * 2))
    P.person(canvas, to_screen(4.5, 4.0), hexc("#f2b134"), hexc("#2a2a3a"), hexc("#2a2026"), "short", 2, 0)
    # 底下一行：一个人 4 向 × 4 帧
    strip = Image.new("RGBA", (FW * FRAMES * DIRS + 8, FH + 6), (60, 70, 80, 255))
    for d in range(DIRS):
        for f in range(FRAMES):
            P.person(strip, ((d * FRAMES + f) * FW + 4 + FW // 2, 33), hexc("#3c7ac8"), hexc("#5a4a3a"), hexc("#4a3020"), "parted", d, f)
    full = Image.new("RGBA", (max(W, strip.size[0]), H + strip.size[1]), (20, 21, 29, 255))
    full.paste(canvas, (0, 0))
    full.paste(strip, (0, H))
    full = full.resize((full.size[0] * 3, full.size[1] * 3), Image.NEAREST)
    full.save(path)
    print("preview:", path)


if __name__ == "__main__":
    generate()
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        preview(sys.argv[2] if len(sys.argv) > 2 else "/tmp/pixel_preview.png")
