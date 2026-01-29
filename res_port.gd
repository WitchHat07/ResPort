@tool
extends Node

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
