@tool
extends Control

enum Mode { EXPORT, IMPORT }
var version: String:
	get: return $Version.text
	set(value): $Version.text = "v" + value

#region Memory
const MEMORY_PATH := "res://addons/res_port/memory.json"
func _ready():
	var data: Dictionary = {}
	if FileAccess.file_exists(MEMORY_PATH):
		var file_text := ResPort.read_text_file(MEMORY_PATH)
		if not file_text.is_empty():
			data = JSON.parse_string(file_text)
	root_directory = data.get("root_directory", "")
	csv_path = data.get("csv_path", "")
	var resource_paths: PackedStringArray = data.get("custom_resources_paths", [])
	load_custom_resource_memory(resource_paths)
	%ResourceType.selected = data.get("selected_resource", -1)
	if not data.get("seen_help", false):
		$TabContainer/Help.show()
		save_memory()
	else: $TabContainer/Actions.show()
	reset_validation()
#func _exit_tree():
	#save_memory()
func save_memory():
	var data := {
		"selected_resource": %ResourceType.selected,
		"root_directory": root_directory,
		"csv_path": csv_path,
		"custom_resources_paths": custom_resources_to_map(),
		"seen_help": true
	}
	var json := JSON.stringify(data)
	ResPort.write_text_file(MEMORY_PATH, json)
	#print("Memory Saved")
#endregion

#region Import/Export
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
	# VALIDATE RESOURCE TYPE
	if selected_resource == null:
		notice = "Select a valid Resource Type"
		return
	var resource_err := selected_resource.validate()
	if not resource_err.is_empty():
		notice = resource_err
		return
	var instance := selected_resource.create_instance()
	if not instance:
		notice = "Failed to initialize a resource from Resource Type"
		return
	# VALIDATE DISCOVERED
	var global_name := selected_resource.global_name
	ResPort.scan_directory_recursive(root_directory, global_name, export_resources)
	if export_resources.is_empty():
		notice = "No %s(s) were found at provided root directory" % global_name
		return
	# FLAG VALID
	notice = "%d %s(s) discovered" % [export_resources.size(), global_name]
	export_valid = true
	execute_button.disabled = false
	save_memory()
func perform_export() -> void:
	if not export_valid:
		return
	var resource: Resource = export_resources[0]
	print("Exporting %d resources to CSV" % export_resources.size())
	# ADD HEADER TO TOP
	var full_header: Array[String] = ResPort.HEADER_BASE + resource.to_csv_header()
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
	return ResPort.DELIMITER.join(string_array) + "\n"
# IMPORTING
var import_valid: bool = false
var import_header: PackedStringArray = []
var import_records: PackedStringArray = []
func validate_import():
	import_header.clear()
	import_records.clear()
	import_valid = false
	# VALIDATE RESOURCE TYPE
	if selected_resource == null:
		notice = "Select a valid Resource Type"
		return
	var resource_err := selected_resource.validate()
	if not resource_err.is_empty():
		notice = resource_err
		return
	var instance := selected_resource.create_instance()
	if not instance:
		notice = "Failed to initialize a resource from Resource Type"
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
	for field in ResPort.HEADER_BASE:
		if not import_header.has(field):
			notice = "CSV header missing base field '%s'" % field
			return
	var script_header: Array[String] = instance.to_csv_header()
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
	notice = "%d %s records ready for import" % [import_records.size(), selected_resource.global_name]
	save_memory()
func perform_import():
	if not import_valid:
		return
	# Perform import
	var path_index := ResPort.HEADER_BASE.find("Path")
	var error_count := 0
	for record in import_records:
		var all_fields := _csv_line_to_packed_array(record)
		var path: String = all_fields[path_index]
		var apply_fields := all_fields.slice(ResPort.HEADER_BASE.size())
		var resource: Resource
		if ResourceLoader.exists(path): 
			resource = ResourceLoader.load(path)
		if not resource: 
			resource = selected_resource.create_instance()
		if not resource:
			ResPort.warn("Failed to initialize resource at path - %s" % path)
			error_count += 1
			continue
		resource.apply_csv_fields(apply_fields)
		ResPort.save_resource(resource, path)
	notice = "%d %s(s) imported" % [import_records.size(), selected_resource.global_name]
	if error_count > 0:
		notice += " with %d errors" % error_count
