class_name BoxingModeRunner
extends "res://addons/aerobeat-mode-core/src/interfaces/mode_runner.gd"

const ModeDescriptor := preload("res://addons/aerobeat-mode-core/src/data_types/mode_descriptor.gd")
const ModeJudgementEvent := preload("res://addons/aerobeat-mode-core/src/data_types/mode_judgement_event.gd")
const ModeRunConfig := preload("res://addons/aerobeat-mode-core/src/data_types/mode_run_config.gd")
const ModeRunFragment := preload("res://addons/aerobeat-mode-core/src/data_types/mode_run_fragment.gd")
const ModeScoreDelta := preload("res://addons/aerobeat-mode-core/src/data_types/mode_score_delta.gd")
const ModeTickFrame := preload("res://addons/aerobeat-mode-core/src/data_types/mode_tick_frame.gd")

const MODE_ID := "boxing"
const CHART_CONTRACT := "aerobeat.boxing.chart.v1"
const INPUT_CONTRACT := "aerobeat.boxing.input.v1"

const DEFAULT_EARLY_WINDOW_SEC := 0.18
const DEFAULT_LATE_WINDOW_SEC := 0.18
const DEFAULT_HIT_SCORE := 100
const DEFAULT_GOOD_SCORE := 70

const PUNCH_EVENTS := [
	"straight_left",
	"straight_right",
	"uppercut_left",
	"uppercut_right",
	"hook_left",
	"hook_right"
]

const TRANSITION_EVENTS := [
	"guard_enabled",
	"guard_disabled",
	"squat_enabled",
	"squat_disabled",
	"weave_left_enabled",
	"weave_left_disabled",
	"weave_right_enabled",
	"weave_right_disabled"
]

var _mode_id := MODE_ID
var _targets: Array[Dictionary] = []
var _target_ids := {}
var _started := false
var _completed := false
var _completion_emitted := false
var _score := 0
var _combo := 0
var _max_combo := 0
var _hits := 0
var _misses := 0

func get_descriptor() -> ModeDescriptor:
	return ModeDescriptor.new({
		"mode_id": MODE_ID,
		"display_name": "AeroBeat Boxing",
		"display_key": "mode.boxing.display_name",
		"supported_chart_contracts": [CHART_CONTRACT],
		"supported_input_contracts": [INPUT_CONTRACT],
		"metadata": {
			"punch_events": PUNCH_EVENTS.duplicate(),
			"transition_events": TRANSITION_EVENTS.duplicate()
		}
	})

func start(config: ModeRunConfig) -> ModeRunFragment:
	_reset_state()
	_started = true
	if config != null and not config.mode_id.is_empty():
		_mode_id = config.mode_id
	if config != null:
		_load_targets(config.chart_data.get("targets", []))
	return ModeRunFragment.new({
		"fragment_type": ModeRunFragment.TYPE_STARTED,
		"mode_id": _mode_id,
		"reason": "started",
		"summary": _summary()
	})

func tick(frame: ModeTickFrame) -> Array:
	if not _started or _completed:
		return []

	var outputs := []
	if frame != null:
		_load_targets(frame.chart_events)
		for input_event in frame.input_events:
			outputs.append_array(_judge_input(input_event))
		outputs.append_array(_judge_expired_targets(frame.position_sec))
		if _all_targets_judged():
			_completed = true

	if _completed and not _completion_emitted:
		_completion_emitted = true
		outputs.append(ModeRunFragment.new({
			"fragment_type": ModeRunFragment.TYPE_COMPLETED,
			"mode_id": _mode_id,
			"reason": "chart_complete",
			"summary": _summary()
		}))

	return outputs

func is_complete() -> bool:
	return _completed

func stop(reason: String = "") -> ModeRunFragment:
	if not _completed:
		_completed = true
	return ModeRunFragment.new({
		"fragment_type": ModeRunFragment.TYPE_STOPPED,
		"mode_id": _mode_id,
		"reason": reason,
		"summary": _summary()
	})

func _reset_state() -> void:
	_mode_id = MODE_ID
	_targets = []
	_target_ids = {}
	_started = false
	_completed = false
	_completion_emitted = false
	_score = 0
	_combo = 0
	_max_combo = 0
	_hits = 0
	_misses = 0

func _load_targets(raw_targets: Variant) -> void:
	if not raw_targets is Array:
		return
	for raw_target in raw_targets:
		if not raw_target is Dictionary:
			continue
		var target := _normalize_target(raw_target)
		if target.is_empty() or _target_ids.has(target.id):
			continue
		_targets.append(target)
		_target_ids[target.id] = true
	_targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.position_sec) < float(b.position_sec))

func _normalize_target(raw_target: Dictionary) -> Dictionary:
	var event_name := String(raw_target.get("event", raw_target.get("type", ""))).strip_edges()
	if not _is_supported_event(event_name):
		return {}
	var position_sec := float(raw_target.get("position_sec", raw_target.get("time_sec", raw_target.get("time", 0.0))))
	var early_window := maxf(0.0, float(raw_target.get("early_window_sec", raw_target.get("window_before_sec", DEFAULT_EARLY_WINDOW_SEC))))
	var late_window := maxf(0.0, float(raw_target.get("late_window_sec", raw_target.get("window_after_sec", DEFAULT_LATE_WINDOW_SEC))))
	var id := String(raw_target.get("id", raw_target.get("target_id", ""))).strip_edges()
	if id.is_empty():
		id = "%s@%.3f" % [event_name, position_sec]
	return {
		"id": id,
		"event": event_name,
		"position_sec": position_sec,
		"early_window_sec": early_window,
		"late_window_sec": late_window,
		"judged": false,
		"metadata": raw_target.get("metadata", {}).duplicate(true) if raw_target.get("metadata", {}) is Dictionary else {}
	}

