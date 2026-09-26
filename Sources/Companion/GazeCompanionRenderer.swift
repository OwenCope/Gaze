import AppKit
import MetalKit
import SwiftUI

struct SoftFaceUniforms {
	var pose: SIMD4<Float>
	var expression: SIMD4<Float>
	var transform: SIMD4<Float>
	var viewport: SIMD4<Float>

	init(pose: GazeCompanionPose, size: CGSize, angle: Double = 0, opacity: Float = 0.68, material: GazeCompanionMaterial = .charcoal) {
		self.pose = SIMD4(Float(pose.face.turn), Float(pose.face.nod), Float(pose.face.eyesOpen), Float(pose.face.mouthOpen))
		expression = SIMD4(Float(pose.face.expression), Float(pose.face.gaze), material == .pearl ? 1 : 0, material == .ink ? 0.48 : 1)
		transform = SIMD4(Float(pose.roll), Float(pose.stretch), Float(pose.lift), Float(pose.drift))
		viewport = SIMD4(Float(size.width), Float(size.height), Float(angle), opacity)
	}
}

enum SoftFaceError: LocalizedError {
	case unavailable, shaderMissing, textureUnavailable, commandUnavailable
	var errorDescription: String? {
		switch self {
		case .unavailable: "Metal is unavailable on this Mac."
		case .shaderMissing: "The 3D face shader could not be loaded."
		case .textureUnavailable: "The 3D render target could not be created."
		case .commandUnavailable: "The 3D frame could not be submitted."
		}
	}
}

final class SoftFaceGPU {
	let device: MTLDevice
	let queue: MTLCommandQueue
	let pipeline: MTLRenderPipelineState
	@MainActor private static var cached: SoftFaceGPU?

	@MainActor static func shared() throws -> SoftFaceGPU {
		if let cached { return cached }
		let gpu = try SoftFaceGPU()
		cached = gpu
		return gpu
	}

	init() throws {
		guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw SoftFaceError.unavailable }
		self.device = device
		self.queue = queue
		let library = try device.makeLibrary(source: GazeCompanionShader.source, options: nil)
		guard let vertex = library.makeFunction(name: "faceVertex"), let fragment = library.makeFunction(name: "faceFragment") else { throw SoftFaceError.shaderMissing }
		let descriptor = MTLRenderPipelineDescriptor()
		descriptor.vertexFunction = vertex
		descriptor.fragmentFunction = fragment
		descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
		pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
	}

	func encode(_ uniforms: SoftFaceUniforms, pass: MTLRenderPassDescriptor, command: MTLCommandBuffer) throws {
		guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw SoftFaceError.commandUnavailable }
		var uniforms = uniforms
		encoder.setRenderPipelineState(pipeline)
		encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SoftFaceUniforms>.stride, index: 0)
		encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
		encoder.endEncoding()
	}
}

class TransparentFaceView: MTKView {
	override var isOpaque: Bool { false }
	var wantsContinuousRendering = false {
		didSet {
			guard wantsContinuousRendering != oldValue else { return }
			updateRenderingState()
		}
	}

	private func updateRenderingState() {
		let paused = !wantsContinuousRendering || window == nil
		if isPaused != paused { isPaused = paused }
		if enableSetNeedsDisplay != paused { enableSetNeedsDisplay = paused }
		if window != nil && isPaused { needsDisplay = true }
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		matchBackingScale()
		updateRenderingState()
	}

	/// MTKView sizes its drawable as bounds × `layer.contentsScale`. The layer is
	/// created in `makeNSView`, before the view has a window, so its scale starts at
	/// 1 — and on the borderless lock-screen window it was never raised, which drew
	/// the companion at half resolution and let the compositor upscale it.
	private func matchBackingScale() {
		guard let scale = window?.backingScaleFactor, layer?.contentsScale != scale else { return }
		layer?.contentsScale = scale
		needsDisplay = true
	}

	override func layout() {
		super.layout()
		if isPaused { needsDisplay = true }
	}

	override func viewDidChangeBackingProperties() {
		super.viewDidChangeBackingProperties()
		matchBackingScale()
		if isPaused { needsDisplay = true }
	}
}

@MainActor
struct GazeCompanionRenderer: NSViewRepresentable {
	let pose: (TimeInterval) -> GazeCompanionPose
	let running: Bool
	var revision = 0
	var angle = 0.0
	var material = GazeCompanionMaterial.charcoal
	var opacity: Float = 0.68
	var report: ((String) -> Void)?
	var diagnosticContext = "preview"
	var failure: (String) -> Void

	func makeCoordinator() -> Coordinator { Coordinator() }

	func makeNSView(context: Context) -> MTKView {
		let view = TransparentFaceView()
		view.wantsLayer = true
		view.layer?.isOpaque = false
		view.colorPixelFormat = .bgra8Unorm
		view.framebufferOnly = true
		view.clearColor = MTLClearColorMake(0, 0, 0, 0)
		view.enableSetNeedsDisplay = true
		view.isPaused = true
		// The display's own rate, up to 120 on ProMotion. At 30 the face visibly stepped
		// next to everything else on screen animating at 60 or 120.
		view.preferredFramesPerSecond = min(120, max(60, NSScreen.main?.maximumFramesPerSecond ?? 60))
		view.setAccessibilityElement(false)
		do {
			context.coordinator.gpu = try SoftFaceGPU.shared()
			view.device = context.coordinator.gpu?.device
			view.delegate = context.coordinator
		} catch {
			Task { @MainActor in failure(error.localizedDescription) }
		}
		return view
	}

