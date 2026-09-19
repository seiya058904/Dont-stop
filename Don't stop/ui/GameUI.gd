extends Control

const weapon_item_pre = preload("res://ui/widgets/WeaponListItem.tscn")
const weapon_bullet_pre = preload("res://ui/widgets/BulletCountItem.tscn")
const rw_top = preload("res://ui/widgets/RewardTopItem.tscn")

@onready var change_audio = $AudioStreamPlayer2D

@onready var box_top = $hpUI
@onready var bottom_bls = $Container
@onready var gold_label = $hpUI/Label
@onready var reward_label = $hpUI/Label2
@onready var weapon_lsit_node = $HBoxContainer
@onready var weapon_change_image = $WeaponChangeUI/WeaponImage
@onready var weapon_bullet_list = $Container/BulletHbox
@onready var ammo_count_label = $Container/Label
@onready var weapon_change_name = $WeaponChangeUI/WeaponImage/Label
@onready var hp_bar = $hpUI/ProgressBar
@onready var ammo_label = $Container/all_ammo
@onready var rw_grid = $RwGridContainer
@onready var level_label = $hpUI/Label3
@onready var level_bar = $hpUI/ProgressBar2
@onready var level_panel = $LevelUpPanel

var weapon_feedback_tween: Tween
var inv_ui
var exp_text: Label
var level_notice: Label
var notice_tween: Tween
var current_weapon_label: Label
var current_weapon_icon: TextureRect
var readout_clock := 0.0
var readout_empty := -1

## The graphic magazine shows the *ratio* of the current magazine, not one shell
## per round. The bar used to build min(bullets_count, 40) shells and then delete
## one shell per round fired, so a 100-round magazine showed 40 shells and went
## empty after 40 shots while 60 rounds were still in the gun.
##
## 40 art segments is the ceiling: at or below it every round gets its own
## segment, above it the remaining fraction is mapped onto 40. The mapping is
## recomputed from the weapon's current state on every change, so it does not
## depend on how many segments have been removed before - increasing ammunition,
## a direct refill or a multi-round burst all land on the same picture.
const MAX_AMMO_SEGMENTS := 40
## A partially filled last segment must still read as "not empty": 1 round out of
## 100 is 0.4 of a segment, which is faint but visible.
const MIN_PARTIAL_ALPHA := 0.35
## Binary floating point makes 0.6 * 40 evaluate to 23.999999999999996, which
## would floor to 23 and break the documented 60/100 -> 24 mapping.
const RATIO_EPSILON := 0.000001

var ammo_weapon_id := -1
var ammo_segments: Array = []
var ammo_lit := -1.0

func _ready() -> void:
	_setup_weapon_readout()
	PlayerData.level_rewards_applied.connect(show_level_rewards)
	level_bar.show_percentage=false
	exp_text=Label.new(); exp_text.position=level_bar.position; exp_text.size=level_bar.size; exp_text.add_theme_font_size_override("font_size",5); box_top.add_child(exp_text)
	for child in level_panel.get_children(): child.hide()
	level_panel.size=Vector2(180,48)
	level_notice=Label.new(); level_notice.position=Vector2(4,3); level_notice.size=Vector2(172,44); level_notice.add_theme_font_size_override("font_size",7); level_panel.add_child(level_notice)
	change_audio.bus = "UI"
	Demo.restored.connect(on_restore)
	Demo.changed.connect(_update_unarmed_hud)
	Utils.onGameStart.connect(self.onGameStart)
	RewardServer.onRewardAdd.connect(self.onRewardAdd)
	PlayerData.onRewardChange.connect(self.onRewardChange)
	PlayerData.onGoldChange.connect(self.onGoldChange)
	PlayerData.onAmmoChange.connect(self.onAmmoChange)
	PlayerData.onPlayerLevelChange.connect(self.onPlayerLevelChange)
	PlayerData.onPlayerExpChange.connect(self.onPlayerExpChange)
	PlayerData.playerWeaponListChange.connect(self.playerWeaponListChange) #武器列表化监听
	PlayerData.onWeaponChangeAnim.connect(self.onWeaponChangeAnim) #武器化监听
	PlayerData.onWeaponBulletsChange.connect(self.onWeaponBulletsChange) #武器化监听
	PlayerData.onHpChange.connect(func hpChange(hp,max_hp): #血量变化监听
		hp_bar.max_value = max_hp;hp_bar.value = hp)