func _judge_input(input_event: Dictionary) -> Array:
	var event_name := String(input_event.get("event", input_event.get("type", ""))).strip_edges()
	if not _is_valid_input_event(event_name, input_event.get("args", [])):
		return []
	var input_position := float(input_event.get("position_sec", input_event.get("time_sec", input_event.get("time", 0.0))))
	var target := _find_nearest_unjudged_target(event_name, input_position)
	if target.is_empty():
		return []

	var offset := input_position - float(target.position_sec)
	var judgement := ModeJudgementEvent.RESULT_HIT
	if offset < -float(target.early_window_sec):
		judgement = ModeJudgementEvent.RESULT_EARLY
	elif offset > float(target.late_window_sec):
		judgement = ModeJudgementEvent.RESULT_LATE
	var accuracy := _accuracy_for(target, offset, judgement)
	return _apply_judgement(target.id, judgement, input_position, offset, accuracy)

func _judge_expired_targets(position_sec: float) -> Array:
	var outputs := []
	for target in _targets:
		if bool(target.judged):
			continue
		var miss_at := float(target.position_sec) + float(target.late_window_sec)
		if position_sec > miss_at:
			outputs.append_array(_apply_judgement(target.id, ModeJudgementEvent.RESULT_MISS, miss_at, float(target.late_window_sec), 0.0))
	return outputs

func _find_nearest_unjudged_target(event_name: String, input_position: float) -> Dictionary:
	var best_index := -1
	var best_distance := INF
	for index in _targets.size():
		var target := _targets[index]
		if bool(target.judged) or target.event != event_name:
			continue
		var distance: float = absf(input_position - float(target.position_sec))
		if distance < best_distance:
			best_index = index
			best_distance = distance
	if best_index < 0:
		return {}
	return _targets[best_index]

func _apply_judgement(target_id: String, judgement: String, position_sec: float, offset_sec: float, accuracy: float) -> Array:
	var index := _target_index(target_id)
	if index < 0:
		return []
	var target := _targets[index]
	target.judged = true
	_targets[index] = target

	var hit := judgement == ModeJudgementEvent.RESULT_HIT
	var score_delta := 0
	var combo_delta := -_combo
	if hit:
		score_delta = DEFAULT_HIT_SCORE if accuracy >= 0.999 else DEFAULT_GOOD_SCORE
		combo_delta = 1
		_combo += 1
		_max_combo = maxi(_max_combo, _combo)
		_hits += 1
	else:
		_combo = 0
		_misses += 1
	_score += score_delta

	var target_ref := _target_ref(target)
	var judgement_event := ModeJudgementEvent.new({
		"mode_id": _mode_id,
		"target_ref": target_ref,
		"position_sec": position_sec,
		"judgement": judgement,
		"timing_offset_sec": offset_sec,
		"accuracy": accuracy,
		"metadata": {
			"event": target.event
		}
	})
	var score := ModeScoreDelta.new({
		"mode_id": _mode_id,
		"target_ref": target_ref,
		"position_sec": position_sec,
		"score_delta": score_delta,
		"combo_delta": combo_delta,
		"accuracy_delta": accuracy,
		"judgement": judgement,
		"metadata": {
			"event": target.event
		}
	})
	return [judgement_event, score]

func _accuracy_for(target: Dictionary, offset_sec: float, judgement: String) -> float:
	if judgement != ModeJudgementEvent.RESULT_HIT:
		return 0.0
	var window := float(target.late_window_sec) if offset_sec >= 0.0 else float(target.early_window_sec)
	if window <= 0.0:
		return 1.0 if is_zero_approx(offset_sec) else 0.0
	return clampf(1.0 - (absf(offset_sec) / window), 0.0, 1.0)

func _target_index(target_id: String) -> int:
	for index in _targets.size():
		if _targets[index].id == target_id:
			return index
	return -1

func _all_targets_judged() -> bool:
	return not _targets.is_empty() and _targets.all(func(target: Dictionary) -> bool: return bool(target.judged))

func _target_ref(target: Dictionary) -> Dictionary:
	return {
		"id": target.id,
		"event": target.event,
		"position_sec": target.position_sec
	}

func _summary() -> Dictionary:
	return {
		"score": _score,
		"combo": _combo,
		"max_combo": _max_combo,
		"hits": _hits,
		"misses": _misses,
		"target_count": _targets.size(),
		"judged_count": _targets.filter(func(target: Dictionary) -> bool: return bool(target.judged)).size()
	}

func _is_valid_input_event(event_name: String, args: Variant) -> bool:
	if PUNCH_EVENTS.has(event_name):
		return (not args is Array) or args.is_empty()
	return TRANSITION_EVENTS.has(event_name)

func _is_supported_event(event_name: String) -> bool:
	return PUNCH_EVENTS.has(event_name) or TRANSITION_EVENTS.has(event_name)
