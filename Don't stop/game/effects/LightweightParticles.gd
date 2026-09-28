extends CPUParticles2D
## Small, short-lived emitters retain their authored appearance without a GPU
## simulation program's first-use compilation stall. Godot 4.7.2's former GPU
## nodes consumed one more global RNG draw on real renderers than CPU nodes;
## retain that draw so visual optimization cannot change seeded gameplay.
func _init():
	if DisplayServer.get_name() != "headless": randi()
