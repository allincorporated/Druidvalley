extends Control
## Pictish war-board — WARBOARD PLAY v2 + slight phone trim. 30×18 (~1/edge from 32×20), ~3 HP/figure.
## Maff pace override: once-per-unit/regiment activation (NOT 3-order budget). Both sides.
## Combat: each figure hits 1 foe in 8-adj (Champion priority, else lowest HP).
## Cav charge 2×; Archers no charge + auto-fire; Inf line-of-3 strips charge; Champion rail + unstoppable.
## Board: open mid rect — 4 corners + 4 side mid pillars + 2×2 oaks. Deploy Inf→Arch→Cav→Hero. No music.
## Pre-set armies (opp-wing cav); BOTH sides deploy extras 7 Inf · 4 Arch · 2 Cav · Champion+Apprentice (central mid-box).
## Reserves from T1 (+2I +2A +1C) each side: once/2 turns (cooldown only), spawn by General + shock.
## Oaks: NOT free pieces — shift a 2×2 oak in roam zone = FULL TURN (no prior acts; no further acts).
##   Timing LOCKED: oak turn = own druids OK; foe next = those druids IMMUNE; own next = DISABLED. Both sides.
## Moves: Inf double-advance; Cav free once/turn (3 steps); Druid Earth/Fire/Water/Holy; Champ file + front shove; Apprentice rear pin + inf chip.
## Symmetric rules: player == opposition. You ARE the General. Pictish framing.

const COLS := 30
const ROWS := 18
## Open mid rect interior (inside pillars at 11/17 × 5/11)
const MID_BOX_X0 := 12
const MID_BOX_X1 := 16
const MID_BOX_Y0 := 6
const MID_BOX_Y1 := 10
var CELL: float = 24.0  ## fitted from BoardHost size so grid fills play area
const AURA_R := 2  ## unused (no queen) — kept for binary compat
const MARGIN := 2.0
const MAX_HP := 3
const INF_HP := 3  ## ~3 HP per figure (locked)
const CHAMP_HP := 5  ## ~+50% over base 3
const APPRENTICE_HP := 2  ## Champ's apprentice stub bodyguard
const DRUID_HP := 6  ## double base HP (2× MAX_HP) — powers only, no auto-attack
const DRUID_CD_EFW := 1  ## Earth/Fire/Water cooldown turns after use
const DRUID_CD_HOLY := 5  ## Holy heal cooldown turns after use
const DRUID_RADIUS := 4  ## Earth/Fire/Water/Holy Chebyshev range (LOCKED)
const AUTO_FORWARD_STEPS := 2  ## unused units end-of-turn forward toward enemy
const CAVALRY_STEPS := 3  ## total steps per activation (opening step counts) — Maff nerf from 4

const RULES_TEXT := """WAR-BOARD — HOW TO PLAY

DEPLOY
• Pre-set armies already sit on the board. Place extras: Inf → Arch → Cav → Champion (+ Apprentice).
• Champion + Champ’s Apprentice deploy in the CENTRAL mid-box (open pillar rect). Enemy mirrors.

ACTIVATION
• Every unit / regiment may move or act once per turn (same both sides). End turn when done.
• Cavalry: free move once per turn (up to 3 steps) — still once per cav regiment.
• Idle units auto-forward up to 2 cells at end of turn (skip blocked; skipped after oak full turn).
• Call Reserve (cooldown 2 turns): spawn beside General + shock. No order budget.

OAKS / TREES
• Oaks are blockers, not free pieces. Shift a 2×2 oak 1 step ortho in its roam zone.
• Costs your FULL TURN (no units acted yet; no further acts after).
• Timing (both sides): oak turn = your druids still OK; foe’s next turn = their druids IMMUNE; your next turn = your druids DISABLED.

DRUID
• Four powers are your moves: Earth (trap), Fire (dmg), Water (shove), Holy (heal). Same both sides.
• No auto-attack / no board walk. Double HP. Power radius 4. Earth/Fire/Water CD 1; Holy CD 5.
• Once per druid / turn. Oak timing: oak turn OK; foe next = IMMUNE; own next = DISABLED.

CHAMPION
• File only (forward / back). Sidestep L/R only if forward is blocked by non-unit (edge / tower / oak / terrain). A unit ahead does NOT grant sidestep.
• Apprentice deploys diagonal back-left of Champion in mid-box (1-step; infantry-like melee chip).
• Team: Champ auto-shoves foes on the file in front; Apprentice catch/holds foes behind the pair (trap≥1). Same both sides.

COMBAT
• Figures auto-engage after moves / end turn. Same rules for you and the opposition.
• You ARE the General — protect yourself.

Enemy AI uses light heuristics (threaten General/Champion, purposeful advance) — it does not mirror your moves.
"""

const FIRE_DMG := 2
const HOLY_HEAL := 2

enum Phase { PLACE, PLACE_CHOICE, MOVE }
enum PType { GENERAL, QUEEN, DRUID, INFANTRY, ARCHER, CAVALRY, TOWER, ENEMY_INF, CHAMPION, OAK, APPRENTICE }

var _phase: Phase = Phase.PLACE
var _board: Array = []
var _selected: Vector2i = Vector2i(-1, -1)
## Once-per-unit economy (Maff pace). Oak = full-turn lock.
var _oak_turn_spent: bool = false
var _placements_done: int = 0
var _place_kind: String = ""
var _place_arch_rot: int = 0  ## 0..3 fixed L facing when placing archers
var _cavalry_steps_left: int = 0
var _cavalry_pos: Vector2i = Vector2i(-1, -1)
var _archer_aiming: bool = false

## Deploy pools AFTER pre-set (locked sheet)
var _pool_inf: int = 7   # Inf lines of 3
var _pool_arch: int = 4  # fixed L of 3
var _pool_cav: int = 2   # cavalry T of 4
var _pool_champ: int = 1 ## Champion — place in central mid-box (+ Apprentice)
var _fallen: bool = false
var _victorious: bool = false
var _enemy_acting: bool = false
## Selected regiment id ("" = solo piece / none). Whole formation moves together.
var _selected_reg: String = ""
var _next_reg_seq: int = 1
var _hit_flashes: Dictionary = {}  # Vector2i -> float remaining
var _turn_n: int = 1
var _reinforcements_done: bool = true  ## mid-game enemy reinforce demoted/off
var _player_reinforce_done: bool = true  ## deploy reinforce demoted — reserves from T1 instead
## Deploy stage lock: infantry → archers → cavalry → champion
var _deploy_stage: String = "infantry"
var _inf_pair_pending: Array = []  ## first of 2 Inf lines
## Turn economy: once-per-unit/regiment (cav free once/turn, multi-step OK)
var _moved_ids: Dictionary = {}  # id -> true (acted/moved this player turn)
var _enemy_acted_ids: Dictionary = {}  # enemy actor keys acted this enemy turn
var _cav_free_used: Dictionary = {}  # cav id -> true (used free activation this turn)

## Terrain: impassable walls / oaks; archer-only gap cells
var _walls: Dictionary = {}       # Vector2i -> true (impassable empty terrain)
var _archer_gaps: Dictionary = {} # Vector2i -> true (only archers may enter)
## Reserves (available from turn 1)
var _reserve_inf: int = 2
var _reserve_arch: int = 2
var _reserve_cav: int = 1
var _reserve_cooldown: int = 0  ## turns until next call allowed (0 = ready)
## Enemy mirrors the same deploy pools + reserves (parity — no enemy-only shortcuts).
var _enemy_pool_inf: int = 7
var _enemy_pool_arch: int = 4
var _enemy_pool_cav: int = 2
var _enemy_pool_champ: int = 1
var _enemy_reserve_inf: int = 2
var _enemy_reserve_arch: int = 2
var _enemy_reserve_cav: int = 1
var _enemy_reserve_cooldown: int = 0
## Oak shift: FULL TURN; both sides; roam zone.
## Timing LOCKED (same both sides): oak turn = druids still OK; opponent turn = druids IMMUNE;
##   your NEXT turn = druids DISABLED (skip acting). Then normal.
var _oak_shifting: bool = false
var _druid_immune_friend: bool = false
var _druid_immune_enemy: bool = false
var _druid_skip_friend: bool = false
var _druid_skip_enemy: bool = false
## 0=none · 1=immune on opponent's next turn · 2=skip on own next turn
var _oak_follow_friend: int = 0
var _oak_follow_enemy: int = 0
var _btn_rules: Button
var _rules_panel: Control
var _rules_visible: bool = false
static var _rules_auto_shown: bool = false
## Charge tracking: cav ids that moved this activation (for 2× charge dmg)
var _charge_ids: Dictionary = {}  # id -> true
## Champ stepped-toward-enemy this activation (rail of terror)
var _champ_rail_from: Vector2i = Vector2i(-1, -1)
var _champ_rail_to: Vector2i = Vector2i(-1, -1)

@onready var _board_host: Control = $BoardFrame/BoardHost
@onready var _status: Label = $TopBar/Status
@onready var _obj: Label = $TopBar/Objective
@onready var _place_panel: VBoxContainer = $SidePanel/PlacePanel
@onready var _move_panel: VBoxContainer = $SidePanel/MovePanel
@onready var _choice_panel: VBoxContainer = $SidePanel/ChoicePanel
@onready var _druid_panel: VBoxContainer = $SidePanel/DruidPanel
@onready var _toast: Label = $Toast

var _cells: Array = []
var _highlights: Dictionary = {}  # Vector2i -> "move"|"capture"|"place"|"aura"
var _toast_t: float = 0.0
## During place: map of anchor cell -> Array[Vector2i] footprint
var _place_options: Dictionary = {}

func _ready() -> void:
	Music.play_area("chess")
	_init_board()
	_preplace()
	_wire_ui()
	_hide_druid_panel()  # powers only when a Druid is selected
	_set_phase_place()
	# Fit grid after layout so BoardHost has a real size (fills play area).
	await get_tree().process_frame
	_build_grid()
	_refresh()
	_show_toast("Pre-set armies ready — Deploy Inf→Arch→Cav→Champion+Apprentice (mid-box). Druid powers on select.", 3.5)
	if not _rules_auto_shown:
		_rules_auto_shown = true
		call_deferred("_toggle_rules")

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0 and _toast:
			_toast.visible = false
	var need_ref := false
	var drop: Array = []
	for k in _hit_flashes.keys():
		_hit_flashes[k] = float(_hit_flashes[k]) - delta
		if float(_hit_flashes[k]) <= 0.0:
			drop.append(k)
		need_ref = true
	for k in drop:
		_hit_flashes.erase(k)
	if need_ref and drop:
		_refresh()

func _show_toast(msg: String, dur: float = 2.2) -> void:
	if _toast:
		_toast.text = msg
		_toast.visible = true
	_toast_t = dur

func _general_pos() -> Vector2i:
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p != null and int(p["type"]) == PType.GENERAL and bool(p["friend"]):
				return Vector2i(c, r)
	return Vector2i(-1, -1)

func _general_alive() -> bool:
	var g := _general_pos()
	if g.x < 0:
		return false
	var p = _piece_at(g)
	return p != null and int(p.get("hp", 0)) > 0

func _match_locked() -> bool:
	return _fallen or _victorious

func _enemy_general_alive() -> bool:
	var g := _enemy_general_pos()
	if g.x < 0:
		return false
	var p = _piece_at(g)
	return p != null and int(p.get("hp", 0)) > 0

func _end_match_ui(win: bool) -> void:
	_clear_selection()
	_cavalry_steps_left = 0
	_highlights.clear()
	_oak_shifting = false
	_enemy_acting = true  # freeze further turns / AI
	if _place_panel:
		_place_panel.visible = false
	if _choice_panel:
		_choice_panel.visible = false
	if _move_panel:
		_move_panel.visible = false
	_hide_druid_panel()
	if win:
		_obj.text = "Victory — the enemy General has fallen"
		_status.text = "Victory — returning to the yard…"
		_show_toast("Victory! Enemy General fallen.", 4.5)
	else:
		_obj.text = "You are the General — you have fallen"
		_status.text = "Defeat — the field is lost without you"
		_show_toast("Defeat — returning to the yard…", 4.5)
	_refresh()
	_return_to_yard_after_match()

func _return_to_yard_after_match() -> void:
	## Async return so toast/UI can show; safe if scene exits mid-await.
	await get_tree().create_timer(2.2).timeout
	if not is_inside_tree():
		return
	_on_back()

func _trigger_fallen() -> void:
	if _match_locked():
		return
	_fallen = true
	_end_match_ui(false)

func _trigger_victory() -> void:
	if _match_locked():
		return
	_victorious = true
	_end_match_ui(true)

func _check_defeat() -> void:
	if _match_locked():
		return
	if not _general_alive():
		_trigger_fallen()

func _check_victory() -> void:
	if _match_locked():
		return
	if not _enemy_general_alive():
		_trigger_victory()

func _check_match_end() -> void:
	_check_defeat()
	_check_victory()

func _mk(ptype: int, friend: bool, hp: int = -1, reg_id: String = "", orient: String = "") -> Dictionary:
	var max_hp := INF_HP if ptype == PType.INFANTRY or ptype == PType.ENEMY_INF else MAX_HP
	if ptype == PType.CHAMPION:
		max_hp = CHAMP_HP
	elif ptype == PType.APPRENTICE:
		max_hp = APPRENTICE_HP
	elif ptype == PType.DRUID:
		max_hp = DRUID_HP
	if hp < 0:
		hp = max_hp
	return {
		"type": ptype,
		"friend": friend,
		"id": str(randi()),
		"hp": hp,
		"max_hp": max_hp,
		"regiment_id": reg_id,
		"orient": orient,
		"trap": 0,  # Earth / surround-pin: turns remaining trapped (can't move)
		"colour_buff": 0,
		# Per-power cooldowns (turns remaining). Earth/Fire/Water = 1; Holy = 5.
		"cd_earth": 0,
		"cd_fire": 0,
		"cd_water": 0,
		"cd_holy": 0,
	}

func _hp_pips(hp: int, max_hp: int = MAX_HP) -> String:
	## Compact pips for higher HP budgets.
	var m := clampi(max_hp, 1, 8)
	var n := clampi(hp, 0, m)
	var s := ""
	for i in range(m):
		s += "●" if i < n else "○"
	return s

func _piece_max_hp(p) -> int:
	if p == null:
		return MAX_HP
	return int(p.get("max_hp", MAX_HP))

func _flash_hit(pos: Vector2i, strong: bool = false) -> void:
	_hit_flashes[pos] = 0.55 if strong else 0.35

func _new_reg_id() -> String:
	var rid := "R%d" % _next_reg_seq
	_next_reg_seq += 1
	return rid

func _reg_id_of(piece) -> String:
	if piece == null:
		return ""
	return str(piece.get("regiment_id", ""))

func _regiment_cells(reg_id: String) -> Array:
	var out: Array = []
	if reg_id == "":
		return out
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p != null and str(p.get("regiment_id", "")) == reg_id:
				out.append(Vector2i(c, r))
	return out

func _regiment_orient(reg_id: String) -> String:
	for pos in _regiment_cells(reg_id):
		var p = _piece_at(pos)
		if p != null:
			return str(p.get("orient", ""))
	return ""

func _is_regiment_piece(piece) -> bool:
	return piece != null and _reg_id_of(piece) != ""

func _clear_selection() -> void:
	_selected = Vector2i(-1, -1)
	_selected_reg = ""
	_archer_aiming = false
	_oak_shifting = false
	_hide_druid_panel()

func _init_board() -> void:
	_board.clear()
	for r in range(ROWS):
		var row: Array = []
		for c in range(COLS):
			row.append(null)
		_board.append(row)

func _preplace() -> void:
	## Board blockers + pre-set armies (no queen, no champion). Deploy pools for extras.
	_build_board_blockers()
	_preplace_player_army()
	_deploy_enemy_army()

func _place_regiment(cells: Array, ptype: int, friend: bool, orient: String) -> void:
	var rid := _new_reg_id()
	for pos in cells:
		var p: Vector2i = pos
		if p.x < 0 or p.x >= COLS or p.y < 0 or p.y >= ROWS:
			continue
		_board[p.y][p.x] = _mk(ptype, friend, -1, rid, orient)


func _build_board_blockers() -> void:
	## OPEN mid rectangle: 4 corner pillars + midpoint pillar on each side (no wall ring).
	## Oaks on halfway L/R as 2×2 clumps (regiment ids) — shift costs full turn.
	_walls.clear()
	_archer_gaps.clear()
	# Mid rect: 32×20 was 12..18 / 6..12; slight trim (−1/edge) → 11..17 / 5..11 on 30×18
	var pillars := [
		Vector2i(11, 5), Vector2i(17, 5), Vector2i(11, 11), Vector2i(17, 11),  # corners
		Vector2i(14, 5), Vector2i(14, 11),  # top / bottom mid
		Vector2i(11, 8), Vector2i(17, 8),  # left / right mid
	]
	for p in pillars:
		_board[p.y][p.x] = _mk(PType.TOWER, false)
	# 2×2 oaks halfway L/R (was cols 2–3 & 28–29 / rows 9–10 → −1)
	_place_oak_clump([Vector2i(1, 8), Vector2i(2, 8), Vector2i(1, 9), Vector2i(2, 9)])
	_place_oak_clump([Vector2i(COLS - 3, 8), Vector2i(COLS - 2, 8), Vector2i(COLS - 3, 9), Vector2i(COLS - 2, 9)])

func _place_oak_clump(cells: Array) -> void:
	var rid := _new_reg_id()
	for pos in cells:
		var p: Vector2i = pos
		if p.x < 0 or p.x >= COLS or p.y < 0 or p.y >= ROWS:
			continue
		_board[p.y][p.x] = _mk(PType.OAK, false, -1, rid, "OAK")

func _preplace_player_army() -> void:
	## G LEFT, Cav RIGHT. All Cav T stem toward enemy (higher row). Druids after archers.
	var gx := 4
	_board[0][gx] = _mk(PType.GENERAL, true)
	# Extra Cav @ old queen — same facing as right-wing (base row 0, stem row 1)
	_place_regiment([Vector2i(gx + 1, 0), Vector2i(gx + 2, 0), Vector2i(gx + 3, 0), Vector2i(gx + 2, 1)], PType.CAVALRY, true, "T")
	_place_regiment([Vector2i(8, 2), Vector2i(9, 2), Vector2i(10, 2)], PType.INFANTRY, true, "H")
	_place_regiment([Vector2i(14, 2), Vector2i(15, 2), Vector2i(16, 2)], PType.INFANTRY, true, "H")
	_place_regiment([Vector2i(20, 3), Vector2i(21, 3), Vector2i(22, 3)], PType.INFANTRY, true, "H")
	_place_regiment([Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)], PType.INFANTRY, true, "H")
	_place_regiment([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], PType.ARCHER, true, "L")
	_place_regiment([Vector2i(COLS - 2, 0), Vector2i(COLS - 1, 0), Vector2i(COLS - 1, 1)], PType.ARCHER, true, "L")
	_place_regiment([Vector2i(12, 0), Vector2i(13, 0), Vector2i(12, 1)], PType.ARCHER, true, "L")
	_place_regiment([Vector2i(COLS - 7, 0), Vector2i(COLS - 6, 0), Vector2i(COLS - 5, 0), Vector2i(COLS - 6, 1)], PType.CAVALRY, true, "T")
	_seat_druid_pair(true)


func _seat_druid_pair(friend: bool) -> void:
	## One LEFT-wing + one RIGHT-wing druid on back row. Never overwrite / same half / adjacent.
	## Left half: cols 0 .. mid-1; right: mid .. COLS-1. Prefer ~COLS/4 and ~3*COLS/4.
	var row := 0 if friend else (ROWS - 1)
	var mid := int(COLS / 2.0)
	var left_pref := int(COLS / 4.0)
	var right_pref := int((3.0 * COLS) / 4.0)
	var left_col := _seat_druid_in_half(row, friend, 0, mid - 1, left_pref, [])
	var avoid: Array = []
	if left_col >= 0:
		avoid.append(left_col)
	_seat_druid_in_half(row, friend, mid, COLS - 1, right_pref, avoid)


func _seat_druid_in_half(row: int, friend: bool, lo: int, hi: int, prefer: int, avoid_adj: Array) -> int:
	## First empty near prefer within [lo, hi], never overwrite, never adjacent to avoid_adj.
	if lo > hi:
		return -1
	var pref := clampi(prefer, lo, hi)
	var order: Array = [pref]
	for dist in range(1, hi - lo + 2):
		var a := pref - dist
		var b := pref + dist
		if a >= lo and a <= hi:
			order.append(a)
		if b >= lo and b <= hi:
			order.append(b)
	for c in order:
		if _board[row][c] != null:
			continue
		var adj := false
		for other in avoid_adj:
			if absi(int(c) - int(other)) <= 1:
				adj = true
				break
		if adj:
			continue
		_board[row][c] = _mk(PType.DRUID, friend)
		return int(c)
	# Fallback: any empty in half (still respect adjacency if possible)
	for c2 in range(lo, hi + 1):
		if _board[row][c2] != null:
			continue
		var adj2 := false
		for other2 in avoid_adj:
			if absi(int(c2) - int(other2)) <= 1:
				adj2 = true
				break
		if adj2:
			continue
		_board[row][c2] = _mk(PType.DRUID, friend)
		return int(c2)
	# Last resort: empty in half even if adjacent (never overwrite)
	for c3 in range(lo, hi + 1):
		if _board[row][c3] != null:
			continue
		_board[row][c3] = _mk(PType.DRUID, friend)
		return int(c3)
	return -1

