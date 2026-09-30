class_name UITokens
extends RefCounted
## UITokens — the single source of truth for the visual language.
##
## Nothing in the UI hardcodes a colour, a radius, a gap or a duration. Changing a value here
## changes it everywhere, which is what makes a large game feel like one product instead of a
## collection of unrelated panels.
##
## Direction: restrained dark fantasy. Deep blue-black ground, slightly raised surfaces,
## parchment text, muted gold reserved for milestones and primary actions, teal for gathering
## and recovery, blue for crafting and the arcane, amber/red for danger.

# ---------------------------------------------------------------- colour: ground & surface
const BG_DEEP := Color("#081321")        ## app background, behind everything
const BG := Color("#0d1a2a")             ## workspace background
const SURFACE := Color("#122236")        ## raised panel
const SURFACE_2 := Color("#1a2d43")      ## raised row / input
const SURFACE_3 := Color("#253c56")      ## hover / selected row
const SURFACE_SUNKEN := Color("#0a1726") ## wells, logs, code-like blocks
const BORDER := Color("#2d4965")
const BORDER_STRONG := Color("#476783")
const BORDER_GOLD := Color("#9d7833")

# ---------------------------------------------------------------- colour: text
const TEXT := Color("#e1eaf3")
const TEXT_STRONG := Color("#f7f9fc")
const TEXT_MUTED := Color("#a7b8c9")
const TEXT_DIM := Color("#74899e")
const TEXT_ON_GOLD := Color("#1a1508")

# ---------------------------------------------------------------- colour: semantics
const GOLD := Color("#d5a640")           ## milestones, primary actions, tracked goals
const GOLD_BRIGHT := Color("#f1cb70")
const TEAL := Color("#4fb3a1")           ## gathering, recovery, positive passive
const BLUE := Color("#5f93d8")           ## crafting, arcane
const AMBER := Color("#dc9a3a")          ## caution / blocked
const RED := Color("#c9553f")            ## danger, combat, destructive
const GREEN := Color("#6fbf73")          ## success, satisfied requirement
const PURPLE := Color("#9a77c9")         ## rare / mastery
const DISABLED := Color("#5a5c60")

# ---------------------------------------------------------------- rarity (presentation only)
## Rarity is a presentation layer derived from data we already have (explicit tier, then sell
## value band). It is documented here so nobody mistakes it for a gameplay stat.
const RARITY: Dictionary = {
	"common": {"label": "Common", "color": BORDER_STRONG},
	"uncommon": {"label": "Uncommon", "color": TEAL},
	"rare": {"label": "Rare", "color": BLUE},
	"epic": {"label": "Epic", "color": PURPLE},
	"legendary": {"label": "Legendary", "color": GOLD},
	"relic": {"label": "Relic", "color": GOLD_BRIGHT},
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
## Wide enough for the longest label at the level cap ("Marksmanship · Lv 120") with
## slack; the sidebar scrolls vertically, so only width decides whether a label clips.
const W_SIDEBAR := 240
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
