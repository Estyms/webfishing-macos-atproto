extends Node

# Signals
signal connection(suceeded)
signal savefile_loaded(uri)

# State
var can_save = true

# AtProto
var did
var pds
var accessJwt
var refreshJwt
var Atproto

func _enter_tree():
	Atproto = self.get_parent()
	
func connected() -> bool:
	return accessJwt != null

func is_token_expired() -> bool:
	var token_data = self.accessJwt.split(".")[1]
	var data = null
	for x in ["", "=", "=="] :
		var json = Marshalls.base64_to_utf8(token_data + x)
		data = parse_json(json)
		if data != null: break
	var expires = data.exp
	var unix = floor(Time.get_unix_time_from_system())
	return expires < unix

func get_header():
	return [
		"Authorization: Bearer " + self.accessJwt,
		"Content-Type: application/json" 
	]

func create_record(record, callback : FuncRef = null):
	
	if is_token_expired():
		refresh_token("create_record", [record])
		return
		
	var payload = {
		repo = did,
		collection = record.at_type,
		record = record
	}
		
	var json_payload = JSON.print(payload)
	json_payload = json_payload.replace("at_type", "$type")
	
	var req = HTTPRequest.new()
	self.add_child(req)
	req.connect("request_completed", self, "_create_record_handler", [req, callback])
	req.request(pds + "/xrpc/com.atproto.repo.createRecord", get_header(), true, HTTPClient.METHOD_POST, json_payload)

	
func _create_record_handler(_result, code, _headers, body: PoolByteArray, req: HTTPRequest, callback: FuncRef):
	req.queue_free()
	if callback == null:
		return
		
	var res = parse_json(body.get_string_from_utf8())
	callback.call_func(res)

## LIST RECORDS

func list_records(callback: FuncRef, collection: String, limit: int = 50, cursor = ""):
	var query_string = "repo=" + did
	query_string += "&collection=" + collection.http_escape()
	query_string += "&limit=" + str(limit).http_escape()
	query_string += "&cursor=" + str(limit).http_escape()
	var req_str = pds + "/xrpc/com.atproto.repo.listRecords?" + query_string
	
	var req = HTTPRequest.new()
	self.add_child(req)
	req.connect("request_completed", self, "_list_record_handler", [req, callback])
	req.request(req_str, get_header(), true, HTTPClient.METHOD_GET)	
	
func _list_record_handler(_result, code, _headers, body: PoolByteArray, req: HTTPRequest, callback: FuncRef):
	req.queue_free()
	var b = body.get_string_from_utf8()
	var res = parse_json(b)
	callback.call_func(res.records)


## GET RECORD

func get_record(callback: FuncRef, did: String, collection: String, rkey: String):
	var query_string = "repo=" + did.http_escape()
	query_string += "&collection=" + collection.http_escape()
	query_string += "&rkey=" + rkey.http_escape()
	
	var req = HTTPRequest.new()
	self.add_child(req)
	req.connect("request_completed", self, "_get_record_handler", [req, callback])
	req.request(pds + "/xrpc/com.atproto.repo.getRecord?" + query_string, get_header(), true, HTTPClient.METHOD_GET)
	
func _get_record_handler(_result, code, _headers, body: PoolByteArray, req: HTTPRequest, callback: FuncRef):
	req.queue_free()
	var res = parse_json(body.get_string_from_utf8())
	callback.call_func(res)


## PUT RECORD

func put_record(uri, record, callback: FuncRef = null):
	if is_token_expired():
		refresh_token("put_record", [uri, record])
		return
	
	var splitted_uri = uri.split("/")
	
	
	var payload = {
		repo = splitted_uri[2],
		collection = splitted_uri[3],
		rkey = splitted_uri[4],
		record = record
	}
		
	var json_payload = JSON.print(payload)
	json_payload = json_payload.replace("at_type", "$type")
	
	var req = HTTPRequest.new()
	self.add_child(req)
	req.connect("request_completed", self, "_put_record_handler", [req, callback])
	req.request(pds + "/xrpc/com.atproto.repo.putRecord", get_header(), true, HTTPClient.METHOD_POST, json_payload)
	
func _put_record_handler(_result, code, _headers, body: PoolByteArray, req: HTTPRequest, callback: FuncRef):
	req.queue_free()
	if callback == null:
		return
	var res = parse_json(body.get_string_from_utf8())
	callback.call_func(res)

################
#    LOGIN     #
################

func login(handle, password):
	var req = HTTPRequest.new()
	self.add_child(req)
	
	req.connect("request_completed", self, "after_handle_resolver", [req, password])
	req.request("https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=" + handle)


