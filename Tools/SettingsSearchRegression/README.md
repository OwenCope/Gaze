# SettingsSearchRegression

Contract checks for the Settings search index (`Sources/App/SettingsSearch.swift`).

`run.sh` compiles the real index file together with `SettingsSearchTests.swift`
— Foundation only, no SwiftUI, no app state — and runs the result. It covers
case/diacritic/whitespace folding, multi-token AND matching, stable declared
ordering, the required topic matches (password, camera, walk-away, theme, …),
blank/unknown queries returning nothing, and unique ids with valid pane and
section destinations. Matching uses plain substring checks; there are no regex
assertions and nothing here is a UI test.

The SwiftUI side (search field, results list, pane switch, scroll-to-section in
`Sources/App/SettingsView.swift`) is verified by type-checking the full
main-app sources with the `build.sh` source selection. Native focus and scroll
behaviour are not visually observed here.
