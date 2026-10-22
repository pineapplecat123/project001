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

## 灰盒：无效弹药（Boss 塞袋用；非 Excel 表行，本地常量）
const INVALID_AMMO_ID := 9001
const INVALID_AMMO_NAME := "无效弹药"

## 精英战倍率（灰盒暂定：复用现有敌人 id，仅抬数值）
const ELITE_HP_MULT := 1.5
const ELITE_ATK_MULT := 1.5
const ELITE_MOBILITY_BONUS := 0
const ELITE_ATTACK_RANGE := 2
const ELITE_ENEMY_COUNT := 2
const REWARD_ELITE_BASE_GOLD := 15

## Boss 终战（灰盒暂定：复用现有敌人 id + 独特塞无效弹）
const BOSS_BODY_ENEMY_ID := 3  ## 熊
const BOSS_HP_MULT := 2.0
const BOSS_ATK_MULT := 2.0
const BOSS_MOBILITY_BONUS := 1
const BOSS_ATTACK_RANGE := 2
const BOSS_INVALID_ON_START := 2
const BOSS_INVALID_PER_ENEMY_TURN := 1
const REWARD_BOSS_BASE_GOLD := 25

## 无效弹药说明（袋内详情用）
const INVALID_AMMO_SPECIAL := "击发伤害为 0。由 Boss 等效果塞入弹药袋，占用抽弹名额。"
