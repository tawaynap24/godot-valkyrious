## BattleLogger — Records every battle event for replay, analysis, and sync.
##
## Architecture:
##   - Autoload singleton (independent from UI)
##   - Logs are plain Dictionaries: { "seq", "time_ms", "turn", "player", "action", ...data }
##   - Designed for future replay / multiplayer sync; does NOT drive any UI directly
##
## Usage:
##   BattleLogger.begin_battle(meta)          # call once at battle start
##   BattleLogger.log_deploy(...)             # call on each deploy
##   ...
##   BattleLogger.end_battle(result)          # call at battle end
##   var json := BattleLogger.export_json()   # get JSON string
##   BattleLogger.import_json(json)           # load a saved log

extends Node

# ── Action type constants ──────────────────────────────────────────────────────

const ACTION_BATTLE_START    := "battle_start"
const ACTION_BATTLE_END      := "battle_end"
const ACTION_TURN_CHANGE     := "turn_change"
const ACTION_CARD_DRAW        := "card_draw"
const ACTION_CARD_DEPLOY      := "card_deploy"
const ACTION_CARD_MOVE        := "card_move"
const ACTION_ATTACK           := "attack"
const ACTION_DAMAGE           := "damage"
const ACTION_DEATH            := "death"
const ACTION_HEAL             := "heal"
const ACTION_BUFF             := "buff"
const ACTION_DEBUFF           := "debuff"
const ACTION_SUMMON           := "summon"
const ACTION_CAPTURE          := "capture"

# ── State ──────────────────────────────────────────────────────────────────────

## Current log session. Cleared by begin_battle().
var _log: Array = []

## Sequential event counter (monotonically increasing within a session).
var _seq: int = 0

## Turn counter — incremented when log_turn_change() is called.
var _turn: int = 0

## Unix timestamp (ms) when begin_battle() was called — used as reference.
var _battle_start_ms: int = 0

## Metadata stored at battle start (mode, player_name, opponent_name, etc.)
var _meta: Dictionary = {}

## Whether a battle is currently in progress.
var is_recording: bool = false

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted whenever a new event is appended (useful for live debug overlays).
signal event_logged(event: Dictionary)

# ── Public API ────────────────────────────────────────────────────────────────

## Start a new log session. Call once at battle begin.
## meta example: { "mode": "ai", "player_name": "Alice", "opponent_name": "AI" }
func begin_battle(meta: Dictionary = {}) -> void:
	_log.clear()
	_seq = 0
	_turn = 1
	_battle_start_ms = _now_ms()
	_meta = meta.duplicate()
	is_recording = true
	_append({
		"action": ACTION_BATTLE_START,
		"meta":   _meta,
	})

## Close the current session.
## result: "win" | "loss" | "draw"
func end_battle(result: String) -> void:
	if not is_recording:
		return
	_append({
		"action": ACTION_BATTLE_END,
		"result": result,
		"total_turns": _turn,
		"duration_ms": _now_ms() - _battle_start_ms,
	})
	is_recording = false

## Log a turn change (call when game clock or logic advances the "turn" concept).
func log_turn_change(new_turn: int = -1) -> void:
	if new_turn >= 1:
		_turn = new_turn
	else:
		_turn += 1
	_append({
		"action": ACTION_TURN_CHANGE,
	})

## Log a card being drawn into the player's hand.
## player: "owner" | "enemy"
func log_card_draw(player: String, card_id: String, card_name: String) -> void:
	_append({
		"action":    ACTION_CARD_DRAW,
		"player":    player,
		"card_id":   card_id,
		"card_name": card_name,
	})

## Log a card deployed onto the field.
func log_deploy(player: String, card_id: String, card_name: String,
		row: int, col: int, cost_spent: int) -> void:
	_append({
		"action":     ACTION_CARD_DEPLOY,
		"player":     player,
		"card_id":    card_id,
		"card_name":  card_name,
		"row":        row,
		"col":        col,
		"cost_spent": cost_spent,
	})

## Log a card moving to a new position.
func log_move(player: String, card_id: String, card_name: String,
		from_row: int, from_col: int, to_row: int, to_col: int) -> void:
	_append({
		"action":    ACTION_CARD_MOVE,
		"player":    player,
		"card_id":   card_id,
		"card_name": card_name,
		"from_row":  from_row,
		"from_col":  from_col,
		"to_row":    to_row,
		"to_col":    to_col,
	})

## Log a combat exchange between two cards (simultaneous damage model).
## attacker / defender are Dictionaries: { "player", "card_id", "card_name", "atk", "hp_before", "hp_after" }
func log_attack(attacker: Dictionary, defender: Dictionary) -> void:
	_append({
		"action":   ACTION_ATTACK,
		"attacker": attacker.duplicate(),
		"defender": defender.duplicate(),
	})
	# Also emit individual damage events for easier filtering
	_append_damage(attacker["player"], attacker["card_id"], attacker["card_name"],
			defender["atk"], attacker["hp_before"], attacker["hp_after"])
	_append_damage(defender["player"], defender["card_id"], defender["card_name"],
			attacker["atk"], defender["hp_before"], defender["hp_after"])

