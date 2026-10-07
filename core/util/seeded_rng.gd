class_name SeededRng
extends RefCounted
## Makes random number generators that give the same results on every PC.
## Each use gets its own "stream" name, so adding a new random roll in one system
## never changes the rolls in another (e.g. adding a loot roll won't change the floor layout).
##
## Example: var rng := SeededRng.make(run_seed, &"level_layout", floor_index)


static func make(base_seed: int, stream: StringName, index: int = 0) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("%d|%s|%d" % [base_seed, stream, index])
	return rng


## Picks an index from a list of weights. Returns -1 if every weight is 0 or the list is empty.
static func pick_weighted(rng: RandomNumberGenerator, weights: PackedFloat32Array) -> int:
	var total: float = 0.0
	for weight: float in weights:
		total += maxf(weight, 0.0)
	if total <= 0.0:
		return -1
	var roll: float = rng.randf() * total
	for i: int in weights.size():
		roll -= maxf(weights[i], 0.0)
		if roll < 0.0:
			return i
	return weights.size() - 1