func _setup_weapon_readout() -> void:
	# Keep the combat centre clear; the current gun belongs beside its ammunition.
	$WeaponChangeUI.hide()
	current_weapon_label = Label.new()
	current_weapon_label.position = Vector2(-46,-23)
	current_weapon_label.size = Vector2(140,11)
	current_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	current_weapon_label.clip_text = true
	current_weapon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	current_weapon_label.add_theme_font_size_override("font_size",6)
	current_weapon_label.add_theme_color_override("font_color",Color("d9e2de"))
	bottom_bls.add_child(current_weapon_label)
	current_weapon_icon = TextureRect.new()
	current_weapon_icon.position = Vector2(-26,-11)
	current_weapon_icon.size = Vector2(32,16)
	current_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	current_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	current_weapon_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	current_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bls.add_child(current_weapon_icon)
	weapon_bullet_list.offset_left = -26
	weapon_bullet_list.offset_right = 94
	ammo_count_label.add_theme_font_size_override("font_size",7)
	ammo_label.add_theme_color_override("font_color",Color("a0b2ba"))
	gold_label.add_theme_color_override("font_color",Color("aebbb9"))
	reward_label.add_theme_color_override("font_color",Color("aebbb9"))
	_update_weapon_readout()

func _process(delta: float) -> void:
	# Reload has no UI signal. Observe its real state; never maintain another timer.
	readout_clock += delta
	if readout_clock < 0.1: return
	readout_clock = 0.0
	_update_weapon_readout()

func _update_weapon_readout() -> void:
	if not is_instance_valid(current_weapon_label): return
	var gun := _equipped_gun()
	var next_text: String = "未装备武器" if gun == null else ("装填 · " if gun.is_reloading else "")+gun.weapon_name
	if current_weapon_label.text != next_text: current_weapon_label.text = next_text
	var next_texture: Texture2D = null if gun == null else gun.image
	if current_weapon_icon.texture != next_texture: current_weapon_icon.texture = next_texture
	var empty: bool = gun == null or gun.bullets_count == 0
	if int(empty) != readout_empty:
		readout_empty = int(empty)
		ammo_count_label.add_theme_color_override("font_color",Color("d3ab7b") if empty else Color("e1e8df"))

func onGameStart():
	level_label.text = "Lv. " + str(PlayerData.player_level)
	onPlayerExpChange(PlayerData.player_exp,PlayerData.getMaxExp())
	onGoldChange(PlayerData.gold)
	onRewardChange(PlayerData.reward_point)
	onAmmoChange(PlayerData.reserve_magazines)
	var tween = get_tree().create_tween().set_ease(Tween.EASE_IN_OUT).set_parallel(true)
	tween.tween_property(box_top,"position:y",box_top.position.y,0.3).from(box_top.position.y-box_top.size.y)
	tween.tween_property(bottom_bls,"position:y",bottom_bls.position.y,0.3).from(bottom_bls.position.y+bottom_bls.size.y)
	tween.tween_property(weapon_lsit_node,"position:y",weapon_lsit_node.position.y,0.3).from(weapon_lsit_node.position.y+weapon_lsit_node.size.y)
	show()

