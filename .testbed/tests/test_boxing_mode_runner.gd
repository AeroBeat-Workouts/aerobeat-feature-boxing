extends "res://addons/aerobeat-vendor-godot-unit-test/test.gd"

const BoxingModeRunner := preload("res://addons/aerobeat-mode-boxing/src/boxing_mode_runner.gd")
const ModeDescriptor := preload("res://addons/aerobeat-mode-core/src/data_types/mode_descriptor.gd")
const ModeJudgementEvent := preload("res://addons/aerobeat-mode-core/src/data_types/mode_judgement_event.gd")
const ModeRunConfig := preload("res://addons/aerobeat-mode-core/src/data_types/mode_run_config.gd")
const ModeRunFragment := preload("res://addons/aerobeat-mode-core/src/data_types/mode_run_fragment.gd")
const ModeScoreDelta := preload("res://addons/aerobeat-mode-core/src/data_types/mode_score_delta.gd")
const ModeTickFrame := preload("res://addons/aerobeat-mode-core/src/data_types/mode_tick_frame.gd")

func test_descriptor_advertises_boxing_contracts_and_no_arg_punches() -> void:
	var descriptor: ModeDescriptor = BoxingModeRunner.new().get_descriptor()

	assert_true(descriptor.is_valid())
	assert_eq(descriptor.mode_id, "boxing")
	assert_has(descriptor.supported_input_contracts, "aerobeat.boxing.input.v1")
	assert_has(descriptor.metadata.punch_events, "straight_left")
	assert_has(descriptor.metadata.punch_events, "hook_right")

func test_hit_scores_judgement_score_and_completion_fragment() -> void:
	var runner := BoxingModeRunner.new()
	runner.start(_config([
		_target("jab_1", "straight_left", 1.0)
	]))

	var outputs := runner.tick(_frame(1.02, [
		_boxing_input("straight_left", 1.02)
	]))

	assert_eq(outputs.size(), 3)
	assert_true(outputs[0] is ModeJudgementEvent)
	assert_true(outputs[1] is ModeScoreDelta)
	assert_true(outputs[2] is ModeRunFragment)
	assert_eq(outputs[0].judgement, ModeJudgementEvent.RESULT_HIT)
	assert_almost_eq(outputs[0].timing_offset_sec, 0.02, 0.001)
	assert_eq(outputs[1].score_delta, 70)
	assert_eq(outputs[1].combo_delta, 1)
	assert_eq(outputs[2].fragment_type, ModeRunFragment.TYPE_COMPLETED)
	assert_true(runner.is_complete())

func test_miss_expires_when_no_matching_input_arrives() -> void:
	var runner := BoxingModeRunner.new()
	runner.start(_config([
		_target("miss_me", "hook_left", 1.0)
	]))

	var outputs := runner.tick(_frame(1.21, []))

	assert_eq(outputs[0].judgement, ModeJudgementEvent.RESULT_MISS)
	assert_eq(outputs[1].score_delta, 0)
	assert_eq(outputs[1].combo_delta, 0)
	assert_eq(outputs[2].fragment_type, ModeRunFragment.TYPE_COMPLETED)

func test_early_and_late_inputs_keep_mode_metadata_minimal() -> void:
	var early_runner := BoxingModeRunner.new()
	early_runner.start(_config([
		_target("too_soon", "uppercut_right", 1.0)
	]))
	var early_outputs := early_runner.tick(_frame(0.70, [
		_boxing_input("uppercut_right", 0.70)
	]))

	var late_runner := BoxingModeRunner.new()
	late_runner.start(_config([
		_target("too_late", "uppercut_left", 1.0)
	]))
	var late_outputs := late_runner.tick(_frame(1.25, [
		_boxing_input("uppercut_left", 1.25)
	]))

	assert_eq(early_outputs[0].judgement, ModeJudgementEvent.RESULT_EARLY)
	assert_eq(late_outputs[0].judgement, ModeJudgementEvent.RESULT_LATE)
	assert_eq(early_outputs[0].metadata, {"event": "uppercut_right"})
	assert_eq(late_outputs[0].metadata, {"event": "uppercut_left"})

func test_combo_resets_on_bad_judgement_and_recovers_on_next_hit() -> void:
	var runner := BoxingModeRunner.new()
	runner.start(_config([
		_target("one", "straight_left", 1.0),
		_target("two", "straight_right", 2.0),
		_target("three", "hook_right", 3.0)
	]))

	var first := runner.tick(_frame(1.0, [_boxing_input("straight_left", 1.0)]))
	var second := runner.tick(_frame(2.24, [_boxing_input("straight_right", 2.24)]))
	var third := runner.tick(_frame(3.0, [_boxing_input("hook_right", 3.0)]))

	assert_eq(first[1].combo_delta, 1)
	assert_eq(second[0].judgement, ModeJudgementEvent.RESULT_LATE)
	assert_eq(second[1].combo_delta, -1)
	assert_eq(third[1].combo_delta, 1)
	assert_eq(third[2].summary.max_combo, 1)

func test_defensive_transition_targets_use_same_timing_rules() -> void:
	var runner := BoxingModeRunner.new()
	runner.start(_config([
		_target("guard", "guard_enabled", 1.0),
		_target("squat", "squat_disabled", 2.0),
		_target("weave", "weave_left_enabled", 3.0)
	]))

	var first := runner.tick(_frame(1.0, [_boxing_input("guard_enabled", 1.0)]))
	var second := runner.tick(_frame(2.0, [_boxing_input("squat_disabled", 2.0)]))
	var third := runner.tick(_frame(3.0, [_boxing_input("weave_left_enabled", 3.0)]))

	assert_eq(first[0].judgement, ModeJudgementEvent.RESULT_HIT)
	assert_eq(second[0].judgement, ModeJudgementEvent.RESULT_HIT)
	assert_eq(third[0].judgement, ModeJudgementEvent.RESULT_HIT)
	assert_eq(third[2].summary.score, 300)
	assert_eq(third[2].summary.max_combo, 3)

func test_punch_inputs_with_args_are_ignored_to_preserve_no_arg_contract() -> void:
	var runner := BoxingModeRunner.new()
	runner.start(_config([
		_target("jab", "straight_left", 1.0)
	]))

	var ignored := runner.tick(_frame(1.0, [
		{"event": "straight_left", "position_sec": 1.0, "args": [0.9]}
	]))
	var miss := runner.tick(_frame(1.21, []))

	assert_eq(ignored.size(), 0)
	assert_eq(miss[0].judgement, ModeJudgementEvent.RESULT_MISS)

func _config(targets: Array) -> ModeRunConfig:
	return ModeRunConfig.new({
		"mode_id": "boxing",
		"chart_id": "fixture_chart",
		"chart_data": {
			"targets": targets
		}
	})

func _target(id: String, event: String, position_sec: float) -> Dictionary:
	return {
		"id": id,
		"event": event,
		"position_sec": position_sec,
		"early_window_sec": 0.18,
		"late_window_sec": 0.18
	}

func _boxing_input(event: String, position_sec: float) -> Dictionary:
	return {
		"contract": "aerobeat.boxing.input.v1",
		"event": event,
		"position_sec": position_sec,
		"args": []
	}

func _frame(position_sec: float, inputs: Array) -> ModeTickFrame:
	return ModeTickFrame.new({
		"position_sec": position_sec,
		"delta_sec": 0.1,
		"input_events": inputs
	})
