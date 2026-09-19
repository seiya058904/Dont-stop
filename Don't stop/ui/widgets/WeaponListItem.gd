extends TextureRect

@onready var image = $image
@onready var press_label = $Label
var slot_id := 0
var local_id := -1
var pressed_name := ""

func _ready() -> void:
	set_meta("slot_id",slot_id)
	pressed_name = "pressed_%d" % (slot_id+1)
	mouse_filter = Control.MOUSE_FILTER_STOP
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.custom_minimum_size = Vector2.ZERO
	image.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	image.position = Vector2(2,2); image.size = Vector2(16,10)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	press_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	press_label.add_theme_font_size_override("font_size",6)
	gui_input.connect(_slot_input)
	PlayerData.onWeaponChanged.connect(refresh_slot)
	Demo.changed.connect(refresh_slot)
	refresh_slot()

func refresh_slot() -> void:
	local_id = PlayerData.weapon_slots[slot_id]
	var gun = PlayerData.player_weapon_list.get(local_id)
	image.texture = gun.image if is_instance_valid(gun) else null
	press_label.text = str(slot_id+1) + (" +" if gun == null else "")
	tooltip_text = (gun.weapon_name if is_instance_valid(gun) else "空槽 · 在营地加入武器")
	var current = is_instance_valid(Utils.player) and Utils.player.gun and Utils.player.gun.weapon_id == local_id
	self_modulate = Color("83e0ff") if current else Color.WHITE
	if current: tooltip_text += " · 当前手持"

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(pressed_name) and not event.is_echo(): _select()

func _slot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Demo.fire_released = false
		_select()
		accept_event()

func _select() -> void:
	if local_id >= 0:
		if not PlayerData.changeWeapon(local_id): tooltip_text = PlayerData.switch_reason
