class_name UITokens
extends RefCounted
## UITokens — the single source of truth for the visual language.
##
## Nothing in the UI hardcodes a colour, a radius, a gap or a duration. Changing a value here
## changes it everywhere, which is what makes a large game feel like one product instead of a
## collection of unrelated panels.
##
## Direction: ember-and-charcoal dark fantasy. Warm charcoal ground, umber surfaces,
## parchment text, ember-orange primary actions, muted gold kept for rarity-tier highlights,
## teal for gathering and recovery, blue for crafting and the arcane, amber/red for danger.

# ---------------------------------------------------------------- colour: ground & surface
const BG_DEEP := Color("#141010")        ## app background, behind everything
const BG := Color("#1e1611")             ## workspace background
const SURFACE := Color("#2a1e15")        ## raised panel
const SURFACE_2 := Color("#38291c")      ## raised row / input
const SURFACE_3 := Color("#4a3826")      ## hover / selected row
const SURFACE_SUNKEN := Color("#100c09") ## wells, logs, code-like blocks
const BORDER := Color("#5a4433")
const BORDER_STRONG := Color("#7d6248")
const BORDER_GOLD := Color("#9d7833")

# ---------------------------------------------------------------- colour: text
const TEXT := Color("#e8dcc3")
const TEXT_STRONG := Color("#faf3e0")
const TEXT_MUTED := Color("#9a8c72")
const TEXT_DIM := Color("#6f6350")
const TEXT_ON_GOLD := Color("#1a1508")

# ---------------------------------------------------------------- colour: semantics
const GOLD := Color("#e2622b")           ## ember-orange: milestones, primary actions, tracked goals
const GOLD_BRIGHT := Color("#ee7d3d")    ## lighter ember for focus rings and highlights
const TEAL := Color("#5fa396")           ## gathering, recovery, positive passive
const BLUE := Color("#5f93d8")           ## crafting, arcane
const AMBER := Color("#bd8f4d")          ## caution / blocked
const RED := Color("#b0604b")            ## danger, combat, destructive
const GREEN := Color("#6fbf73")          ## success, satisfied requirement
const PURPLE := Color("#9a77c9")         ## rare / mastery
const DISABLED := Color("#5a5c60")

# ---------------------------------------------------------------- rarity (presentation only)
## Rarity is a presentation layer derived from data we already have (explicit tier, then sell
## value band). It is documented here so nobody mistakes it for a gameplay stat.
## Legendary/relic keep literal golds: GOLD/GOLD_BRIGHT are the ember accent now.
const RARITY: Dictionary = {
	"common": {"label": "Common", "color": BORDER_STRONG},
	"uncommon": {"label": "Uncommon", "color": TEAL},
	"rare": {"label": "Rare", "color": BLUE},
	"epic": {"label": "Epic", "color": PURPLE},
	"legendary": {"label": "Legendary", "color": Color("#d5a640")},
	"relic": {"label": "Relic", "color": Color("#f1cb70")},
}

# ---------------------------------------------------------------- spacing
const SP_1 := 2
const SP_2 := 4
const SP_3 := 6
const SP_4 := 8
const SP_5 := 14
const SP_6 := 18
const SP_7 := 26
const SP_8 := 34

# ---------------------------------------------------------------- radius
const R_SM := 4
const R_MD := 8
const R_LG := 12
const R_PILL := 999

# ---------------------------------------------------------------- type
const FONT_MICRO := 11
const FONT_SMALL := 13
const FONT_BODY := 14
const FONT_SUBHEAD := 16
const FONT_HEAD := 19
const FONT_DISPLAY := 23
const FONT_NUMERIC := 13

# ---------------------------------------------------------------- motion
const DUR_FAST := 0.10
const DUR_NORMAL := 0.18
const DUR_SLOW := 0.32

# ---------------------------------------------------------------- layering
const Z_BASE := 0
const Z_RAISED := 10
const Z_STRIP := 40
const Z_OVERLAY := 100
const Z_DIALOG := 200
const Z_TOAST := 300

# ---------------------------------------------------------------- component sizes
const H_CONTROL := 32
const H_ROW := 36
const H_HEADER := 38
const H_STRIP := 40
const W_SIDEBAR := 208
const W_SIDEBAR_COMPACT := 56
## The contextual detail pane. It was wide enough to compete with the workspace for attention, so
## it is deliberately the smaller half of the window: the workspace is where the game is played.
const W_DETAIL := 260
const ICON_SM := 18
const ICON_MD := 26
const ICON_LG := 40
const ICON_XL := 64

## Layout breakpoints (viewport width in CSS pixels).
const BP_NARROW := 760      ## below this: drawer navigation, stacked layout
const BP_MEDIUM := 1080     ## below this: detail panel collapses under the workspace

static func rarity(key: String) -> Dictionary:
	return RARITY.get(key, RARITY["common"])

## Derive a presentation rarity from content data. Documented heuristic, not a game stat.
static func rarity_for_item(item: Dictionary) -> String:
	var tier: String = str(item.get("tier", "")).to_lower()
	if tier != "":
		for key in RARITY.keys():
			if key == tier:
				return key
	var value: int = int(item.get("sell_price", 0))
	if value >= 10_000_000:
		return "relic"
	if value >= 500_000:
		return "legendary"
	if value >= 50_000:
		return "epic"
	if value >= 2_000:
		return "rare"
	if value >= 100:
		return "uncommon"
	return "common"
