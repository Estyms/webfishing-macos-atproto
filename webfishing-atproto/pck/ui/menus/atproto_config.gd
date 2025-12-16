extends Node

onready var Atproto := $"/root/Atproto"

const AtProtoNewSaveMenu := preload("res://mods/Atproto/ui/menus/new_save.tscn")

signal setup_done()

var SaveMenu: Node
var Settings: VBoxContainer
var Credentials: VBoxContainer
var Saves : VBoxContainer

func _ready():
	Atproto.AtProtoClient.connect("savefile_loaded", self, "set_save_file")
	Settings = $"%atproto_settings"
	Credentials = Settings.get_node("credentials")
	Saves = Settings.get_node("saves")
	init_save_menu()
	init_credentials()
	
	if Atproto.AtProtoClient.connected() :
		after_login()
	else:
		init_saves()

func init_credentials() -> void:
	
	Credentials.get_node("handle/LineEdit").text = Atproto.config.Handle
	Credentials.get_node("password/LineEdit").text = Atproto.config.Password
	
	var autoconnect: OptionButton = Credentials.get_node("autoconnect").get_node("OptionButton")
	autoconnect.add_item("No", 0)
	autoconnect.set_item_metadata(0, false)
	autoconnect.add_item("Yes", 1)
	autoconnect.set_item_metadata(1, true)
	
	if Atproto.config.Autoconnect:
		autoconnect.select(1)
	
func init_saves(saves = []) -> void:
	var new_save_button: Button = Saves.get_node("buttons").get_node("new_save")
	var load_save_button: Button = Saves.get_node("buttons").get_node("load_save")
	
	var autoload: OptionButton = Saves.get_node("autoload").get_node("OptionButton")
	autoload.clear()
	autoload.add_item("No", 0)
	autoload.set_item_metadata(0, false)
	autoload.add_item("Yes", 1)
	autoload.set_item_metadata(1, true)
	if Atproto.config.Autoload:
		autoload.select(1)
	
	var save_option: OptionButton = Saves.get_node("save").get_node("OptionButton")
	save_option.clear()
	if Atproto.AtProtoClient.connected():
		var i = 0
		for save_record in saves:
			var save = save_record.value
			save_option.add_item(save.name)
			save_option.set_item_metadata(save_option.get_item_count()-1, save.uri)
			if Atproto.config.Save == save.uri:
				save_option.select(i)
			i += 1
		save_option.disabled = save_option.get_item_count() == 0
		load_save_button.disabled = save_option.get_item_count() == 0
		new_save_button.disabled = false
	else:
		save_option.disabled = true
		save_option.add_item("No saves")
		
		load_save_button.disabled = true
		new_save_button.disabled = true
	
	_refresh()
	emit_signal("setup_done")

func _on_apply_pressed() -> void:
	var save : OptionButton = Saves.get_node("save/OptionButton")
	Atproto.config.Autoload = Saves.get_node("autoload/OptionButton").get_selected_id() == 1
	if (Atproto.config.Save != save.get_selected_metadata() or Atproto.save_loaded != save.get_selected_metadata())  and Atproto.config.Autoload:
		Atproto.AtProtoClient.load_save(save.get_selected_metadata())

	
	var autoconnect: OptionButton = Credentials.get_node("autoconnect").get_node("OptionButton")
	
	Atproto.config.Autoconnect = autoconnect.get_selected_id() == 1
	

	Atproto.config.Handle = Credentials.get_node("handle/LineEdit").text
	Atproto.config.Password = Credentials.get_node("password/LineEdit").text
	
	Atproto._save_config()
	
	set("visible", false)

func _on_close_pressed() -> void:
	set("visible", false)


func start_loading():
	var panel = get_node("Panel")
	panel.get_node("Loader").set("visible", true)
	panel.get_node("close").set("disabled", true)
	panel.get_node("apply").set("disabled", true)

func stop_loading():
	var panel = get_node("Panel")
	panel.get_node("Loader").set("visible", false)
	panel.get_node("close").set("disabled", false)
	panel.get_node("apply").set("disabled", false)

# CONNECTION

