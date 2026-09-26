import SwiftUI

struct RecognitionTestReadout {
	var status: String
	var matched: Bool
	var score: Float
	var threshold: Float
	var instruction: String
	var complete: Bool
	var canChallenge: Bool
	var diagnosticRows: [(String, String)]
	var yaw: Double? = nil
	var pitch: Double? = nil
	/// Presentation-only: true while the practice view is establishing its baseline.
	/// Keeps the status indicator neutral; raw matched/score stay untouched for diagnostics.
	var isCollectingBaseline: Bool = false
}

struct RecognitionTestPanel<CameraContent: View, CompanionContent: View>: View {
	let readout: RecognitionTestReadout
	@Binding var showsDetail: Bool
	let next: () -> Void
	let reset: () -> Void
	var onSetup: (() -> Void)? = nil
	@ViewBuilder var camera: () -> CameraContent
	@ViewBuilder var companion: () -> CompanionContent
	@Environment(\.accessibilityReduceMotion) private var reducedMotion
	@Environment(\.notchReduceMotion) private var previewReduceMotion

	var body: some View {
		VStack(spacing: 0) {
			ScrollView {
				VStack(spacing: 18) {
					// The camera is the subject, shown large, with the verdict on it rather
					// than in a table above it.
					camera()
						.frame(maxWidth: .infinity).frame(height: 320)
						.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
						.overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.separator))
						.overlay(alignment: .bottomLeading) { statusPill.padding(14) }
						.overlay(alignment: .topTrailing) {
							InfoButton(title: "Just a recognition test") {
								Text("This window checks your face and a movement. It never enters a password or unlocks your Mac. Movement complete is not an authentication result.")
								Text("The camera stops when you close this window, lock your Mac, sleep, or switch users. Reopen this test after unlocking to start again.")
							}
							.padding(12)
						}
						.accessibilityLabel("Live camera preview")

					if let onSetup {
						VStack(spacing: 12) {
							Text("Enroll your face before testing recognition.")
								.font(.system(size: 17, weight: .semibold)).multilineTextAlignment(.center)
							Button("Set Up Gaze", action: onSetup)
								.gazeButton(.primary, size: .large)
						}
						.frame(maxWidth: .infinity)
						.padding(.vertical, 8)
					} else {
						// One card for the practice: the companion and the movement on top,
						// the match underneath, instead of three pieces floating in the window.
						VStack(spacing: 18) {
							HStack(spacing: 18) {
								companion().frame(width: 96, height: 96)
								VStack(alignment: .leading, spacing: 6) {
									Text(readout.complete ? "Movement complete" : "One small movement")
										.font(.callout.weight(.medium)).foregroundStyle(Theme.secondaryLabel)
									Text(readout.instruction)
										.font(.system(size: 22, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
										.accessibilityLabel(readout.instruction)
										.help(readout.instruction)
										.contentTransition(.opacity)
										.animation(reducedMotion || previewReduceMotion ? nil : .smooth(duration: 0.25), value: readout.instruction)
								}
								.frame(maxWidth: .infinity, alignment: .leading)
								Button("Try another movement", action: next)
									.gazeButton(.standard, size: .regular).disabled(!readout.canChallenge)
							}
							Divider().overlay(Theme.separator)
							matchMeter
						}
						.padding(18)
						.background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
					}

					DisclosureGroup(isExpanded: $showsDetail) {
						VStack(spacing: 0) {
							let rows = summaryRows + readout.diagnosticRows.filter { row in !summaryRows.contains { $0.0 == row.0 } }
							ForEach(rows.indices, id: \.self) { index in
								let row = rows[index]
								HStack(alignment: .firstTextBaseline) {
									Text(row.0).foregroundStyle(Theme.secondaryLabel)
									Spacer()
									Text(row.1).monospacedDigit().multilineTextAlignment(.trailing).textSelection(.enabled)
								}.font(.caption).padding(.vertical, 7)
								if index != rows.indices.last { Divider() }
							}
						}.padding(.top, 10)
					} label: {
						Theme.disclosureLabel("Recognition details")
					}
					.settingsDisclosureRow()
					.animation(reducedMotion || previewReduceMotion ? nil : .easeOut(duration: 0.2), value: showsDetail)
				}
				.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 18)
			}
			.scrollIndicators(.automatic)
			HStack {
				Text("Test only · nothing unlocks")
					.font(.caption).foregroundStyle(Theme.tertiaryLabel)
				Spacer()
				Button("Reset test", action: reset).controlSize(.small)
			}
			.padding(.horizontal, 24).padding(.vertical, 16)
		}
		.frame(minWidth: 520, idealWidth: 600, maxWidth: .infinity,
			minHeight: 600, idealHeight: 700, maxHeight: .infinity)
	}

	private var isRecognised: Bool { !readout.isCollectingBaseline && readout.matched }

	/// The verdict, on the camera: a dot and a word, on a dark glass pill.
	private var statusPill: some View {
		HStack(spacing: 8) {
			Circle().fill(isRecognised ? Theme.faceID : Color.white.opacity(0.5)).frame(width: 8, height: 8)
			Text(readout.status).font(.callout.weight(.semibold)).foregroundStyle(.white)
		}
		.padding(.horizontal, 12).padding(.vertical, 7)
		.background(.black.opacity(0.55), in: Capsule())
		.background(.ultraThinMaterial, in: Capsule())
		.accessibilityElement(children: .combine)
		.animation(reducedMotion || previewReduceMotion ? nil : .smooth(duration: 0.25), value: isRecognised)
		// Status transitions only; the score republishes ~10x a second.
		.onChange(of: readout.status) { oldStatus, newStatus in
			if oldStatus != newStatus { AccessibilityNotification.Announcement(newStatus).post() }
		}
	}

	/// How close the face is to a match: one bar with a mark where recognition starts,
	/// instead of two raw numbers side by side.
	private var matchMeter: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Face match").font(.callout.weight(.medium))
				Spacer()
				Text(isRecognised ? "Recognised" : "Below the line")
					.font(.callout).foregroundStyle(isRecognised ? Theme.faceID : Theme.secondaryLabel)
			}
			GeometryReader { geometry in
				let width = geometry.size.width
				let fill = CGFloat(min(max(readout.score, 0), 1))
				let mark = CGFloat(min(max(readout.threshold, 0), 1))
				ZStack(alignment: .leading) {
					Capsule().fill(.white.opacity(0.1))
					Capsule().fill(isRecognised ? Theme.faceID : Color.white.opacity(0.55))
						.frame(width: max(8, width * fill))
						.animation(reducedMotion || previewReduceMotion ? nil : .smooth(duration: 0.2), value: fill)
					Rectangle().fill(.white.opacity(0.8)).frame(width: 2, height: 16)
						.offset(x: width * mark - 1)
				}
			}
			.frame(height: 10)
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Face match")
		.accessibilityValue(String(format: "%.2f, recognition starts at %.2f", readout.score, readout.threshold))
	}

	private var summaryRows: [(String, String)] {
		[
			("Match score", String(format: "%.3f", readout.score)),
			("Threshold", String(format: "%.2f", readout.threshold)),
			("Yaw (raw)", readout.yaw.map { String(format: "%+.2f rad", $0) } ?? "—"),
			("Pitch (raw)", readout.pitch.map { String(format: "%+.2f rad", $0) } ?? "—")
		]
	}
}
