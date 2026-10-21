#!/usr/bin/env python3
"""店面 / 仓库设备的像素图（01 §4.9、07 文档），由 gen_sprites.py 一起调用，也可单独运行。

所有设备都是"斜 45° 方块"：顶面 + 朝左前（SW）的面 + 朝右前（SE）的面。IsoBox 负责把一个 w×d 格、高 H 美术像素的
方块画成图，并给出每个面上的局部坐标（u 沿面横向的像素、v 从地面往上的像素），细节（层板、柜门、玻璃）都画在面坐标里。
开口朝 SW 的叫 *_sw，朝 SE 的叫 *_se，两张都单独画（不是镜像），这样光照方向一致。

每张图的元数据写进 assets/sprites/equipment.json：
    size    图的像素尺寸
    anchor  地面菱形最上角在图里的位置（游戏里 to_screen(g) 对到这一点）
    H       方块高度
    tiers   每层层板上表面的高度（美术像素），放货用
    slot    放货的格内偏移 [u, v]（格坐标），就是叠好的围巾那个小方块的最上角
"""
import json
import os

from PIL import Image

TILE_W, TILE_H = 32, 16
OUTLINE = (20, 18, 26, 150)


def lighten(c, k):
    return tuple(min(255, int(v + (255 - v) * k)) for v in c[:3]) + c[3:]


def darken(c, k):
    return tuple(int(v * (1 - k)) for v in c[:3]) + c[3:]


