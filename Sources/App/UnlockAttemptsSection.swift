import SwiftUI

/// The recent history of looks at the lock screen: what happened, how long an
/// unlock took, and — when asked — a photo of who was there.
struct UnlockAttemptsSection: View {

	private static let relative: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		// "now" rather than "in 0 seconds" for an attempt that just happened.
		formatter.dateTimeStyle = .named
		return formatter
	}()

	@Bindable private var log = UnlockAttemptLog.shared
	@State private var enlarged: UnlockAttempt?
	@State private var showsAttempts = false

	var body: some View {
		SettingsSection(title: "Unlock Attempts", footer: "Photos delete themselves after 30 days.") {
			SettingRow(title: "Take photos", detail: "Photos stay on this Mac",
				symbol: "camera.viewfinder") {
				SettingsChoiceMenu(title: "Take photos",
					valueLabel: log.photoPolicy.title,
					selection: $log.photoPolicy) {
					ForEach(UnlockAttemptLog.PhotoPolicy.allCases, id: \.self) { policy in
						Text(policy.title).tag(policy)
					}
				}
			}

			let recent = Array(log.attempts.prefix(10))
			RowDivider()
			if recent.isEmpty {
				SettingRow(title: "No attempts yet", symbol: "clock.arrow.circlepath") { EmptyView() }
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
					ForEach(AttemptGroup.allCases, id: \.self) { group in
						let attempts = recent.filter { group.contains($0.result) }
						if !attempts.isEmpty {
							RowDivider()
							groupHeader(group.title)
							ForEach(attempts) { attempt in
								RowDivider()
								attemptRow(attempt)
							}
						}
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
				symbol: Self.symbol(for: attempt)) {
				EmptyView()
			}
		}
	}

	/// One caption per non-empty group, in the section's own caption style.
	private func groupHeader(_ title: String) -> some View {
		Text(title)
			.font(Typography.caption)
			.foregroundStyle(Theme.secondaryLabel)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, Theme.rowInset)
			.padding(.vertical, 8)
	}

	/// Three groups for the ten most recent attempts. Old closedWithoutUnlocking
	/// logs read as opened another way.
	private enum AttemptGroup: String, CaseIterable {
		case gaze
		case anotherWay
		case notUnlocked

		var title: String {
			switch self {
			case .gaze: return "Unlocked with Gaze"
			case .anotherWay: return "Opened another way"
			case .notUnlocked: return "Not unlocked"
			}
		}

		func contains(_ result: UnlockAttempt.Result) -> Bool {
			switch result {
			case .unlocked: return self == .gaze
			case .openedAnotherWay, .closedWithoutUnlocking: return self == .anotherWay
			case .notRecognised, .unknownFace, .spoofRejected, .leftLocked: return self == .notUnlocked
			}
		}
	}

	private static func title(for attempt: UnlockAttempt) -> String {
		switch attempt.result {
		case .unlocked: return "Unlocked"
		case .notRecognised: return "Not recognised"
		case .unknownFace: return "Unknown face"
		case .spoofRejected: return "Photo or screen blocked"
		case .openedAnotherWay, .closedWithoutUnlocking: return "Opened with password or Touch ID"
		case .leftLocked: return "Left locked"
		}
	}

	private static func symbol(for attempt: UnlockAttempt) -> String {
		switch attempt.result {
		case .unlocked: return "checkmark.circle"
		case .openedAnotherWay, .closedWithoutUnlocking: return "key"
		case .notRecognised, .unknownFace, .spoofRejected, .leftLocked: return "xmark.circle"
		}
	}

	private static func detail(for attempt: UnlockAttempt) -> String? {
		let when = relative.localizedString(for: min(attempt.date, Date()), relativeTo: Date())
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
