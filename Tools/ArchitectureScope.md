# Architecture scope: Apple Silicon vs universal

## Recommendation

A universal binary is required for this release.

The declared support floor is "macOS 26" plus "a Mac with a Secure Enclave"
(`RELEASE_NOTES.md:58-60`), with no architecture qualifier anywhere in the
repo. Four Intel Macs run macOS 26 (Apple Support, support.apple.com/en-us/122867:
MacBook Pro 16-inch 2019, MacBook Pro 13-inch 2020 four-port, iMac 27-inch 2020,
Mac Pro 2019), and the codebase itself treats Intel as a supported target
(`toolchain.sh:130-131`). An arm64-only binary cannot execute on any of them,
so shipping host-architecture-only would silently drop supported machines.
That makes the current output a defect, not a documentation issue.

## Evidence

### 1. What the app claims to support

- `Resources/Info.plist:19-20`: `LSMinimumSystemVersion` = `26.0`. The plist
  contains no `LSArchitecturePriority` or any other architecture key (grep for
  `LSArchitecturePriority` returns nothing, exit 1), so the bundle declares no
  architecture restriction of its own.
- `RELEASE_NOTES.md:56-60` (Requirements): "macOS 26"; "A Mac with a Secure
  Enclave. Without one, nothing is stored at all rather than being stored more
  weakly."; camera access (+ Accessibility for the typing mode). No mention of
  Apple Silicon, Intel, arm64, x86_64, or universal.
- `README.md:21`: "Requires the macOS 26 SDK and a valid stable signing
  identity." Build-host requirement only; no statement about which Macs the app
  runs on.
- A repo-wide grep for `Intel|Apple Silicon|arm64|x86_64|universal|Rosetta`
  across `README.md`, `RELEASE_NOTES.md`, `Resources/Info.plist`,
  `Tools/Release/READINESS.md`, `toolchain.sh`, `build.sh` returns exactly two
  hits: the READINESS gate line itself and the `toolchain.sh` comment below.
  The app never tells the user which architectures it supports.

### 2. What the build actually produces

- `build.sh:184-188`: the compile is a single `xcrun swiftc` invocation with
  `-target "$(host_target)"` and no `-arch` flags. One invocation emits one
  architecture.
