## Legacy System.Random sequence; changing draws changes existing floor seeds.
class_name DotNetRandom
extends RefCounted

const MBIG: int = 2147483647
const MSEED: int = 161803398
# Keep the upper bound exclusive under single-precision rounding.
const NEXT_DOUBLE_MAX: float = 0.99999994

var _seed_array: PackedInt64Array = PackedInt64Array()
var _inext: int = 0
var _inextp: int = 21

func _init(seed_value: int) -> void:
	_seed_array.resize(56)
	var subtraction: int = MBIG if seed_value == -2147483648 else absi(seed_value)
	var mj: int = MSEED - subtraction
	_seed_array[55] = mj
	var mk: int = 1
	for i: int in range(1, 55):
		var ii: int = (21 * i) % 55
		_seed_array[ii] = mk
		mk = mj - mk
		if mk < 0:
			mk += MBIG
		mj = _seed_array[ii]

	for _pass: int in range(1, 5):
		for i: int in range(1, 56):
			_seed_array[i] -= _seed_array[1 + (i + 30) % 55]
			if _seed_array[i] < 0:
				_seed_array[i] += MBIG
	_inext = 0
	_inextp = 21

func _internal_sample() -> int:
	var loc_inext: int = _inext + 1
	if loc_inext >= 56:
		loc_inext = 1
	var loc_inextp: int = _inextp + 1
	if loc_inextp >= 56:
		loc_inextp = 1

	var value: int = _seed_array[loc_inext] - _seed_array[loc_inextp]
	if value == MBIG:
		value -= 1
	if value < 0:
		value += MBIG

	_seed_array[loc_inext] = value
	_inext = loc_inext
	_inextp = loc_inextp
	return value

func next_double() -> float:
	return clampf(
		float(_internal_sample()) * (1.0 / float(MBIG)),
		0.0, NEXT_DOUBLE_MAX
	)

# Clamp the public RNG range before values are used as indices.
func next_int(minimum_inclusive: int, maximum_exclusive: int) -> int:
	var range_size: int = maximum_exclusive - minimum_inclusive
	var value: int = int(next_double() * float(range_size)) + minimum_inclusive
	return clampi(value, minimum_inclusive, maximum_exclusive - 1)
