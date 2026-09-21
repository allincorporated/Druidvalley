extends Node
## Shared state for DruidYard3D.

var player_name: String = ""
var warboard_visited: bool = false
var druid_talked: bool = false
var well_visited: bool = false
var geasa_accepted: bool = false
var well_defence_won: bool = false
## When true, next druid_yard load places the player near the World Tree.
var spawn_at_tree: bool = false
## Door / travel spine spawn id after change_scene.
var spawn_point: String = "default"
## Last area id (yard, tree, north_holy, coast, travel_road, hostel).
var last_area: String = ""

## --- General panel / RPG stubs ---
const BAG_SIZE: int = 12

var strength: int = 5
var agility: int = 5
var wisdom: int = 5
var hp: int = 10
var max_hp: int = 10

## Equipped item ids ("" = empty). Appearance mesh swaps = TODO later.
## Locked worn form: neck / arm_l / arm_r / cloak / weapon / side.
var gear_neck: String = "neck_chain"
var gear_arm_l: String = "heavy_armlet"
var gear_arm_r: String = "snake_armlet"
var gear_cloak: String = "cloak_travel"
var gear_weapon: String = "oak_stick"
var gear_side: String = "sgian_dubh"
## Legacy alias kept so older charm calls don't crash — unused in FunYard form.
var gear_charm: String = ""

## Up to BAG_SIZE item id strings; "" = empty slot.
var bag: Array = []

## id → { "name": String, "slot": neck|arm_l|arm_r|cloak|weapon|side|misc }
const ITEM_CATALOG: Dictionary = {
	"neck_chain": {"name": "Neck Chain", "slot": "neck"},
	"heavy_armlet": {"name": "Heavy Armlet", "slot": "arm_l"},
	"snake_armlet": {"name": "Snake Armlet", "slot": "arm_r"},
	"cloak_travel": {"name": "Travel Cloak", "slot": "cloak"},
	"oak_stick": {"name": "Oak Stick", "slot": "weapon"},
	"sgian_dubh": {"name": "Sgian Dubh", "slot": "side"},
	"herb_bundle": {"name": "Herb Bundle", "slot": "misc"},
	"water_skin": {"name": "Water Skin", "slot": "misc"},
	"charm_acorn": {"name": "Acorn Charm", "slot": "misc"},
}

func _ready() -> void:
	_ensure_bag()

func ensure_bag() -> void:
	_ensure_bag()

func _ensure_bag() -> void:
	if bag.is_empty():
		## Starter jewellery + arms are already worn; bag holds loose kit.
		bag = [
			"herb_bundle",
			"water_skin",
			"", "", "", "", "", "", "", "", "", "",
		]
	while bag.size() < BAG_SIZE:
		bag.append("")
	if bag.size() > BAG_SIZE:
		bag.resize(BAG_SIZE)

func display_name() -> String:
	var n := player_name.strip_edges()
	if n.is_empty():
		return "wanderer"
	return n

func item_display_name(item_id: String) -> String:
	if item_id.is_empty():
		return "—"
	if ITEM_CATALOG.has(item_id):
		var entry: Dictionary = ITEM_CATALOG[item_id]
		return str(entry.get("name", item_id))
	return item_id

func item_gear_slot(item_id: String) -> String:
	## Returns neck|arm_l|arm_r|cloak|weapon|side|"" .
	if item_id.is_empty() or not ITEM_CATALOG.has(item_id):
		return ""
	var entry: Dictionary = ITEM_CATALOG[item_id]
	var slot: String = str(entry.get("slot", ""))
	match slot:
		"neck", "arm_l", "arm_r", "cloak", "weapon", "side":
			return slot
		_:
			return ""

func sync_hp_from_player(player: Node) -> void:
	if player == null:
		return
	if "hp" in player:
		hp = int(player.get("hp"))
	if "max_hp" in player:
		max_hp = int(player.get("max_hp"))

func sync_hp_to_player(player: Node) -> void:
	if player == null:
		return
	if "max_hp" in player:
		player.set("max_hp", max_hp)
	if "hp" in player:
		player.set("hp", clampi(hp, 0, max_hp))

