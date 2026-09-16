# Admin workflow review

**Verdict: Blocked.** An existing draft's primary save action requests publication, and the editor offers clip descriptions that it does not save. These interaction problems take priority over the smaller feedback and navigation issues below.

Scope: read-only review of `src/app/admin/page.tsx`, `src/components/release-composer.tsx`, `src/components/readme-editor.tsx`, `src/components/testers-manager.tsx`, `src/components/roles-manager.tsx`, and `src/components/site-nav.tsx` in `/Users/owencope/Developer/gaze-site`. Existing screenshots in `build/website-whole-site/screenshots` supplied visual context. Their account, people, notes, and release content are synthetic fixtures, not evidence about production data. No source changes, builds, requests, or live interactions were performed.

## 1. “Save changes” publishes an existing draft

- **Impact:** High; publication intent is unclear at the point of submission.
- **Observed:** Code-observed. `src/components/release-composer.tsx:477` calls `save(false)` for the primary action. Its label at line 479 becomes `Save changes` whenever `initial` exists, including when `initial.draft` is true. The payload at line 213 sends that `draft` value. The adjacent `Save as draft` at line 470 likewise requests draft status even when editing an already published release.
- **Consequence:** Someone opening a draft to make a small correction can reasonably read “Save changes” as preserving its draft status, while the request explicitly asks to publish it. On a published release, the secondary action changes visibility without calling that consequence out directly.
- **Proposed improvement:** Derive action labels from the existing publication state: new/draft releases get `Save draft` and `Publish release`; published releases get `Save changes` and a separate, explicitly labeled `Unpublish to draft` action with a confirmation explaining that it removes the release from readers' view. Show the resulting audience beside Publish, including the testers-only state.
- **Runtime verification needed:** Yes. Open a synthetic draft and inspect the request/result when using each action; then repeat with a published synthetic release. The mislabeled `draft: false` request is established by source; actual publication was not exercised in this review.

## 2. Long edits have no recovery when the user follows admin navigation

- **Impact:** High for authors writing notes or assembling a release; work can be lost in one ordinary navigation action.
- **Observed:** Code-observed, with screenshot context. Release fields live only in component state at `src/components/release-composer.tsx:68`; tester notes live only in component state at `src/components/readme-editor.tsx:31`. Neither component installs draft persistence or a dirty-state navigation guard. `src/components/site-nav.tsx:43` renders normal links to other admin pages. `admin-new-390.png` and `admin-readme-390.png` show long editors with the navigation continuously available and save controls far below the first viewport.
- **Consequence:** After writing unsaved text, following Dashboard, People, or the website link can unmount the editor; returning starts from server-provided content rather than the local edits. The existing README conflict recovery protects against a conflicting save, but does not cover leaving the page.
- **Proposed improvement:** Track whether the current content differs from the last acknowledged save, retain an unsaved draft for the current browser tab, and show an explicit leave-with-unsaved-changes warning. Restore the draft on return and clear it only after the exact draft is confirmed saved or deliberately discarded. Include release fields and completed attachment references, not just Markdown text.
- **Runtime verification needed:** Yes. Type a distinctive unsaved sentence, navigate with the fixed admin links and browser Back, and revisit each editor. Test both the current loss/recovery behavior and the proposed guard without publishing anything.

## 3. Clip-description fields accept text that the save payload discards

- **Impact:** Medium; editing appears successful while entered accessibility information is lost.
- **Observed:** Code-observed. At `src/components/release-composer.tsx:423`, every media item gets an editable description input, with the accessible label `Clip description` for video at line 424. The change handler at line 430 writes the description into `m.alt`. However, line 208 serializes videos with `.map((m) => m.src)`, and line 84 initializes existing videos with an empty `alt`.
- **Consequence:** An author can spend time describing a clip, save successfully, and see that description disappear on reopening. The interface also implies that the description reaches viewers or assistive technology when this component does not persist it.
- **Proposed improvement:** Until video descriptions are supported end to end, render the editable description field only for images. For clips, show a non-editable filename/type label. Restore clip-description editing only together with a stored video description and corresponding accessible output on the reader page.
- **Runtime verification needed:** Yes, to demonstrate the complete round trip with a synthetic clip. The omission from serialization and reinitialization is directly established by source.

## 4. Build uploads report progress in the pictures section

- **Impact:** Medium; the page attributes an operation to the wrong control and makes slow uploads hard to follow.
- **Observed:** Code-observed. `src/components/release-composer.tsx:136` sets the shared `busy` state to `upload` for a build attachment. The build control at line 374 keeps the static label `Attach build` or `Replace build`. Only the pictures/clips `Add files` control at line 405 consumes that shared upload progress and becomes `Uploading …`. Upload errors are rendered separately in the save panel at line 453. `admin-new-390.png` confirms these are separate vertically stacked cards on a narrow screen.
- **Consequence:** After choosing a build, the control the author used becomes disabled without its own progress feedback; a different section claims to be uploading. On mobile, that section or the eventual error can be outside the visible area.
- **Proposed improvement:** Track upload target (`build` or `media`) and show filename, percentage, and errors in the corresponding card, using a local status announcement. During build upload, label the build control `Uploading build…`; leave the media control labeled `Add files` while it is temporarily disabled. Keep save availability tied to the shared in-flight guard.
- **Runtime verification needed:** Yes. Use a throttled synthetic build upload and a failed upload to verify progress location, screen-reader announcement, and error visibility. No upload was started during this review.

## 5. The active People tab is almost entirely offscreen on mobile

- **Impact:** Lower; navigation remains available by horizontal scrolling, but the current location and a main admin destination are concealed.
- **Observed:** Screenshot-observed and code-observed. In `admin-testers-390.png`, the People page is open, but only the left edge of its active navigation pill appears at the right boundary. Other 390px admin screenshots likewise clip this fourth destination. `src/components/site-nav.tsx:37` uses a horizontally scrolling navigation row; line 47 makes every link nonshrinking with `px-4`, and there is no selected-tab scroll handling in the component.
- **Consequence:** A phone user cannot read the active People label without discovering and scrolling the navigation strip. Opening that page does not bring its location indicator into view.
- **Proposed improvement:** Fit the four admin destinations into a mobile four-column row using shorter visible labels (`Dashboard`, `Release`, `Notes`, `People`) and reduced horizontal padding, preserving the current 44px minimum target height. Keep the full desktop labels at the existing larger breakpoint.
- **Runtime verification needed:** Yes for keyboard focus, touch activation, and 320px/390px layouts after a change. The clipped current tab at 390px is already visible in the supplied screenshot; this finding does not claim that horizontal scrolling is broken.

The dashboard, tester/profile/add forms, and role editor were also inspected. No additional finding from those areas is included merely to fill the six-finding limit.