func on_restore():
	for box in [weapon_lsit_node,rw_grid,weapon_bullet_list]:
		for child in box.get_children(): child.free()
	# The segment pool and the drawn state belonged to the previous session; drop
	# them so nothing can be repainted from a freed node.
	ammo_segments.clear()
	ammo_lit = -1.0
	ammo_weapon_id = -1
	playerWeaponListChange()
	for reward in Utils.player.reward_root.get_children(): onRewardAdd(reward)
	if Utils.player.gun:
		loadWeaponBullets(Utils.player.gun.weapon_id)
	else:
		ammo_count_label.text = "--"
		weapon_change_image.texture = null
		weapon_change_name.text = "未装备武器"

## B13: "no weapon equipped" is a real, first-class state. Any config change (purchase,
## unequip, save restore) re-checks it, so the HUD can never keep showing a stale gun card
## after the player drops their weapon in the camp.
func _update_unarmed_hud():
	if is_instance_valid(Utils.player) and Utils.player.gun == null:
		ammo_count_label.text = "--"
		weapon_change_image.texture = null
		weapon_change_name.text = "未装备武器"

func playerWeaponListChange():
	for item in PlayerData.player_weapon_list:
		if weapon_lsit_node.get_child_count() < 7 and !weapon_lsit_node.has_node(str(item)):
			var ins = weapon_item_pre.instantiate()
			ins.name = str(item)
			ins.local_id = item
			weapon_lsit_node.add_child(ins)

func onWeaponChangeAnim(weapon_id,tag = Utils.GUN_CHANGE_TYPE.CHANGE):
	if tag == Utils.GUN_CHANGE_TYPE.CHANGE:
		change_audio.play()
		# The change card needs the weapon's own metadata, which lives on the gun
		# instance. A gun that is displayed but not owned - a preview, or a harness
		# equipping one directly - has no entry in the player's arsenal, and the
		# unguarded lookup used to abort this handler with a "previously freed" /
		# invalid-key script error on every such change. Skipping the card is
		# correct, and the ammo bar below is refreshed either way.
		var weapon:BaseGun = PlayerData.player_weapon_list.get(weapon_id)
		if is_instance_valid(weapon):
			weapon_change_name.text = weapon.weapon_name
			ammo_count_label.text = "%s" %[weapon.bullets_count]
			weapon_change_image.texture = weapon.image
			if weapon_feedback_tween and weapon_feedback_tween.is_valid(): weapon_feedback_tween.kill()
			weapon_feedback_tween = get_tree().create_tween().set_ease(Tween.EASE_IN_OUT)
			weapon_feedback_tween.tween_property(weapon_change_image,"modulate:a",1.0,0.3).from(0.0)
			weapon_feedback_tween.tween_property(weapon_change_image,"modulate:a",0.0,0.3).from(1.0).set_delay(0.5)
	call_deferred("loadWeaponBullets",weapon_id)

func loadWeaponBullets(weapon_id):
	# A weapon change is the one event that legitimately re-shapes the bar, so the
	# segment pool is rebuilt here and only here.
	ammo_weapon_id = int(weapon_id)
	_render_ammo(true)

## The magazine changed. The signal carries the numbers as a hint, but the
## authoritative values are always read back from the equipped weapon, so a
## late emission from a weapon that is no longer in hand cannot paint stale
## ammunition over the current one.
func onWeaponBulletsChange(_bullet, _bullet_max):
	_render_ammo(false)

## Number of art segments a magazine of `capacity` rounds is drawn with.
func segment_count(capacity: int) -> int:
	if capacity <= 0: return 0
	return capacity if capacity <= MAX_AMMO_SEGMENTS else MAX_AMMO_SEGMENTS

## How many segments are lit, as a possibly fractional count. The last lit
## segment is partial when the ratio does not land on a segment boundary.
func lit_segments(current: int, capacity: int, segments: int) -> float:
	if capacity <= 0 or segments <= 0: return 0.0
	# Empty means empty and full means full, exactly - never one segment short of
	# either, which is what "the bar is empty but I still have bullets" looks like.
	if current <= 0: return 0.0
	if current >= capacity: return float(segments)
	var exact := clampf(float(current) / float(capacity), 0.0, 1.0) * float(segments)
	# floorf(), not floor(): the untyped global returns Variant, which this project
	# treats as a parse error.
	var full := floorf(exact + RATIO_EPSILON)
	return full + clampf(exact - full, 0.0, 1.0)

