@tool
extends EditorPlugin

var debug_remover := GDCCDebugRemoverPlugin.new()

func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	add_export_plugin(debug_remover)
	
	var script_editor := EditorInterface.get_script_editor()
	
	if not script_editor.editor_script_changed.is_connected(_on_script_changed):
		script_editor.editor_script_changed.connect(_on_script_changed)
	
	_apply_highlighter_to_current()


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	remove_export_plugin(debug_remover)
	
	var script_editor = EditorInterface.get_script_editor()
	
	if script_editor.editor_script_changed.is_connected(_on_script_changed):
		script_editor.editor_script_changed.disconnect(_on_script_changed)

func _on_script_changed(_script: Script) -> void:
	_apply_highlighter_to_current()

func _apply_highlighter_to_current() -> void:
	var script_editor := EditorInterface.get_script_editor()
	var current_editor := script_editor.get_current_editor()
	
	if not current_editor:
		return
	
	var code := current_editor.get_base_editor() as CodeEdit
	
	if not code:
		return
	
	if code.syntax_highlighter is GDCCSyntaxHighlighter:
		return
	
	var wrapper := GDCCSyntaxHighlighter.new()
	wrapper.base_high = code.syntax_highlighter
	
	code.syntax_highlighter = wrapper
	
	code.notify_property_list_changed()
	code.queue_redraw()
