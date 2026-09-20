# Credits portraits audit — `Resources/Credits`

Nine files on disk, matching the nine rows in the `credit-portraits` entry of
`Tools/Release/ModelClearance/clearance.json` (lines 317–389, `clearance:
"unresolved"`). Every file below was viewed as a rendered image; descriptions
are from the pixels, not the filenames. All nine arrived in one bulk commit,
`ad7aa83` (2026-09-09, "The setup flow, notch panel and recognition work"),
whose message names "the credits and art assets" with no per-file detail, so
history says nothing about where any single image came from. No permission for
any portrait or icon is recorded anywhere in the repository: the clearance
entry's provenance status is `third-party-unrecorded` and its licence status is
`unresolved` ("No recorded grant covering redistribution of these
portraits/icons in the app bundle"). The Shariq permission record
(`Tools/Release/ModelClearance/SHARIQ-PERMISSION-20260918.md`) covers use of
the Sapphire ArcFace model only and explicitly "does not … grant rights to
unrelated models and assets", so it does not cover `cshariq.png` or
`app-sapphire.png`. Recorded hashes in `clearance.json` match the files on
disk today (verified 2026-09-20).

## Summary

| File | What it depicts | Recommendation |
|---|---|---|
| `cshariq.png` | Photograph of an identifiable man with glasses | Keep and obtain permission — subject is a reachable collaborator |
| `danfq.png` | Photograph of an identifiable young man with sunglasses | Keep and obtain permission — subject is a reachable collaborator |
| `nautey.png` | Stylised "Vequency" text over clouds; not a portrait of a person | Needs owner input — content does not match the credited person |
| `unxnown.png` | Minimal "UX" monogram on black; not a photograph | Keep and obtain permission — presumably the subject's own avatar, one ask |
| `vanilla.png` | Cartoon fox-like animal; not a photograph | Keep and obtain permission — presumably the subject's own avatar, one ask |
| `app-sapphire.png` | Sapphire app icon (blue cube) | Keep and obtain permission — ask cshariq together with the portrait |
| `app-dynamiclake.png` | DynamicLake app icon (purple gradient squircle) | Keep and obtain permission — via Aviorrok's site-listed contacts |
| `app-wallx.png` | WallX app icon (droplet outline) | Keep and obtain permission — ask Unxnown together with the avatar |
| `app-atoll.png` | Atoll app icon (gold ring on teal) | Keep and obtain permission — ask DanFQ together with the portrait |

## `cshariq.png` — 32,651 bytes, 128×128, SHA-256 `08164933…91bb04`

A colour photograph of an identifiable adult man with dark hair and glasses,
wearing a grey buttoned shirt, arms crossed, indoors against shelving and
pendant lights. The face is fully identifiable.

Attribution in `Sources/App/SettingsView.swift`: row name `"cshariq"`
(1571) with detail `"The recognition model this app matches faces with is
theirs"` (1572) and link `"https://github.com/cshariq"` (1574); sub-row
`"Sapphire" — "The notch, reimagined."`, href `"https://sapphire-app.tech/"`
(1575–1577).

Provenance: bulk commit `ad7aa83` only. The site credits list
(`Tools/Release/SecondaryPages/files/src/lib/credits.ts:24-33`) confirms the
identity ("cshariq", github `cshariq`, contribution "Gaze's recognition model
was sourced through Sapphire") and names `rightsHolder: "cshariq"` for the
site's Sapphire icon — a rights label on the website asset, not a permission
grant for this bundled file.

Recommendation: `keep and obtain permission` — identifiable photo (highest-risk
category), but the subject is an active, reachable collaborator already linked
in the app.

## `danfq.png` — 32,039 bytes, 128×128, SHA-256 `5e266a7d…d51d9251`

A colour photograph of an identifiable young man with curly dark hair wearing
sunglasses and a pale yellow shirt, outdoors. The face is identifiable
(sunglasses cover the eyes only).

Attribution in `Sources/App/SettingsView.swift`: row name `"DanFQ"` (1616)
with detail `"Ideas for the app, and a great deal of feedback on it"` (1617)
and link `"https://github.com/danfq"` (1619); sub-row `"Atoll"` with no
description, href `"https://getatoll.app"` (1620–1622).

Provenance: bulk commit `ad7aa83` only. The site credits list
(`credits.ts:47-52`) confirms the identity (github `danfq`, "App ideas and
thoughtful feedback throughout development"). No portrait permission recorded.

Recommendation: `keep and obtain permission` — identifiable photo, but the
subject is reachable through the GitHub link already shown in the app.

## `nautey.png` — 37,112 bytes, 128×127, SHA-256 `9b23cd7e…ff4028c4`

Not a portrait at all: stylised 3D-blue text reading "Vequency" over a cloudy,
lightning-lit blue background. No person is depicted, so there is no likeness
issue — but the content does not match the credited individual either, and the
word suggests artwork made for or by someone/something else.

Attribution in `Sources/App/SettingsView.swift`: row name `"nautey"` (1626)
with detail `"Moderates the Discord, and finds what's broken before anyone
else"` (1630); no link and no app sub-row (1631–1633). The in-code comment
(1563–1564) notes nautey is one of three credited people with no link.

Provenance: bulk commit `ad7aa83` only. The site credits list
(`credits.ts:65-69`) gives nautey's contribution as "Community moderation and
early testing on macOS beta releases" with icon `/credits/nautey.png` — the
same unexplained image, no source note.

Recommendation: `needs owner input` — establish what this image is and where
it came from before deciding; if it is third-party artwork unrelated to
nautey, removal is likely correct, and if it is nautey's own banner, confirm
that with them.

## `unxnown.png` — 3,743 bytes, 128×128, SHA-256 `642b6c1b…f4ebdf8f`

A minimal monogram: thin white letters "UX" on a solid black square. Not a
photograph; no person depicted. Reads as a personal avatar/logo rather than a
likeness.

Attribution in `Sources/App/SettingsView.swift`: row name `"Unxnown"` (1599)
with detail `"Set up the Discord, where every early build lands"` (1600) and
link `"https://github.com/UnxnownYT"` (1602); sub-row `"WallX"` with no
description, href `"https://github.com/UnxnownYT/WallX"` (1603–1605).

Provenance: bulk commit `ad7aa83` only. Corroborating identity evidence:
`Sources/App/GazeApp.swift:250-251` documents that "unxnown reported the Dock
icon appearing…" — an early tester, consistent with the Discord credit. No
avatar permission recorded.

Recommendation: `keep and obtain permission` — almost certainly the subject's
own avatar and one quick ask away via the linked GitHub account; negligible
likeness risk regardless.

## `vanilla.png` — 27,704 bytes, 128×127, SHA-256 `d55d14ed…7d62e072`

A cartoon illustration of a fox-like animal with a waving paw, peeking over a
grassy edge, on white. Not a photograph; no person depicted. Reads as a
personal avatar rather than a likeness.

Attribution in `Sources/App/SettingsView.swift`: row name `"Vanilla"` (1591)
with detail `"Built the anti-spoofing pipeline"` (1592) and link
`"https://github.com/howjin"` (1594); no app sub-row.

Provenance: bulk commit `ad7aa83` only. The site credits list
(`credits.ts:70-76`) confirms the identity (github `howjin`, "Helped develop
anti-spoofing research…"). No avatar permission recorded.

Recommendation: `keep and obtain permission` — presumably the subject's own
avatar, one ask via the linked account; no likeness risk regardless.

## `app-sapphire.png` — 16,628 bytes, 128×128, SHA-256 `353fa0f6…6eef9fd`

An app icon: a light-blue 3D cube/box on a dark background, rounded square.
Used as the Sapphire sub-row icon under cshariq
(`Sources/App/SettingsView.swift:1575-1577`, icon `"app-sapphire"`, href
`"https://sapphire-app.tech/"`, described as `"The notch, reimagined."`).
I recognise this as the Sapphire app's icon, consistent with the in-app label
and link.

Provenance: bulk commit `ad7aa83` only. No icon permission recorded; the
Shariq model permission does not extend to it (see header).

Recommendation: `keep and obtain permission` — ask cshariq in the same message
as the portrait; the two files share one rights holder.

## `app-dynamiclake.png` — 23,370 bytes, 126×128, SHA-256 `a7bf6a5b…ad279527`

An app icon: a purple-gradient rounded square with a thin light border and a
glow at the bottom edge. Used as the DynamicLake sub-row icon under Aviorrok
(`Sources/App/SettingsView.swift:1585-1587`, icon `"app-dynamiclake"`, href
`"https://dynamiclake.com"`, described as `"Dynamic Island for Mac."`). I
believe this is the DynamicLake app's icon, consistent with the label and
link, but I am unsure beyond that match.

Provenance: bulk commit `ad7aa83` only. The site credits list
(`credits.ts:35-46`) confirms Aviorrok/DynamicLake and names
`rightsHolder: "Aviorrok"` for the site icon — again a website-asset label,
not a grant for this file. Note: Aviorrok has no portrait file in
`Resources/Credits` (the row at 1580–1587 looks up `"aviorrok"`, finds
nothing, and renders the glyph fallback), so this icon is the only Aviorrok
asset in the bundle, and the app shows no direct link for the person — only
the site lists contacts (Discord invite, x.com/AVIROK1).

Recommendation: `keep and obtain permission` — via Aviorrok's site-listed
contacts; if unreachable, this is the cheapest icon to drop since its row
already renders without any portrait.

## `app-wallx.png` — 20,389 bytes, 128×128, SHA-256 `34ad906e…15898f`

An app icon: a dark droplet outline over a teal-to-green gradient, rounded
square. Used as the WallX sub-row icon under Unxnown
(`Sources/App/SettingsView.swift:1603-1605`, icon `"app-wallx"`, href
`"https://github.com/UnxnownYT/WallX"`, no description). I am unsure whether
this is WallX's actual icon beyond the in-app label; the droplet motif is
consistent with a wallpaper app.

Provenance: bulk commit `ad7aa83` only. No icon permission recorded.

Recommendation: `keep and obtain permission` — ask Unxnown in the same message
as the avatar; one rights holder for both files.

## `app-atoll.png` — 17,171 bytes, 128×128, SHA-256 `7c46d160…89e7354b`

An app icon: an irregular gold/tan ring (atoll-like) on a dark teal rounded
square. Used as the Atoll sub-row icon under DanFQ
(`Sources/App/SettingsView.swift:1620-1622`, icon `"app-atoll"`, href
`"https://getatoll.app"`, no description). I believe this is the Atoll app's
icon, consistent with the label and link, but I am unsure beyond that match.

Provenance: bulk commit `ad7aa83` only. No icon permission recorded.

Recommendation: `keep and obtain permission` — ask DanFQ in the same message
as the portrait; one rights holder for both files.

## Removal cost

Cheap. `creditPortrait(_:)` (`Sources/App/SettingsView.swift:1264-1270`)
returns `nil` for a missing file by design — "Nil is a normal answer, not a
failure" (1261) — and `SettingRow` then renders its SF Symbol glyph tile
instead (`Sources/App/Theme.swift:702-715`); the app sub-row icon is likewise
optional (`if let icon = creditPortrait(app.icon)`, `SettingsView.swift:1313`)
and the sub-row text renders without it. The six credit rows are independent
with no fixed-count layout, so deleting any file (or any subset) leaves every
row's name, detail text, and links intact; only the 26pt portrait reverts to
the glyph and the 20pt app icon vanishes. This is already proven in
production: the Aviorrok row ships today with no `aviorrok.png` on disk and
renders its `macbook` glyph. No code change is needed to remove files — but
the clearance validator hash-binds the directory, so each deletion must be
paired with removing its row in `clearance.json` (someone else's edit;
flagged, not done here). Net: four permission asks cover eight of the nine
files (cshariq, DanFQ, Unxnown, Aviorrok), with `nautey.png` the one file
needing an ownership answer first.
