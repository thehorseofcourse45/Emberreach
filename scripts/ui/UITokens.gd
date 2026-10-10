class_name UITokens
extends RefCounted
## UITokens — the single source of truth for the visual language.
##
## Nothing in the UI hardcodes a colour, a radius, a gap or a duration. Changing a value here
## changes it everywhere, which is what makes a large game feel like one product instead of a
## collection of unrelated panels.
##
## Direction: Grimoire on the Forge. A dark ember forge behind everything (MainUI's backdrop
## shader), oxblood leather panels with gold trim floating over it, and smoked-vellum cards inside
## them for content. Ember orange marks progress; gold ink marks headings and highlights. The token
## NAMES are the long-standing ones (GOLD = "the primary accent", SURFACE_2 = "a card on a panel"),
## so every panel inherits the look with no edits.

# ---------------------------------------------------------------- colour: ground & surface
const BG_DEEP := Color("#0d0a09")        ## forge, behind everything
const BG := Color("#1b1512")             ## forge, upper half
const FORGE_GLOW := Color(1.0, 0.353, 0.078, 0.35)  ## the glow rising from the forge floor
const SURFACE := Color("#3a1c10")        ## leather panel (mid-tone of the leather gradient)
const SURFACE_2 := Color("#5a3e28")      ## smoked-vellum card (mid-tone of the vellum gradient)
const SURFACE_3 := Color("#7a5636")      ## hover / selected row
const SURFACE_SUNKEN := Color("#2e1f14") ## wells, logs, empty slots
const BORDER := Color("#a8763a")         ## vellum edge
const BORDER_STRONG := Color("#c88c2c")
const BORDER_GOLD := Color("#c88c2c")    ## gold trim
## Gradient stops the generated textures are painted from; the *_MID values are what text sits on.
const LEATHER_TOP := Color("#4a2414")
const LEATHER_BOTTOM := Color("#2a140b")
const LEATHER_MID := Color("#3a1c10")
const VELLUM_TOP := Color("#6b4a30")
const VELLUM_BOTTOM := Color("#4a3220")
const VELLUM_MID := Color("#5a3e28")

# ---------------------------------------------------------------- colour: text
const TEXT := Color("#f1dcb8")           ## body ink
const TEXT_STRONG := Color("#fff3dc")
const TEXT_MUTED := Color("#c9ae86")
const TEXT_DIM := Color("#9c8468")
const TEXT_ON_GOLD := Color("#f3e3bd")   ## text on a filled (oxblood) primary button

# ---------------------------------------------------------------- colour: semantics
## Every ink below reaches 4.5:1 on both VELLUM_MID and LEATHER_MID (test_grimoire_palette).
const GOLD := Color("#c88c2c")           ## primary accent: milestones, primary actions, goals
const GOLD_BRIGHT := Color("#f0c870")    ## heading ink and highlighted values
const TEAL := Color("#5fc3b2")           ## gathering, recovery, positive passive
const BLUE := Color("#87b6ea")           ## crafting, arcane
const AMBER := Color("#e0a84d")          ## caution / blocked
const RED := Color("#ec9d91")            ## danger ink (a light ember-rose: readable on dark vellum)
const GREEN := Color("#76c27a")          ## success, satisfied requirement
const PURPLE := Color("#c4a5ea")         ## rare / mastery
const DISABLED := Color("#7d6a58")

# ---------------------------------------------------------------- colour: forge extras
## Kept names from the glass era, remapped: callers that asked for "the accent fill" or "the glow"
## get the forge equivalent.
const ACCENT_VIOLET := Color("#6b1f12")  ## filled primary button (oxblood)
const ACCENT_PINK := Color("#b8380f")    ## the far end of the accent gradient (ember)
const GLOW := Color("#ff7a2a")           ## glow colour around panels and focus
const BG_GLOW_A := Color("#3a1a0c")
const BG_GLOW_B := Color("#1b1512")
const CURRENCY := Color("#ffe08a")       ## real gold, for coin values and relic loot
const DANGER_FILL := Color("#7a1f12")    ## filled destructive button
const EMBER_BAR_A := Color("#a12a0b")    ## progress gradient: cold end
const EMBER_BAR_B := Color("#ff7a2a")
const EMBER_BAR_C := Color("#ffd27a")    ## progress gradient: hot end

# ---------------------------------------------------------------- rarity (presentation only)
## Rarity is a presentation layer derived from data we already have (explicit tier, then sell
## value band). It is documented here so nobody mistakes it for a gameplay stat.
const RARITY: Dictionary = {
	"common": {"label": "Common", "color": Color("#bcb09b")},
	"uncommon": {"label": "Uncommon", "color": TEAL},
	"rare": {"label": "Rare", "color": BLUE},
	"epic": {"label": "Epic", "color": PURPLE},
	"legendary": {"label": "Legendary", "color": Color("#ffc845")},
	"relic": {"label": "Relic", "color": CURRENCY},
}

## WCAG 2 contrast ratio between two opaque colours (1.0 .. 21.0).
static func contrast_ratio(a: Color, b: Color) -> float:
	var la: float = _luminance(a)
	var lb: float = _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

static func _luminance(c: Color) -> float:
	var ch := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * ch.call(c.r) + 0.7152 * ch.call(c.g) + 0.0722 * ch.call(c.b)

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

# ---------------------------------------------------------------- nine-slice
## The files in assets/ui/ are old-scheme navy art, not ember art, so consuming them is opt-in:
## with this off the UI renders the warm code-drawn surfaces (UIStyle.surface_box's flat
## fallback). Flip it to true once the owner's ember art lands and every
## assets/ui/<kind>_9slice.png is sliced into the surfaces below. A var, not a const, so a test
## can flip it (same pattern as Motion.force_reduced).
static var NINE_SLICE_ART_ENABLED: bool = false
## Per-kind content/expand inset when 9-slice art exists (see UIStyle.surface_box).
## Missing kinds fall back to 12; missing art falls back to StyleBoxFlat.
const NINE_SLICE_MARGINS := {"panel": 12, "button": 8, "chip": 6}

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
