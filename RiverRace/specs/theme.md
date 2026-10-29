# Theme

The app uses the aityx dark palette, from the aityx website
([theme.dart](../riverrace_app/lib/theme.dart)), the same as the other
aityx demos: the page is near-black with a violet tint (`#17161A`),
panels and cards step up through `#201E24` and `#2A272E`, text is light
gray (`#EFF2F4`), muted text `#A9ACB6`, and the primary color is the
orange accent (`#E36742`). App bars are flat and the page's color, with
the title bold and on the left. The web manifest's background and theme
color are `#17161A`.

The river is drawn in the Atari's colors
([race_painter.dart](../riverrace_app/lib/game/race_painter.dart)): blue
water (`#1C3FAA`), green banks (`#4E8F2A`), gray roads with yellow dashes,
brown bridges, red and white fuel depots, and a gray HUD band
(`#8E8E8E`). The player's plane is the original's yellow (`#E8E84A`),
solid; the aityx pilots' are cyan (`#5FE0F0`) and magenta (`#F070E0`), at
25% opacity.