func _is_blocker_type(t: int) -> bool:
	return t == PType.TOWER or t == PType.OAK

func _terrain_blocks(pos: Vector2i, mover_type: int = -1) -> bool:
	## True if pos cannot be entered by mover_type (-1 = any non-archer).
	if _walls.has(pos):
		return true
	if _archer_gaps.has(pos):
		return mover_type != PType.ARCHER
	var p = _piece_at(pos)
	if p != null and _is_blocker_type(int(p["type"])):
		return true
	return false

func _cell_passable_for(pos: Vector2i, mover_type: int, occupied_ok: Dictionary = {}) -> bool:
	if pos.x < 0 or pos.x >= COLS or pos.y < 0 or pos.y >= ROWS:
		return false
	if _terrain_blocks(pos, mover_type):
		return false
	var dest = _piece_at(pos)
	if dest != null and not occupied_ok.has(pos):
		return false
	return true

func _deploy_enemy_army() -> void:
	## G RIGHT, Cav LEFT. All Cav T stem toward player (lower row).
	var er := ROWS - 1
	var egx := COLS - 5
	_board[er][egx] = _mk(PType.GENERAL, false)
	_place_regiment([Vector2i(egx - 3, er), Vector2i(egx - 2, er), Vector2i(egx - 1, er), Vector2i(egx - 2, er - 1)], PType.CAVALRY, false, "T")
	_place_regiment([Vector2i(3, er - 3), Vector2i(4, er - 3), Vector2i(5, er - 3)], PType.INFANTRY, false, "H")
	_place_regiment([Vector2i(20, er - 3), Vector2i(21, er - 3), Vector2i(22, er - 3)], PType.INFANTRY, false, "H")
	_place_regiment([Vector2i(10, er - 5), Vector2i(11, er - 5), Vector2i(12, er - 5)], PType.INFANTRY, false, "H")
	_place_regiment([Vector2i(15, er - 5), Vector2i(16, er - 5), Vector2i(17, er - 5)], PType.INFANTRY, false, "H")
	_place_regiment([Vector2i(0, er), Vector2i(1, er), Vector2i(0, er - 1)], PType.ARCHER, false, "L")
	_place_regiment([Vector2i(COLS - 2, er), Vector2i(COLS - 1, er), Vector2i(COLS - 1, er - 1)], PType.ARCHER, false, "L")
	_place_regiment([Vector2i(8, er - 2), Vector2i(9, er - 2), Vector2i(8, er - 3)], PType.ARCHER, false, "L")
	_place_regiment([Vector2i(4, er), Vector2i(5, er), Vector2i(6, er), Vector2i(5, er - 1)], PType.CAVALRY, false, "T")
	_seat_druid_pair(false)

func _ptype_letter(t: int) -> String:
	match t:
		PType.GENERAL: return "G"
		PType.QUEEN: return "Q"
		PType.DRUID: return "D"
		PType.INFANTRY: return "I"
		PType.ARCHER: return "A"
		PType.CAVALRY: return "C"
		PType.TOWER: return ""
		PType.ENEMY_INF: return "e"
		PType.CHAMPION: return "H"
		PType.OAK: return ""
		PType.APPRENTICE: return "a"
	return "?"

func _ptype_name(t: int) -> String:
	match t:
		PType.GENERAL: return "General"
		PType.QUEEN: return "Queen"
		PType.DRUID: return "Druid"
		PType.INFANTRY: return "Infantry"
		PType.ARCHER: return "Archer"
		PType.CAVALRY: return "Cavalry"
		PType.TOWER: return "Pillar"
		PType.ENEMY_INF: return "Enemy"
		PType.CHAMPION: return "Champion"
		PType.OAK: return "Oak"
		PType.APPRENTICE: return "Champ's Apprentice"
	return "?"

func _token_color(t: int, friend: bool) -> Color:
	if t == PType.TOWER:
		return Color(0.48, 0.50, 0.54)
	if t == PType.OAK:
		return Color(0.22, 0.42, 0.18)
	if not friend:
		match t:
			PType.GENERAL: return Color(0.72, 0.12, 0.10)
			PType.QUEEN: return Color(0.55, 0.12, 0.55)
			PType.DRUID: return Color(0.55, 0.35, 0.12)
			PType.INFANTRY, PType.ENEMY_INF: return Color(0.78, 0.18, 0.16)
			PType.ARCHER: return Color(0.82, 0.28, 0.22)
			PType.CAVALRY: return Color(0.88, 0.32, 0.12)
			PType.CHAMPION: return Color(0.55, 0.05, 0.08)
			PType.APPRENTICE: return Color(0.62, 0.22, 0.18)
			_:
				return Color(0.75, 0.20, 0.18)
	match t:
		PType.GENERAL: return Color(0.95, 0.78, 0.18)
		PType.QUEEN: return Color(0.62, 0.28, 0.88)
		PType.DRUID: return Color(0.22, 0.72, 0.38)
		PType.INFANTRY: return Color(0.28, 0.48, 0.82)
		PType.ARCHER: return Color(0.18, 0.72, 0.72)
		PType.CAVALRY: return Color(0.92, 0.48, 0.18)
		PType.CHAMPION: return Color(0.95, 0.55, 0.12)
		PType.APPRENTICE: return Color(0.85, 0.62, 0.28)
		PType.ENEMY_INF: return Color(0.78, 0.18, 0.16)
	return Color(0.5, 0.5, 0.5)

func _token_shape(t: int) -> String:
	match t:
		PType.GENERAL, PType.QUEEN, PType.DRUID, PType.ENEMY_INF, PType.CHAMPION, PType.APPRENTICE:
			return "circle"
		PType.INFANTRY:
			return "square"
		PType.ARCHER:
			return "diamond"
		PType.CAVALRY:
			return "oval"
		PType.TOWER, PType.OAK:
			return "block"
	return "circle"

func _cell_base_color(r: int, c: int) -> Color:
	var dark := ((r + c) % 2) == 0
	if dark:
		return Color(0.58, 0.40, 0.26)
	return Color(0.90, 0.82, 0.66)

func _fit_cell_to_host() -> void:
	## Scale CELL so COLS×ROWS uses nearly the whole BoardHost (less dead frame).
	var sz: Vector2 = _board_host.size
	if sz.x < 32.0 or sz.y < 32.0:
		var parent := _board_host.get_parent() as Control
		if parent:
			sz = parent.size - Vector2(8, 8)
	if sz.x < 32.0 or sz.y < 32.0:
		sz = Vector2(float(COLS) * 24.0 + MARGIN * 2.0, float(ROWS) * 24.0 + MARGIN * 2.0)
	var cw := (sz.x - MARGIN * 2.0) / float(COLS)
	var ch := (sz.y - MARGIN * 2.0) / float(ROWS)
	CELL = floorf(mini(cw, ch) * 10.0) / 10.0
	if CELL < 14.0:
		CELL = 14.0

func _build_grid() -> void:
	_cells.clear()
	for child in _board_host.get_children():
		child.queue_free()
	_fit_cell_to_host()
	# Centre the grid inside the host if aspect leaves a thin strip
	var board_w := COLS * CELL + MARGIN * 2.0
	var board_h := ROWS * CELL + MARGIN * 2.0
	var ox := maxf(0.0, (_board_host.size.x - board_w) * 0.5)
	var oy := maxf(0.0, (_board_host.size.y - board_h) * 0.5)
	for r in range(ROWS):
		var row_cells: Array = []
		var draw_r := (ROWS - 1) - r
		for c in range(COLS):
			var cell := _make_cell(r, c, draw_r)
			cell.position = Vector2(ox + MARGIN + c * CELL, oy + MARGIN + draw_r * CELL)
			_board_host.add_child(cell)
			row_cells.append(cell)
		_cells.append(row_cells)

func _make_cell(r: int, c: int, draw_r: int) -> Control:
	var root := Control.new()
	root.name = "Cell_%d_%d" % [r, c]
	root.custom_minimum_size = Vector2(CELL, CELL)
	root.size = Vector2(CELL, CELL)
	root.position = Vector2(MARGIN + c * CELL, MARGIN + draw_r * CELL)
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = _cell_base_color(r, c)
	root.add_child(bg)

	var hl := ColorRect.new()
	hl.name = "Highlight"
	hl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hl.color = Color(0, 0, 0, 0)
	root.add_child(hl)

	var token := Panel.new()
	token.name = "Token"
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	token.visible = false
	token.set_anchors_preset(Control.PRESET_CENTER)
	var hs := CELL * 0.5
	token.offset_left = -hs
	token.offset_top = -hs
	token.offset_right = hs
	token.offset_bottom = hs
	root.add_child(token)

	var letter := Label.new()
	letter.name = "Letter"
	letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", maxi(9, int(CELL * 0.42)))
	letter.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04))
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	token.add_child(letter)

	var hp_lab := Label.new()
	hp_lab.name = "HpLabel"
	# Per-figure HP pips (●●●) — each regiment member tracks its own MAX_HP
	hp_lab.position = Vector2(1, CELL - 15)
	hp_lab.size = Vector2(CELL - 2, 14)
	hp_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_lab.add_theme_font_size_override("font_size", 9)
	hp_lab.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	hp_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_lab.visible = false
	root.add_child(hp_lab)

	var btn := Button.new()
	btn.name = "Hit"
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var rr := r
	var cc := c
	btn.pressed.connect(func() -> void: _on_cell(rr, cc))
	root.add_child(btn)

	return root

func _style_token(token: Panel, t: int, friend: bool) -> void:
	var sb := StyleBoxFlat.new()
	var col := _token_color(t, friend)
	sb.bg_color = col
	# Fat team rings (cheap visual lock)
	var ring := Color(0.25, 0.55, 0.95) if friend else Color(0.90, 0.20, 0.18)
	if t == PType.TOWER or t == PType.OAK:
		ring = col.darkened(0.35)
		sb.set_border_width_all(2)
	else:
		sb.set_border_width_all(4)  # fat ring
	sb.border_color = ring
	var shape := _token_shape(t)
	match shape:
		"circle":
			sb.set_corner_radius_all(int(CELL * 0.5))
			token.offset_left = -CELL * 0.48
			token.offset_top = -CELL * 0.48
			token.offset_right = CELL * 0.48
			token.offset_bottom = CELL * 0.48
		"square":
			sb.set_corner_radius_all(3)
			token.offset_left = -CELL * 0.44
			token.offset_top = -CELL * 0.44
			token.offset_right = CELL * 0.44
			token.offset_bottom = CELL * 0.44
		"diamond":
			sb.set_corner_radius_all(4)
			token.offset_left = -CELL * 0.38
			token.offset_top = -CELL * 0.48
			token.offset_right = CELL * 0.38
			token.offset_bottom = CELL * 0.48
		"oval":
			sb.set_corner_radius_all(int(CELL * 0.4))
			token.offset_left = -CELL * 0.52
			token.offset_top = -CELL * 0.38
			token.offset_right = CELL * 0.52
			token.offset_bottom = CELL * 0.38
		"block":
			sb.set_corner_radius_all(2)
			if t == PType.OAK:
				sb.bg_color = Color(0.22, 0.42, 0.18)
				sb.border_color = Color(0.12, 0.28, 0.10)
			else:
				sb.bg_color = Color(0.45, 0.47, 0.50)
				sb.border_color = Color(0.28, 0.30, 0.32)
			sb.set_border_width_all(2)
			token.offset_left = -CELL * 0.58
			token.offset_top = -CELL * 0.58
			token.offset_right = CELL * 0.58
			token.offset_bottom = CELL * 0.58
	if t == PType.GENERAL and friend:
		sb.set_border_width_all(4)
		sb.border_color = Color(1.0, 0.92, 0.35)
		sb.bg_color = Color(0.95, 0.78, 0.18)
	if t == PType.CHAMPION:
		sb.set_border_width_all(5)
		sb.border_color = Color(1.0, 0.75, 0.20) if friend else Color(0.85, 0.10, 0.10)
	elif t == PType.APPRENTICE:
		sb.set_border_width_all(3)
		sb.border_color = Color(0.95, 0.80, 0.35) if friend else Color(0.75, 0.25, 0.20)
	token.add_theme_stylebox_override("panel", sb)
	token.visible = true
	var letter: Label = token.get_node("Letter")
	letter.text = _ptype_letter(t)
	if t == PType.TOWER:
		letter.text = "■"
		letter.add_theme_color_override("font_color", Color(0.85, 0.86, 0.88))
	elif t == PType.OAK:
		letter.text = "♣"
		letter.add_theme_color_override("font_color", Color(0.85, 0.95, 0.70))
	elif t == PType.CHAMPION:
		letter.add_theme_color_override("font_color", Color(0.12, 0.06, 0.02) if friend else Color(1, 0.9, 0.85))
	elif t == PType.GENERAL:
		letter.add_theme_color_override("font_color", Color(0.18, 0.10, 0.02))
	elif not friend and t != PType.TOWER:
		letter.add_theme_color_override("font_color", Color(1, 0.92, 0.90))
	else:
		letter.add_theme_color_override("font_color", Color(0.06, 0.05, 0.04))

func _wire_ui() -> void:
	$SidePanel/PlacePanel/BtnInf.pressed.connect(func() -> void: _pick_place("infantry"))
	$SidePanel/PlacePanel/BtnArch.pressed.connect(func() -> void: _pick_place("archer"))
	$SidePanel/PlacePanel/BtnCav.pressed.connect(func() -> void: _pick_place("cavalry"))
	# Champion button (created if missing)
	var btn_champ := $SidePanel/PlacePanel.get_node_or_null("BtnChamp") as Button
	if btn_champ == null:
		btn_champ = Button.new()
		btn_champ.name = "BtnChamp"
		btn_champ.text = "Champion (mid-box)"
		btn_champ.custom_minimum_size = Vector2(0, 42)
		var cav_i := $SidePanel/PlacePanel/BtnCav.get_index()
		$SidePanel/PlacePanel.add_child(btn_champ)
		$SidePanel/PlacePanel.move_child(btn_champ, cav_i + 1)
	if not btn_champ.pressed.is_connected(_on_pick_champ):
		btn_champ.pressed.connect(_on_pick_champ)
	var btn_cancel := $SidePanel/PlacePanel.get_node_or_null("BtnCancel") as Button
	if btn_cancel:
		if not btn_cancel.pressed.is_connected(_cancel_place):
			btn_cancel.pressed.connect(_cancel_place)
	else:
		push_warning("Chess PlacePanel missing BtnCancel — soft-lock Cancel unavailable")
	var btn_start_place := $SidePanel/PlacePanel.get_node_or_null("BtnStartFromPlace") as Button
	if btn_start_place:
		if not btn_start_place.pressed.is_connected(_on_start_moving):
			btn_start_place.pressed.connect(_on_start_moving)
	else:
		push_warning("Chess PlacePanel missing BtnStartFromPlace — Begin manoeuvres from place unavailable")
	$SidePanel/ChoicePanel/BtnKeep.pressed.connect(_on_keep_placing)
	$SidePanel/ChoicePanel/BtnStart.pressed.connect(_on_start_moving)
	$SidePanel/MovePanel/BtnEndTurn.pressed.connect(_on_end_turn)
	# Call Reserve button on move panel
	var btn_res := $SidePanel/MovePanel.get_node_or_null("BtnCallReserve") as Button
	if btn_res == null:
		btn_res = Button.new()
		btn_res.name = "BtnCallReserve"
		btn_res.text = "Call Reserve"
		btn_res.custom_minimum_size = Vector2(0, 40)
		$SidePanel/MovePanel.add_child(btn_res)
		var end_i0 := $SidePanel/MovePanel.get_node("BtnEndTurn").get_index()
		$SidePanel/MovePanel.move_child(btn_res, end_i0)
	if not btn_res.pressed.is_connected(_on_call_reserve):
		btn_res.pressed.connect(_on_call_reserve)
	var btn_cancel_cav := $SidePanel/MovePanel.get_node_or_null("BtnCancelCav") as Button
	if btn_cancel_cav == null:
		btn_cancel_cav = Button.new()
		btn_cancel_cav.name = "BtnCancelCav"
		btn_cancel_cav.text = "Cancel cavalry"
		btn_cancel_cav.custom_minimum_size = Vector2(0, 40)
		btn_cancel_cav.visible = false
		$SidePanel/MovePanel.add_child(btn_cancel_cav)
		var end_i := $SidePanel/MovePanel.get_node("BtnEndTurn").get_index()
		$SidePanel/MovePanel.move_child(btn_cancel_cav, end_i)
	if not btn_cancel_cav.pressed.is_connected(_cancel_cavalry):
		btn_cancel_cav.pressed.connect(_cancel_cavalry)
	_ensure_druid_panel()
	$TopBar/BackBtn.pressed.connect(_on_back)
	# Rules / How-to overlay (light instructions)
	var btn_rules := get_node_or_null("TopBar/BtnRules") as Button
	if btn_rules == null:
		btn_rules = Button.new()
		btn_rules.name = "BtnRules"
		btn_rules.focus_mode = Control.FOCUS_NONE
		btn_rules.text = "Help / Rules"
		btn_rules.add_theme_font_size_override("font_size", 14)
		btn_rules.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		btn_rules.anchor_left = 1.0
		btn_rules.anchor_right = 1.0
		btn_rules.offset_left = -248.0
		btn_rules.offset_right = -128.0
		btn_rules.offset_top = 6.0
		btn_rules.offset_bottom = 48.0
		$TopBar.add_child(btn_rules)
	_btn_rules = btn_rules
	if not _btn_rules.pressed.is_connected(_toggle_rules):
		_btn_rules.pressed.connect(_toggle_rules)
	_build_rules_panel()




func _ensure_druid_panel() -> void:
	## Phone-safe: guarantee DruidPanel + four ability buttons exist and sit on top of SidePanel.
	var side := $SidePanel as Control
	if side == null:
		return
	var panel := side.get_node_or_null("DruidPanel") as VBoxContainer
	if panel == null:
		panel = VBoxContainer.new()
		panel.name = "DruidPanel"
		side.add_child(panel)
	_druid_panel = panel
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Bottom stack, full SidePanel width — drawn above MovePanel (last child).
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 8.0
	panel.offset_right = -8.0
	panel.offset_top = -280.0
	panel.offset_bottom = -8.0
	panel.add_theme_constant_override("separation", 8)
	# Keep on top for taps
	side.move_child(panel, side.get_child_count() - 1)
	var title := panel.get_node_or_null("DruidTitle") as Label
	if title == null:
		title = Label.new()
		title.name = "DruidTitle"
		panel.add_child(title)
		panel.move_child(title, 0)
	title.text = "DRUID — tap a power"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.55, 0.92, 0.62))
	title.add_theme_font_size_override("font_size", 16)
	var specs := [
		{"name": "BtnEarth", "text": "Earth — trap r4", "kind": "earth"},
		{"name": "BtnFire", "text": "Fire — scorch r4", "kind": "fire"},
		{"name": "BtnWater", "text": "Water — shove r4", "kind": "water"},
		{"name": "BtnHoly", "text": "Holy — heal r4", "kind": "holy"},
	]
	for spec in specs:
		var btn := panel.get_node_or_null(str(spec["name"])) as Button
		if btn == null:
			btn = Button.new()
			btn.name = str(spec["name"])
			panel.add_child(btn)
		btn.text = str(spec["text"])
		btn.custom_minimum_size = Vector2(0, 48)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 15)
		btn.visible = true
		# Rebind cleanly
		for c in btn.pressed.get_connections():
			btn.pressed.disconnect(c["callable"])
		var kind: String = str(spec["kind"])
		btn.pressed.connect(func() -> void: _druid_ability(kind))


func _show_druid_panel() -> void:
	_ensure_druid_panel()
	if _druid_panel == null:
		return
	_druid_panel.visible = true
	# Raise above MovePanel every show (phone taps)
	var side := $SidePanel as Control
	if side and _druid_panel.get_parent() == side:
		side.move_child(_druid_panel, side.get_child_count() - 1)
	_refresh_druid_button_labels()


func _refresh_druid_button_labels() -> void:
	if _druid_panel == null:
		return
	var dp = _piece_at(_selected) if _selected.x >= 0 else null
	if dp == null or int(dp.get("type", -1)) != PType.DRUID:
		dp = null
	var specs := [
		{"name": "BtnEarth", "label": "Earth — trap r4", "key": "cd_earth"},
		{"name": "BtnFire", "label": "Fire — scorch r4", "key": "cd_fire"},
		{"name": "BtnWater", "label": "Water — shove r4", "key": "cd_water"},
		{"name": "BtnHoly", "label": "Holy — heal r4", "key": "cd_holy"},
	]
	for spec in specs:
		var btn := _druid_panel.get_node_or_null(str(spec["name"])) as Button
		if btn == null:
			continue
		var cd := int(dp.get(str(spec["key"]), 0)) if dp else 0
		if cd > 0:
			btn.text = "%s (CD %d)" % [spec["label"], cd]
			btn.disabled = true
		else:
			btn.text = str(spec["label"])
			btn.disabled = false


func _hide_druid_panel() -> void:
	if _druid_panel:
		_druid_panel.visible = false


