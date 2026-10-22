# BOT_LOG

## 2026-10-21

- 收到 harness 完整版 v1.2，放入 `docs/harness.md`。
- 按你确认修订为 v1.3：PAT 推送说明、任务粒度、`docs/implemented-systems.md`、非 Web 渲染器口子、验收录屏策略。
- 新建 `docs/implemented-systems.md` 空壳与本日志。
- 经你批准：提交并推送到 `main`。


## 2026-10-23

- 收到基础游戏文档两份：`游戏项目文档 v0.0.1`、`机制确认清单（闭合版 v1.0）`。
- 经你确认「好的」：入库 `docs/game-design-v0.0.1.md`、`docs/mechanism-checklist-v1.0.md`（冲突以清单为准）。
- 尚未开始功能实现；等待弹药/敌人等设计表。


## 2026-10-23（续）

- 用户确认弹药/敌人表 7 条裁定；批准第一大模块；明确先不做地图，主菜单直进战斗；LOAD/FIRE/ROLL/UNLOAD 须完整可用；设计源会随新表替换。
- 实现中：数据管线（xlsx + 管理文档 + JSON）+ 战斗骨架（白弹 + 平民）+ GUT；本地 commit，push 等批准。

- 完成第一大模块：数据管线 + 战斗骨架；GUT 12/12 通过；本地 commit，**未 push**（等批准）。
- 已知限制：仅白色子弹/平民进局；流血不结算；无调试面板；无地图/商店/奖励；其它弹种仅数据入库。

## 2026-10-23（字体）

- Web 中文乱码：嵌入子集字体 `assets/fonts/NotoSansSC-UI.ttf`，全局 Theme `themes/ui_theme.tres`。

- 2026-10-23：Pages 资源按 SHA 改名防缓存；版本 0.1.2。

## 2026-10-23（Push A · v0.1.3）

- 弹夹改为左轮环形 UI；ROLL=随机转轮，击发点（红标）固定顶部，不再点选起点。
- FIRE：`begin_fire` / `fire_next_shot`；UI 每发间隔 0.4s，射击中禁用行动按钮。
- 修复：袋与弃牌皆空时失败原因为「弹药耗尽」，不再把 `player_hp` 置 0 伪装被杀。
- 怪物仅邻接（格 1）才攻击；远处多回合不掉血（GUT 覆盖）。
- 检视弹药袋只读面板；开发者工具骨架。
- 字体：自 Noto Sans CJK SC 重新 subset，`allow_system_fallback=false`。
