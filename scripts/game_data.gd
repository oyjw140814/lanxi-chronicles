extends RefCounted
## Original gameplay definitions for 岚汐纪. Distances are meters, time is seconds.
const WORLD_SIZE := 80.0
const SAVE_VERSION := 1
const UNITS := {
	"worker": {"name": "拾光者", "hp": 65.0, "speed": 4.4, "damage": 4.0, "range": 1.3, "interval": 1.0, "train_time": 9.0, "radius": 0.38, "vision": 10.0, "description": "经济与施工。采集资源、建造设施，每次携带 12 份资源回响心交付；战斗力弱，留在后方。"},
	"guard": {"name": "棱盾卫", "hp": 165.0, "speed": 3.8, "damage": 16.0, "range": 1.5, "interval": 1.0, "train_time": 12.0, "radius": 0.45, "vision": 11.0, "description": "盾牌近战前排，掩护射手与工人；对弦光手造成 1.5 倍伤害，需提防攻坚兽。"},
	"ranger": {"name": "弦光手", "hp": 85.0, "speed": 4.2, "damage": 12.0, "range": 7.0, "interval": 1.25, "train_time": 14.0, "radius": 0.4, "vision": 13.0, "description": "弓箭远程支援，射程 7 米；对裂岩兽造成 1.6 倍伤害。保持距离，避免骑士与盾卫近身。"},
	"lancer": {"name": "缚潮枪卫", "hp": 140.0, "speed": 3.6, "damage": 14.0, "range": 2.4, "interval": 1.15, "train_time": 13.0, "radius": 0.42, "vision": 11.0, "description": "长枪反骑兵。对逐潮骑士造成 2.2 倍伤害，保护射手免受突袭；移动较慢，应提前布防。"},
	"rider": {"name": "逐潮骑士", "hp": 195.0, "speed": 6.6, "damage": 19.0, "range": 1.9, "interval": 1.1, "train_time": 20.0, "radius": 0.65, "vision": 15.0, "description": "骑乘潮角兽的机动骑兵。对弦光手造成 1.8 倍伤害，适合侦察、侧翼突袭和追击；应避开长枪阵。"},
	"breaker": {"name": "裂岩兽", "hp": 230.0, "speed": 2.8, "damage": 24.0, "range": 1.8, "interval": 1.5, "train_time": 19.0, "radius": 0.62, "vision": 10.0, "description": "重型攻坚，对建筑造成 2.5 倍伤害，对棱盾卫造成 1.3 倍伤害。"}
}
const ROLES := {"worker":"工人", "guard":"盾卫", "ranger":"射手", "lancer":"枪卫", "rider":"骑士", "breaker":"攻坚兽"}
const BUILDINGS := {
	"heart": {"name": "回响心", "hp": 1200.0, "radius": 2.8, "build_time": 45.0, "vision": 17.0, "capacity": 10, "trains": ["worker", "guard", "ranger", "lancer", "rider", "breaker"], "description": "资源交付点与招募中心，可训练工人及全部兵种。失去它就会失败。"},
	"house": {"name": "风栖居", "hp": 400.0, "radius": 1.6, "build_time": 14.0, "vision": 9.0, "capacity": 6, "trains": [], "description": "建成后增加 6 人口上限。"},
	"barracks": {"name": "织锋庭", "hp": 650.0, "radius": 2.1, "build_time": 22.0, "vision": 12.0, "capacity": 0, "trains": ["guard", "ranger", "lancer", "rider", "breaker"], "description": "独立军事训练队列，生产盾卫、射手、枪卫、骑士与攻坚兽。"},
	"tower": {"name": "辉棱哨", "hp": 540.0, "radius": 1.25, "build_time": 20.0, "vision": 16.0, "capacity": 0, "trains": [], "damage": 20.0, "range": 11.0, "interval": 1.6, "description": "自动攻击视野内的敌军。"}
}
const COSTS := {
	"worker": {"food": 45, "wood": 0, "crystal": 0},
	"guard": {"food": 60, "wood": 20, "crystal": 0},
	"ranger": {"food": 35, "wood": 50, "crystal": 0},
	"lancer": {"food": 55, "wood": 35, "crystal": 0},
	"rider": {"food": 95, "wood": 20, "crystal": 25},
	"breaker": {"food": 50, "wood": 30, "crystal": 35},
	"house": {"food": 0, "wood": 70, "crystal": 0},
	"barracks": {"food": 40, "wood": 140, "crystal": 0},
	"tower": {"food": 0, "wood": 100, "crystal": 60},
	"research": {"food": 100, "wood": 100, "crystal": 60}
}
const RESOURCE_NAMES := {"food": "穗粮", "wood": "枝材", "crystal": "岚晶"}
const RESOURCE_KINDS := {"tree": "wood", "berry": "food", "ore": "crystal"}

static func title(kind: String) -> String:
	if UNITS.has(kind):
		return UNITS[kind].name
	if BUILDINGS.has(kind):
		return BUILDINGS[kind].name
	return {"tree": "风铃木", "berry": "穗果丛", "ore": "岚晶矿"}.get(kind, kind)

static func cost_text(kind: String) -> String:
	var parts: PackedStringArray = []
	for key in ["food", "wood", "crystal"]:
		var value: int = COSTS.get(kind, {}).get(key, 0)
		if value > 0:
			parts.append("%s %d" % [RESOURCE_NAMES[key], value])
	return " · ".join(parts)
