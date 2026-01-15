extends Camera2D

@export_group("Mozgás")
@export var pan_speed: float = 600.0
@export var drag_sensitivity: float = 1.0

@export_group("Edge Scroll")
@export var edge_margin: float = 20.0       # Hány pixelre a széltől kezdjen el mozogni
@export var edge_scroll_speed: float = 400.0 # Lassabb sebesség a szélhez

@export_group("Zoom")
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.3
@export var max_zoom: float = 1.0

var is_dragging: bool = false

func _process(delta: float) -> void:
	var dir := Vector2.ZERO

	# 1. Billentyűzet mozgás
	if Input.is_action_pressed("cam_left"): dir.x -= 1
	if Input.is_action_pressed("cam_right"): dir.x += 1
	if Input.is_action_pressed("cam_up"): dir.y -= 1
	if Input.is_action_pressed("cam_down"): dir.y += 1

	# 2. Egér a képernyő szélén (Edge Scroll)
	# Csak akkor fusson, ha nem épp vonszoljuk a kamerát
	if not is_dragging:
		var viewport_size = get_viewport().get_visible_rect().size
		var mouse_pos = get_viewport().get_mouse_position()

		if mouse_pos.x < edge_margin:
			dir.x -= 1
		elif mouse_pos.x > viewport_size.x - edge_margin:
			dir.x += 1
			
		if mouse_pos.y < edge_margin:
			dir.y -= 1
		elif mouse_pos.y > viewport_size.y - edge_margin:
			dir.y += 1

	# Mozgatás végrehajtása (sebesség korrigálva a zoom-mal)
	if dir != Vector2.ZERO:
		var current_speed = edge_scroll_speed if is_mouse_at_edge() else pan_speed
		global_position += dir.normalized() * (current_speed / zoom.x) * delta

func _unhandled_input(event: InputEvent) -> void:
	# Zoom kezelés
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_camera(-zoom_speed)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_camera(zoom_speed)
			
			# Jobb klikk észlelése vonszoláshoz
			if event.button_index == MOUSE_BUTTON_RIGHT:
				is_dragging = true
		else:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				is_dragging = false

	# 3. Jobb klikkes vonszolás (Mouse Drag)
	if event is InputEventMouseMotion and is_dragging:
		# Az elmozdulást elosztjuk a zoom-al, hogy ugyanakkora mozdulatra 
		# ugyanannyit menjen a kamera minden zoom szinten
		global_position -= event.relative * (drag_sensitivity / zoom.x)

func zoom_camera(delta_val: float) -> void:
	var new_zoom = clamp(zoom.x - delta_val, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)

# Segédfüggvény annak eldöntésére, hogy az egér miatt mozog-e a kamera
func is_mouse_at_edge() -> bool:
	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size
	return mouse_pos.x < edge_margin or mouse_pos.x > viewport_size.x - edge_margin or \
		   mouse_pos.y < edge_margin or mouse_pos.y > viewport_size.y - edge_margin
