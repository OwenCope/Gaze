import AVFoundation
import AppKit
import SwiftUI

/// Hosts the live capture preview.
struct CameraPreview: NSViewRepresentable {

	let controller: CameraController

	func makeNSView(context: Context) -> PreviewView {
		let view = PreviewView()
		view.attach(controller.previewLayer())
		return view
	}

	func updateNSView(_ view: PreviewView, context: Context) {}

	final class PreviewView: NSView {
		private var preview: AVCaptureVideoPreviewLayer?

		override init(frame: NSRect) {
			super.init(frame: frame)
			// Order matters for a layer-hosting view: assign the backing layer first,
			// then opt in. Doing it the other way round leaves AppKit owning a layer we
			// then replace, and the preview renders black.
			layer = CALayer()
			wantsLayer = true
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) { fatalError() }

		func attach(_ preview: AVCaptureVideoPreviewLayer) {
			self.preview?.removeFromSuperlayer()
			// The camera image is what the camera sees, not what a mirror would; people
			// expect a mirror when looking at themselves, so flip it horizontally.
			preview.transform = CATransform3DMakeScale(-1, 1, 1)
			layer?.addSublayer(preview)
			self.preview = preview
			layoutPreview()
		}

		override func layout() {
			super.layout()
			layoutPreview()
		}

		private func layoutPreview() {
			CATransaction.begin()
			CATransaction.setDisableActions(true)
			preview?.frame = bounds
			CATransaction.commit()
		}
	}
}