func _on_pick_champ() -> void:
	_pick_place("champion")

func _on_call_reserve() -> void:
	## Call one reserve regiment beside General: once per 2 turns (cooldown only), shock push+2 dmg.
	if _match_locked() or _phase != Phase.MOVE or _enemy_acting:
		return
	if _oak_turn_spent:
		_show_toast("Oak used this turn — End turn.")
		return
	if _reserve_cooldown > 0:
		_show_toast("Reserve call cooling down (%d turn(s))." % _reserve_cooldown)
		return
	if _reserve_inf <= 0 and _reserve_arch <= 0 and _reserve_cav <= 0:
		_show_toast("No reserves left.")
		return
	var g := _general_pos()
	if g.x < 0:
		_show_toast("No General — cannot call reserve.")
		return
	# Prefer Inf, then Arch, then Cav
	var kind := ""
	if _reserve_inf > 0:
		kind = "infantry"
	elif _reserve_arch > 0:
		kind = "archer"
	elif _reserve_cav > 0:
		kind = "cavalry"
	var spawn := _find_reserve_spawn(g, kind)
	if spawn.is_empty():
		_show_toast("No free square beside General for reserve.")
		return
	_reserve_cooldown = 2
	match kind:
		"infantry":
			_reserve_inf -= 1
			_place_regiment(spawn, PType.INFANTRY, true, "H")
		"archer":
			_reserve_arch -= 1
			_place_regiment(spawn, PType.ARCHER, true, "L")
		"cavalry":
			_reserve_cav -= 1
			_place_regiment(spawn, PType.CAVALRY, true, "T")
	_apply_reserve_shock(g)
	_show_toast("Reserve %s arrives — shock wave!" % kind, 3.0)
	_status.text = "Once-per-unit — tap a regiment / End turn"
	_refresh()

func _find_reserve_spawn(g: Vector2i, kind: String) -> Array:
	## Find a legal footprint adjacent to General on player half.
	var footprints: Array = []
	if kind == "infantry":
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
			var anchor := Vector2i(g.x + d.x, g.y + d.y)
			var foot := _inf_h_foot(anchor.x, anchor.y)
			if _cells_empty_and_half(foot) and _foot_clear_of_blockers(foot, PType.INFANTRY):
				return foot
	elif kind == "archer":
		for rot in range(4):
			for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(2, 0)]:
				var a2 := Vector2i(g.x + d2.x, g.y + d2.y)
				var foot2 := _arch_l_foot(a2.x, a2.y, rot)
				if _cells_empty_and_half(foot2) and _foot_clear_of_blockers(foot2, PType.ARCHER):
					return foot2
	elif kind == "cavalry":
		for d3 in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(1, 1), Vector2i(-1, 1)]:
			var a3 := Vector2i(g.x + d3.x, g.y + d3.y)
			var foot3 := _cav_foot(a3.x, a3.y)
			if _cells_empty_and_half(foot3) and _foot_clear_of_blockers(foot3, PType.CAVALRY):
				return foot3
	return []

func _foot_clear_of_blockers(cells: Array, mover_type: int) -> bool:
	for pos in cells:
		var p: Vector2i = pos
		if _terrain_blocks(p, mover_type):
			return false
	return true

func _apply_reserve_shock(g: Vector2i) -> void:
	## Shock: push foes to ≥4 from G + 2 dmg. Champion immune; oaks/pillars block shove.
	for r in range(ROWS):
		for c in range(COLS):
			var pos := Vector2i(c, r)
			var en = _piece_at(pos)
			if en == null or bool(en["friend"]):
				continue
			var et := int(en["type"])
			if et == PType.TOWER or et == PType.OAK:
				continue
			if et == PType.CHAMPION:
				continue  # immune reserve shove
			var dist := _chebyshev(g, pos)
			if dist >= 4:
				# still take 2 dmg if within shock radius? Sheet: push foes to ≥4 from G + 2 dmg
				# Interpret: all foes within <4 are pushed out and take 2; foes already ≥4 unaffected
				continue
			_damage_at(pos, 2)
			# push outward from G until dist>=4 or blocked
			var cur = _piece_at(pos)
			if cur == null:
				continue
			var guard := 0
			var cp := pos
			while _chebyshev(g, cp) < 4 and guard < 8:
				guard += 1
				var dx := 0 if cp.x == g.x else (1 if cp.x > g.x else -1)
				var dy := 0 if cp.y == g.y else (1 if cp.y > g.y else -1)
				var np := Vector2i(cp.x + dx, cp.y + dy)
				if np.x < 0 or np.x >= COLS or np.y < 0 or np.y >= ROWS:
					break
				if _walls.has(np) or _piece_at(np) != null:
					break
				var blk = _piece_at(np)
				# already null
				var piece = _board[cp.y][cp.x]
				_board[cp.y][cp.x] = null
				_board[np.y][np.x] = piece
				cp = np

func _set_phase_place() -> void:
	_phase = Phase.PLACE
	_place_kind = ""
	_selected = Vector2i(-1, -1)
	_selected_reg = ""
	_highlights.clear()
	_place_options.clear()
	_place_panel.visible = true
	_choice_panel.visible = false
	_move_panel.visible = false
	_hide_druid_panel()
	_obj.text = "You are the General — command the field"
	_status.text = "Deploy stage %s — tap type, then glowing footprint on YOUR half" % _deploy_stage

func _pick_place(kind: String) -> void:
	if _match_locked() or _phase != Phase.PLACE:
		return
	# Forced deploy stages: infantry → archers → cavalry → champion
	if kind != _deploy_stage:
		_show_toast("Deploy stage: place %s first." % _deploy_stage.capitalize())
		_refresh()
		return
	if _place_kind == kind and kind == "archer":
		_place_arch_rot = (_place_arch_rot + 1) % 4
		_show_toast("Archer L facing %d/4 — tap green footprint (same L, rotated)." % (_place_arch_rot + 1))
		_status.text = "Place archer L (facing %d/4) — retap Archer to rotate · Cancel to abort" % (_place_arch_rot + 1)
		_rebuild_highlights()
		_refresh()
		return
	if _place_kind == kind:
		_cancel_place()
		_show_toast("Placement cancelled.")
		return
	match kind:
		"infantry":
			if _pool_inf <= 0:
				_show_toast("No infantry regiments left (line of 3).")
				_refresh()
				return
		"archer":
			if _pool_arch <= 0:
				_show_toast("No archer L blocks left (fixed L of 3).")
				_refresh()
				return
			_place_arch_rot = 0
		"cavalry":
			if _pool_cav <= 0:
				_show_toast("No cavalry left (T of 4).")
				_refresh()
				return
		"champion":
			if _pool_champ <= 0:
				_show_toast("Champion already placed.")
				_refresh()
				return
		_:
			return
	var opts := _footprints_for_kind(kind)
	if opts.is_empty():
		_show_toast("No legal footprint for %s — Begin manoeuvres or free space." % kind)
		_cancel_place()
		return
	_place_kind = kind
	if kind == "archer":
		_status.text = "Place archer L (facing %d/4) — retap Archer to rotate · Cancel to abort" % (_place_arch_rot + 1)
	elif kind == "champion":
		_status.text = "Place Champion in CENTRAL mid-box — Apprentice deploys beside"
	else:
		_status.text = "Place %s — glowing footprint · Cancel / retap type to abort" % kind
	_rebuild_highlights()
	if _place_options.is_empty():
		_show_toast("No legal footprint — placement cleared.")
		_cancel_place()
		return
	_refresh()

func _cancel_place() -> void:
	_inf_pair_pending.clear()
	_place_kind = ""
	_place_arch_rot = 0
	_highlights.clear()
	_place_options.clear()
	if _phase == Phase.PLACE and not _match_locked():
		_status.text = "Place: tap type + footprint · Cancel · or Begin manoeuvres"
	_refresh()

func _on_keep_placing() -> void:
	if _fallen:
		return
	_set_phase_place()
	_refresh()

func _on_start_moving() -> void:
	if _fallen:
		return
	# Locked sheet: pre-set + deploy extras, then fight. Enemy gets SAME extras auto-placed.
	_auto_deploy_enemy_extras()
	_phase = Phase.MOVE
	_place_kind = ""
	_oak_shifting = false
	_oak_turn_spent = false
	_moved_ids.clear()
	_enemy_acted_ids.clear()
	_cav_free_used.clear()
	_charge_ids.clear()
	_clear_selection()
	_cavalry_steps_left = 0
	_highlights.clear()
	_place_options.clear()
	_place_panel.visible = false
	_choice_panel.visible = false
	_move_panel.visible = true
	_hide_druid_panel()
	_obj.text = "You are the General — command the field"
	_status.text = "Move: each unit once — tap a regiment / oak, then glow"
	_show_toast("Parity deploy done. Reserves each side: 2I 2A 1C. Oaks: full turn to shift in zone.", 3.6)
	_refresh()

func _on_end_turn() -> void:
	if _match_locked() or _phase != Phase.MOVE or _enemy_acting:
		return
	# Ending own turn clears own druid-skip (disable was for this turn only)
	_druid_skip_friend = false
	_enemy_acting = true
	_clear_selection()
	_cavalry_steps_left = 0
	_highlights.clear()
	_hide_druid_panel()
	# Auto-forward friend units that have not acted (skip if oak spent full turn)
	if not _oak_turn_spent:
		_auto_forward_unacted(true)
	_board_wide_auto_chip(true)
	_tick_traps()
	_tick_colour_buffs()
	_check_match_end()
	if _match_locked():
		_enemy_acting = false
		_refresh()
		return
	_show_toast("Enemy advance…")
	_status.text = "Enemy turn…"
	_refresh()
	await get_tree().create_timer(0.35).timeout
	if _match_locked():
		_enemy_acting = false
		_refresh()
		return
	_run_enemy_turn()
	if not _match_locked():
		_board_wide_auto_chip(false)
	_enemy_acting = false
	if _match_locked():
		_refresh()
		return
	_tick_druid_cooldowns()
	_turn_n += 1
	_oak_turn_spent = false
	_oak_shifting = false
	# Oak follow (friend): enemy turn just ended → clear friend IMMUNE; start friend SKIP if due
	_druid_immune_friend = false
	_druid_skip_friend = false
	if _oak_follow_friend == 2:
		_druid_skip_friend = true
		_oak_follow_friend = 0
	# Oak follow (enemy): if enemy oak'd last turn, their druids are IMMUNE during this player turn
	_druid_immune_enemy = false
	if _oak_follow_enemy == 1:
		_druid_immune_enemy = true
		_oak_follow_enemy = 2
	_druid_skip_enemy = false
	_moved_ids.clear()
	_cav_free_used.clear()
	_charge_ids.clear()
	if _reserve_cooldown > 0:
		_reserve_cooldown -= 1
	if _enemy_reserve_cooldown > 0:
		_enemy_reserve_cooldown -= 1
	var toast := "Your turn — each unit once."
	if _druid_skip_friend:
		toast = "Your turn — druids DISABLED (oak follow). Each unit once."
	elif _druid_immune_enemy:
		toast = "Your turn — enemy druids IMMUNE (their oak). Each unit once."
	_show_toast(toast)
	_status.text = "Move: each unit once — tap a regiment / oak, then glow"
	_rebuild_highlights()
	_refresh()

func _tick_colour_buffs() -> void:
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p == null:
				continue
			var cb := int(p.get("colour_buff", 0))
			if cb > 0:
				p["colour_buff"] = cb - 1

func _board_wide_auto_chip(friend_side: bool) -> void:
	## Melee figures chip 1 target in 8-adj; archers auto-fire Chebyshev 1–2.
	var actors: Array = []
	var seen_reg: Dictionary = {}
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p == null:
				continue
			var pt := int(p["type"])
			if pt == PType.TOWER or pt == PType.OAK:
				continue
			if bool(p["friend"]) != friend_side:
				continue
			if int(p.get("trap", 0)) > 0:
				continue
			var rid := _reg_id_of(p)
			if rid != "":
				if seen_reg.has(rid):
					continue
				seen_reg[rid] = true
				actors.append(_regiment_cells(rid))
			else:
				actors.append([Vector2i(c, r)])
	var hits := 0
	for cells in actors:
		if cells.is_empty():
			continue
		var first = _piece_at(cells[0])
		if first == null:
			continue
		# Oak follow: druids DISABLED only on their own next turn after oak
		if int(first["type"]) == PType.DRUID:
			if friend_side and _druid_skip_friend:
				continue
			if (not friend_side) and _druid_skip_enemy:
				continue
		var before_toast := _toast_t
		if int(first["type"]) == PType.ARCHER:
			_archer_auto_fire(cells)
		else:
			_regiment_chip(cells)
		if _toast_t != before_toast or _hit_flashes:
			hits += 1
	if hits > 0:
		_show_toast(("Your lines strike %d engagement(s)." if friend_side else "Enemy lines strike %d engagement(s).") % hits, 1.4)

func _archer_auto_fire(cells: Array) -> void:
	## Each archer figure fires at 1 foe in Chebyshev 1–2 (champ priority else lowest HP). No charge dmg.
	for pos in cells:
		var p = _piece_at(pos)
		if p == null or int(p["type"]) != PType.ARCHER:
			continue
		var friend := bool(p["friend"])
		var candidates: Array = []
		for r in range(maxi(0, pos.y - 2), mini(ROWS, pos.y + 3)):
			for c in range(maxi(0, pos.x - 2), mini(COLS, pos.x + 3)):
				var to := Vector2i(c, r)
				if to == pos:
					continue
				if _chebyshev(pos, to) < 1 or _chebyshev(pos, to) > 2:
					continue
				var dest = _piece_at(to)
				if dest == null:
					continue
				var dt := int(dest["type"])
				if dt == PType.TOWER or dt == PType.OAK:
					continue
				if bool(dest["friend"]) == friend:
					continue
				candidates.append(to)
		if candidates.is_empty():
			continue
		var tgt := _pick_combat_target(candidates)
		_damage_at(tgt, 1)

func _tick_druid_cooldowns() -> void:
	## Decrement per-power CDs on all druids (both sides) once per side-resolution pass.
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p == null or int(p["type"]) != PType.DRUID:
				continue
			for k in ["cd_earth", "cd_fire", "cd_water", "cd_holy"]:
				var v := int(p.get(k, 0))
				if v > 0:
					p[k] = v - 1


func _tick_traps() -> void:
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p == null:
				continue
			var tr := int(p.get("trap", 0))
			if tr > 0:
				p["trap"] = tr - 1

func _maybe_reinforce() -> void:
	## Demoted: mid-game enemy-only reinforce disabled (player reinforce-at-deploy is locked).
	return

func _on_back() -> void:
	GameState.go_to("res://scenes/druid_yard.tscn", "from_chess", "chess")

func _druid_ability(kind: String) -> void:
	## Earth trap / Water shove / Fire damage / Holy heal-only. Once per druid / turn.
	if _match_locked() or _phase != Phase.MOVE or _enemy_acting:
		return
	if _oak_turn_spent:
		_show_toast("Oak used this turn — End turn.")
		return
	if _druid_skip_friend:
		_show_toast("Druids DISABLED this turn (oak follow).")
		return
	var dpos := _selected
	var dp = _piece_at(dpos)
	if dp == null or int(dp.get("type", -1)) != PType.DRUID or not bool(dp.get("friend", false)):
		dpos = _find_friend_druid()
		dp = _piece_at(dpos)
	if dp == null or int(dp.get("type", -1)) != PType.DRUID:
		_show_toast("Select a Druid first, then use an ability.")
		return
	var daid := _actor_id_for_piece(dp, dpos)
	if daid != "" and _moved_ids.has(daid):
		_show_toast("That Druid already acted this turn.")
		return
	var cd_key := "cd_%s" % kind
	var cd_left := int(dp.get(cd_key, 0))
	if cd_left > 0:
		_show_toast("%s cooling down (%d turn(s))." % [kind.capitalize(), cd_left])
		return
	var did := false
	match kind:
		"earth":
			# Trap nearest enemy within DRUID_RADIUS for 3 turns (cannot move)
			var tgts: Array = []
			for r in range(ROWS):
				for c in range(COLS):
					var p := Vector2i(c, r)
					var en = _piece_at(p)
					if en == null or bool(en["friend"]) or int(en["type"]) == PType.TOWER:
						continue
					var d := _chebyshev(dpos, p)
					if d >= 1 and d <= DRUID_RADIUS:
						tgts.append(p)
			if tgts.is_empty():
				_show_toast("Earth — no foe in range %d to trap." % DRUID_RADIUS)
				return
			tgts.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				return _chebyshev(dpos, a) < _chebyshev(dpos, b))
			var tgt: Vector2i = tgts[0]
			var en2 = _piece_at(tgt)
			en2["trap"] = 3
			_flash_hit(tgt, true)
			did = true
			_show_toast("Earth — %s trapped 3 turns!" % _ptype_name(int(en2["type"])))
		"water":
			# Shove nearest enemy in DRUID_RADIUS to free square behind them
			var nearest: Vector2i = Vector2i(-1, -1)
			var best_d := 99
			for r in range(ROWS):
				for c in range(COLS):
					var p := Vector2i(c, r)
					var en = _piece_at(p)
					if en == null or bool(en["friend"]) or int(en["type"]) == PType.TOWER:
						continue
					var d := _chebyshev(dpos, p)
					if d < 1 or d > DRUID_RADIUS:
						continue
					if d < best_d:
						best_d = d
						nearest = p
			if nearest.x < 0:
				_show_toast("Water — no enemy in range %d to shove." % DRUID_RADIUS)
				return
			var dest := _shove_behind_free(dpos, nearest)
			if dest.x < 0:
				_show_toast("Water — no free square behind that foe.")
				return
			var piece = _board[nearest.y][nearest.x]
			_board[nearest.y][nearest.x] = null
			_board[dest.y][dest.x] = piece
			_flash_hit(dest, true)
			did = true
			_show_toast("Water — shoved %s back!" % _ptype_name(int(piece["type"])))
		"fire":
			# Worthwhile damage (FIRE_DMG) on nearest enemy in DRUID_RADIUS
			var tgts2: Array = []
			for r in range(ROWS):
				for c in range(COLS):
					var p := Vector2i(c, r)
					var en = _piece_at(p)
					if en == null or bool(en["friend"]) or int(en["type"]) == PType.TOWER:
						continue
					var d := _chebyshev(dpos, p)
					if d >= 1 and d <= DRUID_RADIUS:
						tgts2.append(p)
			if tgts2.is_empty():
				_show_toast("Fire — no enemy in range %d." % DRUID_RADIUS)
				return
			tgts2.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				return _chebyshev(dpos, a) < _chebyshev(dpos, b))
			var tgt_f: Vector2i = tgts2[0]
			var before = _piece_at(tgt_f)
			var nm := _ptype_name(int(before["type"])) if before else "foe"
			var killed := _damage_at(tgt_f, FIRE_DMG)
			did = true
			if killed:
				_show_toast("Fire — %s scorched and fallen!" % nm)
			else:
				var left := int(_piece_at(tgt_f).get("hp", 0)) if _piece_at(tgt_f) else 0
				_show_toast("Fire — %s takes %d (HP %d)." % [nm, FIRE_DMG, left])
		"holy":
			# Heal ONLY — restore HOLY_HEAL on lowest-HP friend in DRUID_RADIUS (or self)
			var candidates: Array = []
			for r in range(ROWS):
				for c in range(COLS):
					var p := Vector2i(c, r)
					if _chebyshev(dpos, p) > DRUID_RADIUS:
						continue
					var fr = _piece_at(p)
					if fr == null or not bool(fr["friend"]) or int(fr["type"]) == PType.TOWER:
						continue
					var mx := _piece_max_hp(fr)
					var hp := int(fr.get("hp", mx))
					if hp < mx:
						candidates.append({"pos": p, "hp": hp, "max": mx})
			if candidates.is_empty():
				_show_toast("Holy — no wounded ally in range %d." % DRUID_RADIUS)
				return
			candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a["hp"]) < int(b["hp"]))
			var pos: Vector2i = candidates[0]["pos"]
			var fr2 = _piece_at(pos)
			var mx2 := _piece_max_hp(fr2)
			fr2["hp"] = mini(mx2, int(fr2["hp"]) + HOLY_HEAL)
			_flash_hit(pos, false)
			did = true
			_show_toast("Holy — healed %s to HP %d." % [_ptype_name(int(fr2["type"])), int(fr2["hp"])])
		_:
			_show_toast("Unknown druid call.")
			return
	if not did:
		return
	# Cooldowns: Earth/Fire/Water = 1 turn; Holy = 5 turns (same both sides)
	if kind == "holy":
		dp["cd_holy"] = DRUID_CD_HOLY
	else:
		dp[cd_key] = DRUID_CD_EFW
	if daid != "":
		_moved_ids[daid] = true
	_clear_selection()
	_hide_druid_panel()
	_status.text = "Once-per-unit — tap a regiment"
	_check_match_end()
	_rebuild_highlights()
	_refresh()

