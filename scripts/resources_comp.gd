extends Node2D

func set_res(new_res):
	self.resources = new_res
	
func get_res():
	return self.resources

# Called when the node enters the scene tree for the first time.
func _ready():
	self.resources = 100 # Default value of resources

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
