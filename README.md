# 围巾店模拟器 MyShopSimulator

硬核围巾店经营模拟，Godot 4 · 2D 像素风 · 单机离线。设计文档见 [docs/](docs/)，总纲是 [01-架构设计总览](docs/01-架构设计总览.md)。

当前进度：**阶段 0 · 摆摊 vertical slice**。一旬的完整循环已经能玩：规划（进货、标价、技能）→ 街区选址 → 摆货、开张、议价 → 收摊结算。从摊位堆里抽下层的货要玩抽取小游戏（按角落、斜着拉、先慢后快）。

开店阶段有一个预览（[07-店面仓库与整箱整包](docs/07-店面仓库与整箱整包.md)）：主菜单选"试玩开店（预览）"，直接拿到一间店面、一间仓库和卸货区里的 6 箱货。仓库里搬箱、拆箱、写标签、装手推车；店里摆设备、把包撕开倒到货架上、开门营业。

## 打开项目

用 Godot 4.7 打开本文件夹，按 F5 运行。主菜单里选“新游戏”。存档在每旬开始时自动保存，规划界面也能手动保存。主菜单里还有调试界面，可以一键自动经营一旬。

摆摊时的操作：左键选中一份货，再点另一个格子的空处，把货放到那一堆顶上；右键翻看（可能看错图案）；鼠标悬停看强化记忆；点地上那堆货把它们拾起来。

## 目录

```
core/            纯逻辑，不依赖场景（01 §7）
  truth/         真相层：库存货堆、客人、玩家
  knowledge/     认知层：标签、强化记忆、翻看、采样器
  actions/       ActionAPI（玩家与员工共用）
  ai/            议价状态机、自动售卖策略
  sim/           时钟、经济双循环、趋势、街区、摆摊营业、旬末结算、抽取物理、技能、难度开关
  save/          存档与迁移链
data/            数据表（JSON，稳定字符串 ID）
scenes/          表现层（scenes/view/iso.gd 是斜 45° 像素绘制工具）
assets/sprites/  像素精灵 PNG（由 tools/pixelart/gen_sprites.py 生成，脚本和图都提交；规范见 docs/08）
tests/           单元测试、存档 fixture、调参工具
```

## 测试

```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

另有界面冒烟测试 `tests/tools/ui_smoke.gd`（摆摊玩完一旬）和 `tests/tools/shop_smoke.gd`（试玩开店：摆设备、拆包上架、仓库搬箱装车、开门卖出一单）。CI 在每个 PR 上跑这几项。

## 存档规则（硬约束，01 §7.1）

- 存档是 JSON 字典，根节点带 `schema_version`。
- 改存档结构时：`SaveManager.CURRENT_SCHEMA_VERSION` +1 → 在 `core/save/migrations/` 新增 `m_000N_to_000M.gd`（模板见 `m_template.gd.example`）并在 `migrations.gd` 登记 → 运行 `tests/tools/make_fixture.gd` 生成新版本 fixture 并提交。旧 fixture 永远不删，CI 会逐个迁移并跑一旬。
- 读档保留未知字段，写档前旧档改名 `.bak`；更新版本的存档会被拒绝而不是乱读。

## 调参

`godot --headless --path . --script res://tests/tools/balance_probe.gd` 自动玩 12 旬并打印客流、成交、现金。