func _shove_behind_free(from_druid: Vector2i, foe: Vector2i) -> Vector2i:
	## Prefer square further from druid (behind the foe); else any free neighbour away.
	var away := Vector2i(foe.x - from_druid.x, foe.y - from_druid.y)
	var dirs: Array = []
	if away != Vector2i(0, 0):
		var sx := 0 if away.x == 0 else (1 if away.x > 0 else -1)
		var sy := 0 if away.y == 0 else (1 if away.y > 0 else -1)
		dirs.append(Vector2i(sx, sy))
		dirs.append(Vector2i(sx, 0))
		dirs.append(Vector2i(0, sy))
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var d := Vector2i(dc, dr)
			if d not in dirs:
				dirs.append(d)
	for d in dirs:
		var np := Vector2i(foe.x + d.x, foe.y + d.y)
		if np.x < 0 or np.x >= COLS or np.y < 0 or np.y >= ROWS:
			continue
		if _piece_at(np) != null:
			continue
		# Prefer not closer to the druid
		if _chebyshev(from_druid, np) >= _chebyshev(from_druid, foe):
			return np
	# Fallback: any free neighbour
	for d in dirs:
		var np2 := Vector2i(foe.x + d.x, foe.y + d.y)
		if np2.x < 0 or np2.x >= COLS or np2.y < 0 or np2.y >= ROWS:
			continue
		if _piece_at(np2) == null:
			return np2
	return Vector2i(-1, -1)

func _find_friend_druid() -> Vector2i:
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p != null and int(p["type"]) == PType.DRUID and bool(p["friend"]):
				return Vector2i(c, r)
	return Vector2i(-1, -1)

func _cancel_cavalry() -> void:
	## End multi-step cavalry early — auto-battle chip, clear activation.
	if _fallen or _cavalry_steps_left <= 0:
		return
	var cells := _active_move_cells()
	if cells.is_empty() and _cavalry_pos.x >= 0:
		cells = [_cavalry_pos]
	_regiment_chip(cells)
	_cavalry_steps_left = 0
	_clear_selection()
	_show_toast("Cavalry stands down — engagement resolved.")
	_status.text = "Once-per-unit — tap a regiment"
	_rebuild_highlights()
	_refresh()

func _queen_pos() -> Vector2i:
	## No queen in locked sheet.
	return Vector2i(-1, -1)

func _in_queen_aura(_pos: Vector2i) -> bool:
	## Removed with queen — no retreat aura.
	return false

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func _actor_id_for_piece(piece, pos: Vector2i) -> String:
	if piece == null:
		return ""
	var rid := _reg_id_of(piece)
	if rid != "":
		return "reg:" + rid
	return "solo:%s:%s" % [str(piece.get("type", -1)), str(piece.get("id", "%d_%d" % [pos.x, pos.y]))]

func _actor_id_from_selection() -> String:
	var cells := _active_move_cells()
	if cells.is_empty():
		if _selected.x >= 0:
			return _actor_id_for_piece(_piece_at(_selected), _selected)
		return ""
	var p = _piece_at(cells[0])
	return _actor_id_for_piece(p, cells[0])

func _advance_deploy_stage_after(placed_kind: String) -> void:
	## Inf → Arch → Cav → Hero; stay until that pool is empty.
	var order := ["infantry", "archer", "cavalry", "champion"]
	var pools := {"infantry": _pool_inf, "archer": _pool_arch, "cavalry": _pool_cav, "champion": _pool_champ}
	if int(pools.get(placed_kind, 0)) > 0:
		_deploy_stage = placed_kind
		return
	var idx := order.find(placed_kind)
	if idx < 0:
		idx = order.find(_deploy_stage)
	var start := (idx + 1) % order.size()
	_deploy_stage = _next_deploy_stage_with_pool(order[start])

func _next_deploy_stage_with_pool(prefer: String) -> String:
	var order := ["infantry", "archer", "cavalry", "champion"]
	var pools := {"infantry": _pool_inf, "archer": _pool_arch, "cavalry": _pool_cav, "champion": _pool_champ}
	var idx := order.find(prefer)
	if idx < 0:
		idx = 0
	for i in range(order.size()):
		var k: String = order[(idx + i) % order.size()]
		if int(pools[k]) > 0:
			return k
	return prefer

func _point_in_triangle(p: Vector2i, a: Vector2i, b: Vector2i, c: Vector2i) -> bool:
	## Barycentric in integer grid (inclusive edges).
	var v0x := float(c.x - a.x)
	var v0y := float(c.y - a.y)
	var v1x := float(b.x - a.x)
	var v1y := float(b.y - a.y)
	var v2x := float(p.x - a.x)
	var v2y := float(p.y - a.y)
	var dot00 := v0x * v0x + v0y * v0y
	var dot01 := v0x * v1x + v0y * v1y
	var dot02 := v0x * v2x + v0y * v2y
	var dot11 := v1x * v1x + v1y * v1y
	var dot12 := v1x * v2x + v1y * v2y
	var inv := dot00 * dot11 - dot01 * dot01
	if absf(inv) < 0.00001:
		return false
	var u := (dot11 * dot02 - dot01 * dot12) / inv
	var v := (dot00 * dot12 - dot01 * dot02) / inv
	return u >= -0.001 and v >= -0.001 and (u + v) <= 1.001

func _druid_side_key(pos: Vector2i, friend: bool) -> String:
	## Left = own half of board by x vs general/queen centre; right otherwise.
	var gx := COLS / 2
	if friend:
		var g := _general_pos()
		if g.x >= 0:
			gx = g.x
	else:
		# Enemy general on far row
		for r in range(ROWS - 1, -1, -1):
			for c in range(COLS):
				var p = _board[r][c]
				if p != null and int(p["type"]) == PType.GENERAL and not bool(p["friend"]):
					gx = c
					break
	return "left" if pos.x <= gx else "right"

func _druid_triangle_verts(side: String, friend: bool) -> Array:
	## Far enemy L/R corner → square beside the king → near-side corner on that flank.
	## Cannot enter king's square (caller clamps).
	var gx := COLS / 2
	var gy := 0
	if friend:
		var g := _general_pos()
		if g.x >= 0:
			gx = g.x
			gy = g.y
		var beside := Vector2i(gx - 1, gy) if side == "left" else Vector2i(gx + 1, gy)
		var far := Vector2i(0, ROWS - 1) if side == "left" else Vector2i(COLS - 1, ROWS - 1)
		var near := Vector2i(0, 0) if side == "left" else Vector2i(COLS - 1, 0)
		return [far, beside, near]
	# Enemy: mirror — king on far row, triangle toward player
	var eg := Vector2i(gx, ROWS - 1)
	for r in range(ROWS - 1, -1, -1):
		for c in range(COLS):
			var p2 = _board[r][c]
			if p2 != null and int(p2["type"]) == PType.GENERAL and not bool(p2["friend"]):
				eg = Vector2i(c, r)
				break
	var beside_e := Vector2i(eg.x - 1, eg.y) if side == "left" else Vector2i(eg.x + 1, eg.y)
	var far_e := Vector2i(0, 0) if side == "left" else Vector2i(COLS - 1, 0)
	var near_e := Vector2i(0, ROWS - 1) if side == "left" else Vector2i(COLS - 1, ROWS - 1)
	return [far_e, beside_e, near_e]

func _in_druid_triangle(pos: Vector2i, side: String, friend: bool) -> bool:
	var verts: Array = _druid_triangle_verts(side, friend)
	if verts.size() < 3:
		return false
	# Reject king's square
	if friend:
		var g := _general_pos()
		if g.x >= 0 and pos == g:
			return false
	else:
		for r in range(ROWS):
			for c in range(COLS):
				var p = _board[r][c]
				if p != null and int(p["type"]) == PType.GENERAL and not bool(p["friend"]):
					if pos == Vector2i(c, r):
						return false
	return _point_in_triangle(pos, verts[0], verts[1], verts[2])

func _druid_dest_ok(from: Vector2i, to: Vector2i, friend: bool) -> bool:
	var side := _druid_side_key(from, friend)
	if not _in_druid_triangle(to, side, friend):
		return false
	# Stay on same side (no crossing midline through king)
	if _druid_side_key(to, friend) != side:
		return false
	return true

func _clear_path_diag(from: Vector2i, to: Vector2i) -> bool:
	var dx := to.x - from.x
	var dy := to.y - from.y
	if absi(dx) != absi(dy) or dx == 0:
		return false
	var sx := 1 if dx > 0 else -1
	var sy := 1 if dy > 0 else -1
	var steps := absi(dx)
	for i in range(1, steps):
		var mid := Vector2i(from.x + sx * i, from.y + sy * i)
		if _piece_at(mid) != null:
			return false
	return true

func _druid_move_delta_legal(from: Vector2i, delta: Vector2i, friend: bool) -> bool:
	## Druids have NO board walks — only Earth/Fire/Water/Holy via panel buttons.
	return false

func _on_cell(r: int, c: int) -> void:
	if _match_locked():
		_show_toast("Defeat" if _fallen else "Victory")
		_refresh()
		return
	if _enemy_acting:
		return
	if _phase == Phase.PLACE:
		_try_place(r, c)
	elif _phase == Phase.PLACE_CHOICE:
		_show_toast("Choose Keep deploying or Begin manoeuvres.")
	elif _phase == Phase.MOVE:
		_try_move_select(r, c)
	_check_match_end()
	_rebuild_highlights()
	_refresh()

## --- Regiment footprints ---------------------------------------------------
## Infantry: prefer horizontal row of 3 (facing enemy / line ⊥ attack).
##   Fallback vertical column of 3 toward enemy (+row for player).
## Archers: FIXED L of 3 (two in a row + one attached at one end). Same shape always;
##   player picks facing via 4 rotations (_place_arch_rot). Not random/scatter.
## Cavalry: T of 4 — base three in a row, stem one forward from the centre cell.


func _in_mid_box(pos: Vector2i) -> bool:
	return pos.x >= MID_BOX_X0 and pos.x <= MID_BOX_X1 and pos.y >= MID_BOX_Y0 and pos.y <= MID_BOX_Y1


func _apprentice_attach_offset(friend: bool) -> Vector2i:
	## Back-and-left diagonal relative to facing toward enemy.
	## Friend faces +Y → attach (−1, −1). Enemy faces −Y → attach (+1, +1).
	var fwd := _forward_delta_for(friend)
	return Vector2i(-fwd, -fwd)


func _place_apprentice_beside_champ(champ_pos: Vector2i, friend: bool) -> Vector2i:
	## Attach diagonal BACK-LEFT of Champion relative to facing (both sides).
	## Exact cell first; only if blocked, fall back to other mid-box neighbours.
	var off := _apprentice_attach_offset(friend)
	var pref := Vector2i(champ_pos.x + off.x, champ_pos.y + off.y)
	var candidates: Array = [pref]
	for d in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var p := Vector2i(champ_pos.x + d.x, champ_pos.y + d.y)
		if p != pref:
			candidates.append(p)
	for p in candidates:
		if p.x < 0 or p.x >= COLS or p.y < 0 or p.y >= ROWS:
			continue
		if not _in_mid_box(p):
			continue
		if friend and not _on_player_half(p.y):
			continue
		if (not friend) and not _on_enemy_half(p.y):
			continue
		if _piece_at(p) != null:
			continue
		if _terrain_blocks(p, PType.APPRENTICE):
			continue
		_board[p.y][p.x] = _mk(PType.APPRENTICE, friend)
		return p
	return Vector2i(-1, -1)


func _player_half_max() -> int:
	## Inclusive max row on player (near) half.
	return int(ROWS / 2.0) - 1

func _on_player_half(r: int) -> bool:
	return r >= 0 and r <= _player_half_max()

func _enemy_half_min() -> int:
	## Inclusive min row on enemy (far) half.
	return int(ROWS / 2.0)

func _on_enemy_half(r: int) -> bool:
	return r >= _enemy_half_min() and r < ROWS

func _cells_empty_on_half(cells: Array, enemy_side: bool) -> bool:
	for pos in cells:
		var p: Vector2i = pos
		if p.x < 0 or p.x >= COLS or p.y < 0 or p.y >= ROWS:
			return false
		if enemy_side:
			if not _on_enemy_half(p.y):
				return false
		else:
			if not _on_player_half(p.y):
				return false
		if _piece_at(p) != null:
			return false
		if _walls.has(p):
			return false
	return true

func _cav_foot_for(c: int, r: int, friend: bool) -> Array:
	## T of 4; stem toward enemy (player: +row, enemy: -row).
	if friend:
		return _cav_foot(c, r)
	return [Vector2i(c, r), Vector2i(c + 1, r), Vector2i(c + 2, r), Vector2i(c + 1, r - 1)]

## --- Mirrored enemy deploy extras (same pools/stages as player) -------------

func _auto_deploy_enemy_extras() -> void:
	## Place the SAME extras the player may deploy, on the enemy half (AI).
	## Stages Inf → Arch → Cav → Champion (row ROWS-2).
	var placed := {"infantry": 0, "archer": 0, "cavalry": 0, "champion": 0}
	while _enemy_pool_inf > 0:
		var foot := _find_enemy_footprint("infantry")
		if foot.is_empty():
			break
		_place_regiment(foot, PType.INFANTRY, false, "H")
		_enemy_pool_inf -= 1
		placed["infantry"] += 1
	while _enemy_pool_arch > 0:
		var foot_a := _find_enemy_footprint("archer")
		if foot_a.is_empty():
			break
		_place_regiment(foot_a, PType.ARCHER, false, "L")
		_enemy_pool_arch -= 1
		placed["archer"] += 1
	while _enemy_pool_cav > 0:
		var foot_c := _find_enemy_footprint("cavalry")
		if foot_c.is_empty():
			break
		_place_regiment(foot_c, PType.CAVALRY, false, "T")
		_enemy_pool_cav -= 1
		placed["cavalry"] += 1
	while _enemy_pool_champ > 0:
		var foot_h := _find_enemy_footprint("champion")
		if foot_h.is_empty():
			break
		var hp: Vector2i = foot_h[0]
		_board[hp.y][hp.x] = _mk(PType.CHAMPION, false)
		_place_apprentice_beside_champ(hp, false)
		_enemy_pool_champ -= 1
		placed["champion"] += 1
	_show_toast("Enemy deployed extras I%d A%d C%d H%d (parity)." % [
		placed["infantry"], placed["archer"], placed["cavalry"], placed["champion"]
	], 2.4)

func _find_enemy_footprint(kind: String) -> Array:
	## First legal footprint on enemy half (scan mid→edges).
	if kind == "champion":
		# CENTRAL mid-box on enemy half (scan centre → edges)
		var mid_c := int((MID_BOX_X0 + MID_BOX_X1) / 2.0)
		var cols_scan: Array = []
		for i in range(0, MID_BOX_X1 - MID_BOX_X0 + 1):
			var a := mid_c + i
			var b := mid_c - i
			if a >= MID_BOX_X0 and a <= MID_BOX_X1 and a not in cols_scan:
				cols_scan.append(a)
			if b >= MID_BOX_X0 and b <= MID_BOX_X1 and b not in cols_scan:
				cols_scan.append(b)
		for r in range(MID_BOX_Y0, MID_BOX_Y1 + 1):
			if not _on_enemy_half(r):
				continue
			for c in cols_scan:
				var pos := Vector2i(c, r)
				if _piece_at(pos) != null:
					continue
				if _terrain_blocks(pos, PType.CHAMPION):
					continue
				var off2 := _apprentice_attach_offset(false)
				var ap2 := Vector2i(pos.x + off2.x, pos.y + off2.y)
				var ok := _in_mid_box(ap2) and _on_enemy_half(ap2.y) and _piece_at(ap2) == null and not _terrain_blocks(ap2, PType.APPRENTICE)
				if not ok:
					for d3 in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
						var q2 := Vector2i(pos.x + d3.x, pos.y + d3.y)
						if _in_mid_box(q2) and _on_enemy_half(q2.y) and _piece_at(q2) == null and not _terrain_blocks(q2, PType.APPRENTICE):
							ok = true
							break
				if not ok:
					continue
				return [pos]
		return []
	## Scan from centre outward (no Python-style // — GDScript uses /).
	var mid := int(COLS / 2)
	var cols: Array = [mid]
	var seen: Dictionary = {mid: true}
	for i in range(1, COLS):
		for sign in [1, -1]:
			var c: int = mid + i * sign
			if c < 0 or c >= COLS:
				continue
			if seen.has(c):
				continue
			seen[c] = true
			cols.append(c)
	for r in range(ROWS - 1, _enemy_half_min() - 1, -1):
		for c in cols:
			var foot: Array = []
			match kind:
				"infantry":
					foot = _inf_h_foot(c, r)
				"archer":
					foot = _arch_l_foot(c, r, 1)
				"cavalry":
					foot = _cav_foot_for(c, r, false)
				_:
					return []
			var mtype := PType.INFANTRY
			if kind == "archer":
				mtype = PType.ARCHER
			elif kind == "cavalry":
				mtype = PType.CAVALRY
			if _cells_empty_on_half(foot, true) and _foot_clear_of_blockers(foot, mtype):
				return foot
	return []

## --- Oak shift (FULL TURN) + roam zone ----------------------------------

func _oak_roam_zone_for(cells: Array) -> Rect2i:
	## Left / right halfway bands — oaks stay in their wing zone.
	var min_x := COLS
	for pos in cells:
		min_x = mini(min_x, int(pos.x))
	var mid_r := int(ROWS / 2.0)
	var zone_h := 6
	var y0 := clampi(mid_r - int(zone_h / 2), 0, ROWS - 1)
	if min_x < int(COLS / 2):
		return Rect2i(0, y0, 7, zone_h)
	return Rect2i(maxi(0, COLS - 7), y0, 7, zone_h)

func _oak_cells_in_zone(cells: Array, zone: Rect2i) -> bool:
	for pos in cells:
		var p: Vector2i = pos
		if p.x < zone.position.x or p.x >= zone.position.x + zone.size.x:
			return false
		if p.y < zone.position.y or p.y >= zone.position.y + zone.size.y:
			return false
	return true

func _oak_shift_dest_clear(cells: Array, delta: Vector2i) -> bool:
	var occ: Dictionary = {}
	for pos in cells:
		occ[pos] = true
	for pos in cells:
		var np := Vector2i(pos.x + delta.x, pos.y + delta.y)
		if np.x < 0 or np.x >= COLS or np.y < 0 or np.y >= ROWS:
			return false
		var dest = _piece_at(np)
		if dest != null and not occ.has(np):
			return false
		if _walls.has(np):
			return false
	return true

func _try_commit_oak_shift(to: Vector2i) -> void:
	## Player oak shift: translate selected 2×2 by 1 ortho within roam zone; costs FULL TURN.
	if _oak_turn_spent or not _moved_ids.is_empty() or not _cav_free_used.is_empty():
		_show_toast("Oak shift needs a fresh turn (no units acted) — costs full turn.")
		_oak_shifting = false
		_clear_selection()
		return
	var cells: Array = _regiment_cells(_selected_reg) if _selected_reg != "" else [_selected]
	if cells.is_empty():
		_oak_shifting = false
		return
	# Map tap to a delta from any oak cell
	var delta := Vector2i(0, 0)
	var matched := false
	for pos in cells:
		var d := Vector2i(to.x - pos.x, to.y - pos.y)
		if (absi(d.x) + absi(d.y)) == 1 and _oak_shift_dest_clear(cells, d):
			var trial: Array = []
			for p2 in cells:
				trial.append(Vector2i(p2.x + d.x, p2.y + d.y))
			if _oak_cells_in_zone(trial, _oak_roam_zone_for(cells)):
				delta = d
				matched = true
				break
	if not matched:
		_show_toast("Oaks move 1 step ortho inside their roam zone.")
		return
	_translate_cells(cells, delta)
	_oak_turn_spent = true
	_oak_shifting = false
	_oak_follow_friend = 1  ## next: foe turn IMMUNE, then own turn DISABLED
	_clear_selection()
	_show_toast("Oak shifted (full turn). Next: foe-turn druids IMMUNE; then your druids DISABLED.", 3.2)
	_status.text = "Oak used — End turn."
	_rebuild_highlights()
	_refresh()

func _add_oak_legal_highlights() -> void:
	var cells: Array = _regiment_cells(_selected_reg) if _selected_reg != "" else ([_selected] if _selected.x >= 0 else [])
	if cells.is_empty():
		return
	var zone := _oak_roam_zone_for(cells)
	for pos in cells:
		_highlights[pos] = "selected"
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not _oak_shift_dest_clear(cells, d):
			continue
		var trial: Array = []
		for p2 in cells:
			trial.append(Vector2i(p2.x + d.x, p2.y + d.y))
		if not _oak_cells_in_zone(trial, zone):
			continue
		for p3 in trial:
			if not cells.has(p3):
				_highlights[p3] = "move"

func _enemy_try_oak_shift() -> bool:
	## Shift oak only when useful (costs FULL TURN). Never random every turn.
	## Skip if a high-value strike on player General/Champion is already available.
	if _enemy_any_hv_strike_ready():
		return false
	var best_cells: Array = []
	var best_delta := Vector2i(0, 0)
	var best_score := 0
	var clumps: Array = []
	var seen: Dictionary = {}
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p == null or int(p["type"]) != PType.OAK:
				continue
			var rid := _reg_id_of(p)
			if rid == "" or seen.has(rid):
				continue
			seen[rid] = true
			clumps.append(_regiment_cells(rid))
	var pg := _general_pos()
	var pc := _friend_champ_pos()
	var eg := _enemy_general_pos()
	for cells in clumps:
		if cells.is_empty():
			continue
		var zone := _oak_roam_zone_for(cells)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not _oak_shift_dest_clear(cells, d):
				continue
			var trial: Array = []
			for p2 in cells:
				trial.append(Vector2i(p2.x + d.x, p2.y + d.y))
			if not _oak_cells_in_zone(trial, zone):
				continue
			var sc := _enemy_oak_shift_score(cells, trial, pg, pc, eg)
			if sc > best_score:
				best_score = sc
				best_cells = cells
				best_delta = d
	# Threshold: only spend the whole turn when clearly useful (was 5 — too eager)
	if best_score < 12 or best_cells.is_empty():
		return false
	_translate_cells(best_cells, best_delta)
	_oak_follow_enemy = 1
	return true


