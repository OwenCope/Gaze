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
	@State private var showsInformation = false

	var body: some View {
		VStack(spacing: 0) {
			HStack(alignment: .top) {
				VStack(alignment: .leading, spacing: 5) {
					Text("Meet your Gaze").font(.system(size: 22, weight: .semibold))
					Text("A little practice. Nothing unlocks.")
						.font(.callout).foregroundStyle(Theme.secondaryLabel)
				}
				Spacer()
				Button { showsInformation.toggle() } label: {
					Image(systemName: "info.circle").font(.system(size: 16))
						.frame(width: 22, height: 22)
				}
				.gazeButton(.standard, size: .small)
				.accessibilityLabel("About this recognition test")
				.popover(isPresented: $showsInformation) {
					VStack(alignment: .leading, spacing: 10) {
						Text("Just a recognition test").font(.headline)
						Text("This window checks your face and a movement. It never enters a password or unlocks your Mac. Movement complete is not an authentication result.")
							.font(.callout)
						Text("The camera stops when you close this window, lock your Mac, sleep, or switch users. Reopen this test after unlocking to start again.")
							.font(.callout).foregroundStyle(.secondary)
					}.padding(18).frame(width: 300)
				}
			}
			.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 16)

			// Keep the useful measurements outside the scroll view: opening details
			// or using a short window must not hide the score/pose being recorded.
			VStack(spacing: 12) {
				HStack(spacing: 10) {
					Circle().fill(!readout.isCollectingBaseline && readout.matched ? Theme.faceID : Theme.tertiaryLabel).frame(width: 6, height: 6)
					Text(readout.status).font(.callout.weight(.medium))
					Spacer(minLength: 8)
					Text("Face match").font(.caption).foregroundStyle(Theme.secondaryLabel)
				}
				.accessibilityElement(children: .combine)

				HStack(spacing: 12) {
					ForEach(Array(summaryRows.enumerated()), id: \.offset) { _, row in
						VStack(alignment: .leading, spacing: 4) {
							Text(row.0).font(.caption).foregroundStyle(Theme.secondaryLabel)
							Text(row.1).font(.callout.weight(.semibold)).monospacedDigit()
								.textSelection(.enabled)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
						.accessibilityElement(children: .combine)
					}
				}
			}
			.padding(12)
			.background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
			.padding(.horizontal, 24).padding(.bottom, 16)

			ScrollView {
				VStack(spacing: 16) {
					camera()
						.frame(maxWidth: .infinity).frame(height: 180)
						.clipShape(RoundedRectangle(cornerRadius: 20))
						.overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.separator))
						.accessibilityLabel("Live camera preview")

					if let onSetup {
						VStack(alignment: .leading, spacing: 10) {
							Text("Enroll your face before testing recognition.")
								.font(.system(size: 16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
							Button("Set Up Gaze", action: onSetup)
								.gazeButton(.primary, size: .large)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(12)
						.background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
						.overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.separator))
					} else {
						HStack(spacing: 12) {
							companion().frame(width: 104, height: 104)
							VStack(alignment: .leading, spacing: 7) {
								Text(readout.complete ? "Movement complete" : "One small movement")
									.font(.caption.weight(.medium)).foregroundStyle(Theme.secondaryLabel)
								Text(readout.instruction)
									.font(.system(size: 16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
									.accessibilityLabel(readout.instruction)
									.help(readout.instruction)
								Button("Try another movement", action: next)
									.gazeButton(.standard, size: .small).disabled(!readout.canChallenge)
							}
							.frame(maxWidth: .infinity, alignment: .leading)
						}
						.padding(12)
						.background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
						.overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.separator))
					}

					DisclosureGroup(isExpanded: $showsDetail) {
						VStack(spacing: 0) {
							ForEach(readout.diagnosticRows.indices, id: \.self) { index in
								let row = readout.diagnosticRows[index]
								HStack(alignment: .firstTextBaseline) {
									Text(row.0).foregroundStyle(Theme.secondaryLabel)
									Spacer()
									Text(row.1).monospacedDigit().multilineTextAlignment(.trailing).textSelection(.enabled)
								}.font(.caption).padding(.vertical, 7)
								if index != readout.diagnosticRows.indices.last { Divider() }
							}
						}.padding(.top, 10)
					} label: {
						Text("Recognition details").font(.callout).foregroundStyle(Theme.secondaryLabel)
					}
					.tint(Theme.secondaryLabel)
					.animation(reducedMotion || previewReduceMotion ? nil : .easeOut(duration: 0.2), value: showsDetail)
				}
				.padding(.horizontal, 24).padding(.bottom, 18)
			}
			.scrollIndicators(.automatic)
			HStack {
				Text("Test only · no system authentication")
					.font(.caption).foregroundStyle(Theme.tertiaryLabel)
				Spacer()
				Button("Reset test", action: reset).controlSize(.small)
			}
			.padding(.horizontal, 24).padding(.vertical, 16)
		}
		.frame(minWidth: 480, idealWidth: 560, maxWidth: .infinity,
			minHeight: 650, idealHeight: 820, maxHeight: .infinity)
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
