extends RefCounted
class_name SimpleAI

const DICE_AVG_2D6: float = 7.0
const BASE_AURA_BONUS: int = 5

# mennyire legyen "szeszélyes" a top akciók között
var randomness: float = 0.2

# Attack akkor, ha margin >= threshold
var attack_threshold: float = 1.0


func choose_action(
	grid_data: Dictionary,
	get_neighbors: Callable,
	player_base: Vector2i,
	ai_base: Vector2i
) -> Dictionary:
	# --- ATTACK jelöltek ---
	var attack_targets: Array[Tile] = _gather_attack_targets(grid_data, get_neighbors)

	var best_attack: Tile = null
	var best_attack_score: float = -999999.0

	for t: Tile in attack_targets:
		var margin: float = estimate_attack_margin(
			Tile.Owner.AI, t, grid_data, get_neighbors, player_base, ai_base
		)

		# zóna bónuszok (maradhat)
		if is_in_base_aura(t.coord, player_base, get_neighbors):
			margin += 2.0
		if is_in_base_aura(t.coord, ai_base, get_neighbors):
			margin += 3.0

		if margin > best_attack_score:
			best_attack_score = margin
			best_attack = t

	# --- CLAIM jelölt ---
	var claim_tile: Tile = choose_claim(grid_data, get_neighbors, player_base, ai_base)

	# 1) Ha van jó támadás és megéri: támad
	if best_attack != null and best_attack_score >= attack_threshold:
		return {"action": "attack", "tile": best_attack}

	# 2) Ha van claim: claim
	if claim_tile != null:
		return {"action": "claim", "tile": claim_tile}

	# 3) Ha nincs claim (levágták), de van attack: KÉNYSZER támadás
	if best_attack != null:
		return {"action": "attack", "tile": best_attack}

	# 4) Ha attack sincs (se szomszéd neutral, se szomszéd enemy): tényleg nincs lépés
	return {"action": "none", "tile": null}

# ---------------------------
# CLAIM (a meglévő logikád, kicsit kiszervezve)
# ---------------------------

func choose_claim(
	grid_data: Dictionary,
	get_neighbors: Callable,
	player_base: Vector2i,
	ai_base: Vector2i
) -> Tile:
	var candidates: Array[Tile] = []

	var keys: Array = grid_data.keys()
	for key in keys:
		var coord: Vector2i = key as Vector2i
		var t_any: Variant = grid_data[coord]
		var t: Tile = t_any as Tile
		if t == null:
			continue
		if t.owner_state != Tile.Owner.AI:
			continue

		var nb_any: Variant = get_neighbors.call(coord)
		var nb_list: Array = nb_any as Array
		for nb_v in nb_list:
			var nbc: Vector2i = nb_v as Vector2i
			if not grid_data.has(nbc):
				continue
			var nt_any: Variant = grid_data[nbc]
			var nt: Tile = nt_any as Tile
			if nt != null and nt.owner_state == Tile.Owner.NEUTRAL:
				if not candidates.has(nt):
					candidates.append(nt)

	if candidates.is_empty():
		return null

	var threat: float = estimate_threat(grid_data, get_neighbors, ai_base)
	var defense_weight: float = clamp(threat, 0.0, 1.0)

	var scored: Array[Array] = []
	for tile: Tile in candidates:
		var s: float = score_claim(tile, grid_data, get_neighbors, player_base, ai_base, defense_weight)
		scored.append([s, tile])

	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[0]) > float(b[0])
	)

	var top_n: int = min(3, scored.size())
	if top_n <= 1:
		return scored[0][1] as Tile

	if randf() < randomness:
		var idx: int = randi_range(0, top_n - 1)
		return scored[idx][1] as Tile

	return scored[0][1] as Tile


# (A score_claim és estimate_threat maradhat a mostani verziód, csak használja a tile.level-t, ha akarod)
func score_claim(
	tile: Tile,
	grid_data: Dictionary,
	get_neighbors: Callable,
	player_base: Vector2i,
	ai_base: Vector2i,
	defense_weight: float
) -> float:
	var new_neutral: int = 0
	var ai_neighbors: int = 0
	var player_neighbors: int = 0

	var nb_any: Variant = get_neighbors.call(tile.coord)
	var nb_list: Array = nb_any as Array

	for nb_v in nb_list:
		var c: Vector2i = nb_v as Vector2i
		if not grid_data.has(c):
			continue
		var nt_any: Variant = grid_data[c]
		var nt: Tile = nt_any as Tile
		if nt == null:
			continue

		if nt.owner_state == Tile.Owner.NEUTRAL:
			new_neutral += 1
		elif nt.owner_state == Tile.Owner.AI:
			ai_neighbors += 1
		elif nt.owner_state == Tile.Owner.PLAYER:
			player_neighbors += 1

	var dist_to_player: float = float(tile.coord.distance_to(player_base))
	var offense: float = -dist_to_player
	var defense: float = float(player_neighbors)

	var score: float = 0.0
	score += 3.0 * float(new_neutral)
	score += 2.0 * float(ai_neighbors)
	if ai_neighbors <= 1:
		score -= 2.5

	score += lerp(2.5 * offense, 4.0 * defense, defense_weight)
	return score


