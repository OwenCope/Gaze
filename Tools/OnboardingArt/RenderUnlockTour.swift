// Tools/OnboardingArt/RenderUnlockTour.swift
//
// Static illustrative scene for the welcome tour's "How unlock works" page.
//
// The real NotchCapsule in its movement-prompt phase (charcoal companion,
// closed padlock, "Turn slightly left") composited over a cropped photograph
// of the lock screen. The crop keeps the clock and wallpaper and drops the
// menu-bar indicators and the avatar/name/password area, which must never
// appear in tour artwork. Panel and clock sit in the upper portion because
// TourKit fades the lower half of photographs.
//
// Illustrative only, not an authentication recording: a fresh preview model
// with hardcoded values — no app launch, no camera, no credentials, no lock,
// no real preferences touched. Metal layers are composited with the shared
// CompanionCapture.snapshot helper, the same offscreen technique the preview
// tests use.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Lock-screen scene at the tour media size (16:10), panel over photograph.
struct UnlockTourStage: View {
	static let width: CGFloat = 1320
	static let height: CGFloat = 825

	@Bindable var model: NotchCapsuleModel
	let background: NSImage

	var body: some View {
		ZStack(alignment: .top) {
			Image(nsImage: background)
				.resizable()
				.scaledToFill()
				.frame(width: Self.width, height: Self.height)
				.clipped()
			VStack(spacing: 0) {
				ZStack(alignment: .top) {
					// Production geometry, as in NotchPreviewCanvas.
					NotchCapsule(model: model, width: 278, height: 128, notchInset: 32, cutoutWidth: 180)
					UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9)
						.fill(.black)
						.frame(width: 180, height: 32)
				}
				Spacer(minLength: 0)
			}
			.frame(width: Self.width, height: Self.height)
		}
		.frame(width: Self.width, height: Self.height)
	}
}

@main
enum RenderUnlockTour {
	static let outputName = "tour-how-unlock.png"

	@MainActor static func main() throws {
		let args = CommandLine.arguments
		guard args.count == 3 else {
			throw UnlockTourError.usage("usage: RenderUnlockTour <Resources/Art dir> <work dir>")
		}
		let artDir = URL(fileURLWithPath: args[1], isDirectory: true)
		let workDir = URL(fileURLWithPath: args[2], isDirectory: true)
		try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

		let background = try croppedBackground(artDir: artDir)

		let model = NotchCapsuleModel()
		model.phase = .challenge(
			prompt: "Turn slightly left", symbol: "arrowshape.left.fill",
			hintX: -1, hintY: 0, pulses: false)
		model.isExpanded = true
		model.style = .normal
		model.shape = .attached
		model.glyphPlacement = .centred

		// Reduce Motion keeps the prompt static and the capture deterministic.
		let stage = UnlockTourStage(model: model, background: background)
			.frame(width: UnlockTourStage.width, height: UnlockTourStage.height)
			.environment(\.notchReduceMotion, true)

		let draft = workDir.appendingPathComponent("unlock-tour-draft.png")
		try CompanionCapture.snapshot(stage, to: draft) { surfaces in
			precondition(surfaces.count == 1, "tour scene must contain exactly one Metal face")
			precondition(
				surfaces[0].renderer.material == .charcoal,
				"tour companion must keep the charcoal material")
		}
		let output = artDir.appendingPathComponent(outputName)
		try normalize(draft: draft, to: output)
		print("wrote \(outputName) 1320x825")
	}

	/// lockscreen-base.png cropped to clock + wallpaper. CGImage cropping is
	/// top-left origin: drop the menu-bar strip, keep the clock band, drop
	/// everything from the account area down.
	static func croppedBackground(artDir: URL) throws -> NSImage {
		let url = artDir.appendingPathComponent("lockscreen-base.png")
		guard let source = NSImage(contentsOf: url) else {
			throw UnlockTourError.background("lockscreen-base.png unreadable")
		}
		var proposed = CGRect(origin: .zero, size: source.size)
		guard let cg = source.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
			throw UnlockTourError.background("lockscreen-base.png has no raster")
		}
		let keep = CGRect(
			x: 0, y: Int(Double(cg.height) * 0.05),
			width: cg.width, height: Int(Double(cg.height) * 0.57))
		guard let cropped = cg.cropping(to: keep) else {
			throw UnlockTourError.background("lockscreen-base.png crop failed")
		}
		return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
	}

	/// Snapshot pixels follow the host backing store, so re-encode to exactly
	/// 1320x825 and prove the dimensions before finishing.
	static func normalize(draft: URL, to output: URL) throws {
		guard let source = CGImageSourceCreateWithURL(draft as CFURL, nil),
			let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
		else { throw UnlockTourError.render("draft unreadable") }
		let width = 1320, height = 825
		// Frame the notch and clock closely enough for the prompt to remain readable
		// when TourKit displays this 2x asset at 660 points wide.
		guard let closeUp = image.cropping(to: CGRect(
			x: image.width / 4, y: 0, width: image.width / 2, height: image.height / 2))
		else { throw UnlockTourError.render("close-up crop unavailable") }
		guard
			let context = CGContext(
				data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
				space: CGColorSpace(name: CGColorSpace.sRGB)!,
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
		else { throw UnlockTourError.render("canvas unavailable") }
		context.interpolationQuality = .high
		context.draw(closeUp, in: CGRect(x: 0, y: 0, width: width, height: height))
		guard let final = context.makeImage(), final.width == width, final.height == height else {
			throw UnlockTourError.render("final is not 1320x825")
		}
		guard
			let destination = CGImageDestinationCreateWithURL(
				output as CFURL, UTType.png.identifier as CFString, 1, nil)
		else { throw UnlockTourError.write(outputName) }
		CGImageDestinationAddImage(destination, final, nil)
		guard CGImageDestinationFinalize(destination) else { throw UnlockTourError.write(outputName) }
	}
}

enum UnlockTourError: Error, LocalizedError {
	case usage(String)
	case background(String)
	case render(String)
	case write(String)
	var errorDescription: String? {
		switch self {
		case .usage(let message): return message
		case .background(let message): return "background: \(message)"
		case .render(let message): return "could not render \(message)"
		case .write(let name): return "could not write \(name)"
		}
	}
}
