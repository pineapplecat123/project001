class_name ShopConstants
## 商店灰盒常量。价格/库存量均为灰盒暂定，非 Excel 表数据。

## 货架栏位数（灰盒暂定）
const STOCK_SIZE := 5
## 每发弹药固定售价（灰盒暂定；表无单价）
const AMMO_PRICE := 8
## 重随：先免费 1 次，之后每次花费（灰盒暂定）
const FREE_REROLLS := 1
const REROLL_COST := 5
## 移除费用：单店累计递增，第一次 10、第二次 15…（文档）；离店重置
const REMOVE_BASE_COST := 10
const REMOVE_COST_STEP := 5
