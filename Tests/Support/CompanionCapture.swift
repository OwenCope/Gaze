import AppKit
import MetalKit
import SwiftUI

@MainActor
enum CompanionCapture {
	struct Surface {
		let view: MTKView
		let renderer: GazeCompanionRenderer.Coordinator
	}

	static func surfaces(in view: NSView) -> [Surface] {
		if let metal = view as? MTKView, let renderer = metal.delegate as? GazeCompanionRenderer.Coordinator {
			return [Surface(view: metal, renderer: renderer)]
		}
		return view.subviews.flatMap { surfaces(in: $0) }
	}

	static func frame(gpu: SoftFaceGPU, pose: GazeCompanionPose, size: CGSize,
		material: GazeCompanionMaterial, opacity: Float? = nil) throws -> NSImage {
		let width = max(1, Int(size.width.rounded()))
		let height = max(1, Int(size.height.rounded()))
		let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
		descriptor.usage = [.renderTarget]
		descriptor.storageMode = .shared
		guard let texture = gpu.device.makeTexture(descriptor: descriptor), let command = gpu.queue.makeCommandBuffer() else { throw SoftFaceError.textureUnavailable }
		let pass = MTLRenderPassDescriptor()
		pass.colorAttachments[0].texture = texture
		pass.colorAttachments[0].loadAction = .clear
		pass.colorAttachments[0].storeAction = .store
		try gpu.encode(SoftFaceUniforms(pose: pose, size: size, opacity: opacity ?? (material == .pearl ? 0.82 : 0.68), material: material), pass: pass, command: command)
		command.commit()
		command.waitUntilCompleted()
		if let error = command.error { throw error }
		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
		let provider = CGDataProvider(data: Data(pixels) as CFData)!
		let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
			space: CGColorSpace(name: CGColorSpace.sRGB)!,
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
			provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
		return NSImage(cgImage: image, size: size)
	}

	static func snapshot<Content: View>(_ content: Content, to url: URL, sampleOffset: Double = 0,
		inspect: (([Surface]) -> Void)? = nil) throws {
		let host = NSHostingView(rootView: content)
		host.frame = CGRect(origin: .zero, size: host.fittingSize)
		let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
		window.contentView = host
		host.layoutSubtreeIfNeeded()
		RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.06))
		host.layoutSubtreeIfNeeded()
		let surfaces = surfaces(in: host)
		inspect?(surfaces)
		guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds),
			let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw SoftFaceError.textureUnavailable }
		host.cacheDisplay(in: host.bounds, to: bitmap)
		NSGraphicsContext.saveGraphicsState()
		defer { NSGraphicsContext.restoreGraphicsState() }
		NSGraphicsContext.current = context
		let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
		for surface in surfaces {
			guard let gpu = surface.renderer.gpu, let sample = surface.renderer.pose else { throw SoftFaceError.unavailable }
			var rect = surface.view.convert(surface.view.bounds, to: host)
			if host.isFlipped { rect.origin.y = host.bounds.height - rect.maxY }
			let image = try frame(gpu: gpu, pose: sample(Date.timeIntervalSinceReferenceDate + sampleOffset),
				size: CGSize(width: rect.width * scale, height: rect.height * scale),
				material: surface.renderer.material, opacity: surface.renderer.opacity)
			image.draw(in: rect)
		}
		guard let png = bitmap.representation(using: .png, properties: [:]) else { throw SoftFaceError.textureUnavailable }
		try png.write(to: url)
		window.contentView = nil
	}
}
