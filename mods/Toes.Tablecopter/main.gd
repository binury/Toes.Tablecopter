# Copyright 2025 Robin Ury

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#    http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

extends Node

var Players
var KeybindAPI

const TURBO_SPEED = 36.0

var copter_enabled := false
var default_sprint_speed: float
var turbo_enabled := false
var last_time_busy := 0


func _ready():
	Players = get_node_or_null("/root/ToesSocks/Players")
	Players.connect("player_added", self, "init_player")
	Players.connect("player_removed", self, "init_player")
	Players.connect("ingame", self, "_on_game_entered")

	KeybindAPI = get_node_or_null("/root/BlueberryWolfiAPIs/KeybindsAPI")

	var toggle_copter_signal = KeybindAPI.register_keybind(
		{
			"action_name": "toggle_tablecopter",
			"title": "Toggle Tablecopter",
			"key": KEY_T,
		}
	)
	KeybindAPI.connect(toggle_copter_signal + "_up", self, "_on_toggle_pressed")


func _on_game_entered():
	copter_enabled = false
	default_sprint_speed = Players.local_player.sprint_speed


#func _input(event: InputEvent) -> void:
#	if Input.is_action_just_pressed("chat_enter") or Input.is_action_just_released('chat_enter'):
#		recently_pressed_enter = true
#		yield (get_tree().create_timer(0.250),"timeout")
#		recently_pressed_enter = false


func _spawn_actor(uid: String):
	var skeleton: Skeleton = Players.local_player.get_node("body/player_body/Armature/Skeleton")
	var torso_bone_index = skeleton.find_bone("torso")
	var torso_global_transform = (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(torso_bone_index)
	)
	var pos = torso_global_transform
	Network._sync_create_actor(uid, pos.origin, Players.local_player.current_zone)


func _on_toggle_pressed():
	if not is_instance_valid(Players.local_player) or Players.local_player.busy:
		return
	var is_past_chat_enter_safeguard = last_time_busy + 125 <= Time.get_ticks_msec()
	if not is_past_chat_enter_safeguard:
		return

	if Input.is_action_pressed("move_sneak"):
		turbo_enabled = !turbo_enabled
		PlayerData._send_notification("Turbo " + ("on" if turbo_enabled else "off"))
		if copter_enabled:
			if turbo_enabled:
				Players.local_player.sprint_speed = default_sprint_speed
				for chair in get_actors_from_id("therapist_chair", Network.STEAM_ID):
					Players.local_player._wipe_actor(chair.actor_id)
				_spawn_actor("campfire")
			else:
				Players.local_player.sprint_speed = TURBO_SPEED
				for fire in get_actors_from_id("campfire", Network.STEAM_ID):
					Players.local_player._wipe_actor(fire.actor_id)
				_spawn_actor("therapist_chair")
		return

	copter_enabled = not copter_enabled
#	PlayerData._send_notification("Tablecopter " + ("enabled - soisoisoi!" if copter_enabled else "disabled"))

	if copter_enabled:
		for kind in ["table", "well"]:
			_spawn_actor(kind)
		_spawn_actor("campfire") if turbo_enabled else _spawn_actor("therapist_chair")
		if turbo_enabled:
			Players.local_player.sprint_speed = TURBO_SPEED
		else:
			Players.local_player.sprint_speed = default_sprint_speed
	else:
		for table in get_actors_from_id("table", Network.STEAM_ID):
			Players.local_player._wipe_actor(table.actor_id)
		for well in get_actors_from_id("well", Network.STEAM_ID):
			Players.local_player._wipe_actor(well.actor_id)
		for chair in get_actors_from_id("therapist_chair", Network.STEAM_ID):
			Players.local_player._wipe_actor(chair.actor_id)
		for fire in get_actors_from_id("campfire", Network.STEAM_ID):
			Players.local_player._wipe_actor(fire.actor_id)
		Players.local_player.sprint_speed = default_sprint_speed


func get_actors_from_id(type_or_types, ownerID = Network.STEAM_ID):
	var types := type_or_types if typeof(type_or_types) == TYPE_ARRAY else [type_or_types]
	var actors := []
	var entities = get_node_or_null("/root/world/Viewport/main/entities")
	if not entities: return
	for actor in entities.get_children():
		if actor.actor_type in types and actor.owner_id == ownerID:
			actors.append(actor)
	return actors


func _physics_process(dt):
	var player: Actor = Players.local_player
