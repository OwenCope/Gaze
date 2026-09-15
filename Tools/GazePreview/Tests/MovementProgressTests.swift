import AppKit
import SwiftUI
import Vision

/// Movement progress ("1 of 2") and the neutral post-submission pending state.
///
/// Two-movement outward prompts carry the gate's count so a fresh prompt after a
/// completed movement reads as progress rather than a reset. One-movement mode stays
/// bare. The animated return stays captionless; Reduce Motion and VoiceOver keep their
/// return cues. After password submission the panel shows a neutral "Waiting for macOS"
/// state with the padlock closed — never a success tick or an opening padlock before
/// macOS confirms the unlock.
///
/// Offscreen renders only: no camera, lock, password, enrollment or live preferences.
@MainActor
enum MovementProgressTests {
	static func run(directory: URL) throws {
		try verifyPromptFormatting()
		try verifyAccessibilityAndMotion()
		try verifyProductionWiring()
		try verifyRenders(directory: directory)
		print("PASS: two-movement progress on outward prompts, bare one-movement mode, hidden animated return, neutral pending distinct from confirmed unlock")
	}

	// MARK: - Pure presentation checks

	private static func verifyPromptFormatting() throws {
		let first = NotchCapsuleModel.Phase.outwardPrompt("Turn slightly left",
			completedActions: 0, requiredActions: 2)
		precondition(first == "Turn slightly left · 1 of 2", "First outward prompt must show 1 of 2, got: \(first)")
		let second = NotchCapsuleModel.Phase.outwardPrompt("Blink",
			completedActions: 1, requiredActions: 2)
		precondition(second == "Blink · 2 of 2", "Second outward prompt must show 2 of 2, got: \(second)")
		let single = NotchCapsuleModel.Phase.outwardPrompt("Turn slightly left",
			completedActions: 0, requiredActions: 1)
		precondition(single == "Turn slightly left", "One-movement mode must stay uncluttered, got: \(single)")
		// A gate reset clears completedActions, so the recomputed prompt can never leave
		// a stale "2 of 2" behind: the next presentation starts again at 1 of 2.
		let afterReset = NotchCapsuleModel.Phase.outwardPrompt("Turn slightly left",
			completedActions: 0, requiredActions: 2)
		precondition(afterReset.contains("1 of 2") && !afterReset.contains("2 of 2"),
			"Reset proof must present 1 of 2, got: \(afterReset)")
		precondition(NotchCapsuleModel.Phase.pendingCaption == "Waiting for macOS",
			"Pending caption must name the wait, got: \(NotchCapsuleModel.Phase.pendingCaption)")
		precondition(NotchCapsuleModel.Phase.pending.captionText == "Waiting for macOS",
			"Pending phase must carry its caption")
		precondition(NotchCapsuleModel.Phase.locked.captionText == nil
			&& NotchCapsuleModel.Phase.unlocked.captionText == nil,
			"Resting and confirmed-unlock phases must carry no caption")
		precondition(!NotchCapsuleModel.Phase.pending.isCompact,
			"Pending must drop a panel, or it reads as the resting padlock")
		precondition(NotchCapsuleModel.Phase.locked.isCompact
			&& NotchCapsuleModel.Phase.unlocked.isCompact,
			"Resting and confirmed unlock stay compact")
	}

	private static func verifyAccessibilityAndMotion() throws {
		let first = GazeFaceMark(phase: .challenge(prompt: "Turn slightly left · 1 of 2",
			symbol: "arrowshape.left.fill", hintX: -1, hintY: 0, pulses: false))
		precondition(first.accessibilityLabel.contains("1 of 2"),
			"VoiceOver must announce the progress, got: \(first.accessibilityLabel)")
		let bare = GazeFaceMark(phase: .challenge(prompt: "Turn slightly left",
			symbol: "arrowshape.left.fill", hintX: -1, hintY: 0, pulses: false))
		precondition(!bare.accessibilityLabel.contains("of"),
			"One-movement VoiceOver must stay uncluttered, got: \(bare.accessibilityLabel)")
		let returning = GazeFaceMark(phase: .challenge(prompt: "Return to your starting position",
			symbol: "viewfinder", hintX: 0, hintY: 0, pulses: false, isReturningToRest: true))
		precondition(returning.accessibilityLabel == "Return to your starting position",
			"Accessible return instruction must survive, got: \(returning.accessibilityLabel)")
		precondition(GazeFaceMark(phase: .pending).accessibilityLabel == "Waiting for macOS",
			"Pending VoiceOver must name the wait")
		precondition(GazeFaceMotion(phase: .pending) == .resting,
			"Pending must be neutral motion, never the accepted tick")
		precondition(GazeFaceMotion(phase: .success) == .accepted,
			"The tick stays the accepted motion for autofill")
		precondition(GazeFaceMotion(phase: .unlocked) == .resting,
			"Confirmed unlock rests with the opening padlock")
	}

