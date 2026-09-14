extends Node2D

@onready var builder = $MonsterBuilder
@onready var land = $Land

func _init() -> void:
	Utils.onGameStart.connect(self.onGameStart)

func _ready() -> void:
	$MonsterBuilder.land = land
	$MonsterBuilder.monsterRoot = $MonsterRoot
	$CanvasLayer.onMonsterJoin.connect(self.onMonsterJoin)
	PlayerServer.addPlayerToScene($PlayerRoot)
	PlayerServer.setPlayerPosition($CreatePosition.global_position)
	Utils.gameStart()
	Utils.crosshairChange(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_apply_web_environment()

func _apply_web_environment() -> void:
	# Compatibility (Web) renders glow differently from Forward+: normalized glow
	# is not honoured and additive build-up blows out or vanishes. Use a flatter,
	# cheaper profile that keeps the snowy scene readable in WebGL 2.
	if not OS.has_feature("web"):
		return
	var world_env: WorldEnvironment = $WorldEnvironment
	if world_env == null or world_env.environment == null:
		return
	var env := world_env.environment
	env.glow_normalized = false
	env.glow_intensity = 0.9
	env.set("glow_levels/1", 1.0)
	env.set("glow_levels/2", 0.0)
	env.set("glow_levels/4", 0.0)

func onGameStart():
	$ControlUI.visible = true
	$CanvasLayer/Panel.visible = true
	PlayerData.reserve_magazines = 9999999
	var gun = Utils.weapon_list['0']
	PlayerData.add_weapon(gun.instantiate())
	await get_tree().create_timer(0.7).timeout
	create_tween().tween_property($PlayerRoot/Anchor/Camera2D/PointLight2D,"texture_scale",0.8,1)

func onMonsterJoin():
	Utils.crosshairChange(true)
	Utils.set_gameplay_mouse_mode()
	builder.start()

	EquipServer.addEquipOnFloor(preload("res://game/equip/High-Energy Particle Cannon.tscn").instantiate(),Utils.player.global_position)
	EquipServer.addEquipOnFloor(preload("res://game/equip/Flamethrower.tscn").instantiate(),Utils.player.global_position+ Vector2(20,20))

func addEffectNode(node):
	$EffectRoot.add_child(node)

func addEquip(ins):
	$EquipRoot.add_child(ins)
