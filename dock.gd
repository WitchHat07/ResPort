@tool
extends Control

enum Mode { EXPORT, IMPORT }
var version: String:
	get: return $Version.text
	set(value): $Version.text = "v" + value

#region Memory
const MEMORY_PATH := "res://addons/ResPort/memory.json"
func _ready():
	var data: Dictionary = {}
	if FileAccess.file_exists(MEMORY_PATH):
		var file_text := ResPort.read_text_file(MEMORY_PATH)
		if not file_text.is_empty():
			data = JSON.parse_string(file_text)
	script_name = data.get("script_name", "")
	root_directory = data.get("root_directory", "")
	csv_path = data.get("csv_path", "")
	var found_map: Dictionary = data.get("script_map", {})
	apply_script_map(found_map)
	reset_validation()
func _exit_tree():
	refresh_script_map_cache()
	var data := {
		"script_name": script_name,
		"root_directory": root_directory,
		"csv_path": csv_path,
		"script_map": script_map.duplicate(true),
	}
	var json := JSON.stringify(data)
	ResPort.write_text_file(MEMORY_PATH, json)
#endregion

#region Import/Export
const REQUIRED_EXPORT_METHODS := ["to_csv_header", "to_csv_fields"]
const REQUIRED_IMPORT_METHODS := ["to_csv_header", "apply_csv_fields"]
const DELIMITER := "|"
const HEADER_BASE: Array[String] = ["Path"]
var script_name: String:
	get: return %ScriptName.text
	set(value): %ScriptName.text = value
var root_directory: String:
	get: return %RootDirectory.text
	set(value): %RootDirectory.text = value
var csv_path: String:
	get: return %CsvPath.text
	set(value): %CsvPath.text = value
var mode: Mode:
	get: return %Mode.selected as Mode
	set(value): %Mode.selected = value
var notice: String:
	get: return %Notice.text
	set(value): 
		%Notice.text = value
		%Notice.visible = not value.is_empty()
@export var execute_button: Button
func reset_validation():
	export_valid = false
	import_valid = false
	execute_button.disabled = true
	notice = ""
func _on_import_export_value_changed():
	reset_validation()
func _on_validate_button_pressed():
	reset_validation()
	refresh_script_map_cache()
	match mode:
		Mode.EXPORT: validate_export()
		Mode.IMPORT: validate_import()
func _on_execute_button_pressed():
	match mode:
		Mode.EXPORT: perform_export()
		Mode.IMPORT: perform_import()
# EXPORTING
var export_valid: bool = true
var export_resources: Array[Resource] = []
func validate_export():
	export_resources.clear()
	export_valid = false
	# VALIDATE CSV
	if not csv_path.ends_with(".csv"):
		notice = "CSV path must end in '.csv'!"
		return
	# VALIDATE SCRIPT CREATION
	if not script_map.has(script_name):
		notice = "Script '%s' not found in SCRIPT_MAP - unable to make new" % script_name
		return
	var resource := _create_resource_from_script_name(script_name)
	if not resource:
		notice = "Failed to initialize a resource from Script!"
		return
	# VALIDATE SCRIPT HANDLING
	for f in REQUIRED_EXPORT_METHODS:
		if not resource.has_method(f):
			notice = "Script missing '%s' func!" % f
			return
	var script_header: Array[String] = resource.to_csv_header()
	for field in script_header:
		if HEADER_BASE.has(field):
			notice = "Header collision - '%s' cannot be used as a field in Script!"
			return
	# VALIDATE DISCOVERED
	ResPort.scan_directory_recursive(root_directory, script_name, export_resources)
	if export_resources.is_empty():
		notice = "No %s(s) were found at provided root directory" % script_name
		return
	# FLAG VALID
	notice = "%d %s(s) discovered" % [export_resources.size(), script_name]
	export_valid = true
	execute_button.disabled = false
func perform_export() -> void:
	if not export_valid:
		return
	var resource: Resource = export_resources[0]
	print("Exporting %d resources to CSV" % export_resources.size())
	# ADD HEADER TO TOP
	var full_header: Array[String] = HEADER_BASE + resource.to_csv_header()
	var content := _to_csv_line(full_header)
	# FILL IN ALL THE RESOURCES FIELDS
	for r in export_resources:
		var fields: Array[String] = [r.resource_path]
		fields += r.to_csv_fields()
		content += _to_csv_line(fields)
	if content.is_empty():
		return
	ResPort.write_text_file(csv_path, content)
	_open_csv_file()
func _to_csv_line(string_array: Array[String]) -> String:
	if string_array.is_empty():
		return ""
	return DELIMITER.join(string_array) + "\n"
