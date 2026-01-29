@tool
extends Panel

@export var name_edit: LineEdit
var script_name: String:
	get: return name_edit.text
	set(value): name_edit.text = value
@export var path_edit: LineEdit
var script_path: String:
	get: return path_edit.text
	set(value): path_edit.text = value

signal deleted
func delete():
	deleted.emit()
	queue_free()
