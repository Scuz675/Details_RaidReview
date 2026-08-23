Details_RaidReview v0.3.2

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

SORTING
1. Deaths
2. CC breaks
3. Total useful raid actions (interrupts + dispels + defensives + resurrections + consumables)
4. Interrupts / dispels / defensives as tie-breakers
5. Name

Damage taken is deliberately NOT used for ranking because tanks are expected to take more damage.

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
