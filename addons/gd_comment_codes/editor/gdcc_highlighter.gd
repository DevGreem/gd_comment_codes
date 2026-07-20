@tool
extends SyntaxHighlighter

class_name GDCCSyntaxHighlighter

#func _get_name() -> String:
	#return "GDCCSyntaxHighlighter"
#
#func _get_supported_languages() -> PackedStringArray:
	#return ["GDScript"]

var base_high: SyntaxHighlighter:
	set(value):
		
		if base_high == self:
			return
		
		base_high = value

func _get_line_syntax_highlighting(line: int) -> Dictionary:
	var dict := {}
	
	if base_high:
		var base_dict := base_high.get_line_syntax_highlighting(line)
		
		if base_dict != null:
			dict = base_dict.duplicate(true)
	
	var text := get_text_edit()
	
	if not text:
		return dict
	
	var line_edit := text.get_line(line)
	
	var pos := line_edit.find("#:")
	
	if pos != -1:
		dict[pos] = {"color": Color(1.0, 0.65, 0.0)}
	
	return dict
