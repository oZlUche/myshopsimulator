# 围巾店模拟器 MyShopSimulator

硬核围巾店经营模拟，Godot 4 · 2D 像素风 · 单机离线。设计文档见 [docs/](docs/)，总纲是 [01-架构设计总览](docs/01-架构设计总览.md)。

当前进度：**阶段 0 · 摆摊 vertical slice**（核心框架已搭好，正在做街区 / 摊位 / 议价 / 抽取场景）。

## 打开项目

用 Godot 4.3 或更新版本打开本文件夹即可。主场景暂时是调试界面 `scenes/debug/debug_main.tscn`：可以进货、自动经营一旬、保存 / 读取。

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
scenes/          表现层
tests/           单元测试、存档 fixture、调参工具
```

## 测试

```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

CI 在每个 PR 上跑同样的命令。

## 存档规则（硬约束，01 §7.1）

- 存档是 JSON 字典，根节点带 `schema_version`。
- 改存档结构时：`SaveManager.CURRENT_SCHEMA_VERSION` +1 → 在 `core/save/migrations/` 新增 `m_000N_to_000M.gd`（模板见 `m_template.gd.example`）并在 `migrations.gd` 登记 → 运行 `tests/tools/make_fixture.gd` 生成新版本 fixture 并提交。旧 fixture 永远不删，CI 会逐个迁移并跑一旬。
- 读档保留未知字段，写档前旧档改名 `.bak`；更新版本的存档会被拒绝而不是乱读。

## 调参

`godot --headless --path . --script res://tests/tools/balance_probe.gd` 自动玩 12 旬并打印客流、成交、现金。
