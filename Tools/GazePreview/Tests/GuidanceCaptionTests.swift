import AppKit
import SwiftUI
import Vision

@MainActor
enum GuidanceCaptionTests {
	static func run(directory: URL) throws {
		let phases: [(String, String, CGFloat)] = [
			("Turn slightly left", "arrowshape.left.fill", -1),
			("Turn slightly right", "arrowshape.right.fill", 1),
			("Return to your starting position", "viewfinder", 0)
		]
		var guidanceSizes: [String: CGSize] = [:]
		for reduced in [false, true] {
			for (index, item) in phases.enumerated() {
				let (prompt, symbol, x) = item
				let readout = RecognitionTestReadout(status: "Simulated", matched: true,
					score: 0.8, threshold: 0.45, instruction: prompt,
					complete: false, canChallenge: true, diagnosticRows: [])
				let panel = RecognitionTestPanel(readout: readout, showsDetail: .constant(false), next: {}, reset: {}) {
					Color.gray
				} companion: {
					GazeCompanionView(motion: x < 0 ? .turnLeft : x > 0 ? .turnRight : .returnToCenter)
				}
				let panelURL = directory.appendingPathComponent("guidance-test-\(index)-\(reduced).png")
				try CompanionCapture.snapshot(panel.frame(width: 480, height: 650)
					.environment(\.notchReduceMotion, reduced).environment(\.colorScheme, .dark).background(.black), to: panelURL)
				try assertVisible(prompt, at: panelURL)
				for placement in [Preferences.GlyphPlacement.centred, .ear] {
					for shape in [Preferences.PanelShape.attached, .island] {
						let model = NotchCapsuleModel()
						model.isExpanded = true
						model.glyphPlacement = placement
						model.shape = shape
						model.phase = .challenge(prompt: prompt, symbol: symbol, hintX: x, hintY: 0, pulses: false)
						for adjustment: CGFloat in [0, -20] {
							let key = "\(placement)-\(shape)-\(reduced)-\(Int(adjustment))"
							let url = directory.appendingPathComponent("guidance-notch-\(index)-\(key).png")
							try CompanionCapture.snapshot(NotchCapsule(model: model, width: 278 + adjustment * 2,
								height: (shape == .island ? 244 : 128) + adjustment,
								notchInset: 32, cutoutWidth: 180).environment(\.notchReduceMotion, reduced), to: url) { surfaces in
								precondition(surfaces.count == 1)
								let size = surfaces[0].view.bounds.size
								if let previous = guidanceSizes[key] {
									let pixel = 1 / (surfaces[0].view.window?.backingScaleFactor ?? 1)
									precondition(abs(previous.width - size.width) <= pixel && abs(previous.height - size.height) <= pixel, "The return cue must not resize the companion: \(key), phase \(index), previous \(previous), current \(size)")
								}
								guidanceSizes[key] = size
							}
							try assertVisible(prompt, at: url)
						}
					}
				}
			}
		}
		print("PASS: visible turn and return captions in minimum-size recognition panel and attached/island/ear notch, animated and reduced motion")
	}

	private static func assertVisible(_ prompt: String, at url: URL) throws {
		let request = VNRecognizeTextRequest()
		request.recognitionLevel = .accurate
		request.usesCPUOnly = true
		request.usesLanguageCorrection = false
		try VNImageRequestHandler(url: url).perform([request])
		let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
		// OCR can place the adjacent SF Symbol between the two text lines.
		// Require every instruction word in order, allowing that extra symbol token.
		let words = text.split(whereSeparator: \.isWhitespace)
		var remaining = words[...]
		for word in prompt.split(whereSeparator: \.isWhitespace) {
			guard let index = remaining.firstIndex(of: word) else {
				preconditionFailure("Missing visible instruction in \(url.lastPathComponent): \(text)")
			}
			remaining = remaining[remaining.index(after: index)...]
		}
	}
}
