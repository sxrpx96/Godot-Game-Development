extends Node2D

@export var tile_scene: PackedScene
@export var tile_width: float = 350.0
@export var tile_height: float = 300.0

@export_group("Map Generation Settings")
@export var cols: int = 12
@export var rows: int = 12
@export var radius: float = 5.0
@export var radius_noise: float = 1.5

@onready var ai: SimpleAI = SimpleAI.new()

enum Turn { PLAYER, AI }
var turn: Turn = Turn.PLAYER

var pending_upgrade_tile: Tile = null
var grid_data: Dictionary = {} # Vector2i -> Tile
var hovered_tile: Tile = null

var player_base_coord: Vector2i
var ai_base_coord: Vector2i



func _ready() -> void:
	randomize()
	generate_grid()


# -------------------------------------------------
# MAP GENERATION
# -------------------------------------------------

func generate_grid() -> void:
	clear_grid()

	# 1) Base island (noisy circle)
	var center_coord: Vector2 = Vector2((cols - 1) / 2.0, (rows - 1) / 2.0)
	for r: int in range(rows):
		for c: int in range(cols):
			var p: Vector2 = Vector2(c, r)
			var dist: float = p.distance_to(center_coord)
			var cutoff: float = radius + randf_range(-radius_noise, radius_noise)
			if dist <= cutoff:
				spawn_tile_data(c, r)

	# 2) Holes
	generate_holes()

	# 3) Keep only largest connected component
	remove_disconnected_islands(Vector2i(int(center_coord.x), int(center_coord.y)))

	# 4) Prune thin spikes
	prune_low_neighbor_tiles(2)

	# 5) Place bases (farthest possible, interior)
	assign_starting_positions()

	turn = Turn.PLAYER
	pending_upgrade_tile = null


func spawn_tile_data(c: int, r: int) -> void:
	var tile: Tile = tile_scene.instantiate() as Tile
	add_child(tile)

	# Flat-top layout
	var x_pos: float = c * (tile_width * 0.75)
	var y_pos: float = r * tile_height
	if c % 2 == 1:
		y_pos += tile_height / 2.0

	tile.position = Vector2(x_pos, y_pos)
	tile.setup(Vector2i(c, r))
	grid_data[Vector2i(c, r)] = tile


func generate_holes() -> void:
	var num_holes: int = randi_range(1, 3)

	for _i: int in range(num_holes):
		if grid_data.is_empty():
			break

		# pick random existing coord safely
		var keys: Array = grid_data.keys()
		var start_coord: Vector2i = keys.pick_random() as Vector2i

		var hole_size: int = randi_range(2, 3)
		var to_remove: Array[Vector2i] = [start_coord]

		var neighbors: Array[Vector2i] = get_hex_neighbors(start_coord)
		neighbors.shuffle()

		for n: Vector2i in neighbors:
			if to_remove.size() >= hole_size:
				break
			if grid_data.has(n):
				to_remove.append(n)

		for coord: Vector2i in to_remove:
			if grid_data.has(coord):
				var t: Tile = grid_data[coord] as Tile
				if t != null:
					t.queue_free()
				grid_data.erase(coord)


func clear_grid() -> void:
	for v in grid_data.values():
		var t: Tile = v as Tile
		if t != null:
			t.queue_free()
	grid_data.clear()


# -------------------------------------------------
# BASE PLACEMENT (farthest interior tiles)
# -------------------------------------------------