func _enemy_oak_shift_score(from_cells: Array, trial: Array, pg: Vector2i, pc: Vector2i, eg: Vector2i) -> int:
	## Higher = more useful. Block player approach / shield own General / clog HV files.
	var score := 0
	var old_c := _enemy_cells_centroid(from_cells)
	var new_c := _enemy_cells_centroid(trial)
	# Move oak toward player General / Champion (block their advance)
	if pg.x >= 0:
		var od := _chebyshev(old_c, pg)
		var nd := _chebyshev(new_c, pg)
		if nd < od:
			score += (od - nd) * 3
		if nd <= 3:
			score += 3
		# Same file/row clog near player G
		if new_c.x == pg.x and absi(new_c.y - pg.y) <= 4:
			score += 4
	if pc.x >= 0:
		var od2 := _chebyshev(old_c, pc)
		var nd2 := _chebyshev(new_c, pc)
		if nd2 < od2:
			score += (od2 - nd2) * 2
		if new_c.x == pc.x and absi(new_c.y - pc.y) <= 3:
			score += 5  # clog Champion file
	# Shield own General when player is close
	if eg.x >= 0 and pg.x >= 0 and _chebyshev(pg, eg) <= 5:
		var od3 := _chebyshev(old_c, eg)
		var nd3 := _chebyshev(new_c, eg)
		if nd3 < od3 and nd3 <= 3:
			score += 4
		# Prefer sitting between player G and own G
		if _enemy_point_between(new_c, pg, eg):
			score += 4
	# Player unit adjacent to oak — nudge into their path
	var near_player := false
	for pos in from_cells:
		for n in _chebyshev_neighbors(pos):
			var dest = _piece_at(n)
			if dest != null and bool(dest["friend"]) and int(dest["type"]) != PType.TOWER:
				near_player = true
				break
		if near_player:
			break
	if near_player:
		score += 2
	return score


func _enemy_point_between(p: Vector2i, a: Vector2i, b: Vector2i) -> bool:
	if a.x < 0 or b.x < 0:
		return false
	var minx := mini(a.x, b.x)
	var maxx := maxi(a.x, b.x)
	var miny := mini(a.y, b.y)
	var maxy := maxi(a.y, b.y)
	return p.x >= minx and p.x <= maxx and p.y >= miny and p.y <= maxy


func _enemy_cells_centroid(cells: Array) -> Vector2i:
	if cells.is_empty():
		return Vector2i(0, 0)
	var sx := 0
	var sy := 0
	for pos in cells:
		sx += int(pos.x)
		sy += int(pos.y)
	return Vector2i(int(sx / cells.size()), int(sy / cells.size()))


func _enemy_general_pos() -> Vector2i:
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p != null and int(p["type"]) == PType.GENERAL and not bool(p["friend"]):
				return Vector2i(c, r)
	return Vector2i(-1, -1)


func _friend_champ_pos() -> Vector2i:
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p != null and int(p["type"]) == PType.CHAMPION and bool(p["friend"]):
				return Vector2i(c, r)
	return Vector2i(-1, -1)


func _enemy_hv_targets() -> Array:
	## Player General & Champion — primary AI focus.
	var out: Array = []
	var g := _general_pos()
	if g.x >= 0:
		out.append(g)
	var c := _friend_champ_pos()
	if c.x >= 0:
		out.append(c)
	return out


func _enemy_target_priority(ptype: int) -> int:
	## Higher = more valuable to hit.
	if ptype == PType.GENERAL:
		return 100
	if ptype == PType.CHAMPION:
		return 80
	if ptype == PType.DRUID:
		return 35
	if ptype == PType.CAVALRY:
		return 30
	if ptype == PType.ARCHER:
		return 25
	if ptype == PType.INFANTRY or ptype == PType.ENEMY_INF:
		return 15
	return 5


func _enemy_any_hv_strike_ready() -> bool:
	## True if some enemy unit can chip/shoot player General or Champion right now.
	var hv := _enemy_hv_targets()
	if hv.is_empty():
		return false
	for actor in _enemy_actor_list():
		var rid: String = str(actor.get("reg", ""))
		var cells: Array = _regiment_cells(rid) if rid != "" else [actor["pos"]]
		if cells.is_empty():
			continue
		var piece = _piece_at(cells[0])
		if piece == null:
			continue
		var t: int = int(piece["type"])
		if t == PType.ARCHER:
			for h in hv:
				if _archer_can_hit(cells, h):
					return true
		else:
			for pos in cells:
				for h in hv:
					if _chebyshev(pos, h) == 1:
						return true
	return false


func _enemy_try_call_reserve() -> bool:
	## Mirror player Call Reserve: cooldown 2 only (no order budget), spawn by enemy General + shock.
	if _enemy_reserve_cooldown > 0:
		return false
	if _enemy_reserve_inf <= 0 and _enemy_reserve_arch <= 0 and _enemy_reserve_cav <= 0:
		return false
	# Call when own General is pressured, or occasionally to reinforce
	var eg := _enemy_general_pos()
	var pg := _general_pos()
	var pressured := eg.x >= 0 and pg.x >= 0 and _chebyshev(eg, pg) <= 6
	if not pressured and randf() > 0.22:
		return false
	if pressured and randf() > 0.55:
		return false
	var g := Vector2i(-1, -1)
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p != null and int(p["type"]) == PType.GENERAL and not bool(p["friend"]):
				g = Vector2i(c, r)
				break
		if g.x >= 0:
			break
	if g.x < 0:
		return false
	var kind := ""
	if _enemy_reserve_inf > 0:
		kind = "infantry"
	elif _enemy_reserve_arch > 0:
		kind = "archer"
	elif _enemy_reserve_cav > 0:
		kind = "cavalry"
	var spawn := _find_reserve_spawn_for(g, kind, false)
	if spawn.is_empty():
		return false
	match kind:
		"infantry":
			_place_regiment(spawn, PType.INFANTRY, false, "H")
			_enemy_reserve_inf -= 1
		"archer":
			_place_regiment(spawn, PType.ARCHER, false, "L")
			_enemy_reserve_arch -= 1
		"cavalry":
			_place_regiment(spawn, PType.CAVALRY, false, "T")
			_enemy_reserve_cav -= 1
	_enemy_reserve_cooldown = 2
	_apply_reserve_shock_side(g, false)
	return true

func _find_reserve_spawn_for(g: Vector2i, kind: String, friend: bool) -> Array:
	## Prefer existing helper for friend; enemy uses mirrored scan.
	if friend:
		return _find_reserve_spawn(g, kind)
	var candidates: Array = []
	match kind:
		"infantry":
			for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
				var foot := _inf_h_foot(g.x + d.x, g.y + d.y)
				if _cells_empty_on_half(foot, true) or _foot_clear_empty(foot):
					if _foot_clear_empty(foot) and _foot_clear_of_blockers(foot, PType.INFANTRY):
						candidates.append(foot)
		"archer":
			for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var foot2 := _arch_l_foot(g.x + d.x, g.y + d.y, 1)
				if _foot_clear_empty(foot2) and _foot_clear_of_blockers(foot2, PType.ARCHER):
					candidates.append(foot2)
		"cavalry":
			for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var foot3 := _cav_foot_for(g.x + d.x, g.y + d.y, false)
				if _foot_clear_empty(foot3) and _foot_clear_of_blockers(foot3, PType.CAVALRY):
					candidates.append(foot3)
	return candidates[0] if not candidates.is_empty() else []

func _foot_clear_empty(cells: Array) -> bool:
	for pos in cells:
		var p: Vector2i = pos
		if p.x < 0 or p.x >= COLS or p.y < 0 or p.y >= ROWS:
			return false
		if _piece_at(p) != null:
			return false
		if _walls.has(p):
			return false
	return true

func _apply_reserve_shock_side(g: Vector2i, friend_caller: bool) -> void:
	## Shock foes of the caller (reuse player shock when friend).
	if friend_caller:
		_apply_reserve_shock(g)
		return
	# Enemy calling: push/damage friend units near enemy G
	for r in range(ROWS):
		for c in range(COLS):
			var pos := Vector2i(c, r)
			var p = _piece_at(pos)
			if p == null or not bool(p["friend"]):
				continue
			var et := int(p["type"])
			if et == PType.TOWER or et == PType.OAK or et == PType.CHAMPION:
				continue
			if _chebyshev(pos, g) >= 4:
				continue
			_damage_at(pos, 2)
			# shove toward player edge (lower row)
			var np := Vector2i(pos.x, maxi(0, pos.y - 1))
			if _piece_at(np) == null and not _terrain_blocks(np, et):
				_board[np.y][np.x] = _board[pos.y][pos.x]
				_board[pos.y][pos.x] = null

func _cells_empty_and_half(cells: Array) -> bool:
	for pos in cells:
		var p: Vector2i = pos
		if p.x < 0 or p.x >= COLS or p.y < 0 or p.y >= ROWS:
			return false
		if not _on_player_half(p.y):
			return false
		if _piece_at(p) != null:
			return false
		if _walls.has(p):
			return false
	return true

func _inf_h_foot(c: int, r: int) -> Array:
	return [Vector2i(c, r), Vector2i(c + 1, r), Vector2i(c + 2, r)]

func _inf_v_foot(c: int, r: int) -> Array:
	return [Vector2i(c, r), Vector2i(c, r + 1), Vector2i(c, r + 2)]

func _arch_l_foot(c: int, r: int, rot: int = 0) -> Array:
	## Fixed L tromino — two in a row + one attached at one end. rot 0..3.
	## rot0: ■■ / ■.    rot1: ■. / ■■    rot2: .■ / ■■    rot3: ■■ / .■
	match rot % 4:
		0:
			return [Vector2i(c, r), Vector2i(c + 1, r), Vector2i(c, r + 1)]
		1:
			return [Vector2i(c, r), Vector2i(c, r + 1), Vector2i(c + 1, r + 1)]
		2:
			return [Vector2i(c + 1, r), Vector2i(c, r + 1), Vector2i(c + 1, r + 1)]
		_:
			return [Vector2i(c, r), Vector2i(c + 1, r), Vector2i(c + 1, r + 1)]

func _cav_foot(c: int, r: int) -> Array:
	## T of 4: base (c,r)(c+1,r)(c+2,r); stem forward from centre toward enemy (c+1, r+1)
	return [Vector2i(c, r), Vector2i(c + 1, r), Vector2i(c + 2, r), Vector2i(c + 1, r + 1)]

func _footprints_for_kind(kind: String) -> Array:
	## Returns Array of {"anchor": Vector2i, "cells": Array[Vector2i]}
	var out: Array = []
	if kind == "champion":
		# CENTRAL mid-box (open pillar rect) on player half — Apprentice attaches on place
		for r in range(MID_BOX_Y0, MID_BOX_Y1 + 1):
			if not _on_player_half(r):
				continue
			for c in range(MID_BOX_X0, MID_BOX_X1 + 1):
				var pos := Vector2i(c, r)
				if not _in_mid_box(pos):
					continue
				if _piece_at(pos) != null:
					continue
				if _terrain_blocks(pos, PType.CHAMPION):
					continue
				# Prefer cells that still have room for apprentice attach
				var off := _apprentice_attach_offset(true)
				var ap := Vector2i(pos.x + off.x, pos.y + off.y)
				var attach_ok := _in_mid_box(ap) and _on_player_half(ap.y) and _piece_at(ap) == null and not _terrain_blocks(ap, PType.APPRENTICE)
				if not attach_ok:
					# still allow if any mid-box neighbour free
					attach_ok = false
					for d2 in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
						var q := Vector2i(pos.x + d2.x, pos.y + d2.y)
						if _in_mid_box(q) and _on_player_half(q.y) and _piece_at(q) == null and not _terrain_blocks(q, PType.APPRENTICE):
							attach_ok = true
							break
				if not attach_ok:
					continue
				out.append({"anchor": pos, "cells": [pos]})
		return out
	for r in range(ROWS):
		if not _on_player_half(r):
			continue
		for c in range(COLS):
			match kind:
				"infantry":
					var foot_i := _inf_h_foot(c, r)
					if _cells_empty_and_half(foot_i) and _foot_clear_of_blockers(foot_i, PType.INFANTRY):
						out.append({"anchor": Vector2i(c, r), "cells": foot_i})
				"archer":
					var foot_a := _arch_l_foot(c, r, _place_arch_rot)
					if _cells_empty_and_half(foot_a) and _foot_clear_of_blockers(foot_a, PType.ARCHER):
						out.append({"anchor": Vector2i(c, r), "cells": foot_a})
				"cavalry":
					var foot_c := _cav_foot(c, r)
					if _cells_empty_and_half(foot_c) and _foot_clear_of_blockers(foot_c, PType.CAVALRY):
						out.append({"anchor": Vector2i(c, r), "cells": foot_c})
	return out

func _try_place(r: int, c: int) -> void:
	if _place_kind == "" or _fallen:
		return
	var anchor := Vector2i(c, r)
	if not _place_options.has(anchor):
		# allow tap any cell of a footprint
		var found := false
		for a in _place_options.keys():
			var cells: Array = _place_options[a]
			for p in cells:
				if p == anchor:
					anchor = a
					found = true
					break
			if found:
				break
		if not found:
			_show_toast("Tap a glowing footprint.")
			return
	var cells2: Array = _place_options[anchor]
	if cells2.is_empty():
		return
	match _place_kind:
		"infantry":
			if _pool_inf >= 2:
				if _inf_pair_pending.is_empty():
					_inf_pair_pending = cells2.duplicate()
					_show_toast("Infantry 1/2 — tap the second line")
					_status.text = "Infantry pair — tap 2nd H line (pool %d)" % _pool_inf
					_place_options.erase(anchor)
					var drop: Array = []
					for a2 in _place_options.keys():
						var overlap := false
						for p2 in _place_options[a2]:
							for p1 in _inf_pair_pending:
								if p2 == p1:
									overlap = true
									break
							if overlap:
								break
						if overlap:
							drop.append(a2)
					for d in drop:
						_place_options.erase(d)
					_refresh()
					return
				_place_regiment(_inf_pair_pending, PType.INFANTRY, true, "H")
				_place_regiment(cells2, PType.INFANTRY, true, "H")
				_pool_inf -= 2
				_inf_pair_pending.clear()
			else:
				_place_regiment(cells2, PType.INFANTRY, true, "H")
				_pool_inf -= 1
				_inf_pair_pending.clear()
		"archer":
			_place_regiment(cells2, PType.ARCHER, true, "L")
			_pool_arch -= 1
		"cavalry":
			_place_regiment(cells2, PType.CAVALRY, true, "T")
			_pool_cav -= 1
		"champion":
			var pos: Vector2i = cells2[0]
			if not _in_mid_box(pos) or not _on_player_half(pos.y):
				_show_toast("Champion MUST start in the CENTRAL mid-box.")
				return
			_board[pos.y][pos.x] = _mk(PType.CHAMPION, true)
			var ap := _place_apprentice_beside_champ(pos, true)
			if ap.x >= 0:
				_show_toast("Champion + Apprentice seated (back-left attach).", 1.8)
			else:
				_show_toast("Champion placed — no free mid-box cell for Apprentice.", 2.0)
			_pool_champ -= 1
		_:
			return
	_placements_done += 1
	_advance_deploy_stage_after(_place_kind)
	_place_kind = ""
	_place_options.clear()
	_highlights.clear()
	_show_toast("Placed. Stage → %s" % _deploy_stage)
	_status.text = "Deploy Inf→Arch→Cav→Hero then Begin · now %s · I%d A%d C%d H%d" % [_deploy_stage, _pool_inf, _pool_arch, _pool_cav, _pool_champ]
	_refresh()

func _piece_at(pos: Vector2i):
	if pos.y < 0 or pos.y >= ROWS or pos.x < 0 or pos.x >= COLS:
		return null
	return _board[pos.y][pos.x]

func _damage_at(pos: Vector2i, amount: int) -> bool:
	## Chip one figure's HP. Figure removed only when ITS hp hits 0.
	## Remaining regiment members keep their own HP; formation packs tighter.
	var p = _piece_at(pos)
	if p == null or int(p["type"]) == PType.TOWER or int(p["type"]) == PType.OAK:
		return false
	# Oak follow: druids IMMUNE only on the opponent's turn after an oak shift
	if int(p["type"]) == PType.DRUID:
		if bool(p["friend"]) and _druid_immune_friend:
			_flash_hit(pos, false)
			_show_toast("Your druids are IMMUNE (oak follow).", 1.2)
			return false
		if (not bool(p["friend"])) and _druid_immune_enemy:
			_flash_hit(pos, false)
			return false
	_flash_hit(pos, amount >= 2)
	var hp := int(p.get("hp", _piece_max_hp(p))) - amount
	p["hp"] = hp
	if hp <= 0:
		var was_gen := int(p["type"]) == PType.GENERAL and bool(p["friend"])
		var was_enemy_gen := int(p["type"]) == PType.GENERAL and not bool(p["friend"])
		var rid := _reg_id_of(p)
		_board[pos.y][pos.x] = null
		if rid != "":
			_compact_regiment(rid)
			if _selected_reg == rid and _regiment_cells(rid).is_empty():
				_clear_selection()
		if was_gen:
			_trigger_fallen()
		elif was_enemy_gen:
			_trigger_victory()
		else:
			_check_match_end()
		return true
	_check_match_end()
	return false

func _compact_regiment(reg_id: String) -> void:
	## After a member dies, pack remaining figures adjacent (line/block shrinks).
	var cells: Array = _regiment_cells(reg_id)
	if cells.size() <= 1:
		return
	var orient := _regiment_orient(reg_id)
	# Snapshot pieces
	var members: Array = []
	for pos in cells:
		members.append({"pos": pos, "piece": _board[pos.y][pos.x].duplicate()})
	# Clear old cells
	for pos in cells:
		_board[pos.y][pos.x] = null
	var packed: Array = _pack_positions(cells, orient)
	for i in range(members.size()):
		var np: Vector2i = packed[i]
		_board[np.y][np.x] = members[i]["piece"]
	# Keep selection on a living member if this regiment was selected
	if _selected_reg == reg_id and not packed.is_empty():
		_selected = packed[0]

func _pack_positions(old_cells: Array, orient: String) -> Array:
	## Return contiguous positions for remaining count, anchored near old min corner.
	var n := old_cells.size()
	if n == 0:
		return []
	var min_x := 99
	var min_y := 99
	var max_x := -1
	var max_y := -1
	for pos in old_cells:
		var p: Vector2i = pos
		min_x = mini(min_x, p.x)
		min_y = mini(min_y, p.y)
		max_x = maxi(max_x, p.x)
		max_y = maxi(max_y, p.y)
	var out: Array = []
	match orient:
		"H":
			# Horizontal line of n, keep row of majority / min_y
			var row := min_y
			for i in range(n):
				out.append(Vector2i(min_x + i, row))
		"V":
			var col := min_x
			for i in range(n):
				out.append(Vector2i(col, min_y + i))
		"2x2", "L":
			# Pack remaining into fixed L: 2 on base row + stem if n==3
			if n == 1:
				out.append(Vector2i(min_x, min_y))
			elif n == 2:
				out.append(Vector2i(min_x, min_y))
				out.append(Vector2i(min_x + 1, min_y))
			else:
				out.append(Vector2i(min_x, min_y))
				out.append(Vector2i(min_x + 1, min_y))
				out.append(Vector2i(min_x, min_y + 1))
		"T":
			# Keep T of 4 truncated: base row first, then centre stem if room
			if n == 1:
				out.append(Vector2i(min_x, min_y))
			elif n == 2:
				out.append(Vector2i(min_x, min_y))
				out.append(Vector2i(min_x + 1, min_y))
			elif n == 3:
				out.append(Vector2i(min_x, min_y))
				out.append(Vector2i(min_x + 1, min_y))
				out.append(Vector2i(min_x + 2, min_y))
			else:
				out.append(Vector2i(min_x, min_y))
				out.append(Vector2i(min_x + 1, min_y))
				out.append(Vector2i(min_x + 2, min_y))
				out.append(Vector2i(min_x + 1, min_y + 1))
		_:
			# Fallback: horizontal pack
			for i in range(n):
				out.append(Vector2i(min_x + i, min_y))
	# Clamp / shift onto board if pack ran off
	var shift_x := 0
	var shift_y := 0
	for pos in out:
		var p: Vector2i = pos
		if p.x >= COLS:
			shift_x = mini(shift_x, COLS - 1 - p.x)
		if p.x < 0:
			shift_x = maxi(shift_x, -p.x)
		if p.y >= ROWS:
			shift_y = mini(shift_y, ROWS - 1 - p.y)
		if p.y < 0:
			shift_y = maxi(shift_y, -p.y)
	if shift_x != 0 or shift_y != 0:
		var shifted: Array = []
		for pos in out:
			var p: Vector2i = pos
			shifted.append(Vector2i(p.x + shift_x, p.y + shift_y))
		out = shifted
	return out