	// MARK: - Production wiring (read-only source checks)

	private static func verifyProductionWiring() throws {
		// The preview harness compiles the capsule and the face mark, not the watcher
		// (camera, keychain, XPC), so the watcher's presentation wiring is verified here
		// against its source instead of against a live lock.
		let testsDir = URL(fileURLWithPath: #filePath, isDirectory: false).deletingLastPathComponent()
		let root = testsDir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let watcher = try String(contentsOf: root.appendingPathComponent("Sources/Security/LockWatcher.swift"))
		precondition(watcher.contains("phase: .pending"),
			"Submission must present the neutral pending state")
		precondition(!watcher.contains("phase: .success"),
			"The Mac unlock path must never present the success tick before confirmation")
		precondition(watcher.contains("outwardPrompt(challenge.guidancePrompt")
			&& watcher.contains("challengeGate.completedActions")
			&& watcher.contains("challengeGate.requiredActions"),
			"Outward prompts must reuse the gate's existing count")
		precondition(watcher.contains("isReturningToRest: true"),
			"The return presentation must keep its own captionless path")
		precondition(watcher.contains("challengeGate.reset()"),
			"Resets must clear the gate so no stale second-movement progress survives")
		precondition(watcher.contains("capsule.update(phase: .unlocked)"),
			"Confirmed unlock must still drive the opening padlock")
	}

	// MARK: - Renders across layouts

	private static func verifyRenders(directory: URL) throws {
		let twoFirst = NotchCapsuleModel.Phase.challenge(prompt: "Turn slightly left · 1 of 2",
			symbol: "arrowshape.left.fill", hintX: -1, hintY: 0, pulses: false)
		let twoSecond = NotchCapsuleModel.Phase.challenge(prompt: "Blink · 2 of 2",
			symbol: "eye.fill", hintX: 0, hintY: 0, pulses: true)
		let oneOnly = NotchCapsuleModel.Phase.challenge(prompt: "Turn slightly left",
			symbol: "arrowshape.left.fill", hintX: -1, hintY: 0, pulses: false)
		let layouts: [(String, Preferences.GlyphPlacement, Preferences.PanelShape)] = [
			("attached", .centred, .attached),
			("ear", .ear, .attached),
			("island", .centred, .island)
		]
		for reduced in [false, true] {
			for (name, placement, shape) in layouts {
				try render(phase: twoFirst, name: "progress-\(name)-first-\(reduced)",
					placement: placement, shape: shape, reduced: reduced, directory: directory,
					expectWords: ["Turn", "slightly", "left", "1", "of", "2"])
				try render(phase: twoSecond, name: "progress-\(name)-second-\(reduced)",
					placement: placement, shape: shape, reduced: reduced, directory: directory,
					expectWords: ["Blink", "2", "of", "2"])
				let oneURL = try render(phase: oneOnly, name: "progress-\(name)-single-\(reduced)",
					placement: placement, shape: shape, reduced: reduced, directory: directory,
					expectWords: ["Turn", "slightly", "left"])
				let oneText = try recognizedText(at: oneURL)
				precondition(!oneText.contains("of"),
					"One-movement caption must stay uncluttered in \(name), reduced=\(reduced): \(oneText)")
			}
		}
		// Hidden normal return versus visible Reduce Motion return, every layout.
		let returning = NotchCapsuleModel.Phase.challenge(prompt: "Return to your starting position",
			symbol: "viewfinder", hintX: 0, hintY: 0, pulses: false, isReturningToRest: true)
		for (name, placement, shape) in layouts {
			let animatedURL = try render(phase: returning, name: "progress-\(name)-return-animated",
				placement: placement, shape: shape, reduced: false, directory: directory,
				expectWords: [])
			let animatedText = try recognizedText(at: animatedURL)
			precondition(!animatedText.contains("Return") && !animatedText.contains("starting"),
				"Animated return caption must stay hidden in \(name): \(animatedText)")
			try render(phase: returning, name: "progress-\(name)-return-reduced",
				placement: placement, shape: shape, reduced: true, directory: directory,
				expectWords: ["Return"])
		}
		// Neutral pending distinct from resting and confirmed unlock, every layout.
		for (name, placement, shape) in layouts {
			let pendingURL = try render(phase: .pending, name: "progress-\(name)-pending",
				placement: placement, shape: shape, reduced: false, directory: directory,
				expectWords: ["Waiting"])
			let pendingText = try recognizedText(at: pendingURL)
			precondition(pendingText.contains("macOS"),
				"Pending must name macOS in \(name): \(pendingText)")
			for (state, phase) in [("locked", NotchCapsuleModel.Phase.locked),
				("unlocked", NotchCapsuleModel.Phase.unlocked)] as [(String, NotchCapsuleModel.Phase)] {
				let url = try render(phase: phase, name: "progress-\(name)-\(state)",
					placement: placement, shape: shape, reduced: false, directory: directory,
					expectWords: [])
				let text = try recognizedText(at: url)
				precondition(!text.contains("Waiting"),
					"\(state) must not show the waiting words in \(name): \(text)")
			}
		}
		// Progress must not resize the companion: bare versus suffixed outward prompts
		// keep the same companion geometry within one physical pixel.
		var anchored: CGSize?
		for prompt in ["Turn slightly left", "Turn slightly left · 1 of 2"] {
			let model = NotchCapsuleModel()
			model.isExpanded = true
			model.phase = .challenge(prompt: prompt, symbol: "arrowshape.left.fill",
				hintX: -1, hintY: 0, pulses: false)
			let url = directory.appendingPathComponent("progress-geometry-\(prompt.count).png")
			try CompanionCapture.snapshot(NotchCapsule(model: model, width: 278, height: 128,
				notchInset: 32, cutoutWidth: 180), to: url) { surfaces in
				precondition(surfaces.count == 1)
				let size = surfaces[0].view.bounds.size
				if let previous = anchored {
					let pixel = 1 / (surfaces[0].view.window?.backingScaleFactor ?? 1)
					precondition(abs(previous.width - size.width) <= pixel
						&& abs(previous.height - size.height) <= pixel,
						"Progress must not resize the companion: \(previous) vs \(size)")
				}
				anchored = size
			}
		}
	}

	@discardableResult
	private static func render(phase: NotchCapsuleModel.Phase, name: String,
		placement: Preferences.GlyphPlacement, shape: Preferences.PanelShape,
		reduced: Bool, directory: URL, expectWords: [String]) throws -> URL {
		let model = NotchCapsuleModel()
		model.isExpanded = true
		model.glyphPlacement = placement
		model.shape = shape
		model.phase = phase
		let url = directory.appendingPathComponent("\(name).png")
		try CompanionCapture.snapshot(NotchCapsule(model: model, width: 278,
			height: (shape == .island ? 244 : 128),
			notchInset: 32, cutoutWidth: 180).environment(\.notchReduceMotion, reduced), to: url)
		if !expectWords.isEmpty {
			let text = try recognizedText(at: url)
			let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
			var remaining = words[...]
			for word in expectWords {
				guard let index = remaining.firstIndex(of: word) else {
					preconditionFailure("Missing \(word) in \(name): \(text)")
				}
				remaining = remaining[remaining.index(after: index)...]
			}
		}
		return url
	}

	private static func recognizedText(at url: URL) throws -> String {
		let request = VNRecognizeTextRequest()
		request.recognitionLevel = .accurate
		request.usesCPUOnly = true
		request.usesLanguageCorrection = false
		try VNImageRequestHandler(url: url).perform([request])
		return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
	}
}
