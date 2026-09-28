extends RefCounted
static var glow: GradientTexture2D

static func texture() -> GradientTexture2D:
	if glow != null: return glow
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0,0.18,0.5,1])
	gradient.colors = PackedColorArray([Color(1,1,1,0.7),Color(1,1,1,0.35),Color(1,1,1,0.08),Color(1,1,1,0)])
	glow = GradientTexture2D.new()
	glow.gradient = gradient
	glow.width = 64
	glow.height = 64
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5,0.5)
	glow.fill_to = Vector2(1,0.5)
	return glow
