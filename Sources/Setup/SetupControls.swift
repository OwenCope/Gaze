import SwiftUI

/// Setup's primary button.
///
/// The same native push button the rest of the app uses (`gazeButton`) at `.large`: the
/// system bordered styles, which render as real Liquid Glass on macOS 26 and read as Apple's
/// because they are. No green tint — buttons take the system accent, so green stays reserved
/// for the one thing it means in Gaze, *recognised*.
struct SetupButton: View {
	var title: String = "Continue"
	var isProminent = true
	var action: () -> Void

	var body: some View {
		Button(title, action: action)
			.gazeButton(isProminent ? .primary : .standard, size: .extraLarge)
			// Tinted white, and only here.
			//
			// `.glassProminent` takes the accent colour and lenses whatever is behind it.
			// In Settings that is a light glass sheet and it comes out as a real button. In
			// setup the ground is near-black under an 0.80 scrim, so the material had almost
			// nothing to refract and the accent had nothing to lift: Continue rendered as a
			// dim grey capsule with grey text, which on a dark screen is the exact appearance
			// of a *disabled* control. The one action the screen exists for looked switched
			// off.
			//
			// White rather than a colour, deliberately. Green means "recognised" everywhere
			// in this app and spending it on a navigation button dilutes the one place it
			// carries meaning. A light capsule with dark type is what macOS puts on a dark
			// sheet, and it stays a system glass control — the tint is the only thing
			// changed.
			.tint(isProminent ? .white : Theme.setupSecondary)
	}
}

/// The single glyph a setup screen leads with.
///
/// Just the symbol. It used to sit in a rounded glass tile, on the argument that a bare
/// symbol reads as an icon that failed to load — which is true at 20pt in a list and false
/// at 90pt on an empty screen. At this size the tile was a box drawn around something that
/// did not need one, and on a window whose ground is already glass over wallpaper it added
/// a second material for no reason.
///
/// Weight and size carry it instead, which is what Apple's own permission and setup screens
/// do: a large, light glyph and nothing behind it.
struct SetupGlyph: View {

	let symbol: String
	/// Colour only on signal — a granted permission, a success. Nil for everything else,
	/// which is most things.
	var tint: Color?

	var body: some View {
		Image(systemName: symbol)
			.font(.system(size: 76, weight: .light))
			.foregroundStyle(tint ?? .white)
			.shadow(color: .black.opacity(0.35), radius: 20, y: 8)
	}
}

/// A text field shaped like the rest of the app: a glass capsule.
///
/// `.textFieldStyle(.roundedBorder)` draws AppKit's bezelled field — a light rounded
/// rectangle with a hard focus ring. On a dark window whose ground is glass over the
/// wallpaper it is the one opaque, square-shouldered thing on screen, and the blue ring it
/// grows on focus doubles the problem.
///
/// So: `.plain`, in a capsule with real glass behind it. Focus is shown by lifting the
/// material and warming the edge rather than by drawing a ring around it — the same way
/// Spotlight and the lock screen's own password field indicate focus.
struct GlassField: View {

	let placeholder: String
	@Binding var text: String
	var isSecure = true
	var isEnabled = true
	var onSubmit: () -> Void = {}

	@FocusState private var isFocused: Bool

	var body: some View {
		Group {
			if isSecure {
				SecureField(placeholder, text: $text)
			} else {
				TextField(placeholder, text: $text)
			}
		}
		.textFieldStyle(.plain)
		// Scaled, because this is the one field in setup somebody actually types into —
		// a password, without seeing what they typed. A fixed 15pt meant the person most
		// likely to have raised their system text size got the app's least forgiving
		// control at the app's smallest fixed size.
		.font(.body.scaled(by: 15.0 / 13.0))
		.foregroundStyle(.white)
		.focused($isFocused)
		.onSubmit(onSubmit)
		.disabled(!isEnabled)
		.multilineTextAlignment(.center)
		.padding(.horizontal, 20)
		.padding(.vertical, 12)
		// Long enough to hold a password without scrolling it, and wide enough that the
		// capsule reads as a capsule rather than a pill with two characters in it.
		.frame(width: 360)
		// The material only. No hand-drawn capsule under it.
		//
		// This drew its own fill and its own edge *and then* applied `.glassEffect` on top,
		// so the real material was refracting a painted capsule rather than what was behind
		// the window — two capsules stacked, and the flat one winning. Focus keeps a stroke
		// because a text field has to show where the caret is, but it is now the only thing
		// drawn here that the system does not provide.
		.glassEffect(.regular, in: .capsule)
		.overlay {
			Capsule(style: .continuous)
				.strokeBorder(.white.opacity(isFocused ? 0.34 : 0), lineWidth: 1)
		}
		.animation(Theme.Motion.quick, value: isFocused)
		.onAppear { isFocused = true }
	}
}