func assign_starting_positions() -> void:
	if grid_data.is_empty():
		return

	# 1) interior candidates (6 neighbors)
	var candidates: Array[Tile] = []
	for k in grid_data.keys():
		var coord: Vector2i = k as Vector2i
		if count_existing_neighbors(coord) == 6:
			var t: Tile = grid_data[coord] as Tile
			if t != null:
				candidates.append(t)

	# fallback >= 4 neighbors
	if candidates.size() < 2:
		candidates.clear()
		for k in grid_data.keys():
			var coord2: Vector2i = k as Vector2i
			if count_existing_neighbors(coord2) >= 4:
				var t2: Tile = grid_data[coord2] as Tile
				if t2 != null:
					candidates.append(t2)

	if candidates.size() < 2:
		print("Not enough valid base spots.")
		return

	# 2) farthest pair by POSITION distance (more accurate than coord dx/dy)
	var max_dist: float = -1.0
	var a: Tile = null
	var b: Tile = null

	for i: int in range(candidates.size()):
		for j: int in range(i + 1, candidates.size()):
			var ta: Tile = candidates[i]
			var tb: Tile = candidates[j]
			var d: float = ta.position.distance_to(tb.position)
			if d > max_dist:
				max_dist = d
				a = ta
				b = tb

	if a == null or b == null:
		return

	# 3) Place bases
	a.is_base = true
	b.is_base = true

	# base tiles remain PLAIN type (visual is_base decides texture anyway)
	a.set_tile_type(Tile.TileType.PLAIN)
	b.set_tile_type(Tile.TileType.PLAIN)

	# Randomize which side is player/ai
	if randf() > 0.5:
		a.set_tile_owner(Tile.Owner.PLAYER)
		b.set_tile_owner(Tile.Owner.AI)
		player_base_coord = a.coord
		ai_base_coord = b.coord
	else:
		a.set_tile_owner(Tile.Owner.AI)
		b.set_tile_owner(Tile.Owner.PLAYER)
		player_base_coord = b.coord
		ai_base_coord = a.coord



func count_existing_neighbors(coord: Vector2i) -> int:
	var count: int = 0
	for nb: Vector2i in get_hex_neighbors(coord):
		if grid_data.has(nb):
			count += 1
	return count


# -------------------------------------------------
# CONNECTIVITY CLEANUP
# -------------------------------------------------

func remove_disconnected_islands(start_point: Vector2i) -> void:
	if grid_data.is_empty():
		return

	if not grid_data.has(start_point):
		# pick first existing
		var keys: Array = grid_data.keys()
		start_point = keys[0] as Vector2i

	var reachable: Dictionary = {}
	var stack: Array[Vector2i] = [start_point]
	reachable[start_point] = true

	while stack.size() > 0:
		var current: Vector2i = stack.pop_back()
		for neighbor: Vector2i in get_hex_neighbors(current):
			if grid_data.has(neighbor) and not reachable.has(neighbor):
				reachable[neighbor] = true
				stack.push_back(neighbor)

	# IMPORTANT: iterate over a copy, then erase
	var all_coords: Array[Vector2i] = []
	for k in grid_data.keys():
		all_coords.append(k as Vector2i)

	for coord: Vector2i in all_coords:
		if not reachable.has(coord):
			var t: Tile = grid_data[coord] as Tile
			if t != null:
				t.queue_free()
			grid_data.erase(coord)


func prune_low_neighbor_tiles(min_neighbors: int) -> void:
	var changed: bool = true

	while changed:
		changed = false
		var to_remove: Array[Vector2i] = []

		for k in grid_data.keys():
			var coord: Vector2i = k as Vector2i
			var count: int = 0
			for n: Vector2i in get_hex_neighbors(coord):
				if grid_data.has(n):
					count += 1
			if count < min_neighbors:
				to_remove.append(coord)

		if to_remove.size() > 0:
			changed = true
			for c: Vector2i in to_remove:
				var t: Tile = grid_data[c] as Tile
				if t != null:
					t.queue_free()
				grid_data.erase(c)


# -------------------------------------------------
# NEIGHBORS (flat-top offset)
# -------------------------------------------------

