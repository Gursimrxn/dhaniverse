---
version: alpha
name: Dhaniverse
description: A playful finance-learning world for people who'd rather learn by playing than by reading. Warm, funny about mistakes, never about the player.
colors:
  primary: "#262727"        # ink: body text, footer text. Seen in landing.json.
  secondary: "#5C5642"      # muted text, captions. Seen in landing.json.
  tertiary: "#337E43"       # green: site default accent (wordmark, nav, LinkedIn cover). TODO confirm it is the default.
  neutral: "#FFF8E3"        # cream: page ground, light text on dark and on green.
  surface: "#FFFFFF"        # cards and inputs.
  paper: "#FAFAF8"          # logo tiles, section ground.
  soft: "#F4F4F2"           # inner panels.
  on-tertiary: "#FFFFFF"    # text on green. 5.0:1.
  colorway-blue: "#0011FF"       # logo + Twitter cover 2. Text on it: white (8.3:1).
  colorway-magenta: "#E100FF"    # logo + Twitter cover 3. Text on it: black (5.6:1). White fails (3.7:1).
  colorway-orange: "#FF6600"     # logo + Twitter cover 4. Text on it: black (7.2:1). White fails (2.9:1).
  colorway-black: "#000000"      # logo + Twitter cover 5. Text on it: white.
  # In the Figma file with no stated job. TODO: confirm official or drop.
  mint: "#BDEDD0"
  lavender: "#BEB2FF"
  gold: "#F0C33A"
  gold-light: "#F8D877"
  leaf: "#55C06C"
typography:
  headline-hero:
    fontFamily: Satoshi
    fontSize: 68px
    fontWeight: 700
    lineHeight: 1
    letterSpacing: -0.03em
  headline-lg:
    fontFamily: Satoshi
    fontSize: 48px
    fontWeight: 500
    lineHeight: 1.1
    letterSpacing: -0.025em
  headline-md:
    fontFamily: Satoshi
    fontSize: 40px
    fontWeight: 500
    lineHeight: 1.1
  body-md:
    fontFamily: Satoshi
    fontSize: 16px
    fontWeight: 400
    lineHeight: 1.5
  body-lead:
    fontFamily: Satoshi
    fontSize: 20px
    fontWeight: 300
    lineHeight: 1.5
  quote:
    fontFamily: PP Editorial New   # web substitute: Instrument Serif (bundled)
    fontSize: 32px
    fontWeight: 400
    lineHeight: 1.1
  accent-italic:
    fontFamily: PP Editorial New
    fontSize: 36px
    fontStyle: italic
  button:
    fontFamily: PP Editorial New
    fontSize: 16px
    fontWeight: 400
  ui-label:
    fontFamily: PP Mondwest   # web and game substitute: Bitroad (bundled)
    fontSize: 16px
rounded:
  xs: 4px
  sm: 8px
  md: 10px
  lg: 20px
  xl: 40px        # most common card radius on the 1728px Home frame (50 uses)
  full: 1000px    # pills and circles
spacing:
  TODO: "Not extractable from the export. Auto-layout padding exists per frame. Needs a written scale."
components:
  page:
    backgroundColor: "{colors.neutral}"
    textColor: "{colors.primary}"
    typography: "{typography.body-md}"
  button-primary:
    backgroundColor: "{colors.tertiary}"
    textColor: "{colors.neutral}"
    typography: "{typography.button}"
    rounded: "{rounded.full}"
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.primary}"
    rounded: "{rounded.xl}"
  caption:
    backgroundColor: "{colors.neutral}"
    textColor: "{colors.secondary}"
    typography: "{typography.body-md}"
---
# Dhaniverse

Built from `figma/landing.json`, the SVG exports, `apps/web/public/font`, `apps/web/public/brand-mark.svg` and the brand sheet. Anything not found in those is marked TODO. Never invent a value.

## Overview
Dhaniverse teaches money by letting people live it: earn, spend, save, invest, mess up, recover. The page is airy and cream-warm, with large rounded cards, light shadows and pastel gradients. The copy is casual and self-aware ("bankruptcy isn't a personality trait here"). Illustration mixes painted landscapes, pixel-art scenes, soft 3D characters and an anime-style bot. Closest feel to name: TODO, none stated in the sources.

## Colors
- **Green (#337E43):** site default accent: wordmark, nav, headings accents, LinkedIn cover. TODO: confirm it is the default and the others are campaign colourways.
- **Blue #0011FF, Magenta #E100FF, Orange #FF6600, Black #000000:** the other four colourways of the logo and the social covers. Text on them follows the contrast notes in the YAML.
- **Cream (#FFF8E3):** the page and the text on dark fills. **Paper (#FAFAF8):** logo tiles, section ground. **Ink (#262727):** body text.
- TODO: names for the five colours, and the gradient stops of the gradient mark.
- The game follows the five colours. The Godot game's `game/scripts/autoload/brand.gd` still holds an older "fresh river daylight" palette (teal #0F8F88, gold #F2B632, coral #EF6F5E, ink #1D3341). Both the web pages and the HUD work from that palette.

## Typography
Satoshi (Fontshare, free for commercial use) for headings and body: 68 Bold hero, 40 to 48 Medium section titles, 16 to 24 Regular and Light for body. PP Editorial New for quotes (32), italic accents (36) and buttons (16). It is licensed, so the web uses Instrument Serif. PP Mondwest for product-UI labels at about 16, with Bitroad as the bundled stand-in. Newsreader and Comic Relief are in `public/font`: TODO, unclear if used.

## Layout
The Home frame is 1728px wide (mobile 402px). TODO: grid, maximum content width and the spacing scale.

## Elevation & Depth
Soft drop shadows: 0 4px, 13 to 40px blur, 10 to 25% black. Foreground and background blurs (53 to 227px) for glass panels. No hard borders or offset shadows in the sources.

## Shapes
Cards 40px (also 20, 10, 8, 4 in smaller parts). Buttons and chips are pills (1000px).

## Components
- **Buttons:** cream text on green, pill, PP Editorial New 16. Plain verbs: "Play Now", "Invite People".
- **Cards:** white or pastel gradient, 40px corners.
- TODO: inputs, focus ring, error state.

## Do's and Don'ts
- Do keep text contrast at 4.5:1 or better. Black text on magenta and orange, white on blue, green and black.
- Do use the real logo files. Never redraw the mark.
- Do set every amount of money in the pixel face (Bitroad / Mondwest). This is a proposal, not yet a rule in the sources.
- TODO: Don'ts. No misuse page exists in the sources.

## Iconography
TODO: no icon set is named in the sources. The mark is `apps/web/public/brand-mark.svg` (solid silhouette). The ring and gradient versions exist on the brand sheet only. TODO: export them as SVG, plus clear space and minimum size.

## Voice
Three words: casual, self-aware, kind. Real lines: "It's basically real life… except bankruptcy isn't a personality trait here." "well… every main character needs a training arc, this one just happens to be about money." The jokes target situations, never the player. Button labels stay plain. TODO: five words to never use.
