@tool
extends EditorPlugin

const GLOBAL_NAME := "ResPort"
const GLOBAL_SCRIPT_PATH := "res://addons/res_port/res_port.gd"
const DOCK_PATH := "res://addons/res_port/dock.tscn"
var dock_instance: Control

func _enter_tree() -> void:
	if not ProjectSettings.has_setting("autoload/%s" % GLOBAL_NAME):
		add_autoload_singleton(GLOBAL_NAME, GLOBAL_SCRIPT_PATH)
	dock_instance = load(DOCK_PATH).instantiate()
	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock_instance)
	dock_instance.version = get_plugin_version()

func _exit_tree() -> void:
	if is_instance_valid(dock_instance):
		remove_control_from_docks(dock_instance)
		dock_instance.queue_free()
	if ProjectSettings.has_setting("autoload/%s" % GLOBAL_NAME):
		remove_autoload_singleton(GLOBAL_NAME)
