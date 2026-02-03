@tool
extends Node

const DELIMITER := "|"
const REQUIRED_EXPORT_METHODS := ["to_csv_header", "to_csv_fields"]
const REQUIRED_IMPORT_METHODS := ["to_csv_header", "apply_csv_fields"]
const HEADER_BASE: Array[String] = ["Path"]

#region Read/Write IO
func write_text_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		warn("Failed to open file '%s' for write" % path)
		return
	file.store_string(text)
	file.close()
func read_text_file(path: String) -> String:
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		var file_text := ""
		if not file: warn("Failed to read text file '%s' - read failed" % path)
		else: file_text = file.get_as_text()
		file.close()
		return file_text
	else: warn("Failed to read text file '%s' - file does not exist" % path)
	return ""
func is_path_inside_project(path: String) -> bool:
	var project_root := ProjectSettings.globalize_path("res://")
	var target_path := ProjectSettings.globalize_path(path)
	# Normalize slashes (important on Windows)
	project_root = project_root.simplify_path()
	target_path = target_path.simplify_path()
	return target_path.begins_with(project_root)
func scan_directory_recursive(dir_path: String, script_name: String, out: Array[Resource]):
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if file_name.begins_with("."):
			continue
		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			scan_directory_recursive(full_path, script_name, out)
			continue
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var res := ResourceLoader.load(full_path)
		if res == null:
			continue
		if get_script_name(res) == script_name:
			out.append(res)
	dir.list_dir_end()
func save_resource(resource: Resource, path: String):
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		warn("Failed to save resource '%s'" % path)
#endregion

#region Other
func warn(msg: String):
	pretty_print(name + ": " + msg, Color.ORANGE)
func pretty_print(message: String, color_input):
	print_rich(colorful_string(message, color_input))
func color_to_hex(color: Color) -> String:
	return "#" + color.to_html(false)
func colorful_string(text: String, color) -> String:
	var color_hex: String = ""
	if typeof(color) == TYPE_STRING:
		color_hex = color
	elif typeof(color) == TYPE_COLOR:
		color_hex = color_to_hex(color)
	else:
		return text
	return "[color=%s]%s[/color]" % [color_hex, text]
func get_script_name(obj: Object) -> String:
	var _script: Script = obj.get_script()
	if _script:
		var string_name: StringName = _script.get_global_name()
		if not string_name.is_empty(): return str(string_name)
	return ""
#endregion

#region Validation
func try_identify_resource_error(script_path: String) -> String:
	if not ResourceLoader.exists(script_path):
		return "Path invalid"
	var script := ResourceLoader.load(script_path) as Script
	if script == null:
		return "Failed to load script"
	if not script.is_tool():
		return "Script is not a tool"
	var found_name := script.get_global_name()
	if found_name.is_empty():
		return "Failed to determine script name"
	# Instantiate the script
	var instance: Resource = script.new()
	if instance == null:
		return "%s could not be instantiated" % found_name
	# Validate it extends Resource
	if not instance is Resource:
		return "%s does not extend Resource" % found_name
	# Validate required methods
	for f in REQUIRED_IMPORT_METHODS + REQUIRED_EXPORT_METHODS:
		if not instance.has_method(f):
			return "Resource script missing method '%s'" % f
	# Validate functions
	# to_csv_header
	var header = instance.to_csv_header()
	var header_err := try_identify_string_array_error("to_csv_header", header)
	if not header_err.is_empty():
		return header_err
	elif header.is_empty():
		return "to_csv_header() returned 0 fields"
	for field in header:
		if HEADER_BASE.has(field):
			return "Resource script header field collides with base field '%s'" % field
	# to_csv_fields
	var fields = instance.to_csv_fields()
	var fields_err := try_identify_string_array_error("to_csv_fields", fields)
	if not fields_err.is_empty():
		return fields_err
	elif fields.is_empty():
		return "to_csv_fields() returned 0 fields"
	return ""
func try_identify_string_array_error(method_name: String, result: Variant) -> String:
	if result == null:
		return "%s() returned null. Must return Array[String]" % method_name
	if not result is Array:
		var type := describe_type(result)
		return "%s() returned %s. Must return Array[String]" % [method_name, type]
	for i in result.size():
		if not result[i] is String:
			return "%s() element %d is not a String" % [method_name, i]
	return ""
func describe_type(value) -> String:
	if value == null:
		return "null"
	match typeof(value):
		TYPE_STRING:
			return "String"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_ARRAY:
			return "Array"
		TYPE_DICTIONARY:
			return "Dictionary"
		TYPE_OBJECT:
			var cls = value.get_class()
			var script = value.get_script()
			if script and not script.get_global_name().is_empty():
				return "%s (%s)" % [cls, script.get_global_name()]
			return cls
		_:
			return "Unknown"
#endregion
