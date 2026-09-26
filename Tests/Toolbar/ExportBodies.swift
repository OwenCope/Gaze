import AppKit
import Metal

@main
struct ExportBodies {
	static func main() throws {
		guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
			throw NSError(domain: "Gaze.ToolbarAssets", code: 1)
		}
		let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		for white in [false, true] {
			var source = GazeCompanionShader.source
			for (original, replacement) in [
				("float feature = max(eyes, smile) * front;", "float feature = 0;"),
				("encoded += glow;", "encoded += 0;"),
				("float shellAlpha = clamp(uniforms.viewport.w + rim * 0.16, 0.0, 1.0);", "float shellAlpha = 1;"),
				("return float4(encoded * alpha, alpha);", white
					? "return float4((float3(0.80) + encoded * 0.50) * alpha, alpha);"
					: "return float4(encoded * alpha, alpha);")
			] {
				precondition(source.contains(original), "Companion shader changed; review the toolbar export")
				source = source.replacingOccurrences(of: original, with: replacement)
			}
			let library = try device.makeLibrary(source: source, options: nil)
			let pipeline = MTLRenderPipelineDescriptor()
			pipeline.vertexFunction = library.makeFunction(name: "faceVertex")
			pipeline.fragmentFunction = library.makeFunction(name: "faceFragment")
			pipeline.colorAttachments[0].pixelFormat = .bgra8Unorm
			let state = try device.makeRenderPipelineState(descriptor: pipeline)
			let size = 144
			let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
			descriptor.usage = [.renderTarget]
			descriptor.storageMode = .shared
			guard let texture = device.makeTexture(descriptor: descriptor), let command = queue.makeCommandBuffer() else {
				throw NSError(domain: "Gaze.ToolbarAssets", code: 2)
			}
			let pass = MTLRenderPassDescriptor()
			pass.colorAttachments[0].texture = texture
			pass.colorAttachments[0].loadAction = .clear
			pass.colorAttachments[0].storeAction = .store
			guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
				throw NSError(domain: "Gaze.ToolbarAssets", code: 3)
			}
			let uniforms: [SIMD4<Float>] = [.init(0, 0, 1, 0), .zero, .zero, .init(Float(size), Float(size), 0, 1)]
			encoder.setRenderPipelineState(state)
			uniforms.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
			encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
			encoder.endEncoding()
			command.commit()
			command.waitUntilCompleted()
			if let error = command.error { throw error }
			var pixels = [UInt8](repeating: 0, count: size * size * 4)
			texture.getBytes(&pixels, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
			let provider = CGDataProvider(data: Data(pixels) as CFData)!
			let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
				space: CGColorSpace(name: CGColorSpace.sRGB)!,
				bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
				provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
			let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
			try png.write(to: directory.appendingPathComponent(white ? "gaze-toolbar-white.png" : "gaze-toolbar-black.png"))
		}
	}
}