func get_hex_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var n: Array[Vector2i] = []
	var c: int = coord.x
	var r: int = coord.y

	n.append(Vector2i(c, r - 1))
	n.append(Vector2i(c, r + 1))

	if c % 2 == 0:
		n.append_array([
			Vector2i(c - 1, r - 1),
			Vector2i(c - 1, r),
			Vector2i(c + 1, r - 1),
			Vector2i(c + 1, r),
		])
	else:
		n.append_array([
			Vector2i(c - 1, r),
			Vector2i(c - 1, r + 1),
			Vector2i(c + 1, r),
			Vector2i(c + 1, r + 1),
		])

	return n


# -------------------------------------------------
# HOVER (Tile calls these)
# -------------------------------------------------

func hover_tile(tile: Tile) -> void:
	if hovered_tile == tile:
		return
	if hovered_tile != null:
		hovered_tile.deselect()
	hovered_tile = tile
	if hovered_tile != null:
		hovered_tile.select()


func unhover_tile(tile: Tile) -> void:
	if hovered_tile == tile:
		hovered_tile.deselect()
		hovered_tile = null


# -------------------------------------------------
# INPUT (1 action per turn)
# -------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Upgrade selection active -> only keys
	if pending_upgrade_tile != null:
		if event is InputEventKey and event.pressed and not event.echo:
			handle_upgrade_key((event as InputEventKey).keycode)
		return

	# Player click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if turn != Turn.PLAYER:
			return
		if hovered_tile == null:
			return

		var tile: Tile = hovered_tile

		# 1) Claim
		if try_claim(tile, Tile.Owner.PLAYER):
			end_player_turn()
			return

		# 2) Attack attempt (enemy)
		if tile.owner_state == Tile.Owner.AI:
			try_attack(tile, Tile.Owner.PLAYER)
			end_player_turn()
			return

# 3) Upgrade mode
		if can_upgrade(tile, Tile.Owner.PLAYER):
			start_upgrade(tile)
			return


func end_player_turn() -> void:
	turn = Turn.AI
	await get_tree().create_timer(0.4).timeout
	ai_take_turn()
	turn = Turn.PLAYER


func ai_take_turn() -> void:
	var result: Dictionary = ai.choose_action(
		grid_data,
		Callable(self, "get_hex_neighbors"),
		player_base_coord,
		ai_base_coord
	)

	if not result.has("action"):
		print("AI: invalid result")
		return

	var action: String = result["action"] as String
	var chosen_tile: Tile = result["tile"] as Tile

	if action == "none" or chosen_tile == null:
		print("AI: no moves")
		return

	if action == "claim":
		try_claim(chosen_tile, Tile.Owner.AI)
		return

	if action == "attack":
		try_attack(chosen_tile, Tile.Owner.AI)
		return




func try_claim(tile: Tile, who: int) -> bool:
	if tile.owner_state != Tile.Owner.NEUTRAL:
		return false

	var ok: bool = false
	for nb: Vector2i in get_hex_neighbors(tile.coord):
		if not grid_data.has(nb):
			continue
		var neighbor_tile: Tile = grid_data[nb] as Tile
		if neighbor_tile != null and neighbor_tile.owner_state == who:
			ok = true
			break

	if not ok:
		return false

	# CLAIM ALWAYS PLAIN lvl0
	tile.set_tile_owner(who)
	tile.set_tile_type(Tile.TileType.PLAIN)
	tile.set_level(0)
	return true

const BASE_AURA_BONUS: int = 5
var allow_base_attack: bool = false # Phase 3-nál majd true

func roll_2d6() -> int:
	return randi_range(1, 6) + randi_range(1, 6)


func is_in_base_aura(coord: Vector2i, base_coord: Vector2i) -> bool:
	if coord == base_coord:
		return true
	for nb: Vector2i in get_hex_neighbors(base_coord):
		if nb == coord:
			return true
	return false


func get_defense_aura_bonus(target_coord: Vector2i, defender_owner: int) -> int:
	var base_coord: Vector2i = ai_base_coord if defender_owner == Tile.Owner.AI else player_base_coord
	return BASE_AURA_BONUS if is_in_base_aura(target_coord, base_coord) else 0


