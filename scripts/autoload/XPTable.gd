extends Node
## XPTable — precomputed XP tables for levels 1..120 (autoload singleton).
##
## Uses the canonical RuneScape/Melvor cumulative formula:
##     xp(L) = floor( 0.25 * Σ_{n=1}^{L-1} floor( n + 300 * 2^(n/7) ) )
## which yields EXACTLY:
##     xp(99)  = 13,034,431
##     xp(120) = 104,273,167
##
## NOTE: the brief's per-level recurrence `floor(0.25*(L-1+300*2^((L-1)/7)))`
## drifts by a few XP (13034469 vs 13034431 at 99) because of floor placement.
## We therefore build from the canonical sum, verified at startup.

const MAX_LEVEL: int = 120
const XP_LEVEL_99: int = 13_034_431
const XP_LEVEL_120: int = 104_273_167

# total_xp[level] = cumulative XP required to REACH that level. Index 0 unused.
var _total_xp: PackedInt64Array = PackedInt64Array()

func _ready() -> void:
    build_tables()

## Build the cumulative table once at startup (O(MAX_LEVEL)).
func build_tables() -> void:
    _total_xp.resize(MAX_LEVEL + 1)
    _total_xp[0] = 0
    _total_xp[1] = 0
    var inner: float = 0.0
    for n in range(1, MAX_LEVEL):        # n = 1 .. MAX_LEVEL-1
        inner += floor(n + 300.0 * pow(2.0, float(n) / 7.0))
        _total_xp[n + 1] = int(floor(0.25 * inner))
    # Fail loudly if the environment's float math ever disagrees with the spec.
    assert(_total_xp[99] == XP_LEVEL_99, "XPTable: level 99 total mismatch")
    assert(_total_xp[120] == XP_LEVEL_120, "XPTable: level 120 total mismatch")

## Total XP needed to reach `level` (1..120). Clamped.
func xp_for_level(level: int) -> int:
    return _total_xp[clampi(level, 0, MAX_LEVEL)]

## Highest level fully unlocked by `xp` (capped at MAX_LEVEL).
func level_for_xp(xp: float) -> int:
    var lvl: int = 1
    for l in range(2, MAX_LEVEL + 1):
        if xp >= float(_total_xp[l]):
            lvl = l
        else:
            break
    return lvl

## XP still required to reach the next level (0 if at MAX_LEVEL).
func xp_to_next_level(xp: float, level: int) -> int:
    if level >= MAX_LEVEL:
        return 0
    return int(max(0.0, float(_total_xp[level + 1]) - xp))

## Fractional progress (0..1) through the current level.
func level_progress(xp: float, level: int) -> float:
    if level >= MAX_LEVEL:
        return 1.0
    var start: int = _total_xp[level]
    var nxt: int = _total_xp[level + 1]
    if nxt <= start:
        return 1.0
    return clampf((xp - float(start)) / float(nxt - start), 0.0, 1.0)

## Binary-search the level for large XP values (used by offline simulation).
func level_for_xp_binary(xp: float) -> int:
    var lo: int = 1
    var hi: int = MAX_LEVEL
    while lo < hi:
        var mid: int = int((lo + hi + 1) / 2)
        if xp >= float(_total_xp[mid]):
            lo = mid
        else:
            hi = mid - 1
    return lo

## Raw copy of the table (used by SaveManager / tests / UI graphs).
func get_table() -> PackedInt64Array:
    return _total_xp