	func updateNSView(_ view: MTKView, context: Context) {
		let coordinator = context.coordinator
		coordinator.pose = pose
		coordinator.angle = angle
		coordinator.material = material
		coordinator.opacity = opacity
		coordinator.report = report
		coordinator.failure = failure
		if GazeRenderDiagnostics.enabled && running {
			if coordinator.diagnostics == nil || coordinator.diagnosticContext != diagnosticContext {
				coordinator.finishDiagnostics(in: view, reason: "contextChanged")
				coordinator.diagnostics = GazeRenderDiagnostics()
			}
		} else {
			coordinator.finishDiagnostics(in: view, reason: "paused")
			coordinator.diagnostics = nil
		}
		coordinator.diagnosticContext = diagnosticContext
		if coordinator.revision != revision {
			coordinator.revision = revision
			coordinator.frameTimes = []
		}
		(view as? TransparentFaceView)?.wantsContinuousRendering = running
		if !running {
			view.needsDisplay = true
			if view.window != nil { view.draw() }
		}
	}

	static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
		coordinator.finishDiagnostics(in: view, reason: "removed")
		view.isPaused = true
		view.delegate = nil
		coordinator.pose = nil
	}

	@MainActor
	final class Coordinator: NSObject, MTKViewDelegate {
		var gpu: SoftFaceGPU?
		var pose: ((TimeInterval) -> GazeCompanionPose)?
		var angle = 0.0
		var material = GazeCompanionMaterial.charcoal
		var opacity: Float = 0.68
		var report: ((String) -> Void)?
		var failure: ((String) -> Void)?
		var revision = -1
		var frameTimes: [Double] = []
		var diagnostics: GazeRenderDiagnostics?
		var diagnosticContext = "preview"
		let frameBudget = DispatchSemaphore(value: 2)
		private var lastReport = 0.0

		func finishDiagnostics(in view: MTKView, reason: String) {
			if let summary = diagnostics?.finish() {
				GazeRenderDiagnostics.log(summary, context: diagnosticContext,
					windowVisible: view.window?.occlusionState.contains(.visible) == true, reason: reason)
			}
		}

		func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
			if view.isPaused { view.needsDisplay = true }
		}

		func draw(in view: MTKView) {
			let diagnosticStart = diagnostics != nil && !view.isPaused ? CACurrentMediaTime() : nil
			var outcome = GazeRenderDiagnostics.Outcome.unavailable
			var drawableSeconds = 0.0
			defer {
				if let diagnosticStart,
					let summary = diagnostics?.record(start: diagnosticStart, end: CACurrentMediaTime(), outcome: outcome,
						drawableSeconds: drawableSeconds) {
					GazeRenderDiagnostics.log(summary, context: diagnosticContext,
						windowVisible: view.window?.occlusionState.contains(.visible) == true)
				}
			}
			guard frameBudget.wait(timeout: .now()) == .success else {
				outcome = .busy
				return
			}
			let budget = frameBudget
			guard let gpu, let pose else { budget.signal(); return }
			let drawableStart = diagnosticStart != nil ? CACurrentMediaTime() : nil
			let currentDrawable = view.currentDrawable
			if let drawableStart { drawableSeconds = CACurrentMediaTime() - drawableStart }
			guard let drawable = currentDrawable,
				let pass = view.currentRenderPassDescriptor, let command = gpu.queue.makeCommandBuffer() else {
				budget.signal()
				return
			}
			let time = Date.timeIntervalSinceReferenceDate
			let uniforms = SoftFaceUniforms(pose: pose(time), size: view.drawableSize, angle: angle, opacity: opacity, material: material)
			do { try gpu.encode(uniforms, pass: pass, command: command) }
			catch {
				outcome = .failed
				budget.signal()
				view.isPaused = true
				let message = error.localizedDescription
				Task { @MainActor [weak self] in self?.failure?(message) }
				return
			}
			command.addCompletedHandler { _ in budget.signal() }
			command.present(drawable)
			command.commit()
			outcome = .submitted
			if !view.isPaused, report != nil {
				frameTimes.append(CACurrentMediaTime())
				if frameTimes.count > 240 { frameTimes.removeFirst(frameTimes.count - 240) }
				if time - lastReport > 1, frameTimes.count > 30 {
					lastReport = time
					let intervals = zip(frameTimes.dropFirst(), frameTimes).map { $0 - $1 }.sorted()
					let fps = Double(intervals.count) / intervals.reduce(0, +)
					let percentile = intervals[min(intervals.count - 1, Int(Double(intervals.count) * 0.95))] * 1000
					let text = String(format: "%.0f fps · p95 %.1f ms · render callbacks", fps, percentile)
					Task { @MainActor [weak self] in self?.report?(text) }
				}
			}
		}
	}
}