func _can_translate(cells: Array, delta: Vector2i) -> bool:
	## All members can shift by delta onto empty / own-footprint cells (walls/oaks/gaps enforced).
	if cells.is_empty():
		return false
	var occupied: Dictionary = {}
	for pos in cells:
		occupied[pos] = true
	var sample = _piece_at(cells[0])
	var mover_type := int(sample["type"]) if sample != null else -1
	# Champion unstoppable vs shield/inf but still blocked by G/Champ/oak/pillar/wall
	for pos in cells:
		var p: Vector2i = pos
		var np := Vector2i(p.x + delta.x, p.y + delta.y)
		if np.x < 0 or np.x >= COLS or np.y < 0 or np.y >= ROWS:
			return false
		if _walls.has(np):
			return false
		if _archer_gaps.has(np) and mover_type != PType.ARCHER:
			return false
		var dest = _piece_at(np)
		if dest == null:
			continue
		if occupied.has(np):
			continue
		var dt := int(dest["type"])
		if dt == PType.TOWER or dt == PType.OAK:
			return false
		# cannot enter other pieces
		return false
	return true

func _translate_cells(cells: Array, delta: Vector2i) -> Array:
	## Move all pieces by delta. Returns new cell list.
	var snaps: Array = []
	for pos in cells:
		var p: Vector2i = pos
		snaps.append({"pos": p, "piece": _board[p.y][p.x]})
		_board[p.y][p.x] = null
	var new_cells: Array = []
	for s in snaps:
		var p: Vector2i = s["pos"]
		var np := Vector2i(p.x + delta.x, p.y + delta.y)
		_board[np.y][np.x] = s["piece"]
		new_cells.append(np)
	return new_cells

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _orthogonal_neighbors(from: Vector2i) -> Array:
	## N/E/S/W only.
	var out: Array = []
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		out.append(Vector2i(from.x + d.x, from.y + d.y))
	return out

func _chebyshev_neighbors(from: Vector2i) -> Array:
	## All 8 directions (Chebyshev d==1).
	var out: Array = []
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			out.append(Vector2i(from.x + dc, from.y + dr))
	return out


func _find_side_unit(ptype: int, friend: bool) -> Vector2i:
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p != null and int(p["type"]) == ptype and bool(p["friend"]) == friend:
				return Vector2i(c, r)
	return Vector2i(-1, -1)


func _champ_auto_shove_front(friend: bool) -> void:
	## LOCKED: Champion auto-shoves enemies IN FRONT (same file, toward enemy).
	## Pushes foe further along the file when free — matches rail shove feel. Both sides.
	var champ := _find_side_unit(PType.CHAMPION, friend)
	if champ.x < 0:
		return
	var fwd := _forward_delta_for(friend)
	var file := champ.x
	var shoved := 0
	for dist in range(1, ROWS):
		var ry := champ.y + fwd * dist
		if ry < 0 or ry >= ROWS:
			break
		var q := Vector2i(file, ry)
		var en = _piece_at(q)
		if en == null:
			continue
		if bool(en["friend"]) == friend:
			continue
		var et := int(en["type"])
		if et == PType.TOWER or et == PType.OAK:
			break
		# Adjacent in front (dist==1) or any foe still on file ahead during resolve
		var shove_to := Vector2i(file, q.y + fwd)
		if shove_to.y < 0 or shove_to.y >= ROWS:
			continue
		if _piece_at(shove_to) != null or _walls.has(shove_to):
			continue
		if _archer_gaps.has(shove_to):
			continue
		var piece = _board[q.y][q.x]
		if piece == null:
			continue
		_board[q.y][q.x] = null
		_board[shove_to.y][shove_to.x] = piece
		_flash_hit(shove_to, true)
		shoved += 1
	if shoved > 0:
		_show_toast(("Your" if friend else "Enemy") + " Champion shoves front!", 1.3)


func _apprentice_catch_rear(friend: bool) -> void:
	## LOCKED: if an enemy gets BEHIND the Champ/Apprentice pair (rear vs facing
	## toward enemy), Apprentice CATCHES and HOLDS them (trap≥1). Both sides.
	## Melee chip is separate — standard infantry 8-adj in _regiment_chip.
	var champ := _find_side_unit(PType.CHAMPION, friend)
	var app := _find_side_unit(PType.APPRENTICE, friend)
	if app.x < 0:
		return
	var fwd := _forward_delta_for(friend)
	var rear_edge := app.y
	if champ.x >= 0:
		# Rear edge of the pair = further-back of Champ/App along facing
		if (champ.y - app.y) * fwd < 0:
			rear_edge = champ.y
		else:
			rear_edge = app.y
	var pinned := 0
	for r in range(ROWS):
		for c in range(COLS):
			var pos := Vector2i(c, r)
			var en2 = _piece_at(pos)
			if en2 == null or bool(en2["friend"]) == friend:
				continue
			var et2 := int(en2["type"])
			if et2 == PType.TOWER or et2 == PType.OAK:
				continue
			# Behind the pair: strictly rearward of rear_edge
			if (pos.y - rear_edge) * fwd >= 0:
				continue
			# Catch: Chebyshev-adj to Apprentice (primary) — also adj Champ hugging rear
			var near_app := _chebyshev(app, pos) == 1
			var near_champ := champ.x >= 0 and _chebyshev(champ, pos) == 1
			if not near_app and not near_champ:
				continue
			if champ.x >= 0 and (pos.y - champ.y) * fwd > 0:
				continue  # not ahead of Champ
			en2["trap"] = maxi(int(en2.get("trap", 0)), 1)
			pinned += 1
	if pinned > 0:
		_show_toast(("Your" if friend else "Enemy") + " Apprentice catch — hold!", 1.4)


func _regiment_chip(cells: Array) -> void:
	## Each FIGURE hits 1 foe in 8-adjacent. If Champion in 8-adj MUST hit him; else lowest HP.
	## Cav charge 2× (unless Inf line-of-3 strips). Archers: no charge dmg (ranged auto elsewhere).
	## Champ deals 2×. Druid colour_buff deals 2×. Champ unstoppable vs shield wall.
	if cells.is_empty():
		return
	var first = _piece_at(cells[0])
	if first == null:
		return
	var friend: bool = bool(first["friend"])
	var struck := 0
	var any_kill := false
	var last_name := "foe"
	var last_left := 0
	for pos in cells:
		var pcell = _piece_at(pos)
		if pcell == null:
			continue
		var pt: int = int(pcell["type"])
		if pt == PType.TOWER or pt == PType.OAK:
			continue
		# Archers do not melee-chip here (auto-fire ranged handles them)
		if pt == PType.ARCHER:
			continue
		# Druids: NO auto-attack — only Earth/Fire/Water/Holy via panel
		if pt == PType.DRUID:
			continue
		var foes := _foes_in_8(pos, friend)
		if foes.is_empty():
			continue
		var tgt: Vector2i = _pick_combat_target(foes)
		var before = _piece_at(tgt)
		if before == null:
			continue
		last_name = _ptype_name(int(before["type"]))
		var dmg := 1
		# Champion base 2× dmg
		if pt == PType.CHAMPION:
			dmg = 2
		# Cav charge 2× unless shield wall strips (Inf line-of-3) — Champ ignores strip
		if pt == PType.CAVALRY:
			var charged := _charge_ids.has(str(pcell.get("id", ""))) or _charge_ids.has(_reg_id_of(pcell))
			if charged:
				if pt != PType.CHAMPION and _shield_wall_vs(pos, tgt, friend):
					dmg = 1  # stripped
				else:
					dmg = 2
		var killed := _damage_at(tgt, dmg)
		struck += 1
		if killed:
			any_kill = true
		else:
			var left_p = _piece_at(tgt)
			last_left = int(left_p.get("hp", 0)) if left_p else 0
	if struck == 1:
		if any_kill:
			_show_toast("Struck %s — fallen!" % last_name)
		else:
			_show_toast("Struck %s — HP %d" % [last_name, last_left])
	elif struck > 1:
		_show_toast("Engagement — %d blows%s" % [struck, " (kills)" if any_kill else ""])
	# Champ / Apprentice team locks — only when that unit is among this resolve's figures
	var saw_champ := false
	var saw_app := false
	for pos2 in cells:
		var pc2 = _piece_at(pos2)
		if pc2 == null:
			continue
		var pt2 := int(pc2["type"])
		if pt2 == PType.CHAMPION:
			saw_champ = true
		elif pt2 == PType.APPRENTICE:
			saw_app = true
	if saw_champ:
		_champ_auto_shove_front(friend)
	if saw_app:
		_apprentice_catch_rear(friend)

func _enemies_in_chip_range(from: Vector2i, t: int, friend: bool) -> Array:
	## Legacy helper — archers ranged; others 8-adj list (combat picks one).
	if t == PType.ARCHER:
		var out: Array = []
		for r in range(maxi(0, from.y - 2), mini(ROWS, from.y + 3)):
			for c in range(maxi(0, from.x - 2), mini(COLS, from.x + 3)):
				var to := Vector2i(c, r)
				if to == from:
					continue
				var d := _chebyshev(from, to)
				if d < 1 or d > 2:
					continue
				var dest = _piece_at(to)
				if dest == null or int(dest["type"]) == PType.TOWER or int(dest["type"]) == PType.OAK:
					continue
				if bool(dest["friend"]) == friend:
					continue
				out.append(to)
		return out
	return _foes_in_8(from, friend)


func _foes_in_8(from: Vector2i, friend: bool) -> Array:
	var out: Array = []
	for to in _chebyshev_neighbors(from):
		var dest = _piece_at(to)
		if dest == null:
			continue
		var dt := int(dest["type"])
		if dt == PType.TOWER or dt == PType.OAK:
			continue
		if bool(dest["friend"]) == friend:
			continue
		out.append(to)
	return out

func _pick_combat_target(foes: Array) -> Vector2i:
	## Champion in 8-adj MUST be hit (duel); else lowest HP.
	var champ_tgts: Array = []
	for f in foes:
		var p = _piece_at(f)
		if p != null and int(p["type"]) == PType.CHAMPION:
			champ_tgts.append(f)
	if not champ_tgts.is_empty():
		return champ_tgts[0]
	var best: Vector2i = foes[0]
	var best_hp := 999
	for f2 in foes:
		var p2 = _piece_at(f2)
		if p2 == null:
			continue
		var hp := int(p2.get("hp", 99))
		if hp < best_hp:
			best_hp = hp
			best = f2
	return best

func _shield_wall_vs(attacker: Vector2i, target: Vector2i, atk_friend: bool) -> bool:
	## Inf line-of-3 strips charge bonus only. Check if target (or its regiment) forms line-of-3 INF.
	var tp = _piece_at(target)
	if tp == null or int(tp["type"]) != PType.INFANTRY:
		return false
	if bool(tp["friend"]) == atk_friend:
		return false
	var rid := _reg_id_of(tp)
	var cells: Array = _regiment_cells(rid) if rid != "" else [target]
	if cells.size() < 3:
		# also check orthogonal friend-inf neighbours forming 3
		var line = _count_inf_line_through(target, bool(tp["friend"]))
		return line >= 3
	return true

func _count_inf_line_through(pos: Vector2i, friend: bool) -> int:
	## Count contiguous infantry along row or col through pos.
	var best := 1
	for axis in ["h", "v"]:
		var n := 1
		for dir in [-1, 1]:
			var step := 1
			while true:
				var q := Vector2i(pos.x + (dir * step if axis == "h" else 0), pos.y + (dir * step if axis == "v" else 0))
				var p = _piece_at(q)
				if p == null or int(p["type"]) != PType.INFANTRY or bool(p["friend"]) != friend:
					break
				n += 1
				step += 1
		best = maxi(best, n)
	return best

func _post_action_chip(from: Vector2i) -> void:
	## Solo wrapper — same multi-target rules as regiment chip.
	_regiment_chip([from])

func _try_move_select(r: int, c: int) -> void:
	var pos := Vector2i(c, r)
	var piece = _board[r][c]

	if _cavalry_steps_left > 0:
		_continue_cavalry(pos)
		return

	if _archer_aiming and (_selected.x >= 0 or _selected_reg != ""):
		_try_archer_attack(pos)
		return

	# Oaks: either side may select to shift (FULL TURN) within roam zone.
	if piece != null and int(piece["type"]) == PType.OAK:
		if _oak_turn_spent or not _moved_ids.is_empty() or not _cav_free_used.is_empty():
			_show_toast("Oak shift needs a fresh turn (no units acted) — costs full turn.")
			return
		_selected = pos
		_selected_reg = _reg_id_of(piece)
		_oak_shifting = true
		_archer_aiming = false
		_hide_druid_panel()
		_status.text = "Oak — tap glow in roam zone (FULL TURN; then foe-turn immune, next-turn disable)"
		_rebuild_highlights()
		_refresh()
		return

	if piece != null and bool(piece["friend"]) and int(piece["type"]) != PType.TOWER:
		if _oak_turn_spent:
			_show_toast("Oak used this turn — End turn.")
			return
		if int(piece["type"]) == PType.DRUID and _druid_skip_friend:
			_show_toast("Druids DISABLED this turn (oak follow).")
			return
		if int(piece.get("trap", 0)) > 0:
			_show_toast("Trapped by Earth — %d turn(s) left." % int(piece.get("trap", 0)))
			return
		var aid := _actor_id_for_piece(piece, pos)
		var t0: int = int(piece["type"])
		# Once-per-unit (cav free once/turn, multi-step OK — still once).
		if _moved_ids.has(aid) or (t0 == PType.CAVALRY and _cav_free_used.has(aid)):
			_show_toast("That unit already acted this turn.")
			return
		_selected = pos
		_selected_reg = _reg_id_of(piece)
		_archer_aiming = (int(piece["type"]) == PType.ARCHER)
		var t: int = int(piece["type"])
		var n_mem := _regiment_cells(_selected_reg).size() if _selected_reg != "" else 1
		if t == PType.DRUID:
			_show_druid_panel()
			_status.text = "Druid — tap Earth / Fire / Water / Holy below. No auto-attack."
		else:
			_hide_druid_panel()
		if t == PType.GENERAL:
			_status.text = "YOU (General) — tap glowing square to move"
		elif t == PType.ARCHER:
			_status.text = "Archer regiment (%d) — green = move; auto-fire each turn" % n_mem
		elif t == PType.CAVALRY:
			_status.text = "Cavalry (%d) — free once/turn; up to 3 steps; Cancel ends early" % n_mem
		elif t == PType.CHAMPION:
			_status.text = "Champion — file fwd/back; L/R if fwd blocked (non-unit); front shove; rail"
		elif t == PType.APPRENTICE:
			_status.text = "Champ's Apprentice — 1 step; rear catch/hold; infantry melee chip"
		elif t == PType.INFANTRY:
			_status.text = "Infantry regiment (%d) — whole line moves together" % n_mem
		elif t != PType.DRUID:
			_status.text = "%s — tap a glowing square" % _ptype_name(t)
		return

	if _selected.x < 0 and _selected_reg == "":
		_hide_druid_panel()
		_show_toast("Tap one of YOUR regiments / heroes / an oak first.")
		return
	if _oak_shifting:
		_try_commit_oak_shift(pos)
		return
	_attempt_move(_selected, pos)

func _active_move_cells() -> Array[Vector2i]:
	## Cells that translate together this activation.
	var out: Array[Vector2i] = []
	if _selected_reg != "":
		for pos in _regiment_cells(_selected_reg):
			out.append(pos as Vector2i)
		return out
	if _selected.x >= 0:
		out.append(_selected)
		return out
	return out

func _continue_cavalry(to: Vector2i) -> void:
	## Whole cavalry regiment steps one Chebyshev square as a rigid body.
	var cells := _active_move_cells()
	if cells.is_empty():
		cells = [_cavalry_pos]
	var delta := Vector2i(to.x - _cavalry_pos.x, to.y - _cavalry_pos.y)
	if _chebyshev(Vector2i(0, 0), delta) != 1 or not _can_translate(cells, delta):
		var found := false
		for pos in cells:
			var d := Vector2i(to.x - pos.x, to.y - pos.y)
			if _chebyshev(Vector2i(0, 0), d) == 1 and _can_translate(cells, d):
				delta = d
				found = true
				break
		if not found:
			_show_toast("Cavalry steps one square at a time (whole regiment).")
			return
	var ref: Vector2i = cells[0]
	if not _backward_ok_delta(ref, delta):
		_show_toast("Illegal retreat.")
		return
	var new_cells := _translate_cells(cells, delta)
	_cavalry_pos = new_cells[0]
	_selected = new_cells[0]
	_cavalry_steps_left -= 1
	# Chip after every step so mid-activation adjacency deals 1 HP
	_charge_ids[_actor_id_from_selection()] = true
	_regiment_chip(new_cells)
	if _cavalry_steps_left <= 0:
		_clear_selection()
		_show_toast("Cavalry activation done.")
		_status.text = "Once-per-unit — tap a regiment"
	else:
		_status.text = "Cavalry steps left: %d · Cancel cavalry to end early" % _cavalry_steps_left

func _archer_can_hit(cells: Array, target: Vector2i) -> bool:
	for pos in cells:
		var d := _chebyshev(pos, target)
		if d >= 1 and d <= 2:
			return true
	return false

func _try_archer_attack(target: Vector2i) -> void:
	var cells := _active_move_cells()
	var occ = _piece_at(target)
	if occ == null or bool(occ["friend"]) or int(occ["type"]) == PType.TOWER:
		_archer_aiming = false
		var from: Vector2i = _selected if _selected.x >= 0 else (cells[0] as Vector2i if not cells.is_empty() else Vector2i(-1, -1))
		_attempt_move(from, target)
		return
	if not _archer_can_hit(cells, target):
		_show_toast("Archer range is 1–2 from any figure in the block.")
		return
	var piece0 = _piece_at(cells[0]) if not cells.is_empty() else null
	var aid := _actor_id_for_piece(piece0, cells[0]) if piece0 else ""
	if aid == "" or not _commit_activation_cost(aid, PType.ARCHER):
		return
	var name := _ptype_name(int(occ["type"]))
	var killed := _damage_at(target, 1)
	_clear_selection()
	if _fallen:
		return
	if killed:
		_show_toast("Archer volley — %s fallen!" % name)
	else:
		_show_toast("Archer volley — %s wounded" % name)
	_status.text = "Once-per-unit — tap a regiment"

func _forward_delta_for(friend: bool) -> int:
	return 1 if friend else -1

func _is_backwards(from: Vector2i, to: Vector2i, friend: bool) -> bool:
	var fwd := _forward_delta_for(friend)
	return (to.y - from.y) * fwd < 0

func _backward_ok(from: Vector2i, to: Vector2i) -> bool:
	## No queen / no retreat aura — backward always allowed (locked sheet).
	return true

func _backward_ok_delta(from: Vector2i, delta: Vector2i) -> bool:
	## Check backwards using piece still at `from` before translate.
	return _backward_ok(from, Vector2i(from.x + delta.x, from.y + delta.y))

func _king_adj(from: Vector2i, to: Vector2i) -> bool:
	return _chebyshev(from, to) == 1

func _commit_activation_cost(aid: String, t: int) -> bool:
	## Once-per-unit/regiment. Cav free once/turn (multi-step OK). Oak full-turn lock.
	if _oak_turn_spent:
		_show_toast("Oak used this turn — End turn.")
		return false
	if aid == "":
		return false
	if _moved_ids.has(aid) or (t == PType.CAVALRY and _cav_free_used.has(aid)):
		_show_toast("That unit already acted this turn.")
		return false
	if t == PType.CAVALRY:
		_cav_free_used[aid] = true
	_moved_ids[aid] = true
	return true

