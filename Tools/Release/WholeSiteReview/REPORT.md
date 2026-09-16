# Whole-site review — September 16, 2026

**Verdict: Blocked for release sign-off.** The visual structure is more consistent,
but remaining publication/draft behavior and text contrast need attention. This
review distinguishes measured behavior from source findings. It is not a claim
that public authentication, uploads or release distribution were tested.

## Priority order

| Before | After | Why |
| --- | --- | --- |
| **P0 — An existing draft's primary button says Save changes but calls save(false).** release-composer.tsx:477–479 sends draft:false at :213. Source-observed; no publication was performed. | Use Save draft and Publish release for drafts. On published releases, Save changes preserves publication; make Unpublish a separate explicit action. | A routine edit must not ambiguously change release visibility. |
| **P1 — Unsaved tester notes disappear after navigating to Dashboard and back.** Live synthetic check returned draftRetained:false. | Preserve a per-tab draft and warn on leaving with unacknowledged edits. Clear only the exact acknowledged draft or an explicit discard. | Protect work during normal navigation. The release editor also lacks persistence/guarding in source; its round-trip loss was not exercised. |
| **P1 — Small secondary text is too faint.** On Features, measured rgb(110,110,115) against rgb(16,16,18) is 3.75:1; the same color on admin cards #202023 is 3.20:1. Light faint text #86868b on #f5f5f7 is 3.33:1 and on white is 3.62:1. | Use the normal secondary-ink color for 12–14px labels, metadata and hints. Reserve faint color for decoration; verify both themes. | Normal text needs at least 4.5:1. Visual quietness should come from layout and hierarchy rather than illegibility. |
| **P1 — The homepage repeats the product story and media.** At 1440×900, Home is 6008px tall; its hero alone is 1340px. Features and How It Works reuse the same panel clip/setup scenes. | Show one decisive unlock demonstration on Home, concise feature summaries, and clear next steps. Put detailed setup material on How It Works and actual settings/control evidence on Features. | Page length should add information. Reduce repeated screenshot framing and empty space. |
| **P1 — Product captures are not yet good enough for large presentation.** Original setup exports were downsampled to 880px then enlarged; native glass button surfaces are absent in offscreen renders. | Restore lossless original pixels, avoid enlarged low-resolution sources, and show well-framed content details until faithful full-window captures are available. | Text and control quality matter more than adding another surface treatment. The owner's follow-up image-quality request was implemented separately; see ../PreviewImageQuality/REPORT.md. Genuine native Liquid Glass still needs a valid capture. |
| **P2 — Compatibility and build access are not clear early enough.** The hero sends people to Discord; exact platform requirements are not visible there. Website sign-in/tester access differs from the app's no-account claim. | Put verified requirements near the CTA; explain development/build availability and keep the app-versus-website account distinction visible at sign-in. | Visitors need to know whether Gaze works on their Mac and what happens after clicking. Do not invent supported chips/OS versions or promise access. |
| **P2 — Upload and media controls imply behavior they do not provide.** Clip descriptions are edited but serialized as URL strings only. Build upload progress appears in the media button. | Hide unsupported video descriptions until persisted end to end; show progress and errors in the card that started the upload. | Avoid lost input and feedback in the wrong place. Both are source findings requiring a synthetic upload/round-trip test before implementation sign-off. |
| **P2 — Mobile admin navigation conceals the active destination.** At 390px, People spans x=366.875…443.984: most of its label is offscreen. | Fit four shorter mobile labels in the available width while retaining 44px targets, or reliably reveal the selected item with an obvious scrolling affordance. | The current location should remain visible. Horizontal scrolling itself was not found broken. |
| **P2 — Some motion still feels like a swap rather than a connected transition.** Gallery selection/dialog appearance is immediate; walkthrough panels differ by about 59px in height at 390px. | Add a short, interruptible image crossfade and restrained dialog entrance; keep reduced motion instant. Stabilize the walkthrough's surrounding layout. | Invest motion in changes users trigger. Do not restore product hover tilt, scroll reveals or automatic carousels. |
| **P2 — Trust/support routes are incomplete.** The site says open source without a direct verified Gaze repository link; explanatory-page footers omit the Discord support exit. | Link the verified source when public, provide consistent support links, and state saved-password/shared-account implications before activation decisions. | Help readers inspect claims and resolve questions. Preserve honest security caveats. |

## Evidence and coverage

Root revisited Home, Features, How It Works, Security, Credits, Releases, release
detail, Sign-in, Dashboard, new-release editor, tester-note editor, People/Roles,
and tester access at the existing local server. The earlier viewport pass also
covered the edit-release route and 404. Current captures and DOM measurements are
under build/whole-site-review/. Private pages used only the synthetic preview
account and records; no credentials, uploads, Save or Publish actions were used.

Specific measurements: desktop-observations.json, interaction-observations.json,
and draft-navigation.json in build/whole-site-review. The 390px walkthrough panels
measured 550.73 / 578.36 / 609.72px; switching moved the next section by up to 58.98px.

Hank 4 reviewed admin code and recorded five findings in ADMIN.md. Walter 4 reviewed
visitor content/navigation and recorded six findings in VISITOR.md. Root checked
the source publication request, reproduced unsaved-note loss, measured text
contrast, page heights and mobile active-tab clipping, and combined priorities.

The review itself changed no website behavior. The later owner screenshot complaint
explicitly triggered the image-quality correction described in PreviewImageQuality.
The functional findings above remain open; do not report them as fixed.

## Later feedback addressed

The owner subsequently requested slower playback and a different gallery layout.
GalleryPacing/REPORT.md supersedes the original gallery-motion observation: the
thumbnail strip/padded frame are replaced by an editorial split, fixed dark stage
and text segments; pointer images crossfade over400ms. The hero plays at0.6x.
PreviewImageQuality/REPORT.md covers the repaired resolution and native-detail
crops. The publication/draft recovery, contrast and visitor-journey findings above
remain open. These targeted visual follow-ups are not a claim that the whole
review backlog has been implemented.
