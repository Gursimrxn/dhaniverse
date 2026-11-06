extends Node
## Dhaniverse brand palette: "fresh river daylight".
## Recognisable through: deep lush greens, clear teal water, slate roofs,
## grey river stone, honey timber, and coin-gold reserved for money moments.
## Every shader/UI colour should come from here so the look stays consistent.

# The brand's own colours and fonts, for the game's UI (DESIGN.md)
const BLUE := Color("0011FF")           # the coin
const ORANGE := Color("FF6600")         # a moment that needs attention
const PLATE := Color("262727")          # dark plates
const CREAM := Color("FFF8E3")          # plate outlines, text on plates and on the scene
const GREEN := Color("337E43")          # a price that fell
const MAGENTA := Color("E100FF")
const CREAM_MUTED := Color("E4DCC0")   # small print on plates
const FONT_BODY := preload("res://assets/fonts/Satoshi-Bold.otf")       # words and money
const FONT_DISPLAY := preload("res://assets/fonts/Bitroad-Regular.otf") # keycaps, labels, big moments
const FONT_NUMBER := preload("res://assets/fonts/BitroadMono-RegularMono.otf")  # the HUD's numbers, as on the design boards
const FONT_EDITORIAL := preload("res://assets/fonts/InstrumentSerif-Regular.ttf")  # printed headlines
const FONT_EDITORIAL_ITALIC := preload("res://assets/fonts/InstrumentSerif-Italic.ttf")
const FONT_PROSE := preload("res://assets/fonts/Newsreader-Light.ttf")  # printed prose
const MINT := Color("BDEDD0")           # money gained, on plates and the scene

## The boards' .plate at the game's scale: its cream ring sits outside the box (box-shadow 0 0 0 .3rem), so the content margins
## and positions are the board's own; then the drop shadow, 0 1rem 2.4rem rgba(0,0,0,.28).
static func as_plate(s: StyleBoxFlat) -> StyleBoxFlat:
	s.set_expand_margin_all(s.border_width_top)
	s.shadow_color = Color(0, 0, 0, 0.28)
	s.shadow_size = 11
	s.shadow_offset = Vector2(0, 9)
	return s

# Sky and light
const SKY_TOP := Color("4f8fd1")        # clear blue
const SKY_MID := Color("8cc0e8")
const SKY_HORIZON := Color("e3f1f4")    # pale, slightly warm
const SUN := Color("fff2dc")            # warm white
const SHADOW := Color("4a6a8c")         # cool blue shade
const FOG := Color("d7e9ee")

# Signature accents
const GOLD := Color("f2b632")           # dhani gold: money, rewards
const TEAL := Color("0f8f88")           # brand primary: water, the bank, UI
const AQUA := Color("5fd0c3")           # shallow water, positive feedback
const CORAL := Color("ef6f5e")          # warnings, costs
const INK := Color("1d3341")            # UI text: deep slate-teal
const SNOW := Color("fbfdfc")           # UI surfaces

# Greens: lush and saturated, cool in shade, sunlit chartreuse highlights
const LEAF_LIGHT := Color("b9df63")
const LEAF_MID := Color("5fa547")
const LEAF_DEEP := Color("2f6a3c")
const LEAF_SHADE := Color("1f4a3f")
const PINE_MID := Color("2f6f4e")
const BLOSSOM := Color("f4a6bd")
const BARK := Color("5b4033")

# Ground
const GRASS_ROOT := Color("2f6b36")
const GRASS_TIP := Color("a9d65a")
const PATH := Color("c9c6bd")           # grey river-stone setts
const PATH_DARK := Color("8f8b84")
const SOIL := Color("7a5a44")
const STONE := Color("a3a7a6")
const TIMBER := Color("a26a3f")
const SLATE := Color("3b4350")          # roofs

# Per-building wall colours (no cream): natural, distinct at a glance
const WALLS := {
	"dv01": Color("b7c4a6"),   # arrival hall: sage stone
	"dv02": Color("2f8079"),   # bank: deep teal, the money building
	"dv03": Color("9a6a46"),   # market: warm timber
	"dv04": Color("b65e4c"),   # common table: brick red
	"dv05": Color("8ea8c6"),   # housing: dusty blue
	"shelter": Color("9a6a46"),
}

# legacy names still used by HUD/props
const PLUM := INK
const CREAM_INK := SNOW
const JADE := TEAL