func _attempt_move(from: Vector2i, to: Vector2i) -> void:
	var cells := _active_move_cells()
	if cells.is_empty() and from.x >= 0:
		cells = [from]
	if cells.is_empty():
		return
	var piece = _piece_at(cells[0])
	if piece == null:
		piece = _piece_at(from)
	if piece == null:
		return
	var t: int = int(piece["type"])
	var aid := _actor_id_for_piece(piece, cells[0])
	var dest = _piece_at(to)

	# Archer shoot at enemy in range of ANY regiment member (does not move)
	if t == PType.ARCHER and dest != null and not bool(dest["friend"]) and int(dest["type"]) != PType.TOWER and int(dest["type"]) != PType.OAK:
		if _archer_can_hit(cells, to):
			if not _commit_activation_cost(aid, t):
				return
			var name := _ptype_name(int(dest["type"]))
			var killed := _damage_at(to, 1)
			_clear_selection()
			if _fallen:
				return
			if killed:
				_show_toast("Archer volley — %s fallen!" % name)
			else:
				_show_toast("Archer volley — %s wounded" % name)
			_status.text = "Once-per-unit — tap a regiment"
			return
		_show_toast("Out of archer range.")
		return

	var delta := Vector2i(to.x - from.x, to.y - from.y)
	if from.x < 0:
		delta = Vector2i(to.x - cells[0].x, to.y - cells[0].y)
	if not (_move_delta_legal(cells, delta, piece, t) and _can_translate(cells, delta)):
		var matched := false
		for pos in cells:
			var d := Vector2i(to.x - pos.x, to.y - pos.y)
			if _move_delta_legal(cells, d, piece, t) and _can_translate(cells, d):
				delta = d
				matched = true
				break
		if not matched:
			var on_own := false
			for p in cells:
				if p == to:
					on_own = true
					break
			if dest != null and not on_own:
				_show_toast("Cannot enter occupied — move adjacent; combat resolves automatically.")
			else:
				_show_toast(_move_hint(t))
			return

	var ref: Vector2i = cells[0]
	if not _backward_ok_delta(ref, delta):
		_show_toast("Illegal retreat.")
		return

	if not _commit_activation_cost(aid, t):
		return

	# Mark cav charge for this activation
	if t == PType.CAVALRY:
		_charge_ids[aid] = true
		_charge_ids[str(piece.get("id", ""))] = true

	# Champion rail of terror when stepping toward enemy
	if t == PType.CHAMPION:
		_champ_rail_from = ref
		_champ_rail_to = Vector2i(ref.x + delta.x, ref.y + delta.y)

	# Druid colour-flip: 1 orthogonal → double strength
	if t == PType.DRUID and (absi(delta.x) + absi(delta.y)) == 1 and not (absi(delta.x) == absi(delta.y)):
		piece["colour_buff"] = 2
		_show_toast("Druid colour-switch — double strength!")

	match t:
		PType.GENERAL, PType.QUEEN, PType.DRUID, PType.ARCHER, PType.INFANTRY, PType.CHAMPION, PType.APPRENTICE:
			var new_cells := _translate_cells(cells, delta)
			if t == PType.CHAMPION:
				_apply_champ_rail(new_cells[0], bool(piece["friend"]))
			_regiment_chip(new_cells)
			_clear_selection()
			_hide_druid_panel()
			_status.text = "Once-per-unit — tap a regiment"
		PType.CAVALRY:
			var new_cells2 := _translate_cells(cells, delta)
			_cavalry_steps_left = maxi(CAVALRY_STEPS - 1, 0)
			_cavalry_pos = new_cells2[0]
			_selected = new_cells2[0]
			_regiment_chip(new_cells2)
			if _cavalry_steps_left <= 0:
				_clear_selection()
				_show_toast("Cavalry activation done — auto engagement.")
				_status.text = "Once-per-unit — tap a regiment"
			else:
				_status.text = "Cavalry steps left: %d · Cancel cavalry to end early" % _cavalry_steps_left
		_:
			_show_toast("Cannot move that.")


func _apply_champ_rail(champ_pos: Vector2i, friend: bool) -> void:
	## Rail of terror: when stepping toward enemy, foes on same file within 2 take 1 dmg + shove.
	if _champ_rail_from.x < 0:
		return
	var fwd := _forward_delta_for(friend)
	var dy := champ_pos.y - _champ_rail_from.y
	# Only when stepping toward enemy
	if dy * fwd <= 0:
		_champ_rail_from = Vector2i(-1, -1)
		return
	var file := champ_pos.x
	for dist in [1, 2]:
		var q := Vector2i(file, champ_pos.y + fwd * dist)
		var en = _piece_at(q)
		if en == null:
			continue
		if bool(en["friend"]) == friend:
			continue
		var et := int(en["type"])
		if et == PType.TOWER or et == PType.OAK:
			break
		_damage_at(q, 1)
		# shove one further along file if free
		var shove := Vector2i(file, q.y + fwd)
		if shove.y >= 0 and shove.y < ROWS and _piece_at(shove) == null and not _walls.has(shove):
			var piece = _board[q.y][q.x]
			if piece != null:
				_board[q.y][q.x] = null
				_board[shove.y][shove.x] = piece
				_flash_hit(shove, true)
	_champ_rail_from = Vector2i(-1, -1)
	_show_toast("Champion — rail of terror!")

func _move_hint(t: int) -> String:
	match t:
		PType.INFANTRY:
			return "Infantry: shift 1 any way, or double-advance forward if clear."
		PType.CAVALRY:
			return "Cavalry: free move/turn — start with a 1-square step (whole T)."
		PType.DRUID:
			return "Druid: Earth/Fire/Water (CD 1) · Holy heal (CD 5). No auto-attack."
		PType.APPRENTICE:
			return "Champ's Apprentice: 1 step; rear catch/hold (pin); infantry melee chip."
		PType.CHAMPION:
			return "Champion: file fwd/back; L/R if fwd blocked (non-unit); auto-shove foes in front."
		_:
			return "That unit moves 1 square (like a king)."

func _champ_forward_blocked_by_non_unit(from: Vector2i, friend: bool) -> bool:
	## True if the square ahead is edge / pillar / oak / wall — not a unit.
	## Far end row can't go forward → sidestep OK. Unit ahead → no sidestep grant.
	var fwd := _forward_delta_for(friend)
	var np := Vector2i(from.x, from.y + fwd)
	if np.x < 0 or np.x >= COLS or np.y < 0 or np.y >= ROWS:
		return true
	if _walls.has(np):
		return true
	if _archer_gaps.has(np):
		return true
	var dest = _piece_at(np)
	if dest == null:
		return false
	var dt := int(dest["type"])
	if dt == PType.TOWER or dt == PType.OAK:
		return true
	return false  # unit in front — shove/unstoppable, not sidestep

func _move_delta_legal(cells: Array, delta: Vector2i, piece: Dictionary, t: int) -> bool:
	if delta == Vector2i(0, 0):
		return false
	if not _can_translate(cells, delta):
		return false
	var step := _chebyshev(Vector2i(0, 0), delta)
	match t:
		PType.DRUID:
			return _druid_move_delta_legal(cells[0], delta, bool(piece["friend"]))
		PType.CHAMPION:
			# File forward/back always. Sidestep L/R only when FORWARD is blocked by
			# non-unit (edge / tower / oak / terrain) — NOT when a unit is in front.
			if delta.x == 0 and absi(delta.y) == 1:
				return true
			if absi(delta.x) == 1 and delta.y == 0:
				return _champ_forward_blocked_by_non_unit(cells[0], bool(piece["friend"]))
			return false
		PType.GENERAL, PType.QUEEN, PType.ARCHER, PType.APPRENTICE:
			return step == 1
		PType.CAVALRY:
			return step == 1
		PType.INFANTRY:
			if step == 1:
				return true
			var fwd := _forward_delta_for(bool(piece["friend"]))
			if delta.x != 0 or delta.y != fwd * 2:
				return false
			var mid_d := Vector2i(0, fwd)
			return _can_translate(cells, mid_d)
		_:
			return false

func _inf_double_fwd(from: Vector2i, to: Vector2i, piece: Dictionary) -> bool:
	var fwd := _forward_delta_for(bool(piece["friend"]))
	if to.x != from.x:
		return false
	if to.y != from.y + fwd * 2:
		return false
	var mid := Vector2i(from.x, from.y + fwd)
	return _piece_at(mid) == null and _piece_at(to) == null

func _do_step(from: Vector2i, to: Vector2i) -> void:
	_board[to.y][to.x] = _board[from.y][from.x]
	_board[from.y][from.x] = null
	_check_match_end()


func _auto_forward_unacted(friend_side: bool) -> void:
	## End-of-side: unused units step up to AUTO_FORWARD_STEPS (2) legal FORWARD cells toward enemy.
	## Skip blocked. Units that already acted stay. Oaks/towers ignored. Skipped after oak full turn (caller).
	var fwd := _forward_delta_for(friend_side)
	var delta := Vector2i(0, fwd)
	var actors: Array = []
	var seen_reg: Dictionary = {}
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p == null:
				continue
			var pt := int(p["type"])
			if pt == PType.TOWER or pt == PType.OAK:
				continue
			if bool(p["friend"]) != friend_side:
				continue
			if int(p.get("trap", 0)) > 0:
				continue
			if friend_side and pt == PType.DRUID and _druid_skip_friend:
				continue
			if (not friend_side) and pt == PType.DRUID and _druid_skip_enemy:
				continue
			var rid := _reg_id_of(p)
			var cells: Array
			var aid: String
			if rid != "":
				if seen_reg.has(rid):
					continue
				seen_reg[rid] = true
				cells = _regiment_cells(rid)
				if cells.is_empty():
					continue
				aid = "reg:" + rid
			else:
				cells = [Vector2i(c, r)]
				aid = _actor_id_for_piece(p, cells[0])
			# Already acted?
			if friend_side:
				if _moved_ids.has(aid) or (pt == PType.CAVALRY and _cav_free_used.has(aid)):
					continue
			else:
				if _enemy_acted_ids.has(aid) or _enemy_acted_ids.has(_enemy_actor_key({"reg": rid, "pos": cells[0], "type": pt})):
					continue
			actors.append({"cells": cells, "piece": _piece_at(cells[0]), "aid": aid})
	var moved_n := 0
	for a in actors:
		if _match_locked():
			break
		var cells2: Array = a["cells"]
		var piece = a["piece"]
		if piece == null or cells2.is_empty():
			# refresh live cells
			continue
		# Re-resolve live cells (board may have shifted)
		var rid2 := _reg_id_of(piece)
		if rid2 != "":
			cells2 = _regiment_cells(rid2)
		else:
			# find by id
			var found := false
			for r2 in range(ROWS):
				for c2 in range(COLS):
					var q = _board[r2][c2]
					if q != null and str(q.get("id", "")) == str(piece.get("id", "")):
						cells2 = [Vector2i(c2, r2)]
						piece = q
						found = true
						break
				if found:
					break
		if cells2.is_empty() or piece == null:
			continue
		var t: int = int(piece["type"])
		var legal_t := PType.INFANTRY if t == PType.ENEMY_INF else t
		# Druids act via powers — do not auto-march them
		if t == PType.DRUID:
			continue
		var stepped := 0
		for _s in range(AUTO_FORWARD_STEPS):
			# re-resolve live cells each step
			if rid2 != "":
				cells2 = _regiment_cells(rid2)
				piece = _piece_at(cells2[0]) if not cells2.is_empty() else null
			else:
				var found2 := false
				for r3 in range(ROWS):
					for c3 in range(COLS):
						var q3 = _board[r3][c3]
						if q3 != null and str(q3.get("id", "")) == str(piece.get("id", "")):
							cells2 = [Vector2i(c3, r3)]
							piece = q3
							found2 = true
							break
					if found2:
						break
			if cells2.is_empty() or piece == null:
				break
			if not _move_delta_legal(cells2, delta, piece, legal_t):
				break
			if not _can_translate(cells2, delta):
				break
			cells2 = _translate_cells(cells2, delta)
			stepped += 1
		if stepped > 0:
			moved_n += 1
	if moved_n > 0:
		_show_toast(("Your" if friend_side else "Enemy") + " idle units auto-forward ×%d (%d units)." % [AUTO_FORWARD_STEPS, moved_n], 1.6)


func _run_enemy_turn() -> void:
	## Light heuristics AI — once-per-unit (same shared rules), not a 3-order loop.
	## Prefer normal units (inf/arch/cav/champ/druid); oak ONLY when useful as a FULL TURN
	## and never instead of activating the army. Does NOT mirror player.
	_druid_immune_enemy = false
	_druid_skip_enemy = false
	if _oak_follow_enemy == 2:
		_druid_skip_enemy = true
		_oak_follow_enemy = 0
	_druid_immune_friend = false
	if _oak_follow_friend == 1:
		_druid_immune_friend = true
		_oak_follow_friend = 2
	# Clear per-side acted marks for enemy auto-forward tracking
	_enemy_acted_ids.clear()
	# Call Reserve: cooldown only (no order-budget gate)
	_enemy_try_call_reserve()
	var actors: Array = _enemy_actor_list()
	actors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _enemy_actor_priority(a) > _enemy_actor_priority(b)
	)
	var acted := 0
	var acted_keys: Dictionary = {}
	var failed: Array = []
	for i in range(actors.size()):
		if _match_locked():
			break
		var a: Dictionary = actors[i]
		var key := _enemy_actor_key(a)
		if acted_keys.has(key):
			continue
		if _enemy_act_actor(a):
			acted += 1
			acted_keys[key] = true
			_enemy_acted_ids[key] = true
		else:
			failed.append(a)
	# One retry pass for failed actors (still once each)
	if not _match_locked() and not failed.is_empty():
		for a2 in failed:
			if _match_locked():
				break
			var key2 := _enemy_actor_key(a2)
			if acted_keys.has(key2):
				continue
			if _enemy_act_actor(a2):
				acted += 1
				acted_keys[key2] = true
				_enemy_acted_ids[key2] = true
	# Oak: only if NO unit acted AND shift is clearly useful (full turn / ends side)
	if not _match_locked() and acted == 0 and _enemy_try_oak_shift():
		_show_toast("Enemy oak shift (full turn) — your druids immune next; theirs skip after.")
		_druid_skip_enemy = false  # oak turn itself: druids NOT disabled
		_check_match_end()
		return
	# Auto-forward enemy units that did not act (oak full-turn skips this)
	if not _match_locked():
		_auto_forward_unacted(false)
	if acted == 0:
		_show_toast("Enemy holds…")
	else:
		_status.text = "Enemy acted (%d units)…" % acted
	_check_match_end()


func _enemy_actor_priority(actor: Dictionary) -> int:
	## Sort key: HV strikes first, then near HV, then forward threat.
	var rid: String = str(actor.get("reg", ""))
	var from: Vector2i = actor["pos"]
	var cells: Array = _regiment_cells(rid) if rid != "" else [from]
	if cells.is_empty():
		return -999
	var piece = _piece_at(cells[0])
	if piece == null:
		return -999
	var t: int = int(piece["type"])
	var score := 0
	var hv := _enemy_hv_targets()
	# Immediate HV strike
	if t == PType.ARCHER:
		for h in hv:
			if _archer_can_hit(cells, h):
				var hp = _piece_at(h)
				score += 1000 + _enemy_target_priority(int(hp["type"]) if hp else 0)
	else:
		for pos in cells:
			for h in hv:
				if _chebyshev(pos, h) == 1:
					var hp2 = _piece_at(h)
					score += 900 + _enemy_target_priority(int(hp2["type"]) if hp2 else 0)
	# Can step into HV threat this act?
	var best_move := _enemy_best_advance_delta(cells, piece, t)
	if best_move != Vector2i(0, 0):
		var trial: Array = []
		for p in cells:
			trial.append(Vector2i(p.x + best_move.x, p.y + best_move.y))
		for pos2 in trial:
			for h2 in hv:
				if t == PType.ARCHER:
					if _archer_can_hit(trial, h2):
						score += 400
				elif _chebyshev(pos2, h2) == 1:
					score += 500
	# Proximity to HV
	var anchor: Vector2i = cells[0]
	var mind := 99
	for h3 in hv:
		mind = mini(mind, _chebyshev(anchor, h3))
	if mind < 99:
		score += (12 - mind) * 20
	# Type bias: Champion / Cav press; General last
	match t:
		PType.CHAMPION:
			score += 60
		PType.CAVALRY:
			score += 40
		PType.INFANTRY, PType.ENEMY_INF:
			score += 25
		PType.ARCHER:
			score += 20
		PType.DRUID:
			score += 15
		PType.GENERAL:
			score += 5
	return score


func _enemy_actor_key(actor: Dictionary) -> String:
	var rid := str(actor.get("reg", ""))
	if rid != "":
		return "reg:" + rid
	var pos: Vector2i = actor.get("pos", Vector2i(-1, -1))
	var p = _piece_at(pos)
	if p != null:
		return _actor_id_for_piece(p, pos)
	return "solo:%s:%s" % [str(actor.get("type", -1)), str(pos)]


func _enemy_actor_list() -> Array:
	## One entry per regiment (or solo piece). Skip towers / oaks.
	var seen_reg: Dictionary = {}
	var out: Array = []
	for r in range(ROWS):
		for c in range(COLS):
			var p = _board[r][c]
			if p == null or bool(p["friend"]) or int(p["type"]) == PType.TOWER or int(p["type"]) == PType.OAK:
				continue
			if int(p["type"]) == PType.DRUID and _druid_skip_enemy:
				continue
			var rid := _reg_id_of(p)
			if rid != "":
				if seen_reg.has(rid):
					continue
				seen_reg[rid] = true
				out.append({"pos": Vector2i(c, r), "reg": rid, "type": int(p["type"])})
			else:
				out.append({"pos": Vector2i(c, r), "reg": "", "type": int(p["type"])})
	return out


func _enemy_act_actor(actor: Dictionary) -> bool:
	var rid: String = str(actor.get("reg", ""))
	var from: Vector2i = actor["pos"]
	var cells: Array = []
	if rid != "":
		cells = _regiment_cells(rid)
		if cells.is_empty():
			return false
		from = cells[0]
	else:
		var live = _piece_at(from)
		if live == null or bool(live["friend"]):
			return false
		cells = [from]
	var piece = _piece_at(from)
	if piece == null:
		return false
	if int(piece.get("trap", 0)) > 0:
		return false
	var t: int = int(piece["type"])
	# 0) Druids: use Earth/Fire/Water/Holy (parity with player panel kit)
	if t == PType.DRUID:
		if _enemy_try_druid_ability(cells[0]):
			return true
	# 1) Archers: prefer General / Champion, else any shot
	if t == PType.ARCHER:
		if _enemy_try_archer_shot(cells):
			return true
	# 2) Prefer stepping into HV threat over chipping trash
	var hv_move := _enemy_best_hv_approach_delta(cells, piece, t)
	if hv_move != Vector2i(0, 0):
		return _enemy_commit_move(cells, piece, t, hv_move)
	# 3) Already adjacent — chip (combat prefers Champ, else lowest HP)
	var tgts: Array = []
	var seen: Dictionary = {}
	for pos in cells:
		for tgt in _enemies_in_chip_range(pos, t, false):
			if not seen.has(tgt):
				seen[tgt] = true
				tgts.append(tgt)
	if not tgts.is_empty():
		_regiment_chip(cells)
		return true
	# 4) Purposeful advance (threaten / take space)
	return _enemy_advance(cells, piece, t)



func _enemy_try_druid_ability(dpos: Vector2i) -> bool:
	## Mirror player four powers. Oak skip already filtered in actor list.
	if _druid_skip_enemy:
		return false
	var dp = _piece_at(dpos)
	if dp == null or int(dp["type"]) != PType.DRUID or bool(dp["friend"]):
		return false
	# Prefer Fire → Earth → Holy → Water
	for kind in ["fire", "earth", "holy", "water"]:
		if _enemy_druid_cast(dpos, kind):
			return true
	return false


func _enemy_druid_cast(dpos: Vector2i, kind: String) -> bool:
	var dp = _piece_at(dpos)
	if dp == null:
		return false
	var cd_key := "cd_%s" % kind
	if int(dp.get(cd_key, 0)) > 0:
		return false
	match kind:
		"earth":
			var tgts: Array = []
			for r in range(ROWS):
				for c in range(COLS):
					var p := Vector2i(c, r)
					var en = _piece_at(p)
					if en == null or not bool(en["friend"]) or int(en["type"]) == PType.TOWER:
						continue
					var d := _chebyshev(dpos, p)
					if d >= 1 and d <= DRUID_RADIUS:
						tgts.append(p)
			if tgts.is_empty():
				return false
			tgts.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				return _chebyshev(dpos, a) < _chebyshev(dpos, b))
			var tgt: Vector2i = tgts[0]
			_piece_at(tgt)["trap"] = 3
			_flash_hit(tgt, true)
			_show_toast("Enemy Druid — Earth trap!", 1.2)
			dp["cd_earth"] = DRUID_CD_EFW
			return true
		"fire":
			var tgts2: Array = []
			for r in range(ROWS):
				for c in range(COLS):
					var p := Vector2i(c, r)
					var en = _piece_at(p)
					if en == null or not bool(en["friend"]) or int(en["type"]) == PType.TOWER:
						continue
					var d := _chebyshev(dpos, p)
					if d >= 1 and d <= DRUID_RADIUS:
						tgts2.append(p)
			if tgts2.is_empty():
				return false
			tgts2.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				return _chebyshev(dpos, a) < _chebyshev(dpos, b))
			_damage_at(tgts2[0], FIRE_DMG)
			_show_toast("Enemy Druid — Fire!", 1.2)
			dp["cd_fire"] = DRUID_CD_EFW
			return true
		"holy":
			var candidates: Array = []
			for r in range(ROWS):
				for c in range(COLS):
					var p := Vector2i(c, r)
					if _chebyshev(dpos, p) > DRUID_RADIUS:
						continue
					var fr = _piece_at(p)
					if fr == null or bool(fr["friend"]) or int(fr["type"]) == PType.TOWER:
						continue
					var mx := _piece_max_hp(fr)
					if int(fr.get("hp", mx)) < mx:
						candidates.append({"pos": p, "hp": int(fr["hp"])})
			if candidates.is_empty():
				return false
			candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a["hp"]) < int(b["hp"]))
			var pos: Vector2i = candidates[0]["pos"]
			var fr2 = _piece_at(pos)
			fr2["hp"] = mini(_piece_max_hp(fr2), int(fr2["hp"]) + HOLY_HEAL)
			_flash_hit(pos, false)
			_show_toast("Enemy Druid — Holy heal!", 1.2)
			dp["cd_holy"] = DRUID_CD_HOLY
			return true
		"water":
			var nearest: Vector2i = Vector2i(-1, -1)
			var best_d := 99
			for r in range(ROWS):
				for c in range(COLS):
					var p := Vector2i(c, r)
					var en = _piece_at(p)
					if en == null or not bool(en["friend"]) or int(en["type"]) == PType.TOWER:
						continue
					var d := _chebyshev(dpos, p)
					if d < 1 or d > DRUID_RADIUS:
						continue
					if d < best_d:
						best_d = d
						nearest = p
			if nearest.x < 0 or best_d > DRUID_RADIUS:
				return false
			var dest := _shove_behind_free(dpos, nearest)
			if dest.x < 0:
				return false
			var piece = _board[nearest.y][nearest.x]
			_board[nearest.y][nearest.x] = null
			_board[dest.y][dest.x] = piece
			_flash_hit(dest, true)
			_show_toast("Enemy Druid — Water shove!", 1.2)
			dp["cd_water"] = DRUID_CD_EFW
			return true
	return false