#	var player: Actor = Players.get_players()[1]
	if not is_instance_valid(PlayerData) or not is_instance_valid(player):
		copter_enabled = false
		return

	if player.busy:
		last_time_busy = Time.get_ticks_msec()

	if not copter_enabled:
		return

	var propType := "table"
	var offsets = {
		"bush": Transform(Basis(), Vector3(0, 0.0, 0.125)),
		"campfire": Transform(Basis(), Vector3(-0, -0.725, -1)),
		"chair": Transform(Basis(), Vector3(0, -1.05, 0.125)),
		"island_tiny": Transform(Basis(), Vector3(0, 0.7, 0.125)),
		"rock": Transform(Basis(), Vector3(0, 0.7, 0.125)),
		"table": Transform(Basis(), Vector3(0, -1.05, 0.0)),
		"therapist_chair": Transform(Basis(), Vector3(0.0, -0.125, -2.25)),
		"well": Transform(Basis(), Vector3(0, -0.5, 0.125)),
		"whoopie": Transform(Basis(), Vector3(0, 1.0, 0.125))
	}

	var is_not_chatting = Players.local_player.busy == false
	var should_update_table = true

	# Player pos
	var skeleton: Skeleton = player.get_node("body/player_body/Armature/Skeleton")
	var torso_bone_index = skeleton.find_bone("torso")
	var torso_global_transform = (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(torso_bone_index)
	)

	var wells = get_actors_from_id("well")
	var well = wells[0]

	well.global_transform = torso_global_transform * offsets["well"]
	Network._send_P2P_Packet(
		{
			"type": "actor_update",
			"actor_id": well.actor_id,
			"pos": well.global_transform.origin,
			"rot": well.rotation
		},
		"peers",
		Network.CHANNELS.ACTOR_UPDATE
	)

	var offset: Transform
	var should_maintain_lift = (
		[Input.is_action_pressed("move_forward"), Input.is_action_pressed("move_back"), Input.is_action_pressed("move_left"), Input.is_action_pressed("move_right")].has(
			true
		)
		and is_not_chatting
	)
	if should_maintain_lift and not Input.is_action_pressed("move_jump"):
#		Players.local_player.rotation.x = Players.local_player.rotation.y - 0.001
		offset = offsets["table"]
	elif Input.is_action_pressed("move_jump") and is_not_chatting:
		offset = Transform(Basis(), Vector3(0, -0.95, 0.125))
	else:
		should_update_table = false
		offset = Transform(Basis(), Vector3(0, -1.1, 0.125))

	var bushes = get_actors_from_id(propType, Network.STEAM_ID)
	var bush = bushes[0] if bushes.size() >= 1 else null
	if not is_instance_valid(bush):
		return

	bush.global_transform = torso_global_transform * offset

	if should_update_table:
		Network._send_P2P_Packet(
			{
				"type": "actor_update",
				"actor_id": bush.actor_id,
				"pos": bush.global_transform.origin,
				"rot": bush.rotation
			},
			"peers",
			Network.CHANNELS.ACTOR_UPDATE
		)

	if not turbo_enabled:
		Players.local_player.sprint_speed = default_sprint_speed
		var backseats = get_actors_from_id("therapist_chair", Network.STEAM_ID)

		var backseat = backseats[0] if backseats.size() >= 1 else null
		if not propType == "table" or not is_instance_valid(backseat):
			return
		backseat.global_transform = bush.global_transform * offsets.therapist_chair
		Network._send_P2P_Packet(
			{
				"type": "actor_update",
				"actor_id": backseat.actor_id,
				"pos": backseat.global_transform.origin,
				"rot": backseat.rotation
			},
			"peers",
			Network.CHANNELS.ACTOR_UPDATE
		)

	# Back back seating
#	var back_backseat = backseats[-1] if backseats.size() >= 2 else null
#	if not is_instance_valid(back_backseat):
#		PlayerData._send_notification("Creating therapy chair")
#		var pos = backseat.global_transform * offsets.therapist_chair
#
#		Network._sync_create_actor("therapist_chair", pos.origin, Players.local_player.current_zone)
#	else:
#		back_backseat.global_transform = backseat.global_transform * Transform(Basis(), Vector3(0.0, -0.125, -2.25))
#		Network._send_P2P_Packet({"type": "actor_update", "actor_id": back_backseat.actor_id, "pos": back_backseat.global_transform.origin, "rot": back_backseat.rotation}, "peers", Network.CHANNELS.ACTOR_UPDATE)

	if turbo_enabled:
		Players.local_player.sprint_speed = TURBO_SPEED
		var fires: Array = get_actors_from_id("campfire")
		var fire: Actor = fires[0]

		fire.global_transform = torso_global_transform * offsets["campfire"]
		fire.rotation.x = 18
		Network._send_P2P_Packet(
			{
				"type": "actor_update",
				"actor_id": fire.actor_id,
				"pos": fire.global_transform.origin,
				"rot": fire.rotation
			},
			"peers",
			Network.CHANNELS.ACTOR_UPDATE
		)


func sample(list):
	# TODO null check
	if !list or list.size() == 0:
		return null
	return list[randi() % list.size()]