func _equipped_gun() -> BaseGun:
	if not is_instance_valid(Utils.player): return null
	var gun = Utils.player.gun
	return gun if is_instance_valid(gun) else null

func _render_ammo(force_rebuild: bool) -> void:
	var gun := _equipped_gun()
	var weapon_id := int(gun.weapon_id) if gun != null else -1
	var capacity := maxi(0, int(gun.bullets_max_count)) if gun != null else 0
	var current := clampi(int(gun.bullets_count), 0, capacity) if gun != null else 0

	# Numbers first: remaining / effective capacity. A weapon with no usable
	# capacity says so instead of dividing by zero. The reserve is its own readout
	# (`all_ammo`) and is deliberately not folded into this number.
	if capacity > 0:
		ammo_count_label.text = "%d/%d" % [current, capacity]
	else:
		ammo_count_label.text = "--"

	var segments := segment_count(capacity)
	if force_rebuild or weapon_id != ammo_weapon_id or segments != ammo_segments.size():
		_build_segments(segments)
		ammo_weapon_id = weapon_id

	var lit := lit_segments(current, capacity, segments)
	if is_equal_approx(lit, ammo_lit) and not force_rebuild: return
	_paint_segments(lit)

func _build_segments(count: int) -> void:
	for item in weapon_bullet_list.get_children():
		weapon_bullet_list.remove_child(item)
		item.free()
	ammo_segments.clear()
	for _index in count:
		var ins = weapon_bullet_pre.instantiate()
		weapon_bullet_list.add_child(ins)
		ammo_segments.append(ins)
	ammo_lit = -1.0

func _paint_segments(lit: float) -> void:
	var full := floorf(lit + RATIO_EPSILON)
	for index in ammo_segments.size():
		var item = ammo_segments[index]
		if not is_instance_valid(item): continue
		if index < full:
			item.set_lit(1.0)
		elif index == full and lit > full:
			item.set_lit(maxf(lit - full, MIN_PARTIAL_ALPHA))
		else:
			item.set_lit(0.0)
	ammo_lit = lit

func onGoldChange(gold):
	gold_label.text = tr("GOLD_HAS") + str(gold)

func onAmmoChange(ammo):
	ammo_label.text = "%d MAGS" % ammo

func onRewardChange(reward):
	reward_label.text = tr("REWARD_POINT") + str(reward)

func onRewardAdd(rw:BaseReward):
	if rw.only_start:
		return
	if rw_grid.has_node(str(rw.id)):
		rw_grid.get_node(str(rw.id)).setData(rw)
	else:
		var ins = rw_top.instantiate()
		ins.name = str(rw.id)
		rw_grid.add_child(ins)
		ins.setData(rw)

func onPlayerLevelChange(level):
	level_label.text = "Lv. " + str(level)

func show_level_rewards(rewards: Dictionary):
	if Demo.loading: return
	level_notice.text=PlayerData.PROGRESSION.notice(rewards)
	level_panel.position=Vector2(8,65); level_panel.show()
	if notice_tween: notice_tween.kill()
	notice_tween=create_tween(); notice_tween.tween_interval(3.0); notice_tween.tween_callback(level_panel.hide)

func onPlayerExpChange(exp,max_exp):
	level_bar.max_value = max_exp
	level_bar.value = exp
	if is_instance_valid(exp_text): exp_text.text="EXP %.1f / %.1f" % [exp,max_exp]

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inv") and Utils.is_game_start and Demo.pause_stack.is_empty():
		Demo.open_panel()
		get_viewport().set_input_as_handled()
