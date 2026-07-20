@tool
extends EditorExportPlugin

class_name GDCCDebugRemoverPlugin

func _get_name() -> String:
	return "GDCCDebugRemoverPlugin"

func _export_file(path: String, type: String, features: PackedStringArray) -> void:
	
	if not path.ends_with(".gd"):
		return
	
	var file := FileAccess.open(path, FileAccess.READ)
	
	if not file:
		return
	
	var source := file.get_as_text()
	file.close()
	
	if not "#:" in source:
		return
	
	var cleaned_source := ""
	
	add_file(path, cleaned_source.to_utf8_buffer(), true)

func _remove_debug_lines(source: String) -> String:
	
	var lines := source.split("\n")
	var new_lines: PackedStringArray = []
	var skip_next_line := false
	
	for line in lines:
		
		var trimmed = line.strip_edges()
		
		if trimmed == "#: debug_only":
			skip_next_line = true
			continue
		
		if skip_next_line:
			skip_next_line = false
			continue
		
		if "#: debug_only" in line:
			continue
		
		new_lines.append(line)
	
	return "\n".join(new_lines)
