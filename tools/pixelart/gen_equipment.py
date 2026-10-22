#!/usr/bin/env python3
"""店面 / 仓库设备的像素图（01 §4.9、07 文档），由 gen_sprites.py 一起调用，也可单独运行。

所有设备都是"斜 45° 方块"：顶面 + 朝左前（SW）的面 + 朝右前（SE）的面。IsoBox 负责把一个 w×d 格、高 H 美术像素的
方块画成图，并给出每个面上的局部坐标（u 沿面横向的像素、v 从地面往上的像素），细节（层板、柜门、玻璃）都画在面坐标里。
开口朝 SW 的叫 *_sw，朝 SE 的叫 *_se，两张都单独画（不是镜像），这样光照方向一致。

S 是精细度：S=1 标清（一格 32×16），S=2 高清（一格 64×32，细节翻倍再加高光 / 倒角 / 纹理）。
尺寸和高度都按标清单位写，内部乘 S；高清图正好是标清图的两倍大，锚点也翻倍，所以游戏只读一份 equipment.json（标清单位）：
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
    """占地 w×d 格（w 沿 gx 右下，d 沿 gy 左下）、高 H 美术像素（标清单位）的方块。mode 'RGBA' 画固定色，'LA' 画可上色的灰度。"""

    def __init__(self, H, w=1.0, d=1.0, mode="RGBA", S=1):
        self.S = S
        self.tw, self.th = TILE_W * S, TILE_H * S
        self.H = int(H * S)
        self.w, self.d = w, d
        self.mode = mode
        # 先按标清取整再乘 S，高清图才正好是标清的 S 倍
        self.ox = int(round(d * TILE_W / 2)) * S        # 地面菱形最上角的 x
        self.W = int(round((w + d) * TILE_W / 2)) * S
        self.ground_h = int(round((w + d) * TILE_H / 2)) * S
        self.img = Image.new(mode, (self.W, self.ground_h + self.H), (0, 0, 0, 0) if mode == "RGBA" else (0, 0))
        # 地面菱形（局部坐标，y 从 0 起）的每列最底一个像素
        self._yg = {}
        for x in range(self.W):
            ys = [y for y in range(self.ground_h) if self.inside(x, y)]
            if ys:
                self._yg[x] = max(ys)
        self.bx = int(round(self.ox / S + w * TILE_W / 2 - d * TILE_W / 2)) * S   # 最下角（B）的 x，左边是 SW 面，右边是 SE 面
        self.lx = min(self._yg) if self._yg else 0
        self.rx = max(self._yg) if self._yg else 0
        self.pad = 0

    # ---- 几何
    def uv(self, x, y):
        cx, cy = x + 0.5 - self.ox, y + 0.5
        return (cx / (self.tw / 2) + cy / (self.th / 2)) / 2, (-cx / (self.tw / 2) + cy / (self.th / 2)) / 2

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

    def edge(self):
        """前面那条竖棱 + 外轮廓（高清时轮廓也是 1 像素，更细）。"""
        W, Hh = self.img.size
        for y in range(Hh):
            f = self.face_px(self.bx, y)
            if f and self.img.getpixel((self.bx, y))[-1]:
                self.put(self.bx, y, darken(self.img.getpixel((self.bx, y)), 0.35))
        sil = {(x, y) for y in range(Hh) for x in range(W) if self.img.getpixel((x, y))[-1]}
        S = self.S
        out = Image.new(self.mode, (W + 2 * S, Hh + 2 * S), (0, 0, 0, 0) if self.mode == "RGBA" else (0, 0))
        out.paste(self.img, (S, S))
        oc = OUTLINE if self.mode == "RGBA" else (0, 150)
        for (x, y) in sil:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                p = (x + dx, y + dy)
                if p not in sil:
                    out.putpixel((p[0] + S, p[1] + S), oc)
        self.img = out
        self.ox += S
        self.pad = S
        return self

    def anchor(self):
        return [self.ox, self.H + self.pad]


def split_layers(b, front_px, board_px):
    """把一件有层板的设备拆成几张叠画的图（都在 edge() 之后调用，坐标是 edge 之前的）：
    底图（后面的立柱、背板、侧板）+ 每层一张"层板"图（层板顶面和它朝外的横梁 / 前沿）+ 一张"前框"图（朝外的立柱）。
    游戏里按 底图 → 第 0 层板 → 第 0 层的货 → 第 1 层板 → 第 1 层的货 → … → 顶板 → 前框 画，
    第 N 层的货压在第 N 层板上、又被第 N+1 层板（也就是第 N 层的顶）挡住，最后前框挡住所有层。
    board_px 是按层从下往上的像素集合列表（最后一个是顶板）。返回 (底图, [层板图...], 前框图)。"""
    S = b.S
    img = b.img
    used = set(front_px)
    for s in board_px:
        used |= s

    def only(pxs):
        out = Image.new(img.mode, img.size, (0, 0, 0, 0) if img.mode == "RGBA" else (0, 0))
        for (x, y) in pxs:
            out.putpixel((x + S, y + S), img.getpixel((x + S, y + S)))
        return out

    base = img.copy()
    clear = (0, 0, 0, 0) if img.mode == "RGBA" else (0, 0)
    for (x, y) in used:
        base.putpixel((x + S, y + S), clear)
    return base, [only(s) for s in board_px], only(front_px)


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


def shop_shelf(front, S=1):
    """店面货架：三层开放式层板，正面能看到每层的货。"""
    H = 39
    b = IsoBox(H, S=S).fill(WOOD)
    tiers = [2, 14, 26]
    side = "se" if front == "sw" else "sw"
    n = b.face_len(front)
    HS = H * S

    def face_front(u, v, cur):
        if u < 2 * S or u >= n - 2 * S:
            if S >= 2 and (u == 0 or u == n - 2 * S):
                return lighten(WOOD, 0.08)      # 立柱受光的一侧
            return darken(WOOD, 0.1)           # 侧立柱
        if v >= HS - 2 * S:
            return darken(WOOD, 0.1)           # 顶框
        for t in tiers:
            t0 = (t - 2) * S
            if t0 <= v < t0 + 2 * S:
                if S >= 2 and v == t0 + 2 * S - 1:
                    return lighten(WOOD, 0.55)  # 层板上沿高光
                return lighten(WOOD, 0.35)
        if S >= 2 and any(v == t * S for t in tiers):
            return (56, 40, 28, 255)           # 层板下面一道阴影
        return (70, 50, 34, 255)               # 背板（阴影里）

    def face_side(u, v, cur):
        m = b.face_len(side)
        if 3 * S <= u < m - 3 * S and 4 * S <= v < HS - 4 * S:
            if S >= 2 and (u == 3 * S or v == HS - 4 * S - 1):
                return lighten(cur, 0.16)      # 凹槽的亮边
            return lighten(cur, 0.06)          # 侧板凹槽
        return cur

    b.paint_face(front, face_front).paint_face(side, face_side)
    # 拆层：正面两根立柱是前框；每层层板的前沿（含下面那道阴影）是那一层的层板，顶框是顶板
    posts, boards = set(), [set() for _ in tiers] + [set()]
    for y in range(b.img.size[1]):
        for x in range(b.img.size[0]):
            f = b.face_px(x, y)
            if not f or f[0] != front:
                continue
            u, v = f[1], f[2]
            if u < 2 * S or u >= n - 2 * S:
                posts.add((x, y))
            elif v >= HS - 2 * S:
                boards[-1].add((x, y))
            else:
                for k, tt in enumerate(tiers):
                    if (tt - 2) * S <= v <= tt * S:
                        boards[k].add((x, y))
    b.edge()
    base, board_imgs, front_img = split_layers(b, posts, boards)
    b.img = base
    slot = [0.2, 0.78] if front == "sw" else [0.78, 0.2]
    return b, {"tiers": tiers, "slot": slot, "boards": board_imgs, "front": front_img}


def shop_cabinet(front, S=1):
    """货柜：两扇柜门，客人看不到里面。"""
    H = 40
    b = IsoBox(H, S=S).fill(WOOD, top=lighten(WOOD, 0.25))
    side = "se" if front == "sw" else "sw"
    n = b.face_len(front)
    HS = H * S
    BRASS = (220, 200, 120, 255)

    def face_front(u, v, cur):
        if v < 3 * S:
            return darken(WOOD, 0.35)                              # 底座
        if u < S or u >= n - S or v >= HS - 2 * S:
            return darken(WOOD, 0.15)                              # 外框
        if n // 2 - S <= u < n // 2 + S:
            return darken(WOOD, 0.4)                               # 两扇门之间的缝
        if (n // 2 - 3 * S <= u < n // 2 - 2 * S or n // 2 + 2 * S <= u < n // 2 + 3 * S) and 17 * S <= v < 21 * S:
            if S >= 2 and v == 21 * S - 1:
                return lighten(BRASS, 0.5)
            return BRASS                                           # 铜把手
        panel_l = (u == 2 * S or (S >= 2 and u == 2 * S + 1)) or (u == n - 3 * S or (S >= 2 and u == n - 3 * S - 1))
        panel_h = (4 * S <= v < 4 * S + S) or (HS - 4 * S <= v < HS - 4 * S + S)
        if panel_l or panel_h:
            if S >= 2 and (u == 2 * S or v == HS - 4 * S + S - 1):
                return lighten(WOOD, 0.2)                          # 门板倒角：左上亮
            return darken(WOOD, 0.1)                               # 右下暗
        return lighten(WOOD, 0.05) if (u < n // 2) else WOOD

    b.paint_face(front, face_front).paint_face(side, lambda u, v, cur: darken(cur, 0.1) if v < 3 * S else cur).edge()
    return b, {"tiers": [], "slot": [0.5, 0.5]}


def shop_window(front, S=1):
    """橱窗：下面一截台座，上面是框着玻璃的展示格，两层。玻璃单独一张叠在货上面。"""
    H = 31
    FRAME = (214, 206, 192, 255)
    PLINTH = (84, 76, 70, 255)
    b = IsoBox(H, S=S).fill(FRAME, top=lighten(FRAME, 0.3))
    tiers = [5, 18]
    side = "se" if front == "sw" else "sw"
    n = b.face_len(front)
    HS = H * S

    def face_front(u, v, cur):
        if v < 4 * S:
            if S >= 2 and v == 4 * S - 1:
                return lighten(PLINTH, 0.3)
            return PLINTH                                          # 台座
        if u < 2 * S or u >= n - 2 * S or v >= HS - 2 * S:
            return darken(FRAME, 0.1)                              # 窗框
        for t in tiers:
            if (t - 1) * S <= v < t * S:
                return (190, 178, 158, 255)                        # 层板
        return (250, 244, 228, 255)                                # 里面的衬板

    b.paint_face(front, face_front).paint_face(side, lambda u, v, cur: PLINTH if v < 4 * S else cur).edge()
    # 玻璃层：只盖窗格那块，带一道斜的反光
    g = IsoBox(H, S=S)

    def glass(u, v, cur):
        if v < 4 * S or u < 2 * S or u >= n - 2 * S or v >= HS - 2 * S:
            return None
        if (u + v) % (11 * S) < 2 * S and u > 3 * S:
            return (255, 255, 255, 120)
        if S >= 2 and (u + v) % (11 * S) in (2 * S, 2 * S + 1) and u > 3 * S:
            return (255, 255, 255, 60)
        return (170, 210, 240, 70)

    g.paint_face(front, glass)
    gi = Image.new("RGBA", (g.img.size[0] + 2 * S, g.img.size[1] + 2 * S), (0, 0, 0, 0))
    gi.paste(g.img, (S, S))
    slot = [0.2, 0.74] if front == "sw" else [0.74, 0.2]
    return b, {"tiers": tiers, "slot": slot, "overlay": gi}


def shop_counter(front, S=1):
    """收银台：矮柜，台面上放一台收银机。"""
    H = 17
    b = IsoBox(H, S=S).fill(WOOD, top=(176, 142, 96, 255))
    side = "se" if front == "sw" else "sw"
    n = b.face_len(front)
    HS = H * S

    def face_front(u, v, cur):
        if v < 2 * S:
            return darken(WOOD, 0.4)
        if v >= HS - 2 * S:
            return lighten(WOOD, 0.2)                              # 台面沿
        if 2 * S <= u < n - 2 * S and 4 * S <= v < HS - 4 * S and (u < 3 * S or u >= n - 3 * S or v < 5 * S or v >= HS - 5 * S):
            return darken(WOOD, 0.1)                               # 面板线
        if S >= 2 and (u + 3 * v) % 9 == 0 and 3 * S <= u < n - 3 * S and 5 * S <= v < HS - 5 * S:
            return darken(WOOD, 0.04)                              # 木纹
        return cur

    def top_grain(u, v, cur):
        if S >= 2 and int(v * 24) % 6 == 0:
            return darken(cur, 0.05)
        return cur

    def register(u, v, cur):
        cu, cv = (0.5, 0.3) if front == "sw" else (0.3, 0.5)
        if abs(u - cu) < 0.16 and abs(v - cv) < 0.16:
            return (70, 72, 80, 255)
        return cur

    b.paint_face(front, face_front).paint_face(side, lambda u, v, cur: darken(cur, 0.1) if v < 2 * S else cur).paint_top(top_grain).paint_top(register)
    # 收银机的立体部分：在顶面那块上方叠一个小方块
    cx = b.ox + (0 if front == "sw" else -3 * S)
    cy = 3 * S
    for dy in range(-6 * S, 0):
        for dx in range(-4 * S, 4 * S + 1):
            c = (70, 72, 80, 255) if dy > -5 * S else (96, 98, 108, 255)
            if -4 * S <= dy < -3 * S and -3 * S <= dx <= S:
                c = (120, 220, 150, 255)                           # 显示屏
            if -2 * S <= dy < -S and (dx // S) % 2 == 0:
                c = (150, 150, 160, 255)                           # 按键
            if S >= 2 and dx == -4 * S:
                c = lighten(c, 0.2)
            b.put(cx + dx, cy + dy + 6 * S, c)
    b.edge()
    return b, {"tiers": [], "slot": [0.5, 0.5]}


def mannequin(S=1):
    """模特：矮台座 + 人台，身上的围巾单独一层按颜色上色。"""
    base = IsoBox(4, 0.5, 0.5, S=S).fill((80, 70, 66, 255), top=(110, 98, 92, 255))
    W, Hh = 24 * S, 36 * S
    img = Image.new("RGBA", (W, Hh), (0, 0, 0, 0))
    scarf = Image.new("LA", (W, Hh), (0, 0))
    cx = 12 * S
    img.paste(base.img, (cx - base.img.size[0] // 2, Hh - base.img.size[1]))
    BODY = (236, 224, 206, 255)
    SH = (206, 190, 168, 255)
    SH2 = (186, 170, 150, 255)
    # 人台：肩 10 宽 → 腰 6 → 臀 8（标清单位），高清按曲线插值更圆润
    rows_sd = {8: 4, 9: 10, 10: 10, 11: 10, 12: 9, 13: 8, 14: 7, 15: 6, 16: 6, 17: 7, 18: 8, 19: 8, 20: 8, 21: 7}
    if S == 1:
        rows = rows_sd
    else:
        rows = {}
        keys = sorted(rows_sd)
        for y in range(keys[0] * S, (keys[-1] + 1) * S):
            fy = y / S
            k0 = max(k for k in keys if k <= fy)
            k1 = min(keys[-1], k0 + 1)
            t = fy - k0
            rows[y] = int(round((rows_sd[k0] * (1 - t) + rows_sd[k1] * t) * S))
    for y, w in rows.items():
        for x in range(cx - w // 2, cx - w // 2 + w):
            if x >= cx + 3 * S:
                img.putpixel((x, y), SH2 if S >= 2 else SH)
            elif x >= cx + 2 * S:
                img.putpixel((x, y), SH)
            else:
                img.putpixel((x, y), BODY)
    for y in range(4 * S, 8 * S):                                  # 脖子和头钮
        for x in range(cx - S, cx + S):
            img.putpixel((x, y), BODY if x < cx else SH)
    if S >= 2:
        for x in range(cx - 2 * S, cx + 2 * S):                    # 头钮圆一点
            for y in range(4 * S, 6 * S):
                img.putpixel((x, y), BODY if x < cx else SH)
    for y in range(22 * S, 32 * S):                                # 杆
        for x in range(cx - S, cx + S):
            img.putpixel((x, y), (90, 90, 96, 255) if x < cx else (60, 60, 66, 255))
    # 围巾：绕肩一圈，一头垂在朝镜头这边，高清加流苏
    for y in range(8 * S, 10 * S):
        for x in range(cx - 5 * S, cx + 5 * S):
            scarf.putpixel((x, y), (255 if x < cx + 2 * S else 190, 255))
    for y in range(10 * S, 20 * S):
        for x in range(cx + S, cx + 3 * S):
            scarf.putpixel((x, y), (205 if x < cx + 2 * S else 160, 255))
    for x in range(cx + S, cx + 3 * S):
        if S >= 2 and (x - cx - S) % 2 == 1:
            continue
        scarf.putpixel((x, 20 * S), (130, 255))
        if S >= 2:
            scarf.putpixel((x, 20 * S + 1), (130, 255))
    # 轮廓
    sil = {(x, y) for y in range(Hh) for x in range(W) if img.getpixel((x, y))[3]}
    for (x, y) in list(sil):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            p = (x + dx, y + dy)
            if p not in sil and 0 <= p[0] < W and 0 <= p[1] < Hh:
                img.putpixel(p, OUTLINE)
    anchor = [cx - base.img.size[0] // 2 + base.ox, Hh - base.img.size[1] + base.H]
    return img, scarf, anchor


def warehouse_rack(front, S=1):
    """仓库货架：蓝立柱、橙横梁的金属架，三层，前后通透。"""
    H = 46
    b = IsoBox(H, S=S)
    tiers = [2, 17, 32]
    POST = (70, 90, 130, 255)
    BEAM = (220, 120, 40, 255)
    BOARD = (150, 150, 150, 255)
    n = b.face_len("sw")
    HS = H * S

    def frame(u, v, cur):
        if u < 2 * S or u >= n - 2 * S:
            if S >= 2 and v % 4 == 1 and (u == S or u == n - S - 1):
                return darken(POST, 0.4)                           # 立柱上的孔
            return POST
        for t in tiers + [H]:
            t0 = (t - 2) * S
            if t0 <= v < t0 + 2 * S:
                if S >= 2 and v == t0 + 2 * S - 1:
                    return lighten(BEAM, 0.3)
                return BEAM
        return None

    b.paint_face("sw", frame).paint_face("se", lambda u, v, cur: darken(frame(u, v, cur), 0.28) if frame(u, v, cur) else None)
    # 拆层（见 split_layers）：朝外两面的立柱是前框；每层的横梁和层板顶面是那一层的层板
    posts, boards = set(), [set() for _ in tiers] + [set()]
    for y in range(b.img.size[1]):
        for x in range(b.img.size[0]):
            f = b.face_px(x, y)
            if not f or not b.img.getpixel((x, y))[3]:
                continue
            u, v = f[1], f[2]
            if u < 2 * S or u >= b.face_len(f[0]) - 2 * S:
                posts.add((x, y))
                continue
            for k, tt in enumerate(tiers + [H]):
                if (tt - 2) * S <= v < tt * S:
                    boards[k].add((x, y))
    # 后面的立柱（透过架子能看到）和每层的层板
    for (x, y0) in [(b.ox, 0), (b.lx, b.ground_h // 2), (b.rx, b.ground_h // 2)]:
        for y in range(y0 + 1, y0 + HS + 1):
            for dx in range(0, 2 * S):
                xx = min(x + dx, b.W - 1)
                if not b.img.getpixel((xx, y))[3]:
                    b.put(xx, y, darken(POST, 0.2))
    for t in tiers + [H]:
        for y in range(b.ground_h):
            for x in range(b.W):
                if b.inside(x, y):
                    yy = y + HS - t * S
                    if not b.img.getpixel((x, yy))[3] or t == H:
                        c = BOARD if t == H else darken(BOARD, 0.15)
                        if S >= 2 and t == H and (x + 2 * y) % 8 == 0:
                            c = darken(BOARD, 0.08)                # 顶层板的网格纹
                        b.put(x, yy, c)
                        boards[(tiers + [H]).index(t)].add((x, yy))
    b.edge()
    base, board_imgs, front_img = split_layers(b, posts, boards)
    b.img = base
    slot = [0.08, 0.1] if front == "sw" else [0.1, 0.08]
    return b, {"tiers": tiers, "slot": slot, "boards": board_imgs, "front": front_img}


def carton(w=1.0, d=1.0, H=8, S=1):
    """纸箱：顶面一道胶带，正面一张小标签；高清加盖子折缝和标签上的字迹。"""
    b = IsoBox(H, w, d, S=S).fill(CARD, top=lighten(CARD, 0.12))
    TAPE = (160, 118, 70, 255)
    HS = H * S
    n = b.face_len("sw")

    def top(u, v, cur):
        if abs(u / w - 0.5) < 0.07:
            if S >= 2 and abs(u / w - 0.5) > 0.055:
                return darken(TAPE, 0.15)
            return TAPE
        if abs(v / d - 0.5) < 0.03:
            return darken(cur, 0.08)                               # 盖子的折缝
        return cur

    def front(u, v, cur):
        if v >= HS - S:
            return darken(cur, 0.12)
        if 2 * S <= u < min(6 * S, n - 2 * S) and 2 * S <= v < min(5 * S, HS - 2 * S):
            if S >= 2 and v in (3 * S, 3 * S + 1) and (u - 2 * S) % 3 != 2:
                return (120, 110, 100, 255)                        # 标签上的字
            return (240, 236, 226, 255)                            # 标签
        return cur

    b.paint_top(top).paint_face("sw", front).paint_face("se", lambda u, v, cur: darken(cur, 0.1) if v >= HS - S else cur).edge()
    return b


def bag(S=1):
    """整包：鼓鼓的塑料袋，上面打了个结。"""
    b = IsoBox(3, 0.36, 0.46, S=S).fill((222, 226, 236, 255), top=(240, 242, 248, 255), se=(190, 196, 210, 255))
    # 顶上鼓起一点 + 结
    for x in range(b.W):
        for y in range(b.ground_h):
            if b.inside(x, y) and b.img.getpixel((x, y))[3]:
                for k in range(1, S + 1):
                    if y - k >= 0 and b.img.getpixel((x, y - k))[3] == 0:
                        b.put(x, y - k, (240, 242, 248, 255))
    if S >= 2:
        for x in range(b.lx + 2, b.bx, 3):                         # 褶皱高光
            yy = b._yg[x] + b.H - 2
            b.put(x, yy, (250, 252, 255, 255))
    for dx in range(0, 2 * S):
        b.put(b.ox + dx, 0, (120, 110, 130, 255))
    b.edge()
    return b


def handcart(front, S=1):
    """手推车：一块矮板、两个轮子、一头一根扶手。front 是扶手在哪一头（也就是推车人站的那头，车往反方向走）：
    'sw' 扶手在 gx 小的那头（往 +gx 推）、'se' 在 gy 小的那头（往 +gy 推）、
    'ne' 在 gx 大的那头（往 -gx 推，扶手朝镜头）、'nw' 在 gy 大的那头（往 -gy 推，扶手朝镜头）。"""
    H = 3
    w, d = (0.9, 0.7) if front in ("sw", "ne") else (0.7, 0.9)
    b = IsoBox(H, w, d, S=S).fill((80, 100, 130, 255), top=(110, 130, 160, 255))
    pad = 20 * S
    img = Image.new("RGBA", (b.W + 2 * S, b.img.size[1] + pad + 2 * S), (0, 0, 0, 0))
    img.paste(b.img, (S, pad + S))
    # 轮子：板子两侧靠中间
    r = S
    for (x, y) in [(S + b.lx + 2 * S, pad + S + b._yg[b.lx + 2 * S] + b.H), (S + b.rx - 2 * S, pad + S + b._yg[b.rx - 2 * S] + b.H)]:
        for dx in range(-r, r + 1):
            for dy in range(0, 2 * r + 1):
                if abs(dx) + abs(dy - r) <= 2 * r:
                    img.putpixel((x + dx, y + dy), (40, 40, 46, 255) if not (S >= 2 and dx == 0 and dy == r) else (90, 90, 96, 255))
    # 扶手：从后面两个角立起来，顶上一根横杆
    corner = {"l": (S + b.lx, pad + S + b._yg[b.lx]), "r": (S + b.rx, pad + S + b._yg[b.rx]),
              "o": (S + b.ox, pad + S), "b": (S + b.bx, pad + S + b._yg[b.bx])}
    posts = [corner[c] for c in {"sw": "lo", "se": "ro", "ne": "rb", "nw": "lb"}[front]]
    BAR = (60, 64, 72, 255)
    for (x, y) in posts:
        for yy in range(y - 18 * S, y):
            for dx in range(S):
                img.putpixel((x + dx, yy), BAR if not (S >= 2 and dx == 0) else lighten(BAR, 0.25))
    (x0, y0), (x1, y1) = posts
    steps = abs(x1 - x0)
    for i in range(steps + 1):
        t = i / max(1, steps)
        px = int(round(x0 + (x1 - x0) * t))
        py = int(round(y0 - 18 * S + (y1 - y0) * t))
        for dy in range(S):
            img.putpixel((px, py + dy), lighten(BAR, 0.25) if (S >= 2 and dy == 0) else BAR)
    anchor = [b.ox + S, pad + S + b.H]
    return img, anchor


def scarf_fold_slanted(front, S=1):
    """躺在层板上的一份叠好的围巾：长边顺着那个面，灰度图按 SKU 颜色上色。"""
    w, d = (0.62, 0.22) if front == "sw" else (0.22, 0.62)
    b = IsoBox(3, w, d, mode="LA", S=S).fill((230, 255), top=(255, 255), se=((170, 255) if front == "sw" else (200, 255)), sw=((230, 255) if front == "sw" else (190, 255)))
    n = b.face_len(front)

    def crease(u, v, cur):
        if v == S and u % (5 * S) == 2 * S and u < n - S:
            return (250, 255)
        if v < S:
            return (max(0, cur[0] - 50), 255)
        if S >= 2 and v == 2 * S and u % (5 * S) == 2 * S + 1:
            return (215, 255)
        return cur

    b.paint_face(front, crease)
    return b


def generate(out, S=1):
    meta = {}

    def save(name, img, anchor, H=0, extra=None):
        img.save(os.path.join(out, name + ".png"))
        m = {"size": list(img.size), "anchor": anchor, "H": H}
        if extra:
            m.update({k: v for k, v in extra.items() if k not in ("overlay", "front", "boards")})
        meta[name] = m

    for front in ("sw", "se"):
        for kind, fn in [("shop_shelf", shop_shelf), ("shop_cabinet", shop_cabinet), ("shop_window", shop_window),
                         ("shop_counter", shop_counter), ("warehouse_rack", warehouse_rack)]:
            b, extra = fn(front, S)
            save("eq_%s_%s" % (kind, front), b.img, b.anchor(), b.H, extra)
            if "overlay" in extra:
                save("eq_%s_glass_%s" % (kind, front), extra["overlay"], b.anchor(), b.H)
            if "front" in extra:
                save("eq_%s_front_%s" % (kind, front), extra["front"], b.anchor(), b.H)
            for k, img in enumerate(extra.get("boards", [])):
                save("eq_%s_board%d_%s" % (kind, k, front), img, b.anchor(), b.H)
        cart, anchor = handcart(front, S)
        save("eq_handcart_%s" % front, cart, anchor, 3 * S)
        cart, anchor = handcart({"sw": "ne", "se": "nw"}[front], S)
        save("eq_handcart_%s" % {"sw": "ne", "se": "nw"}[front], cart, anchor, 3 * S)
        f = scarf_fold_slanted(front, S)
        save("fold_%s" % front, f.img, [f.ox, f.H], f.H)
    img, scarf, anchor = mannequin(S)
    save("eq_mannequin", img, anchor, 29 * S)
    save("eq_mannequin_scarf", scarf, anchor, 29 * S)
    c = carton(S=S)
    save("eq_carton", c.img, c.anchor(), c.H)
    c = carton(0.44, 0.8, 6, S)
    save("eq_carton_small_sw", c.img, c.anchor(), c.H)
    c = carton(0.8, 0.44, 6, S)
    save("eq_carton_small_se", c.img, c.anchor(), c.H)
    bg = bag(S)
    save("eq_bag", bg.img, bg.anchor(), bg.H)
    # 人抱在身前的小纸箱（比人窄，两只手露在两边）
    c = carton(0.32, 0.32, 6, S)
    save("eq_carton_carry", c.img, c.anchor(), c.H)
    if S == 1:
        with open(os.path.join(out, "equipment.json"), "w", encoding="utf-8") as fp:
            json.dump(meta, fp, ensure_ascii=False, indent=1)
    else:
        # 高清图必须正好是标清的 S 倍，游戏里才能共用一份元数据
        sd_path = os.path.join(os.path.dirname(out.rstrip("/")), "sprites", "equipment.json")
        with open(sd_path, encoding="utf-8") as fp:
            sd = json.load(fp)
        for name, m in meta.items():
            ref = sd[name]
            assert m["size"] == [ref["size"][0] * S, ref["size"][1] * S], (name, m["size"], ref["size"])
            assert m["anchor"] == [ref["anchor"][0] * S, ref["anchor"][1] * S], (name, m["anchor"], ref["anchor"])
    return meta


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    print(json.dumps(generate(os.path.join(root, "assets", "sprites")), ensure_ascii=False, indent=1))