func _csv_line_to_packed_array(str: String) -> PackedStringArray:
	str = str.replace("\r", "")
	return str.split(ResPort.DELIMITER)
#endregion

#region CSV Path Prompting
func toggle_csv_path_edit(toggled_on: bool):
	$ClickBlock.visible = toggled_on
	$CsvDialog.visible = toggled_on
	%CsvPath.unedit()
func _on_csv_path_editing_toggled(toggled_on: bool) -> void:
	toggle_csv_path_edit(toggled_on)
func _on_csv_dialog_canceled() -> void:
	toggle_csv_path_edit(false)
func _on_csv_dialog_file_selected(path: String) -> void:
	if ResPort.is_path_inside_project(path):
		# Prompt confirmation of in-project path
		await get_tree().process_frame
		$WithinProjectConfirm.show()
	else:
		# Confirm external path immediately
		toggle_csv_path_edit(false)
		csv_path = $CsvDialog.current_path
func _on_within_project_confirm_canceled() -> void:
	# User has canceled the in-project path select
	csv_path = ""
	toggle_csv_path_edit(false)
func _on_within_project_confirm_confirmed() -> void:
	# User has selected to use the path anyways
	toggle_csv_path_edit(false)
	csv_path = $CsvDialog.current_path
#endregion

#region Custom Resources
var custom_resource_ps: PackedScene = load("res://addons/res_port/custom_resource.tscn")
@export var custom_resource_container: VBoxContainer
var resource_notice: String:
	set(value):
		%ResourceNotice.text = value
		%ResourceNotice.visible = not value.is_empty()
var custom_resources: Array[ResPortResource]
var selected_resource: ResPortResource:
	get:
		var res_index: int = %ResourceType.selected
		if res_index < 0 or res_index >= custom_resources.size():
			return null
		return custom_resources[res_index]
func refresh_resource_dropdown():
	%ResourceType.clear()
	for res in custom_resources:
		%ResourceType.add_item(res.global_name)
	if selected_resource == null:
		%ResourceType.selected = -1 
func custom_resources_to_map() -> PackedStringArray:
	var result: PackedStringArray
	for res in custom_resources:
		res.validate()
		if res.is_valid:
			result.append(res.script_path)
	return result
func load_custom_resource_memory(array: PackedStringArray):
	clear_custom_resources()
	for value in array:
		add_custom_resource(value)
	refresh_resource_dropdown()
# NEW CUSTOM RESOURCE PROMPTING
func prompt_script_dialogue():
	resource_notice = ""
	$ScriptDialog.show()
func _on_script_dialog_file_selected(path: String) -> void:
	var error_msg := ResPort.try_identify_resource_error(path)
	if not error_msg.is_empty():
		resource_notice = error_msg
		return
	for res in custom_resources:
		if is_instance_valid(res) and res.script_path == path:
			resource_notice = "Resource Type already exists"
			return
	resource_notice = ""
	add_custom_resource(path, true)
	refresh_resource_dropdown()
	save_memory()
func _on_script_dialog_canceled() -> void:
	resource_notice = ""
# RES ADDITION
func add_custom_resource(_path: String, at_top: bool = false) -> ResPortResource:
	var new_config: ResPortResource = custom_resource_ps.instantiate()
	custom_resource_container.add_child(new_config)
	custom_resources.append(new_config)
	new_config.script_path = _path
	new_config.deleted.connect(Callable(self, "_on_custom_resource_deleted").bind(new_config), CONNECT_ONE_SHOT)
	if at_top:
		custom_resource_container.move_child(new_config, 0)
	return new_config
# RES REMOVAL
func remove_custom_resource(remove: ResPortResource):
	if is_instance_valid(remove) and custom_resources.has(remove):
		custom_resources.erase(remove)
func _on_custom_resource_deleted(res: ResPortResource):
	remove_custom_resource(res)
	refresh_resource_dropdown()
	save_memory()
func clear_custom_resources():
	custom_resources.clear()
	%ResourceType.clear()
	for child in custom_resource_container.get_children():
		child.queue_free()
#endregion

#region Helpers
func _open_csv_file():
	if not FileAccess.file_exists(csv_path):
		notice = "Failed to open CSV file"
		return
	var full_csv_path := ProjectSettings.globalize_path(csv_path)
	OS.shell_open(full_csv_path)
#endregion