class IsoBox:
    """占地 w×d 格（w 沿 gx 右下，d 沿 gy 左下）、高 H 美术像素的方块。mode 'RGBA' 画固定色，'LA' 画可上色的灰度。"""

    def __init__(self, H, w=1.0, d=1.0, mode="RGBA"):
        self.H = int(H)
        self.w, self.d = w, d
        self.mode = mode
        self.ox = int(round(d * TILE_W / 2))        # 地面菱形最上角的 x
        self.W = int(round((w + d) * TILE_W / 2))
        self.ground_h = int(round((w + d) * TILE_H / 2))
        self.img = Image.new(mode, (self.W, self.ground_h + self.H), (0, 0, 0, 0) if mode == "RGBA" else (0, 0))
        # 地面菱形（局部坐标，y 从 0 起）的每列最底一个像素
        self._yg = {}
        for x in range(self.W):
            ys = [y for y in range(self.ground_h) if self.inside(x, y)]
            if ys:
                self._yg[x] = max(ys)
        self.bx = int(round(self.ox + w * TILE_W / 2 - d * TILE_W / 2))   # 最下角（B）的 x，左边是 SW 面，右边是 SE 面
        self.lx = min(self._yg) if self._yg else 0
        self.rx = max(self._yg) if self._yg else 0

    # ---- 几何
    def uv(self, x, y):
        cx, cy = x + 0.5 - self.ox, y + 0.5
        return (cx / (TILE_W / 2) + cy / (TILE_H / 2)) / 2, (-cx / (TILE_W / 2) + cy / (TILE_H / 2)) / 2

    def inside(self, x, y):
        u, v = self.uv(x, y)
        return 0 <= u < self.w and 0 <= v < self.d

    def face_of(self, x):
        """这一列属于哪个面：'sw' 或 'se'。"""
        return "sw" if x < self.bx else "se"

    def face_len(self, face):
        return (self.bx - self.lx) if face == "sw" else (self.rx - self.bx + 1)

    def face_px(self, x, y):
        """图坐标 → (面, u 像素, v 像素)；不在面上返回 None。"""
        if x not in self._yg:
            return None
        yg = self._yg[x] + self.H
        v = yg - y
        if v < 0 or v >= self.H:
            return None
        face = self.face_of(x)
        u = (x - self.lx) if face == "sw" else (x - self.bx)
        return face, u, v

    def top_px(self, x, y):
        """图坐标 → 顶面的格内 (u, v)，不在顶面返回 None。"""
        if y < 0 or y >= self.ground_h or not self.inside(x, y):
            return None
        return self.uv(x, y)

    def put(self, x, y, c):
        if 0 <= x < self.img.size[0] and 0 <= y < self.img.size[1] and c is not None:
            self.img.putpixel((x, y), c)

    # ---- 画
    def fill(self, base, top=None, se=None, sw=None):
        top = top or lighten(base, 0.18)
        sw = sw or base
        se = se or darken(base, 0.28)
        for y in range(self.img.size[1]):
            for x in range(self.img.size[0]):
                if self.top_px(x, y) is not None:
                    self.put(x, y, top)
                    continue
                f = self.face_px(x, y)
                if f:
                    self.put(x, y, sw if f[0] == "sw" else se)
        return self

    def paint_face(self, face, fn):
        """fn(u, v, cur) -> 新颜色或 None。u 是面上横向像素（0 在远端、往 B 增大），v 从地面往上。"""
        for y in range(self.img.size[1]):
            for x in range(self.img.size[0]):
                f = self.face_px(x, y)
                if f and f[0] == face:
                    self.put(x, y, fn(f[1], f[2], self.img.getpixel((x, y))))
        return self

    def paint_top(self, fn):
        """fn(u, v, cur)，u/v 是格坐标 0..w / 0..d。"""
        for y in range(self.ground_h):
            for x in range(self.img.size[0]):
                t = self.top_px(x, y)
                if t:
                    self.put(x, y, fn(t[0], t[1], self.img.getpixel((x, y))))
        return self

    def clear_face(self, face, fn):
        """把面上 fn(u, v) 为真的像素挖空（开放式货架）。"""
        hole = (0, 0, 0, 0) if self.mode == "RGBA" else (0, 0)
        for y in range(self.img.size[1]):
            for x in range(self.img.size[0]):
                f = self.face_px(x, y)
                if f and f[0] == face and fn(f[1], f[2]):
                    self.put(x, y, hole)
        return self

    def edge(self):
        """前面那条竖棱 + 外轮廓。"""
        W, Hh = self.img.size
        for y in range(Hh):
            f = self.face_px(self.bx, y)
            if f and self.img.getpixel((self.bx, y))[-1]:
                self.put(self.bx, y, darken(self.img.getpixel((self.bx, y)), 0.35))
        sil = {(x, y) for y in range(Hh) for x in range(W) if self.img.getpixel((x, y))[-1]}
        out = Image.new(self.mode, (W + 2, Hh + 2), (0, 0, 0, 0) if self.mode == "RGBA" else (0, 0))
        out.paste(self.img, (1, 1))
        oc = OUTLINE if self.mode == "RGBA" else (0, 150)
        for (x, y) in sil:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                p = (x + dx, y + dy)
                if p not in sil:
                    out.putpixel((p[0] + 1, p[1] + 1), oc)
        self.img = out
        self.ox += 1
        self.pad = 1
        return self

    def anchor(self):
        return [self.ox, self.H + getattr(self, "pad", 0)]


# ------------------------------------------------------------ 具体设备

WOOD = (122, 90, 58, 255)
WOOD_DARK = (86, 62, 40, 255)
METAL = (150, 152, 160, 255)
CARD = (196, 156, 104, 255)


def stripe(u, v, boards, color, thick=2):
    for b in boards:
        if b <= v < b + thick:
            return color
    return None


def shop_shelf(front):
    """店面货架：三层开放式层板，正面能看到每层的货。"""
    H = 39
    b = IsoBox(H).fill(WOOD)
    tiers = [2, 14, 26]
    side = "se" if front == "sw" else "sw"

    def face_front(u, v, cur):
        n = b.face_len(front)
        if u < 2 or u >= n - 2:
            return darken(WOOD, 0.1)           # 侧立柱
        if v >= H - 2:
            return darken(WOOD, 0.1)           # 顶框
        c = stripe(u, v, [t - 2 for t in tiers], lighten(WOOD, 0.35))
        if c:
            return c
        return (70, 50, 34, 255)               # 背板（阴影里）

    def face_side(u, v, cur):
        n = b.face_len(side)
        if 3 <= u < n - 3 and 4 <= v < H - 4:
            return lighten(cur, 0.06)          # 侧板凹槽
        return cur

    b.paint_face(front, face_front).paint_face(side, face_side).edge()
    slot = [0.2, 0.78] if front == "sw" else [0.78, 0.2]
    return b, {"tiers": tiers, "slot": slot}


