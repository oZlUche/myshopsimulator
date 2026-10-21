class_name Migrations
extends RefCounted
## 迁移注册表：{起始版本: 迁移脚本}。脚本把 N 版字典改成 N+1 版。
## 规则（01 §7.1）：只能增字段、改名、换默认值，不能依赖游戏逻辑；每次新增必须加一份存档 fixture。
## 新增示例：
##   const REGISTRY := {1: preload("res://core/save/migrations/m_0001_to_0002.gd")}

const REGISTRY := {
	1: preload("res://core/save/migrations/m_0001_to_0002.gd"),
}