func loop_hint() -> String:
	## Short next-goal line for the General panel loop strip.
	if player_name.strip_edges().is_empty():
		return "Name yourself at the gate of the tale."
	if not druid_talked and not warboard_visited:
		return "Walk the yard — speak with the Druid or find the war-board."
	if not well_visited and not well_defence_won:
		return "Enter the World Tree — the well waits in the roots."
	if well_visited and not geasa_accepted and not well_defence_won:
		return "Hear the well's geasa — or stand the defence."
	if well_defence_won or geasa_accepted:
		if not warboard_visited:
			return "Command as General — visit the war-board house."
		return "The yard is known — Crossroads ahead, Glade left, Hostel right."
	if warboard_visited and not well_visited:
		return "Roots call — enter the World Tree portal."
	return "Explore doors: Crossroads · Glade · Hostel · Tree."

func equip_from_bag(slot_i: int) -> bool:
	## Equip bag[slot_i] into its gear slot; swap prior gear back into that bag index.
	_ensure_bag()
	if slot_i < 0 or slot_i >= bag.size():
		return false
	var item_id: String = str(bag[slot_i]).strip_edges()
	if item_id.is_empty():
		return false
	var gear_slot: String = item_gear_slot(item_id)
	if gear_slot.is_empty():
		return false  # misc / look-only leftovers stay in bag
	var previous: String = str(_get_gear(gear_slot))
	_set_gear(gear_slot, item_id)
	bag[slot_i] = previous
	# TODO: appearance mesh swap for weapon / charm / cloak when art is ready.
	return true

func equip_first_from_bag_for_slot(slot_name: String) -> bool:
	## Put the first bag item that fits this gear slot back on (re-equip after unequip).
	_ensure_bag()
	var key: String = slot_name.strip_edges().to_lower()
	if key.begins_with("gear_"):
		key = key.substr(5)
	match key:
		"neck", "arm_l", "arm_r", "cloak", "weapon", "side", "charm":
			pass
		_:
			return false
	if not _get_gear(key).is_empty():
		return false  # already wearing something
	var i: int = 0
	while i < bag.size():
		var item_id: String = str(bag[i])
		if not item_id.is_empty() and item_gear_slot(item_id) == key:
			return equip_from_bag(i)
		i += 1
	return false



## Aliases — older panel call sites / typos.
func try_equip_from_bag(slot_i: int) -> bool:
	return equip_from_bag(slot_i)

func unequip_to_bag(slot_name: String) -> bool:
	## Move a worn gear slot into the first empty bag slot.
	_ensure_bag()
	var key: String = slot_name.strip_edges().to_lower()
	if key.begins_with("gear_"):
		key = key.substr(5)
	match key:
		"neck", "arm_l", "arm_r", "cloak", "weapon", "side", "charm":
			pass
		_:
			return false
	var item_id: String = _get_gear(key)
	if item_id.is_empty():
		return false
	var empty_i: int = -1
	var i: int = 0
	while i < bag.size():
		if str(bag[i]).is_empty():
			empty_i = i
			break
		i += 1
	if empty_i < 0:
		return false
	bag[empty_i] = item_id
	_set_gear(key, "")
	# TODO: appearance mesh swap revert when art is ready.
	return true

func _get_gear(slot: String) -> String:
	match slot:
		"neck":
			return gear_neck
		"arm_l":
			return gear_arm_l
		"arm_r":
			return gear_arm_r
		"cloak":
			return gear_cloak
		"weapon":
			return gear_weapon
		"side":
			return gear_side
		"charm":
			return gear_charm
		_:
			return ""

func _set_gear(slot: String, item_id: String) -> void:
	match slot:
		"neck":
			gear_neck = item_id
		"arm_l":
			gear_arm_l = item_id
		"arm_r":
			gear_arm_r = item_id
		"cloak":
			gear_cloak = item_id
		"weapon":
			gear_weapon = item_id
		"side":
			gear_side = item_id
		"charm":
			gear_charm = item_id

func go_to(scene_path: String, spawn: String, from_area: String) -> void:
	spawn_point = spawn
	last_area = from_area
	if spawn == "from_tree":
		spawn_at_tree = true
	get_tree().change_scene_to_file(scene_path)

func take_spawn_point(default_id: String = "default") -> String:
	var s := spawn_point
	if s.is_empty():
		s = default_id
	spawn_point = "default"
	return s