func _enemy_try_archer_shot(cells: Array) -> bool:
	var best: Vector2i = Vector2i(-1, -1)
	var best_score := -99999
	for r in range(ROWS):
		for c in range(COLS):
			var to := Vector2i(c, r)
			var dest = _piece_at(to)
			if dest == null or not bool(dest["friend"]) or int(dest["type"]) == PType.TOWER or int(dest["type"]) == PType.OAK:
				continue
			if not _archer_can_hit(cells, to):
				continue
			var hp := int(dest.get("hp", MAX_HP))
			var sc := _enemy_target_priority(int(dest["type"])) * 10 - hp
			# Extra weight General / Champion
			if int(dest["type"]) == PType.GENERAL:
				sc += 200
			elif int(dest["type"]) == PType.CHAMPION:
				sc += 150
			if sc > best_score:
				best_score = sc
				best = to
	if best.x < 0:
		return false
	_damage_at(best, 1)
	return true


func _enemy_legal_deltas(cells: Array, piece: Dictionary, t: int) -> Array:
	## Shared-rule legal move deltas for this actor (Champion file / conditional sidestep).
	var out: Array = []
	var seen: Dictionary = {}
	var legal_t := t
	if t == PType.ENEMY_INF:
		legal_t = PType.INFANTRY
	var candidates: Array = []
	match legal_t:
		PType.CHAMPION:
			candidates = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
		PType.DRUID:
			for d0 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				candidates.append(d0)
		PType.INFANTRY:
			for dr in [-1, 0, 1]:
				for dc in [-1, 0, 1]:
					if dr == 0 and dc == 0:
						continue
					candidates.append(Vector2i(dc, dr))
			var fwd2 := _forward_delta_for(bool(piece["friend"]))
			candidates.append(Vector2i(0, fwd2 * 2))
		_:
			for dr in [-1, 0, 1]:
				for dc in [-1, 0, 1]:
					if dr == 0 and dc == 0:
						continue
					candidates.append(Vector2i(dc, dr))
	for d in candidates:
		if seen.has(d):
			continue
		seen[d] = true
		if _move_delta_legal(cells, d, piece, legal_t):
			out.append(d)
	return out


func _enemy_delta_score(cells: Array, delta: Vector2i, piece: Dictionary, t: int) -> int:
	## Higher = better purposeful advance.
	var trial: Array = []
	for p in cells:
		trial.append(Vector2i(p.x + delta.x, p.y + delta.y))
	var anchor: Vector2i = trial[0]
	var old: Vector2i = cells[0]
	var score := 0
	var hv := _enemy_hv_targets()
	var friend := bool(piece["friend"])
	var fwd := _forward_delta_for(friend)
	# Enter chip / shoot range on HV
	for h in hv:
		var hp = _piece_at(h)
		var pri := _enemy_target_priority(int(hp["type"]) if hp else 0)
		if t == PType.ARCHER:
			if _archer_can_hit(trial, h):
				score += 800 + pri
			elif not _archer_can_hit(cells, h):
				# Closer to range
				var od := _chebyshev(old, h)
				var nd := _chebyshev(anchor, h)
				if nd < od:
					score += (od - nd) * 30 + pri
		else:
			if _chebyshev(anchor, h) == 1:
				score += 1000 + pri
			else:
				var od2 := _chebyshev(old, h)
				var nd2 := _chebyshev(anchor, h)
				if nd2 < od2:
					score += (od2 - nd2) * 45 + int(pri / 2)
	# Forward with purpose (take space toward player half)
	var forward_step := delta.y * fwd
	if forward_step > 0:
		score += 25 * forward_step
	elif forward_step < 0:
		score -= 15  # mild retreat penalty unless HV requires it
	# Threaten any player unit (8-adj after move)
	var threatened := false
	for pos in trial:
		for n in _chebyshev_neighbors(pos):
			var dest = _piece_at(n)
			if dest != null and bool(dest["friend"]) and int(dest["type"]) != PType.TOWER and int(dest["type"]) != PType.OAK:
				threatened = true
				score += 40
				score += _enemy_target_priority(int(dest["type"]))
				break
		if threatened:
			break
	# Champion: prefer file forward; sidestep only when it improves HV approach
	if t == PType.CHAMPION:
		if delta.x == 0 and forward_step > 0:
			score += 35
		elif delta.x != 0:
			# Sidestep must earn its keep
			score -= 10
	# Slight mid-file preference (space, not shuffle)
	var mid := int(COLS / 2)
	score += maxi(0, 6 - absi(anchor.x - mid))
	return score


func _enemy_best_advance_delta(cells: Array, piece: Dictionary, t: int) -> Vector2i:
	var best := Vector2i(0, 0)
	var best_sc := -999999
	for d in _enemy_legal_deltas(cells, piece, t):
		var sc := _enemy_delta_score(cells, d, piece, t)
		if sc > best_sc:
			best_sc = sc
			best = d
	return best


func _enemy_best_hv_approach_delta(cells: Array, piece: Dictionary, t: int) -> Vector2i:
	## Only return a move that newly threatens General or Champion.
	var hv := _enemy_hv_targets()
	if hv.is_empty():
		return Vector2i(0, 0)
	var best := Vector2i(0, 0)
	var best_sc := 0
	for d in _enemy_legal_deltas(cells, piece, t):
		var trial: Array = []
		for p in cells:
			trial.append(Vector2i(p.x + d.x, p.y + d.y))
		var gains := false
		for h in hv:
			var now := false
			var later := false
			if t == PType.ARCHER:
				now = _archer_can_hit(cells, h)
				later = _archer_can_hit(trial, h)
			else:
				for pos in cells:
					if _chebyshev(pos, h) == 1:
						now = true
						break
				for pos2 in trial:
					if _chebyshev(pos2, h) == 1:
						later = true
						break
			if later and not now:
				gains = true
				break
		if not gains:
			continue
		var sc := _enemy_delta_score(cells, d, piece, t)
		if sc > best_sc:
			best_sc = sc
			best = d
	return best


func _enemy_commit_move(cells: Array, piece: Dictionary, t: int, delta: Vector2i) -> bool:
	if delta == Vector2i(0, 0):
		return false
	var ref: Vector2i = cells[0]
	# Cav charge mark (parity with player)
	if t == PType.CAVALRY:
		var aid := _actor_id_for_piece(piece, ref)
		_charge_ids[aid] = true
		_charge_ids[str(piece.get("id", ""))] = true
	# Champion rail
	if t == PType.CHAMPION:
		_champ_rail_from = ref
		_champ_rail_to = Vector2i(ref.x + delta.x, ref.y + delta.y)
	# Druid colour-flip
	if t == PType.DRUID and (absi(delta.x) + absi(delta.y)) == 1 and not (absi(delta.x) == absi(delta.y)):
		piece["colour_buff"] = 2
	var new_cells := _translate_cells(cells, delta)
	if t == PType.CHAMPION:
		_apply_champ_rail(new_cells[0], bool(piece["friend"]))
	_regiment_chip(new_cells)
	return true


func _enemy_advance(cells: Array, piece: Dictionary, t: int) -> bool:
	var best_delta := _enemy_best_advance_delta(cells, piece, t)
	if best_delta == Vector2i(0, 0):
		return false
	# Require non-trivial purpose: avoid pure sideways shuffle when a forward exists
	var sc := _enemy_delta_score(cells, best_delta, piece, t)
	if sc < 5:
		# Still take the least-bad forward if any
		var fwd := _forward_delta_for(bool(piece["friend"]))
		var fwd_d := Vector2i(0, fwd)
		if _enemy_legal_deltas(cells, piece, t).has(fwd_d):
			best_delta = fwd_d
		elif sc < 0:
			return false
	return _enemy_commit_move(cells, piece, t, best_delta)


func _enemy_act(from: Vector2i) -> void:
	## Legacy single-cell entry — wraps actor helper.
	var p = _piece_at(from)
	if p == null:
		return
	_enemy_act_actor({"pos": from, "reg": _reg_id_of(p), "type": int(p["type"])})


## --- Legal move / place highlights -----------------------------------------

func _rebuild_highlights() -> void:
	_highlights.clear()
	_place_options.clear()
	if _match_locked():
		return
	if _phase == Phase.PLACE and _place_kind != "":
		var opts := _footprints_for_kind(_place_kind)
		for opt in opts:
			var cells: Array = opt["cells"]
			var anchor: Vector2i = opt["anchor"]
			_place_options[anchor] = cells
			for pos in cells:
				_highlights[pos] = "place"
		return
	if _phase != Phase.MOVE:
		return
	# Mark selected regiment members
	if _selected_reg != "":
		for pos in _regiment_cells(_selected_reg):
			_highlights[pos] = "selected"
	elif _selected.x >= 0:
		_highlights[_selected] = "selected"
	if _cavalry_steps_left > 0:
		_add_regiment_legal(true)
		return
	if _selected.x < 0 and _selected_reg == "":
		return
	if _oak_shifting:
		_add_oak_legal_highlights()
		return
	_add_regiment_legal(false)

func _add_regiment_legal(cavalry_step: bool) -> void:
	var cells := _active_move_cells()
	if cells.is_empty():
		return
	var piece = _piece_at(cells[0])
	if piece == null:
		return
	var t: int = int(piece["type"])
	var friend := bool(piece["friend"])
	if t == PType.DRUID and not cavalry_step:
		var from: Vector2i = cells[0]
		# Optional 1 ortho reposition — powers are on DruidPanel
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if _move_delta_legal(cells, d, piece, t):
				var np := Vector2i(from.x + d.x, from.y + d.y)
				_highlights[np] = "move"
		return
	if t == PType.CHAMPION and not cavalry_step:
		var from_c: Vector2i = cells[0]
		for d2 in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			if _move_delta_legal(cells, d2, piece, t):
				_highlights[Vector2i(from_c.x + d2.x, from_c.y + d2.y)] = "move"
		return
	var deltas: Array = []
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			deltas.append(Vector2i(dc, dr))
	if t == PType.INFANTRY and not cavalry_step:
		var fwd2 := _forward_delta_for(friend)
		deltas.append(Vector2i(0, fwd2 * 2))
	for d3 in deltas:
		var delta2: Vector2i = d3
		if cavalry_step or t == PType.CAVALRY:
			if _chebyshev(Vector2i(0, 0), delta2) != 1:
				continue
			if not _can_translate(cells, delta2):
				continue
		elif not _move_delta_legal(cells, delta2, piece, t):
			continue
		for pos in cells:
			var p: Vector2i = pos
			var np3 := Vector2i(p.x + delta2.x, p.y + delta2.y)
			var prev2: String = _highlights.get(np3, "")
			if prev2 == "" or prev2 == "selected":
				_highlights[np3] = "move"
	if t == PType.ARCHER and not cavalry_step:
		for r in range(ROWS):
			for c in range(COLS):
				var to := Vector2i(c, r)
				var dest = _piece_at(to)
				if dest == null or bool(dest["friend"]) or int(dest["type"]) == PType.TOWER or int(dest["type"]) == PType.OAK:
					continue
				if _archer_can_hit(cells, to):
					_highlights[to] = "capture"

func _refresh_place_buttons() -> void:
	var btn_inf: Button = $SidePanel/PlacePanel/BtnInf
	var btn_arch: Button = $SidePanel/PlacePanel/BtnArch
	var btn_cav: Button = $SidePanel/PlacePanel/BtnCav
	var btn_champ: Button = $SidePanel/PlacePanel.get_node_or_null("BtnChamp") as Button
	var btn_cancel: Button = $SidePanel/PlacePanel.get_node_or_null("BtnCancel") as Button
	btn_inf.disabled = (_pool_inf <= 0) or _match_locked() or _phase != Phase.PLACE or _deploy_stage != "infantry"
	btn_arch.disabled = (_pool_arch <= 0) or _match_locked() or _phase != Phase.PLACE or _deploy_stage != "archer"
	btn_cav.disabled = (_pool_cav <= 0) or _match_locked() or _phase != Phase.PLACE or _deploy_stage != "cavalry"
	if btn_champ:
		btn_champ.disabled = (_pool_champ <= 0) or _match_locked() or _phase != Phase.PLACE or _deploy_stage != "champion"
		btn_champ.modulate = Color(0.55, 0.55, 0.55) if btn_champ.disabled else Color(1, 1, 1)
		if _place_kind == "champion" and not btn_champ.disabled:
			btn_champ.modulate = Color(1.15, 1.2, 0.85)
	btn_inf.modulate = Color(0.55, 0.55, 0.55) if btn_inf.disabled else Color(1, 1, 1)
	btn_arch.modulate = Color(0.55, 0.55, 0.55) if btn_arch.disabled else Color(1, 1, 1)
	btn_cav.modulate = Color(0.55, 0.55, 0.55) if btn_cav.disabled else Color(1, 1, 1)
	if _place_kind == "infantry" and not btn_inf.disabled:
		btn_inf.modulate = Color(1.15, 1.2, 0.85)
	elif _place_kind == "archer" and not btn_arch.disabled:
		btn_arch.modulate = Color(1.15, 1.2, 0.85)
	elif _place_kind == "cavalry" and not btn_cav.disabled:
		btn_cav.modulate = Color(1.15, 1.2, 0.85)
	if btn_cancel:
		btn_cancel.disabled = (_place_kind == "") or _match_locked() or _phase != Phase.PLACE
		btn_cancel.modulate = Color(0.6, 0.6, 0.6) if btn_cancel.disabled else Color(1, 1, 1)
	var btn_start_place: Button = $SidePanel/PlacePanel.get_node_or_null("BtnStartFromPlace") as Button
	if btn_start_place:
		btn_start_place.disabled = _match_locked() or (_phase != Phase.PLACE and _phase != Phase.PLACE_CHOICE)
		btn_start_place.modulate = Color(0.55, 0.55, 0.55) if btn_start_place.disabled else Color(1.05, 1.1, 0.9)
	var btn_res := $SidePanel/MovePanel.get_node_or_null("BtnCallReserve") as Button
	if btn_res:
		var can_res := (_phase == Phase.MOVE and not _match_locked() and not _oak_turn_spent and _reserve_cooldown <= 0
			and (_reserve_inf + _reserve_arch + _reserve_cav) > 0)
		btn_res.visible = _phase == Phase.MOVE and not _match_locked()
		btn_res.disabled = not can_res
		btn_res.text = "Call Reserve cd:%d" % _reserve_cooldown if _reserve_cooldown > 0 else "Call Reserve"
		btn_res.modulate = Color(0.55, 0.55, 0.55) if btn_res.disabled else Color(1.05, 0.95, 0.75)

func _refresh() -> void:
	$SidePanel/PlacePanel/PoolLabel.text = "Pools — Inf %d · Arch %d · Cav %d · Champ %d | Res I%d A%d C%d" % [_pool_inf, _pool_arch, _pool_cav, _pool_champ, _reserve_inf, _reserve_arch, _reserve_cav]
	_refresh_place_buttons()
	if _phase == Phase.MOVE and not _match_locked():
		if _oak_turn_spent:
			$SidePanel/MovePanel/MovesLabel.text = "Oak used — End turn"
		else:
			$SidePanel/MovePanel/MovesLabel.text = "Each unit acts once · %d acted" % _moved_ids.size()
	var btn_cc := $SidePanel/MovePanel.get_node_or_null("BtnCancelCav") as Button
	if btn_cc:
		btn_cc.visible = (_phase == Phase.MOVE and _cavalry_steps_left > 0 and not _match_locked())
		btn_cc.disabled = not btn_cc.visible
	var gpos := _general_pos()
	for r in range(ROWS):
		for c in range(COLS):
			var root: Control = _cells[r][c]
			var bg: ColorRect = root.get_node("Bg")
			var hl: ColorRect = root.get_node("Highlight")
			var token: Panel = root.get_node("Token")
			var hp_lab: Label = root.get_node("HpLabel")
			var base := _cell_base_color(r, c)
			if r <= _player_half_max():
				base = base.lerp(Color(0.40, 0.55, 0.38), 0.08)
			else:
				base = base.lerp(Color(0.55, 0.36, 0.36), 0.07)
			if _walls.has(Vector2i(c, r)):
				base = base.lerp(Color(0.35, 0.32, 0.30), 0.55)
			elif _archer_gaps.has(Vector2i(c, r)):
				base = base.lerp(Color(0.55, 0.75, 0.95), 0.35)
			bg.color = base

			var piece = _board[r][c]
			var hl_kind: String = _highlights.get(Vector2i(c, r), "")
			if hl_kind == "place":
				hl.color = Color(0.35, 0.85, 0.45, 0.42)
			elif hl_kind == "move":
				hl.color = Color(0.30, 0.90, 0.55, 0.50)
			elif hl_kind == "capture":
				hl.color = Color(0.95, 0.30, 0.22, 0.48)
			elif hl_kind == "selected" or (_selected.x == c and _selected.y == r):
				hl.color = Color(1.0, 0.92, 0.25, 0.55)
			elif _selected_reg != "" and piece != null and str(piece.get("regiment_id", "")) == _selected_reg:
				hl.color = Color(1.0, 0.92, 0.25, 0.40)
			else:
				hl.color = Color(0, 0, 0, 0)

			if piece != null:
				_style_token(token, int(piece["type"]), bool(piece["friend"]))
				if int(piece["type"]) != PType.TOWER:
					hp_lab.visible = true
					var mx := _piece_max_hp(piece)
					var hp_v := int(piece.get("hp", mx))
					var trap_n := int(piece.get("trap", 0))
					var trap_mark := "⛓" if trap_n > 0 else ""
					hp_lab.text = "%s%s%d" % [trap_mark, _hp_pips(hp_v, mx), hp_v]
					if trap_n > 0:
						hp_lab.add_theme_color_override("font_color", Color(0.75, 0.95, 0.55))
					elif hp_v <= 2:
						hp_lab.add_theme_color_override("font_color", Color(1.0, 0.35, 0.28))
					elif hp_v * 2 <= mx:
						hp_lab.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
					else:
						hp_lab.add_theme_color_override("font_color", Color(0.85, 1.0, 0.75))
				else:
					hp_lab.visible = false
				# Hit flash / lunge cue
				var flash_t := float(_hit_flashes.get(Vector2i(c, r), 0.0))
				if flash_t > 0.0:
					var pulse := clampf(flash_t / 0.55, 0.0, 1.0)
					hl.color = Color(1.0, 0.45, 0.15, 0.25 + pulse * 0.55)
					token.position = Vector2(0, -4.0 * pulse)
					token.modulate = Color(1.35, 1.1, 0.85, 1.0)
				else:
					token.position = Vector2.ZERO
					token.modulate = Color(1, 1, 1, 1)
			else:
				token.visible = false
				hp_lab.visible = false
				token.position = Vector2.ZERO
				token.modulate = Color(1, 1, 1, 1)

			if _fallen and gpos.x < 0:
				bg.color = bg.color.lerp(Color(0.25, 0.08, 0.10), 0.30)


func _build_rules_panel() -> void:
	_rules_panel = Control.new()
	_rules_panel.visible = false
	_rules_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rules_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_rules_panel.z_index = 40
	add_child(_rules_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_toggle_rules()
	)
	_rules_panel.add_child(dim)

	var sheet := PanelContainer.new()
	sheet.set_anchors_preset(Control.PRESET_CENTER)
	sheet.anchor_left = 0.5
	sheet.anchor_right = 0.5
	sheet.anchor_top = 0.5
	sheet.anchor_bottom = 0.5
	sheet.offset_left = -210
	sheet.offset_right = 210
	sheet.offset_top = -300
	sheet.offset_bottom = 300
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.14, 0.98)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.75, 0.65, 0.40)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sheet.add_theme_stylebox_override("panel", sb)
	_rules_panel.add_child(sheet)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	sheet.add_child(v)

	var hdr := Label.new()
	hdr.text = "War-board Rules"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color", Color(0.95, 0.88, 0.65))
	v.add_child(hdr)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	var body := Label.new()
	body.text = RULES_TEXT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94))
	scroll.add_child(body)
	body.custom_minimum_size = Vector2(380, 0)

	var close_btn := Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(_toggle_rules)
	v.add_child(close_btn)


func _toggle_rules() -> void:
	_rules_visible = not _rules_visible
	if _rules_panel:
		_rules_panel.visible = _rules_visible
	if _btn_rules:
		_btn_rules.text = "Close Help" if _rules_visible else "Help / Rules"