func sum_support_levels(coord: Vector2i, owner: int) -> int:
	var sum_lvl: int = 0
	for nb: Vector2i in get_hex_neighbors(coord):
		if not grid_data.has(nb):
			continue
		var t: Tile = grid_data[nb] as Tile
		if t != null and t.owner_state == owner:
			sum_lvl += t.level
	return sum_lvl


func try_attack(target: Tile, attacker: int) -> bool:
	if target == null:
		return false

	var defender: int = target.owner_state
	if defender == Tile.Owner.NEUTRAL:
		return false
	if defender == attacker:
		return false

	# Phase rule: base támadás tiltva
	if target.is_base and not allow_base_attack:
		print("Base attack not allowed yet.")
		return false

	# kell adjacency: legyen a target mellett legalább 1 attacker tile
	var adjacent_ok: bool = false
	for nb: Vector2i in get_hex_neighbors(target.coord):
		if not grid_data.has(nb):
			continue
		var tnb: Tile = grid_data[nb] as Tile
		if tnb != null and tnb.owner_state == attacker:
			adjacent_ok = true
			break
	if not adjacent_ok:
		return false

	# pontszámok
	var atk_support: int = sum_support_levels(target.coord, attacker)
	var def_support: int = sum_support_levels(target.coord, defender)
	var aura_bonus: int = get_defense_aura_bonus(target.coord, defender)

	var atk_roll: int = roll_2d6()
	var def_roll: int = roll_2d6()

	var atk_total: int = atk_support + atk_roll
	var def_total: int = def_support + target.level + aura_bonus + def_roll

	print("ATTACK:", atk_total, "(support=", atk_support, " roll=", atk_roll, ")",
		" vs DEF:", def_total, "(support=", def_support, " targetlvl=", target.level, " aura=", aura_bonus, " roll=", def_roll, ")")

	if atk_total > def_total:
		# győzelem: foglalás -1 lvl
		target.set_tile_owner(attacker)
		target.set_level(max(target.level - 1, 0))
		# tile_type marad (forest->corrupt forest sprite, stb.)
		return true

	return false


func can_upgrade(tile: Tile, who: int) -> bool:
	if tile.owner_state != who:
		return false
	if tile.is_base:
		return false
	if tile.level >= 3:
		return false
	return true


func start_upgrade(tile: Tile) -> void:
	pending_upgrade_tile = tile
	print("Upgrade mode: 1=Forest, 2=Water, 3=Mountain, 0/ESC=Cancel")
	print("Upgrade mode started on:", tile.coord, " type=", Tile.TileType.keys()[tile.tile_type], " lvl=", tile.level)


func handle_upgrade_key(keycode: int) -> void:
	if pending_upgrade_tile == null:
		return

	var t: Tile = pending_upgrade_tile
	var upgraded: bool = false

	match keycode:
		KEY_1:
			upgraded = _apply_upgrade_choice(t, Tile.TileType.FOREST)
		KEY_2:
			upgraded = _apply_upgrade_choice(t, Tile.TileType.WATER)
		KEY_3:
			upgraded = _apply_upgrade_choice(t, Tile.TileType.MOUNTAIN)
		KEY_0, KEY_ESCAPE:
			pending_upgrade_tile = null
			print("Upgrade cancelled")
			return
		_:
			return

	if upgraded:
		pending_upgrade_tile = null
		end_player_turn()
	else:
		# marad upgrade módban
		print("Choose a valid upgrade")



func _apply_upgrade_choice(t: Tile, chosen_type: int) -> bool:
	# plain -> terrain lvl1
	if t.tile_type == Tile.TileType.PLAIN:
		t.set_tile_type(chosen_type)
		t.set_level(1)
		return true

	# terrain -> szintlépés, ha ugyanaz a típus
	if t.tile_type == chosen_type:
		if t.level < 3:
			t.set_level(t.level + 1)
			return true
		else:
			print("Already max level")
			return false

	print("Wrong upgrade key for this tile")
	return false
