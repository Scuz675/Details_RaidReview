Details_RaidReview v0.4.3

Native RAID plugin for the Wrath 3.3.5 Details build supplied with Triumvirate.

INSTALL / UPDATE
1. Remove or disable the old TriRaidReview addon if it is still installed.
2. Replace your existing Details_RaidReview folder with this one.
3. /reload

RECOMMENDED DETAILS AUTOMATION
- All Roles (in combat): Tiny Threat
- Damager (out of combat): Raid Review
- Healer (out of combat): Raid Review
- Tank (out of combat): Raid Review
- After Wipe: Raid Review (optional)

ROW KEY
X = deaths
! = crowd-control breaks
I = interrupts
D = dispels
C = defensive cooldowns
R = resurrections
P = combat potions
H = health potion / healthstone usage

BARS + SORTING
The bars now carry a real metric instead of all being full-width.

Default: Review Priority
1. Deaths
2. CC breaks
3. Damage Taken
4. Useful raid activity

Options also provide:
- Damage Taken: exact incoming-damage ranking; bar length = damage taken
- Deaths: death ranking; bar length = death count
- Raid Actions: interrupts + dispels + defensives + resurrections + consumables

T# on each row shows Damage Taken. Damage is context, not an automatic judgement: tanks are naturally expected to rank highly.

In Review Priority mode, bar length is an attention indicator combining deaths, CC breaks and damage taken. The individual X/!/T values remain visible so the reason for a high bar is never hidden.

TOOLTIP
Hover a player for:
- review flags and raid-action totals
- damage taken context
- interrupt / dispel / defensive / resurrection / CC-break spell breakdowns
- spells interrupted and auras dispelled
- combat potions and health consumables
- a death recap showing the final damaging hits before each death

OPTIONS
Use Details > Plugins > Raid Review > Options, or /rrp options.
Options include whole-roster display, X0 visibility, class colours, death/CC highlighting, death recap depth and tooltip spell-row limits.

COMMANDS
/rrp status
/rrp show
/rrp options
/rrp refresh
/rrp install

CHANGES IN v0.3.0
- Added proper plugin options panel.
- Added R (resurrection) and H (health consumable) row markers.
- Changed sorting to flags first, then combined useful raid activity instead of lexicographic metric ranking.
- Added configurable red death and orange CC-break highlighting.
- Added last-hit death recap based on Details' own death-event data.
- Added optional filtering of completely inactive rows.
- Kept Damage Taken as context only, never a ranking penalty.


CHANGES IN v0.3.2
- Fixed player mouseover tooltips on the older 3.3.5 DetailsFramework.
- Uses direct row mouse scripts instead of the framework SetHook wrapper.
- Uses Blizzard GameTooltip instead of GameCooltip for maximum client compatibility.
- Keeps the detailed interrupt, dispel, defensive, consumable and death-recap breakdown.


v0.3.2: Hover reliability pass. Each row now has a dedicated high-level invisible Button hitbox above the Details bar; tooltip generation is protected and reports any tooltip-side error instead of failing silently. Added /rrp debug.


SCROLLING
- Mouse-wheel over the Raid Review list to move through players that do not fit in the window.
- Scrolls 3 rows per wheel notch.
- A slim indicator appears on the right edge when more rows are available.


CHANGES IN v0.4.3
-----------------
- Added a Performance section to each player tooltip.
- Shows Damage Done and DPS.
- Shows Healing Done and HPS.
- Shows Overheal as both an amount and percentage of attempted healing.
- DPS/HPS prefer Details' own cached values so they match the normal meters,
  with a safe actor-time fallback if the cache has not refreshed yet.
- Visible rows remain deliberately clean: player name on the left, deaths on
  the right, class colour and bar length for at-a-glance distinction.

CHANGES IN v0.4.2
- Bars now have meaningful relative lengths.
- Damage Taken is shown as T# on each row by default.
- Added Review Priority, Damage Taken, Deaths and Raid Actions sort modes.
- Added mouse-wheel scrolling for full raid rosters.
- Added a slim visual scroll position indicator.


v0.4.2
- Simplified visible rows to player name on the left and death count (X#) on the right.
- Damage taken, interrupts, dispels, defensives, resurrections and consumables remain available in the mouseover tooltip.
- Bar metric, sorting modes and mouse-wheel scrolling are unchanged from v0.4.0.


v0.4.2
- Bars now always use WoW class colours for player distinction.
- Deaths remain visible as X# on the right; death/CC colour overrides were removed.
- Bar length and sorting continue to represent the selected review metric.