def shop_cabinet(front):
    """货柜：两扇柜门，客人看不到里面。"""
    H = 40
    b = IsoBox(H).fill(WOOD, top=lighten(WOOD, 0.25))
    side = "se" if front == "sw" else "sw"

    def face_front(u, v, cur):
        n = b.face_len(front)
        if v < 3:
            return darken(WOOD, 0.35)                              # 底座
        if u < 1 or u >= n - 1 or v >= H - 2:
            return darken(WOOD, 0.15)                              # 外框
        if u == n // 2 - 1 or u == n // 2:
            return darken(WOOD, 0.4)                               # 两扇门之间的缝
        if (u == n // 2 - 3 or u == n // 2 + 2) and 17 <= v < 21:
            return (220, 200, 120, 255)                            # 铜把手
        if (u in (2, n - 3)) or v in (4, H - 4):
            return darken(WOOD, 0.08)                              # 门板边
        return lighten(WOOD, 0.05) if (u < n // 2) else WOOD

    b.paint_face(front, face_front).paint_face(side, lambda u, v, cur: darken(cur, 0.1) if v < 3 else cur).edge()
    return b, {"tiers": [], "slot": [0.5, 0.5]}


def shop_window(front):
    """橱窗：下面一截台座，上面是框着玻璃的展示格，两层。玻璃单独一张叠在货上面。"""
    H = 31
    FRAME = (214, 206, 192, 255)
    b = IsoBox(H).fill(FRAME, top=lighten(FRAME, 0.3))
    tiers = [5, 18]
    side = "se" if front == "sw" else "sw"

    def face_front(u, v, cur):
        n = b.face_len(front)
        if v < 4:
            return (84, 76, 70, 255)                               # 台座
        if u < 2 or u >= n - 2 or v >= H - 2:
            return darken(FRAME, 0.1)                              # 窗框
        c = stripe(u, v, [t - 1 for t in tiers], (190, 178, 158, 255), 1)
        if c:
            return c
        return (250, 244, 228, 255)                                # 里面的衬板

    b.paint_face(front, face_front).paint_face(side, lambda u, v, cur: (84, 76, 70, 255) if v < 4 else cur).edge()
    # 玻璃层：只盖窗格那块，带一道斜的反光
    g = IsoBox(H)
    n = g.face_len(front)

    def glass(u, v, cur):
        if v < 4 or u < 2 or u >= n - 2 or v >= H - 2:
            return None
        if (u + v) % 11 in (0, 1) and u > 3:
            return (255, 255, 255, 120)
        return (170, 210, 240, 70)

    g.paint_face(front, glass)
    g.img = g.img.crop((0, 0, g.img.size[0], g.img.size[1]))
    gi = Image.new("RGBA", (g.img.size[0] + 2, g.img.size[1] + 2), (0, 0, 0, 0))
    gi.paste(g.img, (1, 1))
    slot = [0.2, 0.74] if front == "sw" else [0.74, 0.2]
    return b, {"tiers": tiers, "slot": slot, "overlay": gi}


def shop_counter(front):
    """收银台：矮柜，台面上放一台收银机。"""
    H = 17
    b = IsoBox(H).fill(WOOD, top=(176, 142, 96, 255))
    side = "se" if front == "sw" else "sw"

    def face_front(u, v, cur):
        if v < 2:
            return darken(WOOD, 0.4)
        if v >= H - 2:
            return lighten(WOOD, 0.2)                              # 台面沿
        n = b.face_len(front)
        if 2 <= u < n - 2 and 4 <= v < H - 4 and (u in (2, n - 3) or v in (4, H - 5)):
            return darken(WOOD, 0.1)                               # 面板线
        return cur

    def register(u, v, cur):
        # 收银机：顶面靠后一小块
        cu, cv = (0.5, 0.3) if front == "sw" else (0.3, 0.5)
        if abs(u - cu) < 0.16 and abs(v - cv) < 0.16:
            return (70, 72, 80, 255)
        return cur

    b.paint_face(front, face_front).paint_face(side, lambda u, v, cur: darken(cur, 0.1) if v < 2 else cur).paint_top(register)
    # 收银机的立体部分：在顶面那块上方叠一个小方块
    cx = b.ox + (0 if front == "sw" else -3)
    cy = 3
    for dy in range(-6, 0):
        for dx in range(-4, 5):
            c = (70, 72, 80, 255) if dy > -5 else (96, 98, 108, 255)
            if dy == -4 and -3 <= dx <= 1:
                c = (120, 220, 150, 255)                           # 显示屏
            if dy == -2 and dx % 2 == 0:
                c = (150, 150, 160, 255)                           # 按键
            b.put(cx + dx, cy + dy + 6, c)
    b.edge()
    return b, {"tiers": [], "slot": [0.5, 0.5]}


def mannequin():
    """模特：矮台座 + 人台，身上的围巾单独一层按颜色上色。"""
    base = IsoBox(4, 0.5, 0.5).fill((80, 70, 66, 255), top=(110, 98, 92, 255))
    W = 24
    img = Image.new("RGBA", (W, 36), (0, 0, 0, 0))
    scarf = Image.new("LA", (W, 36), (0, 0))
    cx = 12
    img.paste(base.img, (cx - base.img.size[0] // 2, 36 - base.img.size[1]))
    BODY = (236, 224, 206, 255)
    SH = (206, 190, 168, 255)
    # 人台：肩 10 宽 → 腰 6 → 臀 8，下面一根杆到台座
    rows = {8: 4, 9: 10, 10: 10, 11: 10, 12: 9, 13: 8, 14: 7, 15: 6, 16: 6, 17: 7, 18: 8, 19: 8, 20: 8, 21: 7}
    for y, w in rows.items():
        for x in range(cx - w // 2, cx - w // 2 + w):
            img.putpixel((x, y), SH if x >= cx + 2 else BODY)
    for y in range(4, 8):                                          # 脖子和头钮
        img.putpixel((cx - 1, y), BODY)
        img.putpixel((cx, y), SH)
    for y in range(22, 32):                                        # 杆
        img.putpixel((cx - 1, y), (90, 90, 96, 255))
        img.putpixel((cx, y), (60, 60, 66, 255))
    # 围巾：绕肩一圈，一头垂在朝镜头这边
    for y in (8, 9):
        for x in range(cx - 5, cx + 5):
            scarf.putpixel((x, y), (255 if x < cx + 2 else 190, 255))
    for y in range(10, 20):
        scarf.putpixel((cx + 1, y), (205, 255))
        scarf.putpixel((cx + 2, y), (160, 255))
    scarf.putpixel((cx + 1, 20), (130, 255))
    scarf.putpixel((cx + 2, 20), (130, 255))
    # 轮廓
    sil = {(x, y) for y in range(36) for x in range(W) if img.getpixel((x, y))[3]}
    for (x, y) in list(sil):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            p = (x + dx, y + dy)
            if p not in sil and 0 <= p[0] < W and 0 <= p[1] < 36:
                img.putpixel(p, OUTLINE)
    anchor = [cx - base.img.size[0] // 2 + base.ox, 36 - base.img.size[1] + base.H]
    return img, scarf, anchor


def warehouse_rack(front):
    """仓库货架：蓝立柱、橙横梁的金属架，三层，前后都是空的。"""
    H = 46
    b = IsoBox(H)
    tiers = [2, 17, 32]
    POST = (70, 90, 130, 255)
    BEAM = (220, 120, 40, 255)
    BOARD = (150, 150, 150, 255)
    n = b.face_len("sw")

    def frame(u, v, cur):
        if u < 2 or u >= n - 2:
            return POST
        c = stripe(u, v, [t - 2 for t in tiers] + [H - 2], BEAM)
        return c

    b.paint_face("sw", frame).paint_face("se", lambda u, v, cur: darken(frame(u, v, cur) or (0, 0, 0, 0), 0.28) if frame(u, v, cur) else None)
    # 后面的立柱（透过架子能看到）和每层的层板
    for (x, y0) in [(b.ox, 0), (b.lx, b.ground_h // 2), (b.rx, b.ground_h // 2)]:
        for y in range(y0 + 1, y0 + H + 1):
            for dx in (0, 1):
                if not b.img.getpixel((min(x + dx, b.W - 1), y))[3]:
                    b.put(x + dx, y, darken(POST, 0.2))
    for t in tiers + [H]:
        for y in range(b.ground_h):
            for x in range(b.W):
                if b.inside(x, y):
                    yy = y + H - t
                    if not b.img.getpixel((x, yy))[3] or t == H:
                        b.put(x, yy, BOARD if t == H else darken(BOARD, 0.15))
    b.edge()
    slot = [0.08, 0.1] if front == "sw" else [0.1, 0.08]
    return b, {"tiers": tiers, "slot": slot}


def carton(w=1.0, d=1.0, H=8):
    """纸箱：顶面一道胶带，正面一张小标签。"""
    b = IsoBox(H, w, d).fill(CARD, top=lighten(CARD, 0.12))
    TAPE = (160, 118, 70, 255)

    def top(u, v, cur):
        if abs(u / w - 0.5) < 0.07:
            return TAPE
        if abs(v / d - 0.5) < 0.03:
            return darken(cur, 0.08)                               # 盖子的折缝
        return cur

    def front(u, v, cur):
        n = b.face_len("sw")
        if v == H - 1:
            return darken(cur, 0.12)
        if 2 <= u < min(6, n - 2) and 2 <= v < min(5, H - 2):
            return (240, 236, 226, 255)                            # 标签
        return cur

    b.paint_top(top).paint_face("sw", front).paint_face("se", lambda u, v, cur: darken(cur, 0.1) if v == H - 1 else cur).edge()
    return b


def bag():
    """整包：鼓鼓的塑料袋，上面打了个结。"""
    b = IsoBox(3, 0.36, 0.46).fill((222, 226, 236, 255), top=(240, 242, 248, 255), se=(190, 196, 210, 255))
    # 顶上鼓起一点 + 结
    for x in range(b.W):
        for y in range(b.ground_h):
            if b.inside(x, y) and b.img.getpixel((x, y))[3]:
                b.put(x, y - 1, (240, 242, 248, 255) if b.img.getpixel((x, y - 1))[3] == 0 else b.img.getpixel((x, y - 1)))
    b.put(b.ox, 0, (120, 110, 130, 255))
    b.put(b.ox + 1, 0, (120, 110, 130, 255))
    b.edge()
    return b


def handcart(front):
    """手推车：一块矮板、两个轮子、后面一根扶手。front 是扶手在哪一头：'sw' 扶手在 gx 小的那头。"""
    H = 3
    w, d = (0.9, 0.7) if front == "sw" else (0.7, 0.9)
    b = IsoBox(H, w, d).fill((80, 100, 130, 255), top=(110, 130, 160, 255))
    pad = 20
    img = Image.new("RGBA", (b.W + 2, b.img.size[1] + pad + 2), (0, 0, 0, 0))
    img.paste(b.img, (1, pad + 1))
    # 轮子：板子两侧靠中间
    for (x, y) in [(1 + b.lx + 2, pad + 1 + b._yg[b.lx + 2] + H), (1 + b.rx - 2, pad + 1 + b._yg[b.rx - 2] + H)]:
        for dx in (-1, 0, 1):
            for dy in (0, 1, 2):
                if abs(dx) + abs(dy - 1) <= 2:
                    img.putpixel((x + dx, y + dy), (40, 40, 46, 255))
    # 扶手：从后面两个角立起来，顶上一根横杆
    if front == "sw":
        posts = [(1 + b.lx, pad + 1 + b._yg[b.lx]), (1 + b.ox, pad + 1)]
    else:
        posts = [(1 + b.rx, pad + 1 + b._yg[b.rx]), (1 + b.ox, pad + 1)]
    BAR = (60, 64, 72, 255)
    for (x, y) in posts:
        for yy in range(y - 18, y):
            img.putpixel((x, yy), BAR)
    (x0, y0), (x1, y1) = posts
    steps = abs(x1 - x0)
    for i in range(steps + 1):
        t = i / max(1, steps)
        img.putpixel((int(round(x0 + (x1 - x0) * t)), int(round(y0 - 18 + (y1 - y0) * t))), BAR)
    anchor = [b.ox + 1, pad + 1 + b.H]
    return img, anchor


def scarf_fold_slanted(front):
    """躺在层板上的一份叠好的围巾：长边顺着那个面，灰度图按 SKU 颜色上色。"""
    w, d = (0.62, 0.22) if front == "sw" else (0.22, 0.62)
    b = IsoBox(3, w, d, mode="LA").fill((230, 255), top=(255, 255), se=((170, 255) if front == "sw" else (200, 255)), sw=((230, 255) if front == "sw" else (190, 255)))

    def crease(u, v, cur):
        n = b.face_len(front)
        if v == 1 and u % 5 == 2 and u < n - 1:
            return (250, 255)
        if v == 0:
            return (max(0, cur[0] - 50), 255)
        return cur

    b.paint_face(front, crease)
    return b


def generate(out):
    meta = {}

    def save(name, img, anchor, H=0, extra=None):
        img.save(os.path.join(out, name + ".png"))
        m = {"size": list(img.size), "anchor": anchor, "H": H}
        if extra:
            m.update({k: v for k, v in extra.items() if k != "overlay"})
        meta[name] = m

    for front in ("sw", "se"):
        for kind, fn in [("shop_shelf", shop_shelf), ("shop_cabinet", shop_cabinet), ("shop_window", shop_window),
                         ("shop_counter", shop_counter), ("warehouse_rack", warehouse_rack)]:
            b, extra = fn(front)
            save("eq_%s_%s" % (kind, front), b.img, b.anchor(), b.H, extra)
            if "overlay" in extra:
                save("eq_%s_glass_%s" % (kind, front), extra["overlay"], b.anchor(), b.H)
        cart, anchor = handcart(front)
        save("eq_handcart_%s" % front, cart, anchor, 3)
        f = scarf_fold_slanted(front)
        save("fold_%s" % front, f.img, [f.ox, f.H], f.H)
    img, scarf, anchor = mannequin()
    save("eq_mannequin", img, anchor, 29)
    save("eq_mannequin_scarf", scarf, anchor, 29)
    c = carton()
    save("eq_carton", c.img, c.anchor(), c.H)
    c = carton(0.44, 0.8, 6)
    save("eq_carton_small_sw", c.img, c.anchor(), c.H)
    c = carton(0.8, 0.44, 6)
    save("eq_carton_small_se", c.img, c.anchor(), c.H)
    bg = bag()
    save("eq_bag", bg.img, bg.anchor(), bg.H)
    with open(os.path.join(out, "equipment.json"), "w", encoding="utf-8") as fp:
        json.dump(meta, fp, ensure_ascii=False, indent=1)
    return meta


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    print(json.dumps(generate(os.path.join(root, "assets", "sprites")), ensure_ascii=False, indent=1))