# IMPORTING
var import_valid: bool = false
var import_header: PackedStringArray = []
var import_records: PackedStringArray = []
func validate_import():
	import_header.clear()
	import_records.clear()
	import_valid = false
	# VALIDATE SCRIPT CREATION
	if not script_map.has(script_name):
		notice = "Script '%s' not found in SCRIPT_MAP - unable to make new" % script_name
		return
	var resource := _create_resource_from_script_name(script_name)
	if not resource:
		notice = "Failed to initialize a resource from Script!"
		return
	# VALIDATE SCRIPT HANDLING
	for f in REQUIRED_IMPORT_METHODS:
		if not resource.has_method(f):
			notice = "Script missing '%s' func!" % f
			return
	var script_header: Array[String] = resource.to_csv_header()
	for field in script_header:
		if HEADER_BASE.has(field):
			notice = "Script header field collides with base field '%s'" % field
			return
	# VALIDATE CSV
	if not csv_path.ends_with(".csv"):
		notice = "CSV path must end in '.csv'!"
		return
	var file_text := ResPort.read_text_file(csv_path)
	import_records = file_text.split("\n", false)
	# VALIDATE HEADER
	if import_records.is_empty():
		notice = "CSV missing header!"
		return
	import_header = _csv_line_to_packed_array(import_records[0])
	import_records.remove_at(0)
	for field in HEADER_BASE:
		if not import_header.has(field):
			notice = "CSV header missing base field '%s'" % field
			return
	for field in script_header:
		if not import_header.has(field):
			notice = "CSV header missing Script field '%s'" % field
			return
	# VALIDATE RECORDS
	if import_records.is_empty():
		notice = "CSV contains no records!"
		return
	# FLAG VALID
	import_valid = true
	execute_button.disabled = false
	notice = "%d %s records ready for import" % [import_records.size(), script_name]
func perform_import():
	if not import_valid:
		return
	# Perform import
	var path_index := HEADER_BASE.find("Path")
	var error_count := 0
	for record in import_records:
		var all_fields := _csv_line_to_packed_array(record)
		var path: String = all_fields[path_index]
		var apply_fields := all_fields.slice(HEADER_BASE.size())
		var resource: Resource
		if ResourceLoader.exists(path): 
			resource = ResourceLoader.load(path)
		if not resource: 
			resource = _create_resource_from_script_name(script_name)
		if not resource:
			ResPort.warn("Failed to initialize resource at path - %s" % path)
			error_count += 1
			continue
		resource.apply_csv_fields(apply_fields)
		ResPort.save_resource(resource, path)
	notice = "%d %s(s) imported" % [import_records.size(), script_name]
	if error_count > 0:
		notice += " with %d errors" % error_count
func _csv_line_to_packed_array(str: String) -> PackedStringArray:
	str = str.replace("\r", "")
	return str.split(DELIMITER)
#endregion

#region Settings
var script_block_ps: PackedScene = load("res://addons/ResPort/script_block.tscn")
@export var script_block_container: VBoxContainer
var script_map: Dictionary[String, String] = {}
func apply_script_map(map: Dictionary):
	# Create Controls
	script_map.clear()
	for child in script_block_container.get_children():
		child.queue_free()
	for key in map.keys():
		add_script_block(key, map[key])
	refresh_script_map_cache()
func add_script_block(_name: String, _path: String, at_top: bool = false) -> Control:
	var new_block = script_block_ps.instantiate()
	script_block_container.add_child(new_block)
	new_block.script_name = _name
	new_block.script_path = _path
	if at_top:
		script_block_container.move_child(new_block, 0)
	return new_block
func refresh_script_map_cache():
	script_map.clear()
	for child in script_block_container.get_children():
		var block_name = child.get("script_name")
		if not block_name or block_name.is_empty():
			continue
		var block_path = child.get("script_path")
		if not block_path or block_path.is_empty():
			continue
		script_map[block_name] = block_path
#endregion

#region Helpers
func _create_resource_from_script_name(_name: String) -> Resource:
	if not script_map.has(_name):
		ResPort.warn("Unknown script name: %s" % _name)
		return null
	var script_path: String = script_map[_name]
	var script := ResourceLoader.load(script_path) as Script
	if script == null:
		ResPort.warn("Failed to load script: %s" % script_path)
		return null
	var instance = script.new()
	if not instance is Resource:
		ResPort.warn("Script does not extend Resource: %s" % script_path)
		return null
	return instance
func _open_csv_file():
	if not FileAccess.file_exists(csv_path):
		notice = "CSV file does not exist!"
		return
	var full_csv_path := ProjectSettings.globalize_path(csv_path)
	OS.shell_open(full_csv_path)
#endregion