func _on_connect_button_button_down():
	var handle_field : LineEdit = Credentials.get_node("handle/LineEdit")
	var password_field : LineEdit = Credentials.get_node("password/LineEdit")
	Atproto.AtProtoClient.connect("connection", self, "_after_connect")
	start_loading()
	Atproto.AtProtoClient.login(handle_field.text, password_field.text)

func _after_connect(success):
	if !success:
		PopupMessage._show_popup("An error has occured !")
	else:
		PopupMessage._show_popup("Connection successful !")
		after_login()
	stop_loading()

func after_login(_a = null):
	Atproto.AtProtoClient.get_saves(funcref(self, "init_saves"))
	
func _refresh():
	$"%atproto_settings/save_info".text = get_loaded_save_info()

func get_loaded_save_info():
	if UserSave.current_loaded_slot != Atproto.ATPROTO_SLOT:
		return "No AtProto save loaded"
	else:
		var save_option: OptionButton = Saves.get_node("save").get_node("OptionButton")
		var i = 0
		while i < save_option.get_item_count():
			var metadata = save_option.get_item_metadata(i)
			if metadata == Atproto.save_loaded:
				return save_option.get_item_text(i) + " is currently loaded"
			i+=1
		return "Invalid save file loaded"
# SAVES

func set_save_file(save_uri):
	Atproto.config.Save = save_uri
	PopupMessage._show_popup("AtProto save loaded : " + get_current_save_name())
	_refresh()
	pass

func _on_load_save_button_down():
	var save: OptionButton = Saves.get_node("save").get_node("OptionButton")
	Atproto.AtProtoClient.load_save(save.get_selected_metadata())
	pass


func get_current_save_name() -> String:
	if UserSave.current_loaded_slot != 99:
		return "Slot " + str(UserSave.current_loaded_slot + 1)
		
	var save_option: OptionButton = Saves.get_node("save").get_node("OptionButton")
	var i = 0
	while i < save_option.get_item_count():
			var metadata = save_option.get_item_metadata(i)
			if metadata == Atproto.save_loaded:
				return save_option.get_item_text(i)
			i+=1
	return ""

func _on_new_save_button_down():
	var current = get_current_save_name()
	if current != "":
		SaveMenu.get_node("save_menu/duplicate").text = "Duplicate " + current
		SaveMenu.get_node("save_menu/duplicate").disabled = false
	else:
		SaveMenu.get_node("save_menu/duplicate").text = "Invalid Save"
		SaveMenu.get_node("save_menu/duplicate").disabled = true
	 
	SaveMenu.visible = true


# Create Save Menu
func init_save_menu():
	SaveMenu = AtProtoNewSaveMenu.instance()
	add_child(SaveMenu)
	SaveMenu.visible = false
	var x : Button
	SaveMenu.get_node("save_menu/close").connect("button_down", self, "close_save_menu")
	SaveMenu.get_node("save_menu/duplicate").connect("button_down", self, "create_save", [true])
	SaveMenu.get_node("save_menu/new").connect("button_down", self, "create_save", [false])

func create_save(duplicate = false):
	var backup = backup_save()
	if !duplicate:
		PlayerData._reset_save()
	Atproto.AtProtoClient.create_save(funcref(self, "create_save_file"))
	close_save_menu()
	restore_save(backup)
	pass
	
func save_file_created(record):
	var file_name = SaveMenu.get_node("save_menu/Panel/save_name/LineEdit").text
	PopupMessage._show_popup("AtProto save created : " + file_name)
	SaveMenu.get_node("save_menu/Panel/save_name/LineEdit").text = ""
	after_login()
	pass
	
func create_save_file(save_record):
	var file_name = SaveMenu.get_node("save_menu/Panel/save_name/LineEdit").text
	var uri = save_record.uri
	Atproto.AtProtoClient.create_save_file(uri, file_name, funcref(self, "save_file_created"))
	pass
	
