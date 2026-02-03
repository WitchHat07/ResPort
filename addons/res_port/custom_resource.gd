@tool
extends Panel
class_name ResPortResource

@export var name_field: Label
var global_name: String:
	get: return name_field.text
	set(value): name_field.text = value
@export var path_field: Label
var script_path: String:
	get: return path_field.text
	set(value):
		path_field.text = value
		global_name = ""
		var script := ResourceLoader.load(value) as Script
		if script:
			global_name = script.get_global_name()
		toggle_valid(not global_name.is_empty())

@export var valid_color: Color
@export var invalid_color: Color
func toggle_valid(on: bool):
	name_field.self_modulate = valid_color if on else invalid_color
	#path_field.self_modulate = valid_color if on else invalid_color

signal deleted
func delete():
	deleted.emit()
	queue_free()

var is_valid := false
func validate() -> String:
	var err := ResPort.try_identify_resource_error(script_path)
	is_valid = err.is_empty()
	if not is_valid:
		name_field.self_modulate = invalid_color
	return err

func create_instance() -> Resource:
	var script := ResourceLoader.load(script_path) as Script
	if script == null:
		ResPort.warn("Failed to load Resource script: %s" % script_path)
		return null
	var instance = script.new()
	if not instance is Resource:
		ResPort.warn("Script does not extend Resource: %s" % script_path)
		return null
	return instance
