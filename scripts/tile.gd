class_name Tile
extends Node2D

const TEX_NEUTRAL := preload("res://assets/tiles/Neutral.png")

const TEX_NATURE_BASE := preload("res://assets/tiles/Nature Base.png")
const TEX_NATURE_PLAIN := preload("res://assets/tiles/Plain.png")
const TEX_NATURE_FOREST_L1 := preload("res://assets/tiles/Forest 1.png")
const TEX_NATURE_MOUNTAIN_L1 := preload("res://assets/tiles/Mountain 1.png")
const TEX_NATURE_WATER_L1 := preload("res://assets/tiles/Water 1.png")

const TEX_CORRUPT_BASE := preload("res://assets/tiles/Corrupt Base.png")
const TEX_CORRUPT_PLAIN := preload("res://assets/tiles/Corrupt Plain.png")

@onready var sprite: Sprite2D = $Sprite2D
@onready var area: Area2D = $Area2D

enum Owner { NEUTRAL, PLAYER, AI }
enum TileType { PLAIN, FOREST, WATER, MOUNTAIN }

var tile_type: int = TileType.PLAIN
var coord: Vector2i = Vector2i(-1, -1)
var owner_state: int = Owner.NEUTRAL
var is_base: bool = false

# NEW: level 0..3 (0 = plain/neutral alap)
var level: int = 0


func _ready() -> void:
	deselect()
	area.mouse_entered.connect(_on_mouse_entered)
	area.mouse_exited.connect(_on_mouse_exited)


func setup(p_coord: Vector2i) -> void:
	coord = p_coord
	is_base = false
	tile_type = TileType.PLAIN
	level = 0
	set_tile_owner(Owner.NEUTRAL)


func set_tile_owner(new_owner: int) -> void:
	owner_state = new_owner
	update_visuals()


func set_tile_type(new_type: int) -> void:
	tile_type = new_type
	update_visuals()


func set_level(new_level: int) -> void:
	level = clampi(new_level, 0, 3)
	update_visuals()


# --- Texture helpers (safe) ---

func _try_load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		return res as Texture2D
	return null


func _get_nature_terrain_texture(tt: int, lvl: int) -> Texture2D:
	# Plain nem “lvl-es” (marad ugyanaz)
	if tt == TileType.PLAIN:
		return TEX_NATURE_PLAIN

	# Lvl1 biztosan van (preload), lvl2-3 csak ha létezik a fájl
	var path: String = ""
	match tt:
		TileType.FOREST:
			if lvl <= 1:
				return TEX_NATURE_FOREST_L1
			path = "res://assets/tiles/Forest %d.png" % lvl
			var t: Texture2D = _try_load(path)
			return t if t != null else TEX_NATURE_FOREST_L1
		TileType.WATER:
			if lvl <= 1:
				return TEX_NATURE_WATER_L1
			path = "res://assets/tiles/Water %d.png" % lvl
			var t2: Texture2D = _try_load(path)
			return t2 if t2 != null else TEX_NATURE_WATER_L1
		TileType.MOUNTAIN:
			if lvl <= 1:
				return TEX_NATURE_MOUNTAIN_L1
			path = "res://assets/tiles/Mountain %d.png" % lvl
			var t3: Texture2D = _try_load(path)
			return t3 if t3 != null else TEX_NATURE_MOUNTAIN_L1

	return TEX_NATURE_PLAIN


func _get_corrupt_terrain_texture(tt: int, lvl: int) -> Texture2D:
	# Ha még nincs külön corrupt terrain textúrázás implementálva biztosan,
	# akkor safe fallback: corrupt plain.
	# Ha már vannak fájlok, próbáljuk betölteni őket.
	if tt == TileType.PLAIN:
		return TEX_CORRUPT_PLAIN

	# Itt a név-konvenciót lehet majd a te fájlneveidhez igazítani.
	# Példa feltételezés: "Corrupt Forest 1.png", "Corrupt Forest 2.png", ...
	var path: String = ""
	match tt:
		TileType.FOREST:
			path = "res://assets/tiles/Corrupt Forest %d.png" % max(lvl, 1)
		TileType.WATER:
			path = "res://assets/tiles/Corrupt Water %d.png" % max(lvl, 1)
		TileType.MOUNTAIN:
			path = "res://assets/tiles/Corrupt Mountain %d.png" % max(lvl, 1)

	var t: Texture2D = _try_load(path)
	return t if t != null else TEX_CORRUPT_PLAIN


func update_visuals() -> void:
	# Base külön
	if is_base:
		if owner_state == Owner.PLAYER:
			sprite.texture = TEX_NATURE_BASE
		elif owner_state == Owner.AI:
			sprite.texture = TEX_CORRUPT_BASE
		else:
			sprite.texture = TEX_NEUTRAL
		return

	# Neutral
	if owner_state == Owner.NEUTRAL:
		sprite.texture = TEX_NEUTRAL
		return

	# AI
	if owner_state == Owner.AI:
		sprite.texture = _get_corrupt_terrain_texture(tile_type, level)
		return

	# Player
	sprite.texture = _get_nature_terrain_texture(tile_type, level)


func select() -> void:
	sprite.modulate.a = 0.7


func deselect() -> void:
	sprite.modulate.a = 1.0


func _on_mouse_entered() -> void:
	if get_parent().has_method("hover_tile"):
		get_parent().hover_tile(self)
	


func _on_mouse_exited() -> void:
	if get_parent().has_method("unhover_tile"):
		get_parent().unhover_tile(self)