func after_handle_resolver(_result, code, _headers, body: PoolByteArray, req: HTTPRequest, password):
	req.disconnect("request_completed", self, "after_handle_resolver")
	
	if code != 200:
		emit_signal("connection", false)
		return
	
	var res = parse_json(body.get_string_from_utf8())
	self.did = res.did
	
	req.connect("request_completed", self, "after_get_pds", [req, password])
	req.request("https://plc.directory/" + self.did)
	
	
func after_get_pds(_result, code, _headers, body: PoolByteArray,req: HTTPRequest, password):
	req.disconnect("request_completed", self, "after_get_pds")
	
	if code != 200:
		emit_signal("connection", false)
		return
	
	var res = parse_json(body.get_string_from_utf8())
	for x in res.service:
		if x.id == "#atproto_pds":
			self.pds = x.serviceEndpoint
	
	var payload = {
		identifier = self.did,
		password = password
	}
	
	req.connect("request_completed", self, "after_create_session", [req])
	req.request(pds + "/xrpc/com.atproto.server.createSession", ["Content-Type: application/json"], true, HTTPClient.METHOD_POST, JSON.print(payload))

	
func after_create_session(_result, code, _headers, body: PoolByteArray, req: HTTPRequest):
	req.queue_free()
	
	if code != 200:
		emit_signal("connection", false)
		return
	
	var res = parse_json(body.get_string_from_utf8())
	self.accessJwt = res.accessJwt
	self.refreshJwt = res.refreshJwt
	emit_signal("connection", true)

#######################
#    REFRESH TOKEN    #
#######################
func refresh_token(method = "", payload = []):
	var req = self.requester

	var headers = [
		"Authorization: Bearer " + self.refreshJwt,
		"Content-Type: application/json" 
	]
	req.connect("request_completed", self, "after_refresh_token", [method, payload])
	req.request(pds + "/xrpc/com.atproto.server.refreshSession", headers, true, HTTPClient.METHOD_POST)

func after_refresh_token(_result, _response_code, _headers, body: PoolByteArray, method, payload):
	var req = self.requester
	req.disconnect("request_completed", self, "after_refresh_token")
	
	var res = parse_json(body.get_string_from_utf8())
	self.accessJwt = res.accessJwt
	self.refreshJwt = res.refreshJwt
	
	if method != "":
		self.callv(method, payload)


######################
#    Method Calls    #
######################

func catch_fish(fish, size, quality):
	var fish_data = Globals.item_data[fish]["file"]
	var record = {
		at_type = "dev.regnault.webfishing.fish",
		id = fish,
		name = fish_data.item_name,
		size = str(size),
		quality = quality
	}
	create_record(record)
	

# SAVES	

func create_save_file(uri: String, filename: String, callback: FuncRef = null):
	var record = {
		at_type = "dev.regnault.webfishing.savefile",
		uri = uri,
		name = filename,
	}
	create_record(record, callback)
	pass

func get_saves(callback: FuncRef):
	list_records(callback, "dev.regnault.webfishing.savefile")
	
	
func get_save_data():
	var save_data = {
		"inventory": PlayerData.inventory, 
		"hotbar": PlayerData.hotbar, 
		"cosmetics_unlocked": PlayerData.cosmetics_unlocked, 
		"cosmetics_equipped": PlayerData.cosmetics_equipped, 
		"new_cosmetics": [], 
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
	}
	save_data = save_data.duplicate(true)
	
	# JOURNAL
	var modified_journal = []
	for area in save_data.journal:
		var area_entry = {
			name = area,
			entries = []
		}
		for entry_name in save_data.journal[area]:
			var entry = save_data.journal[area][entry_name]
			area_entry.entries.append({
				name = entry_name,
				count = entry.count,
				record = str(entry.record),
				quality = entry.quality
			})
		modified_journal.append(area_entry)
	save_data.journal = modified_journal
	
	# Quests
	var modified_quests = []
	for quest_id in save_data.quests:
		var entry = save_data.quests[quest_id].duplicate(true)
		entry.id = quest_id
		modified_quests.append(entry)
	save_data.quests = modified_quests
	
	# Inventory
	for item in save_data.inventory:
		item.size = str(item.size)
		
		
	# Version
	save_data.version = str(save_data.version)
	
	# Voice Pitch
	save_data.voice_pitch = str(save_data.voice_pitch)
	
	# Aqua Fish
	save_data.saved_aqua_fish.size = str(save_data.saved_aqua_fish.size)
	
	# Letters
	for letter in save_data.inbound_mail:
		for item in letter.items:
			item.size = str(item.size)
			
	return save_data
	
