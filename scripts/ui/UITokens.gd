class_name UITokens
extends RefCounted
## UITokens — the single source of truth for the visual language.
##
## Nothing in the UI hardcodes a colour, a radius, a gap or a duration. Changing a value here
## changes it everywhere, which is what makes a large game feel like one product instead of a
## collection of unrelated panels.
##
## Direction: Arcane Glass. A deep violet night behind everything (painted by MainUI as a radial
## gradient), frosted translucent panels floating over it, soft coloured glows instead of hard
## borders, and a violet→magenta accent reserved for primary actions and milestones. Cyan marks
## gathering/recovery, rose marks danger. The legacy token NAMES are kept (GOLD = "the primary
## accent", BORDER_GOLD = "the accent edge") so every panel inherits the look with no edits.

# ---------------------------------------------------------------- colour: ground & surface
const BG_DEEP := Color("#07071a")        ## app background, behind everything
const BG := Color("#0c0b24")             ## workspace background
## Surfaces are translucent on purpose: the gradient behind them shows through, which is what
## makes the panels read as glass rather than flat cards.
const SURFACE := Color("#1a1842c4")      ## raised panel (glass)
const SURFACE_2 := Color("#ffffff0f")    ## raised row / input, layered on a panel
const SURFACE_3 := Color("#8b5cf633")    ## hover / selected row (violet tint)
const SURFACE_SUNKEN := Color("#0000004d") ## wells, logs, code-like blocks
const BORDER := Color("#ffffff1c")
const BORDER_STRONG := Color("#ffffff3d")
const BORDER_GOLD := Color("#a78bfa")    ## accent edge (violet)

# ---------------------------------------------------------------- colour: text
const TEXT := Color("#e4e2f5")
const TEXT_STRONG := Color("#ffffff")
const TEXT_MUTED := Color("#b9b6d6")
const TEXT_DIM := Color("#8b88b0")
const TEXT_ON_GOLD := Color("#ffffff")   ## text on a filled primary button

# ---------------------------------------------------------------- colour: semantics
const GOLD := Color("#a78bfa")           ## primary accent: milestones, primary actions, goals
const GOLD_BRIGHT := Color("#d8ccff")    ## headings and highlighted values
const TEAL := Color("#22d3ee")           ## gathering, recovery, positive passive
const BLUE := Color("#60a5fa")           ## crafting, arcane
const AMBER := Color("#fbbf24")          ## caution / blocked
const RED := Color("#fb5a7a")            ## danger, combat, destructive
const GREEN := Color("#34d399")          ## success, satisfied requirement
const PURPLE := Color("#e879f9")         ## rare / mastery
const DISABLED := Color("#5d5a7d")

# ---------------------------------------------------------------- colour: glass extras
const ACCENT_VIOLET := Color("#7c3aed")  ## filled primary button
const ACCENT_PINK := Color("#db2777")    ## the far end of the accent gradient
const GLOW := Color("#8b5cf6")           ## shadow colour that makes panels glow
const BG_GLOW_A := Color("#2b1d6e")      ## background gradient: light source
const BG_GLOW_B := Color("#120f35")      ## background gradient: mid
const CURRENCY := Color("#fcd34d")       ## real gold, for coin values and legendary loot

# ---------------------------------------------------------------- rarity (presentation only)
## Rarity is a presentation layer derived from data we already have (explicit tier, then sell
## value band). It is documented here so nobody mistakes it for a gameplay stat.
const RARITY: Dictionary = {
	"common": {"label": "Common", "color": Color("#8b88b0")},
	"uncommon": {"label": "Uncommon", "color": TEAL},
	"rare": {"label": "Rare", "color": BLUE},
	"epic": {"label": "Epic", "color": PURPLE},
	"legendary": {"label": "Legendary", "color": Color("#fbbf24")},
	"relic": {"label": "Relic", "color": CURRENCY},
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
const R_SM := 5
const R_MD := 10
const R_LG := 14
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
