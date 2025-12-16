extends GenericUIButton


func _on_mods_pressed() -> void:
	var atproto_menu = $"../../atproto_config"
	atproto_menu._refresh()
	atproto_menu.visible = true
