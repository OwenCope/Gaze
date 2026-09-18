# Gaze Tour Handoff — Use TourKit and That Only

For the next agent: the welcome tour must be base TourKit and nothing else.

## Requirement

- Use TourKit: https://github.com/rampatra/TourKit
- No custom TabView paging, no local `TourPage` struct, no custom dots, no custom Back/Next/Skip buttons, no `tourPageView` helper, no `pageMedia` hacks, no `windowContent` forks.
- `GazeWelcomeTour` renders one `TourSlideshowView` with upstream args only: `pages`, `width`, `initialPageIndex`, `continueButtonTitle: "Next"`, `finishButtonTitle: "Start setup"`, `onFinish`, `onClose`.
- Exactly 5 `TourPage`s with upstream init (`imageName` + `imageBundle` + `title` + `description`):
  1. Meet Gaze — Art/tour-recognition.png
  2. Stays on your Mac — Art/tour-privacy.png
  3. How unlock works — Art/how-unlock.png
  4. A quick movement check — Art/tour-practice.png
  5. Unlocking stays your choice — Art/how-keychain.png (ends with "Automatic unlocking stays off unless you turn it on.")
- Dismiss relies on TourKit built-in close control only. No second Skip overlay.
- Vendored TourKit at `ThirdParty/TourKit/TourKit.swift` is upstream base (660 width, 16:10 art, card radius 20). Do not re-fork it.

## Current bug (see screenshot)

- Double "Skip": one at top-right of window chrome + one inside TourKit card.
- Extra "Gaze" title header + "Step 1 of 1" footer from `SetupFlow` wrapping the tour. The tour should fill the step with no outer scaffold.
- Fix in `Sources/Setup/SetupFlow.swift` (.welcome case) and `Sources/Setup/SetupWelcomeStep.swift` (thin host), not in TourKit.

## Key files

- `Sources/Setup/GazeWelcomeTour.swift` — pure TourKit caller (already clean)
- `Sources/Setup/SetupWelcomeStep.swift` — thin host around GazeWelcomeTour
- `Sources/Setup/SetupFlow.swift` — .welcome hosts SetupWelcomeStep, window 720x560
- `ThirdParty/TourKit/TourKit.swift` — upstream base, do not modify
- `Tools/Release/ShipPass20260918/check-tour.py` — expects 5 pages + Start setup

## What else was done this session

- Settings copy/layout pass: `Sources/App/SettingsView.swift`, `NotchSettings.swift`, `GazeSettingsPicker.swift`
- Onboarding back-button + permission copy: `Sources/Setup/SetupPlan.swift`, `SetupFlow.swift`, `SetupPermissionStep.swift`, `SetupPasswordStep.swift`, `SetupCaptureStep.swift`, `GazeWelcomeTour.swift`
- Lock screen: `Sources/LockScreen/NotchCapsule.swift` teardownDelay 0.12→0.16, `GazeFaceMark.swift` spoof label → "Photo rejected"
- Enrollment/companion: `Sources/Enrollment/EnrollmentModel.swift`, `EnrollmentRing.swift`, `Sources/Companion/GazeCompanionMotion.swift`, `GazeCuriosityMotion.swift`
- Passwords/autofill UX: `Tools/GazePasswords/Live/BrowserLoginChoices.swift`, `BrowserSaveProposal.swift`, `Views/VaultView.swift`, `LoginDetailView.swift`
- Website (gaze-site): homepage/nav, features/how-it-works/security/credits, releases/admin/testers, layout/modal/sign-in polish
- Tour arc: 9 pages → 5, window unified 720x560, TourKit restored to upstream after a bad custom rewrite