## Log a card dying and being removed from the field.
func log_death(player: String, card_id: String, card_name: String,
		row: int, col: int) -> void:
	_append({
		"action":    ACTION_DEATH,
		"player":    player,
		"card_id":   card_id,
		"card_name": card_name,
		"row":       row,
		"col":       col,
	})

## Log a direct heal event.
func log_heal(player: String, card_id: String, card_name: String,
		amount: int, hp_before: int, hp_after: int) -> void:
	_append({
		"action":    ACTION_HEAL,
		"player":    player,
		"card_id":   card_id,
		"card_name": card_name,
		"amount":    amount,
		"hp_before": hp_before,
		"hp_after":  hp_after,
	})

## Log a buff applied to a card.
## stat_changes: Dictionary e.g. { "atk": 2, "hp": 0 }
func log_buff(player: String, card_id: String, card_name: String,
		source: String, stat_changes: Dictionary) -> void:
	_append({
		"action":       ACTION_BUFF,
		"player":       player,
		"card_id":      card_id,
		"card_name":    card_name,
		"source":       source,
		"stat_changes": stat_changes.duplicate(),
	})

## Log a debuff applied to a card.
func log_debuff(player: String, card_id: String, card_name: String,
		source: String, stat_changes: Dictionary) -> void:
	_append({
		"action":       ACTION_DEBUFF,
		"player":       player,
		"card_id":      card_id,
		"card_name":    card_name,
		"source":       source,
		"stat_changes": stat_changes.duplicate(),
	})

## Log a special summon (card appearing on field without going through normal deploy).
func log_summon(player: String, card_id: String, card_name: String,
		row: int, col: int) -> void:
	_append({
		"action":    ACTION_SUMMON,
		"player":    player,
		"card_id":   card_id,
		"card_name": card_name,
		"row":       row,
		"col":       col,
	})

## Log a slot being captured (card reaches enemy base row).
func log_capture(player: String, card_id: String, card_name: String,
		row: int, col: int) -> void:
	_append({
		"action":    ACTION_CAPTURE,
		"player":    player,
		"card_id":   card_id,
		"card_name": card_name,
		"row":       row,
		"col":       col,
	})

# ── Query helpers ─────────────────────────────────────────────────────────────

## Return the full event log (read-only copy).
func get_log() -> Array:
	return _log.duplicate(true)

## Return only events matching a specific action type.
func filter_by_action(action_type: String) -> Array:
	var out: Array = []
	for ev in _log:
		if ev.get("action", "") == action_type:
			out.append(ev.duplicate(true))
	return out

## Return all events for a specific player ("owner" or "enemy").
func filter_by_player(player: String) -> Array:
	var out: Array = []
	for ev in _log:
		if ev.get("player", "") == player:
			out.append(ev.duplicate(true))
	return out

## Return the current metadata.
func get_battle_meta() -> Dictionary:
	return _meta.duplicate()

# ── Import / Export ───────────────────────────────────────────────────────────

## Export the current log session to a JSON string.
## The string is self-contained and can be saved to a file or sent over the network.
func export_json() -> String:
	var payload := {
		"version":          1,
		"meta":             _meta.duplicate(true),
		"battle_start_ms":  _battle_start_ms,
		"events":           _log.duplicate(true),
	}
	return JSON.stringify(payload, "\t")

## Import a previously exported JSON string, replacing the current in-memory log.
## Returns true on success, false on parse error.
func import_json(json_string: String) -> bool:
	var result: Variant = JSON.parse_string(json_string)
	if result == null or not result is Dictionary:
		push_warning("[BattleLogger] import_json: invalid JSON")
		return false
	var doc := result as Dictionary
	if doc.get("version", 0) != 1:
		push_warning("[BattleLogger] import_json: unsupported version")
		return false
	_log                = (doc.get("events", []) as Array).duplicate(true)
	_meta               = (doc.get("meta", {}) as Dictionary).duplicate(true)
	_battle_start_ms    = int(doc.get("battle_start_ms", 0))
	_seq                = _log.size()
	is_recording        = false
	return true

## Save export_json() directly to a file path (e.g. "user://battle_log.json").
func save_to_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[BattleLogger] save_to_file: cannot open '%s'" % path)
		return false
	file.store_string(export_json())
	file.close()
	return true

## Load and import a JSON log from a file path.
func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("[BattleLogger] load_from_file: file not found '%s'" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[BattleLogger] load_from_file: cannot open '%s'" % path)
		return false
	var content := file.get_as_text()
	file.close()
	return import_json(content)

# ── Private helpers ───────────────────────────────────────────────────────────

func _append(data: Dictionary) -> void:
	data["seq"]     = _seq
	data["time_ms"] = _now_ms() - _battle_start_ms
	data["turn"]    = _turn
	_log.append(data)
	_seq += 1
	event_logged.emit(data)

func _append_damage(player: String, card_id: String, card_name: String,
		amount: int, hp_before: int, hp_after: int) -> void:
	_append({
		"action":    ACTION_DAMAGE,
		"player":    player,
		"card_id":   card_id,
		"card_name": card_name,
		"amount":    amount,
		"hp_before": hp_before,
		"hp_after":  hp_after,
	})

func _now_ms() -> int:
	return int(Time.get_ticks_msec())