- `toolchain.sh:128-134`: `host_target()` prints
  `$(uname -m)-apple-macos26.0`, i.e. whatever the build machine is ("The
  architecture of the machine doing the building"). On this Apple Silicon host
  that is `arm64-apple-macos26.0`; nothing ever requests `x86_64`.
- The same comment block (`toolchain.sh:130-131`) states: "This was pinned to
  arm64, which fails on an Intel Mac for no reason — nothing in the project is
  Apple silicon-specific." The project therefore already intends Intel
  buildability; the release artifact just doesn't follow through.
- `Tools/Release/DMG/package.py:86`: `architecture = run("/usr/bin/lipo",
  "-archs", ...)` — records the binary's architectures into the DMG filename
  and receipt. No assertion, no minimum-architectures check.
- `Tools/Release/verify.sh:42`: `echo "Architecture: $(lipo -archs ...)"` —
  informational only. A single-arch release binary passes `verify.sh` today.
- `Tools/Release/READINESS.md:377-378`: "Verify all claimed OS/architecture
  combinations. The build script produces the build host's architecture, not a
  universal binary." Accurate as far as it goes, but "all claimed combinations"
  is undefined because no combinations are claimed anywhere (see step 1).

Emitting both slices from `swiftc` takes two compilations (one
`-target x86_64-apple-macos26.0`, one arm64) combined with `lipo -create`;
there is no single-invocation universal flag in the current command.

### 3. Whether Intel is in scope

- Declared minimum OS is 26.0 (`Resources/Info.plist:19-20`). Apple lists four
  Intel models as macOS Tahoe 26 compatible (support.apple.com/en-us/122867):
  MacBook Pro (16-inch, 2019), MacBook Pro (13-inch, 2020, four Thunderbolt 3
  ports), iMac (27-inch, 2020), Mac Pro (2019). So the minimum-OS requirement
  does not exclude Intel; it includes exactly these machines.
- Notch: no Intel Mac has a display notch, but the app does not require one.
  `Sources/LockScreen/NotchMetrics.swift:41-43` (`hasNotch`) detects a notch
  rather than assuming it, and every consumer falls back to a constant:
  `Sources/LockScreen/NotchCapsuleController.swift:162,184,238` and
  `Sources/LockScreen/WallpaperBrightness.swift:62` all use
  `NotchMetrics.width(on: screen) ?? 180`. Non-notch Macs get a 180pt panel.
- Apple Silicon-only frameworks / Neural Engine: none found. Grep over
  `Sources/` for `MLComputeUnits|neuralEngine|NeuralEngine|ANE|
  MLModelConfiguration|computeUnits` returns nothing — Core ML runs on default
  compute units. Linked frameworks (`build.sh:191-198`: SwiftUI, AppKit,
  AVFoundation, Vision, CoreML, CryptoKit, LocalAuthentication,
  OpenDirectory) all exist on Intel macOS 26.
- Secure Enclave: `Sources/Security/SecureVault.swift:35-37` — "True on Apple
  Silicon and T2 Macs." The four Tahoe Intel Macs are all T2 machines, so the
  vault's enclave requirement is satisfiable on every Intel Mac in scope.
  (Non-enclave Macs are already handled: enrollment refuses to store rather
  than storing weakly, `RELEASE_NOTES.md:59-60`.)
- Private SkyLight SPI: `Sources/LockScreen/LockScreenSpace.swift:34-39`
  declares the SPI as `@convention(c)` function-pointer types resolved at
  runtime — architecture-independent source that compiles identically for both
  slices. Any fragility there is OS-version fragility, already gated by the
  READINESS line on testing every supported OS version, not an arch blocker.
  (LockScreenSpace.swift:17 notes unlock itself never depends on the capsule;
  `README.md` takes the stricter view that submission requires the panel —
  either way, that question is API-availability, identical on both archs.)

### 4. Dependencies: nothing single-architecture found

`build/Gaze.app` and `Frameworks/` do not exist in this worktree, so there is
no built binary to inspect here. Verbatim command output:

```
$ ls build/Gaze.app/Contents/MacOS/ build/Gaze.app/Contents/Frameworks/
ls: build/Gaze.app/Contents/MacOS/: No such file or directory
ls: build/Gaze.app/Contents/Frameworks/: No such file or directory
$ ls Frameworks/
ls: Frameworks/: No such file or directory
$ file build/Gaze.app/Contents/MacOS/Gaze
build/Gaze.app/Contents/MacOS/Gaze: cannot open `build/Gaze.app/Contents/MacOS/Gaze' (No such file or directory)
$ lipo -archs build/Gaze.app/Contents/MacOS/Gaze
lipo: file not found 'build/Gaze.app/Contents/MacOS/Gaze'
```

(The lead should rerun `file`/`lipo -archs` on `build/release/Gaze.app` in a
checkout where it exists; nothing below substitutes for that check.)

What the repo itself contains:

- No bundled binary frameworks anywhere: `find . -name "*.framework" -o
  -name "*.dylib" -o -name "*.a"` (excluding `build/`) returns nothing.
  `ThirdParty/` holds only `TourKit.swift` source plus `LICENSE`,
  `SOURCE.json`, `LOCAL-CHANGES.md` — compiled in, no binary to be arch-bound.
- Models ship as portable sources, compiled by `coremlc` at build time
  (`build.sh` model sections): `Resources/FaceEmbedding.mlpackage`
  (`Manifest.json`, `Data/com.apple.CoreML/model.mlmodel`,
  `Data/com.apple.CoreML/weights/weight.bin`) and `Resources/Spoof.mlmodel`.
  Verbatim `file` output:
```
Resources/FaceEmbedding.mlpackage/Data/com.apple.CoreML/weights/weight.bin: a.out little-endian 32-bit executable
Resources/FaceEmbedding.mlpackage/Data/com.apple.CoreML/model.mlmodel:      data
Resources/FaceEmbedding.mlpackage/Manifest.json:                            JSON data
Resources/Spoof.mlmodel:                                                    data
```
  The `weight.bin` label is a `file(1)` heuristic misfire on a raw float blob:
  its first 16 bytes are `07 01 00 00 02 00 00 00 ...` (`xxd`), not a Mach-O
  magic (`cafebabe`/`cffaedfe`/`feedface`/`feedfacf`). It is 7,408,704 bytes of
  weights, not executable code, and `coremlc` compiles the model for whichever
  target it is invoked with. No dependency blocks a universal binary.

## If Apple Silicon only

If the owner decides the four Tahoe Intel Macs are out of scope despite the
above, the gate line and the user-facing statement must say so explicitly —
today they imply "any Mac on macOS 26 with a Secure Enclave". Do NOT apply
these edits; they are the proposed text only.

1. `Tools/Release/READINESS.md:377-379`, replace
   "- Verify all claimed OS/architecture combinations. The build script produces the
     build host's architecture, not a universal binary. Private lock-screen window
     APIs need real testing on every supported OS version."
   with
   "- Apple Silicon only: verify the arm64 build on Apple Silicon Macs running
     each supported macOS 26.x version. The build script produces the build
     host's architecture (`-target $(uname -m)-apple-macos26.0`,
     `build.sh:188`); on Apple Silicon that is arm64-only, which is the
     supported configuration — Intel Macs are not supported (see Requirements).
     Private lock-screen window APIs need real testing on every supported OS
     version."

2. `RELEASE_NOTES.md` Requirements (`:56-60`), append an explicit line:
   "- Apple Silicon Macs only. Intel Macs are not supported in this release,
     even models that can run macOS 26."

3. `Resources/Info.plist`: optionally add `LSArchitecturePriority` =
   `["arm64"]` so a copied bundle fails fast with a clear system message on
   Intel rather than an opaque launch failure. Cosmetic; the store/DMG path
   never reaches Intel users anyway once the docs say Apple Silicon only.

Even then, keep the `toolchain.sh` Intel build path working — several
developers build on Intel, and breaking their builds is unrelated to the
release scope decision.

## If universal is required

1. `build.sh:184-199` — compile twice and `lipo` the results. Sketch, keeping
   the existing SDK/entitlement/signing flow unchanged:
   - Run the current `xcrun swiftc ... -target arm64-apple-macos26.0 ... -o
     "$BIN.arm64"` and again with `-target x86_64-apple-macos26.0` to
     `"$BIN.x86_64"`. `host_target()` stays for the log line and as the
     default when only one slice is wanted (e.g. local iteration).
   - `lipo -create "$BIN.arm64" "$BIN.x86_64" -output "$BIN"`, then sign once
     as today. `coremlc` output is arch-neutral; models need no per-arch pass.
   - The `DIST=1` `SDK_FLAGS` `-platform_version` linker stamp applies per
     slice identically; no change needed there.
   - Cross-compiling x86_64 from the Apple Silicon build host is supported by
     the macOS 26 SDK; no Intel builder is required. Still, the first
     universal artifact must be launch-tested on a real Tahoe Intel Mac —
     none of the synthetic suites execute the foreign slice.
2. `Tools/Release/verify.sh:42` — promote the informational `lipo -archs`
   echo to a gate: fail unless the output contains both `x86_64` and `arm64`.
3. `Tools/Release/DMG/package.py:86` — the architecture string becomes
   `x86_64 arm64` and flows into the DMG filename automatically; no change
   needed, but confirm the `x86_64-arm64` filename renders as intended.
4. `Tools/Release/READINESS.md:377` — replace "Verify all claimed
   OS/architecture combinations" with "Verify arm64 and x86_64 slices on real
   hardware: an Apple Silicon Mac and one of the four Tahoe Intel Macs (MBP
   16-inch 2019, MBP 13-inch 2020 four-port, iMac 27-inch 2020, Mac Pro 2019),
   each on macOS 26."
5. No dependency blocks this: step 4 found no bundled Mach-O, no
   single-architecture framework, no ANE-pinned model. The one check that must
   still be run in a checkout containing the built app is `lipo -archs` on the
   final universal binary plus a launch test on Tahoe Intel hardware.