func save_file(callback: FuncRef = null, creation = false):
	if UserSave.current_loaded_slot != Atproto.ATPROTO_SLOT:
		return
	if !connected(): return
	
	var save_data = get_save_data()
	save_data.at_type = "dev.regnault.webfishing.save"
	
	if Atproto.save_loaded != "":
		put_record(Atproto.save_loaded, save_data)

func create_save(callback: FuncRef = null):
	if !connected(): return
	var save_data = get_save_data()
	save_data.at_type = "dev.regnault.webfishing.save"
	create_record(save_data, callback)

func load_save(uri: String):
	var splitted_uri = uri.split("/")
	var did = splitted_uri[2]
	var collection = splitted_uri[3]
	var rkey = splitted_uri[4]
	get_record(funcref(self, "_after_get_save"), did, collection, rkey)
	pass

func _after_get_save(save_record):
	var save = save_record.value
	
	UserSave._load_save(Atproto.ATPROTO_SLOT)
	
	var modified_journal: Dictionary = {}
	for area in save.journal:
		var area_entries = {}
		for entry in area.entries:
			var new_quality = []
			for x in entry.quality:
				if !new_quality.has(int(x)):
					new_quality.append(int(x))
			area_entries[entry.name] = {
				count = entry.count,
				record = float(entry.record),
				quality = new_quality
			}
			
		modified_journal[area.name] = area_entries
	save.journal = modified_journal
	
	var modified_quests = {}
	for quest in save.quests:
		var id = quest.id
		modified_quests[quest.id] = quest
		modified_quests[quest.id].erase("id")
	save.quests = modified_quests
	
	# Inventory
	for item in save.inventory:
		item.size = float(item.size)
		item.quality = int(item.quality) 
		
	save.version = float(save.version)
	save.saved_aqua_fish.quality  = int(save.saved_aqua_fish.quality)
	save.saved_aqua_fish.size = float(save.saved_aqua_fish.size)
	for letter in save.inbound_mail:
		for item in letter.items:
			item.size = float(item.size)
			item.quality = int(item.quality)
			
	var modified_hotbar = {}
	for item in save.hotbar:
		modified_hotbar[int(item)] = save.hotbar[item]
	save.hotbar = modified_hotbar

	PlayerData.inventory = save.inventory
	PlayerData.hotbar = save.hotbar
	PlayerData.cosmetics_unlocked = save.cosmetics_unlocked
	PlayerData.cosmetics_equipped = save.cosmetics_equipped
	PlayerData.money = save.money
	PlayerData.players_muted = save.muted_players
	PlayerData.players_hidden = save.hidden_players
	PlayerData.bait_inv = save.bait_inv
	PlayerData.bait_selected = save.bait_selected
	PlayerData.bait_unlocked = save.bait_unlocked
	PlayerData.max_bait = save.max_bait
	PlayerData.lure_unlocked = save.lure_unlocked
	PlayerData.lure_selected = save.lure_selected
	PlayerData.journal_logs = save.journal
	PlayerData.current_quests = save.quests
	PlayerData.completed_quests = save.completed_quests
	PlayerData.badge_level = int(save.level)
	PlayerData.badge_xp = int(save.xp)
	PlayerData.saved_aqua_fish = save.saved_aqua_fish
	PlayerData.inbound_mail = save.inbound_mail
	PlayerData.saved_tags = save.saved_tags
	PlayerData.loan_level = int(save.loan_level)
	PlayerData.loan_left = save.loan_left
	PlayerData.rod_power_level = save.rod_power
	PlayerData.rod_speed_level = save.rod_speed
	PlayerData.rod_chance_level = save.rod_chance
	PlayerData.rod_luck_level = save.rod_luck
	PlayerData.buddy_level = save.buddy_level
	PlayerData.buddy_speed = save.buddy_speed
	PlayerData.guitar_shapes = save.guitar_shapes
	PlayerData.fish_caught = save.fish_caught
	PlayerData.cash_total = save.cash_total
	PlayerData.voice_pitch = float(save.voice_pitch)
	PlayerData.voice_speed = save.voice_speed
	PlayerData.locked_refs = save.locked_refs
	PlayerData._validate_guitar_shapes()
	PlayerData._validate_inventory()
	PlayerData._journal_check()
	PlayerData._missing_quest_check()
	PlayerData._unlock_defaults()
	
	can_save = false
	UserSave._save_slot(Atproto.ATPROTO_SLOT)
	can_save = true
	
	emit_signal("savefile_loaded", save_record.uri)
	
	