func estimate_threat(
	grid_data: Dictionary,
	get_neighbors: Callable,
	ai_base: Vector2i
) -> float:
	var visited: Dictionary = {}
	var frontier: Array[Vector2i] = [ai_base]
	visited[ai_base] = true

	var depth: int = 0
	var player_count: int = 0

	while depth < 2:
		var next: Array[Vector2i] = []
		for c: Vector2i in frontier:
			var nb_any: Variant = get_neighbors.call(c)
			var nb_list: Array = nb_any as Array
			for nb_v in nb_list:
				var nbc: Vector2i = nb_v as Vector2i
				if visited.has(nbc):
					continue
				visited[nbc] = true

				if grid_data.has(nbc):
					var t_any: Variant = grid_data[nbc]
					var t: Tile = t_any as Tile
					if t != null and t.owner_state == Tile.Owner.PLAYER:
						player_count += 1

				next.append(nbc)

		frontier = next
		depth += 1

	return clamp(float(player_count) / 3.0, 0.0, 1.0)


# ---------------------------
# ATTACK evaluation helpers
# ---------------------------

func _gather_attack_targets(grid_data: Dictionary, get_neighbors: Callable) -> Array[Tile]:
	var targets: Array[Tile] = []
	var keys: Array = grid_data.keys()

	for key in keys:
		var coord: Vector2i = key as Vector2i
		var t_any: Variant = grid_data[coord]
		var t: Tile = t_any as Tile
		if t == null:
			continue
		if t.owner_state != Tile.Owner.AI:
			continue

		var nb_any: Variant = get_neighbors.call(coord)
		var nb_list: Array = nb_any as Array
		for nb_v in nb_list:
			var nbc: Vector2i = nb_v as Vector2i
			if not grid_data.has(nbc):
				continue
			var nt_any: Variant = grid_data[nbc]
			var nt: Tile = nt_any as Tile
			if nt != null and nt.owner_state == Tile.Owner.PLAYER:
				if not targets.has(nt):
					targets.append(nt)

	return targets


func is_in_base_aura(coord: Vector2i, base_coord: Vector2i, get_neighbors: Callable) -> bool:
	if coord == base_coord:
		return true

	var nb_any: Variant = get_neighbors.call(base_coord)
	var nb_list: Array = nb_any as Array
	for nb_v in nb_list:
		var nbc: Vector2i = nb_v as Vector2i
		if nbc == coord:
			return true

	return false


func sum_support_levels(
	coord: Vector2i,
	owner: int,
	grid_data: Dictionary,
	get_neighbors: Callable
) -> int:
	var sum_lvl: int = 0
	var nb_any: Variant = get_neighbors.call(coord)
	var nb_list: Array = nb_any as Array

	for nb_v in nb_list:
		var nbc: Vector2i = nb_v as Vector2i
		if not grid_data.has(nbc):
			continue
		var t_any: Variant = grid_data[nbc]
		var t: Tile = t_any as Tile
		if t == null:
			continue
		if t.owner_state != owner:
			continue
		sum_lvl += t.level

	return sum_lvl


func estimate_attack_margin(
	attacker_owner: int,
	target: Tile,
	grid_data: Dictionary,
	get_neighbors: Callable,
	player_base: Vector2i,
	ai_base: Vector2i
) -> float:
	if target == null:
		return -999999.0

	var defender_owner: int = target.owner_state
	if defender_owner == Tile.Owner.NEUTRAL:
		return -999999.0
	if defender_owner == attacker_owner:
		return -999999.0

	var atk_support: int = sum_support_levels(target.coord, attacker_owner, grid_data, get_neighbors)
	var def_support: int = sum_support_levels(target.coord, defender_owner, grid_data, get_neighbors)

	var target_lvl: int = target.level

	var defender_base: Vector2i = ai_base if defender_owner == Tile.Owner.AI else player_base
	var aura_bonus: int = BASE_AURA_BONUS if is_in_base_aura(target.coord, defender_base, get_neighbors) else 0

	var expected_atk: float = float(atk_support) + DICE_AVG_2D6
	var expected_def: float = float(def_support + target_lvl + aura_bonus) + DICE_AVG_2D6

	return expected_atk - expected_def
