# Theme

The app uses the aityx dark palette, taken from the aityx website
([theme.dart](../mortgagehub_app/lib/theme.dart); every color is listed in
[theme-colors.txt](theme-colors.txt)): the page is a near-black with a violet
tint (`#17161A`), panels and cards step up through `bg1` (`#201E24`) and
`bg2` (`#2A272E`), outlines are `#37333C`, text is `#EFF2F4` with muted text
`#A9ACB6`, and the primary color is the aityx orange (`#E36742`).

Verdicts and check results use their own colors so they don't read as the
accent: green (secondary) for processable and pass, amber (tertiary) for
needs review, and red (error) for not processable and fail.

App bars are flat and the page's color, with the title bold and on the left.
