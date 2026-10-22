class_name RestConstants
## 休息节点灰盒常量。设计文档未给出精确回血数值，下列为灰盒暂定。

## 回复最大生命的百分比（灰盒暂定；不封顶超过 max HP）
const HEAL_PERCENT := 30


## 按最大生命计算本次回血量（至少 1，若已满血实际增益可为 0）。
static func heal_amount(max_hp: int) -> int:
	if max_hp <= 0:
		return 0
	return maxi(1, int(ceili(float(max_hp) * float(HEAL_PERCENT) / 100.0)))
