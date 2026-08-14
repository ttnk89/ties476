extends StaticBody3D

@onready var detection_area = $DetectionArea

func _ready():
	if detection_area:
		detection_area.body_entered.connect(_on_detection_area_body_entered)
	else:
		print("ERROR: Could not find detection_area!")

func _on_detection_area_body_entered(body):
	print("something close to door: ", body.name)
	
	# Check if the body is the player or a child of the player
	if body.get_class() == "CharacterBody3D":
		if body.keys_held:
			_open_door()
		else:
			print("The door is locked. You need keys.")

func _open_door():
	# Use a simple tween to rotate the door 90 degrees
	var tween = create_tween()
	tween.tween_property(self.get_parent(), "rotation_degrees:y", 90, 1.0).set_trans(Tween.TRANS_SINE)
