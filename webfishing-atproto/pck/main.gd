extends Node

var config: Dictionary

const ATPROTO_SLOT = 99
var save_loaded: String

const CONFIG_PATH = "user://atproto-config.json"
var default_config: Dictionary = {
	Autoconnect = false,
	Autoload = false,
	Handle = "",
	Password = "",
	Save = ""
}

const AtProtoClient_t := preload("res://mods/Atproto/atproto_client.gd")
var AtProtoClient: AtProtoClient_t

# UI
const AtProtoMenu := preload("res://mods/Atproto/ui/menus/atproto_config.tscn")
const AtProtoButton := preload("res://mods/Atproto/ui/buttons/atproto.tscn")

var setuped = false

func _enter_tree():
	AtProtoClient = AtProtoClient_t.new()
	add_child(AtProtoClient)
	AtProtoClient.connect("savefile_loaded", self, "set_save_file")
	get_tree().connect("node_added", self, "_add_atproto_menu")
	
	
func _ready() -> void:
	_init_config()

func _init_config():
	var config_file = File.new()
	
	if not config_file.file_exists(CONFIG_PATH):
		config = default_config
		_save_config()
		
	config_file.open(CONFIG_PATH, File.READ)
	var saved_config = JSON.parse(config_file.get_line()).result

	for key in default_config.keys():
		if not saved_config.has(key):
			saved_config[key] = default_config[key]
	config = saved_config
	if config.Autoconnect == true:
		AtProtoClient.login(config.Handle, config.Password)

func _save_config():
	var config_file = File.new()
	config_file.open(CONFIG_PATH, File.WRITE)
	config_file.store_line(JSON.print(config))
	config_file.close()
	return

func _add_atproto_menu(node: Node):
	if node.name == "main_menu":
		var atproto_menu: Node = AtProtoMenu.instance()
		atproto_menu.visible = false
		node.add_child(atproto_menu)
		
		var button = AtProtoButton.instance()
		var menu_list: Node = node.get_node("VBoxContainer")
		var settings_button: Node = menu_list.get_node("settings")
		menu_list.add_child(button)
		menu_list.move_child(button, settings_button.get_index() + 1)
		atproto_menu.connect("setup_done", self, "_after_setup")
	pass

func _after_setup():
	if setuped:
		return
	setuped = true
	
	if config.Save != "" and config.Autoload and AtProtoClient.connected():
		AtProtoClient.load_save(config.Save)

func can_save_to_atproto():
	return AtProtoClient.can_save && UserSave.current_loaded_slot == ATPROTO_SLOT && AtProtoClient.connected()

func set_save_file(save_uri):
	save_loaded = save_uri
