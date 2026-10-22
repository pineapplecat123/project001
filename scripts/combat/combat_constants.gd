class_name CombatConstants
## 战斗常量表（灰盒）。

const BOARD_SIZE := 10
const PLAYER_CELL := 0
const MAGAZINE_SIZE := 6
const PLAYER_MAX_HP := 20
const WHITE_AMMO_ID := 1
const CIVILIAN_ENEMY_ID := 1
## 灰盒开局弹药袋：若干发白色（足够打完平民并演示抽弃洗）。
const STARTER_WHITE_COUNT := 12

## 战斗胜利奖励（灰盒）
const REWARD_BASE_GOLD := 10
const REWARD_SKIP_EXTRA_GOLD := 5
const REWARD_CHOICE_COUNT := 3
# 预留（灰盒不做）：无伤额外金、三回合内额外金
const REWARD_NO_DAMAGE_EXTRA_GOLD := 0
const REWARD_FAST_CLEAR_EXTRA_GOLD := 0
const REWARD_FAST_CLEAR_TURN_LIMIT := 3
