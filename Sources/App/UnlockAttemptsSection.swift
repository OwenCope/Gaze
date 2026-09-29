import SwiftUI

/// The recent history of looks at the lock screen: what happened, how long an
/// unlock took, and — only when asked — a photo of who couldn’t get in.
struct UnlockAttemptsSection: View {

	private static let relative: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return formatter
	}()

	@Bindable private var log = UnlockAttemptLog.shared
	@State private var enlarged: UnlockAttempt?
	@State private var showsAttempts = false

	var body: some View {
		SettingsSection(title: "Unlock Attempts", footer: "Photos delete themselves after 30 days.") {
			SettingToggle(title: "Take a photo when someone can’t unlock",
				detail: "Photos stay on this Mac",
				symbol: "camera.viewfinder",
				isOn: $log.capturesPhotos)

			let recent = Array(log.attempts.prefix(10))
			RowDivider()
			if recent.isEmpty {
				SettingRow(title: "No attempts yet") { EmptyView() }
			} else {
				// Collapsed by default: the list is for when something went wrong, not
				// something to scroll past every time. A row like its neighbours, so the
				// title lines up with theirs instead of sitting under a disclosure arrow.
				Button {
					withAnimation(.snappy) { showsAttempts.toggle() }
				} label: {
					SettingRow(title: "Recent Attempts", symbol: "clock.arrow.circlepath") {
						HStack(spacing: 8) {
							Text("\(log.attempts.count)")
								.font(Typography.detail.monospacedDigit())
								.foregroundStyle(Theme.secondaryLabel)
							Image(systemName: "chevron.right")
								.font(.footnote.weight(.semibold))
								.foregroundStyle(Theme.secondaryLabel)
								.rotationEffect(.degrees(showsAttempts ? 90 : 0))
						}
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.accessibilityValue(showsAttempts ? "Expanded" : "Collapsed")
				if showsAttempts {
					ForEach(recent) { attempt in
						RowDivider()
						attemptRow(attempt)
					}
					RowDivider()
					SettingRow(title: "Delete All", symbol: "trash") {
						Button("Delete All") { log.deleteAll() }
							.gazeButton()
					}
				}
			}
		}
	}

	@ViewBuilder
	private func attemptRow(_ attempt: UnlockAttempt) -> some View {
		if let image = log.photo(for: attempt) {
			Button {
				enlarged = attempt
			} label: {
				SettingRow(title: Self.title(for: attempt), detail: Self.detail(for: attempt),
					portrait: image) { EmptyView() }
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			// A popover, not a sheet: clicking anywhere outside it, or the close button,
			// or Escape puts it away.
			.popover(isPresented: Binding(
				get: { enlarged?.id == attempt.id },
				set: { if !$0 { enlarged = nil } }
			), arrowEdge: .trailing) {
				Image(nsImage: image)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: 480)
					.clipShape(.rect(cornerRadius: 10, style: .continuous))
					.overlay(alignment: .topTrailing) {
						Button {
							enlarged = nil
						} label: {
							Image(systemName: "xmark")
								.font(.system(size: 11, weight: .bold))
								.frame(width: 26, height: 26)
						}
						.buttonStyle(.glass)
						.buttonBorderShape(.circle)
						.keyboardShortcut(.cancelAction)
						.accessibilityLabel("Close photo")
						.padding(8)
					}
					.padding(12)
			}
		} else {
			SettingRow(title: Self.title(for: attempt), detail: Self.detail(for: attempt),
				symbol: attempt.result == .unlocked ? "checkmark.circle" : "xmark.circle") {
				EmptyView()
			}
		}
	}

	private static func title(for attempt: UnlockAttempt) -> String {
		switch attempt.result {
		case .unlocked: return "Unlocked"
		case .notRecognised: return "Not recognised"
		case .unknownFace: return "Unknown face"
		case .spoofRejected: return "Photo or screen blocked"
		case .closedWithoutUnlocking: return "Opened without unlocking"
		}
	}

	private static func detail(for attempt: UnlockAttempt) -> String? {
		let when = relative.localizedString(for: attempt.date, relativeTo: Date())
		if attempt.result == .unlocked, let duration = attempt.duration {
			var line = "\(when) · in \(String(format: "%.1f", duration)) s"
			// Where the time went, so a slow unlock says which part was slow.
			if let steps = attempt.steps {
				var parts = [("camera", steps.camera), ("face", steps.recognise), ("checks", steps.check), ("macOS", steps.macOS)]
					.compactMap { name, value in value.map { "\(name) \(String(format: "%.1f", $0))" } }
				if let movement = steps.movement {
					parts.append("movement \(String(format: "%.1f", movement))")
				}
				if !parts.isEmpty { line += " (" + parts.joined(separator: ", ") + ")" }
			}
			return line
		}
		if let reason = attempt.reason {
			return "\(when) · \(Self.reasonText(reason))"
		}
		return when
	}

	private static func reasonText(_ reason: UnlockAttempt.Reason) -> String {
		switch reason {
		case .tooDark: return "Too dark or blurry"
		case .tooFar: return "Too far away"
		case .faceTurned: return "Face turned away"
		case .noFace: return "No face seen"
		case .differentPerson: return "Someone else"
		case .movementTimedOut: return "Movement not seen in time"
		case .photoOrScreen: return "Looked like a photo or screen"
		}
	}
}