func backup_save():
	return {
		"inventory": PlayerData.inventory, 
		"hotbar": PlayerData.hotbar, 
		"cosmetics_unlocked": PlayerData.cosmetics_unlocked, 
		"cosmetics_equipped": PlayerData.cosmetics_equipped, 
		"new_cosmetics": PlayerData.new_cosmetics, 
		"version": Globals.GAME_VERSION, 
		"muted_players": PlayerData.players_muted, 
		"hidden_players": PlayerData.players_hidden, 
		"recorded_time": PlayerData.last_recorded_time, 
		"money": PlayerData.money, 
		"bait_inv": PlayerData.bait_inv, 
		"bait_selected": PlayerData.bait_selected, 
		"bait_unlocked": PlayerData.bait_unlocked, 
		"shop": PlayerData.current_shop, 
		"journal": PlayerData.journal_logs, 
		"quests": PlayerData.current_quests, 
		"completed_quests": PlayerData.completed_quests, 
		"level": PlayerData.badge_level, 
		"xp": PlayerData.badge_xp, 
		"max_bait": PlayerData.max_bait, 
		"lure_unlocked": PlayerData.lure_unlocked, 
		"lure_selected": PlayerData.lure_selected, 
		"saved_aqua_fish": PlayerData.saved_aqua_fish, 
		"inbound_mail": PlayerData.inbound_mail, 
		"rod_power": PlayerData.rod_power_level, 
		"rod_speed": PlayerData.rod_speed_level, 
		"rod_chance": PlayerData.rod_chance_level, 
		"rod_luck": PlayerData.rod_luck_level, 
		"saved_tags": PlayerData.saved_tags, 
		"loan_level": PlayerData.loan_level, 
		"loan_left": PlayerData.loan_left, 
		"buddy_level": PlayerData.buddy_level, 
		"buddy_speed": PlayerData.buddy_speed, 
		"guitar_shapes": PlayerData.guitar_shapes, 
		"fish_caught": PlayerData.fish_caught, 
		"cash_total": PlayerData.cash_total, 
		"voice_pitch": PlayerData.voice_pitch, 
		"voice_speed": PlayerData.voice_speed, 
		"locked_refs": PlayerData.locked_refs, 
	}.duplicate(true)

func restore_save(data):
	PlayerData.inventory = data.inventory
	PlayerData.hotbar = data.hotbar
	PlayerData.cosmetics_unlocked = data.cosmetics_unlocked
	PlayerData.cosmetics_equipped = data.cosmetics_equipped
	PlayerData.new_cosmetics = data.new_cosmetics
	PlayerData.players_muted = data.muted_players
	PlayerData.players_hidden = data.hidden_players
	PlayerData.last_recorded_time = data.recorded_time
	PlayerData.money = data.money
	PlayerData.bait_inv = data.bait_inv
	PlayerData.bait_selected = data.bait_selected
	PlayerData.bait_unlocked = data.bait_unlocked
	PlayerData.current_shop = data.shop
	PlayerData.journal_logs = data.journal
	PlayerData.current_quests = data.quests
	PlayerData.completed_quests = data.completed_quests
	PlayerData.badge_level = data.level
	PlayerData.badge_xp = data.xp
	PlayerData.max_bait = data.max_bait
	PlayerData.lure_unlocked = data.lure_unlocked
	PlayerData.lure_selected = data.lure_selected
	PlayerData.saved_aqua_fish = data.saved_aqua_fish
	PlayerData.inbound_mail = data.inbound_mail
	PlayerData.rod_power_level = data.rod_power
	PlayerData.rod_speed_level = data.rod_speed
	PlayerData.rod_chance_level = data.rod_chance
	PlayerData.rod_luck_level = data.rod_luck
	PlayerData.saved_tags = data.saved_tags
	PlayerData.loan_level = data.loan_level
	PlayerData.loan_left = data.loan_left
	PlayerData.buddy_level = data.buddy_level
	PlayerData.buddy_speed = data.buddy_speed
	PlayerData.guitar_shapes = data.guitar_shapes
	PlayerData.fish_caught = data.fish_caught
	PlayerData.cash_total = data.cash_total
	PlayerData.voice_pitch = data.voice_pitch
	PlayerData.voice_speed = data.voice_speed
	PlayerData.locked_refs = data.locked_refs
	

func close_save_menu():
	SaveMenu.visible = false
