// Tools/OnboardingArt/Generate.swift
//
// Deterministic offscreen artwork generator for tour/onboarding illustrations.
//
// It reuses the REAL companion renderer pieces, compiled verbatim (see run.sh):
//   Sources/Companion/GazeCompanionShader.swift    — the Metal face shader
//   Sources/Companion/GazeCompanionRenderer.swift  — SoftFaceGPU / SoftFaceUniforms
//   Sources/Companion/GazeCompanionView.swift       — companion view (compile dep)
//   Sources/Companion/GazeCompanionMotion.swift    — still + guidance poses
//   Sources/Companion/GazeRenderDiagnostics.swift  — renderer dependency
//   Sources/LockScreen/GazeFaceMark.swift          — GazeFaceMotion / GazeFacePose
// and the offscreen-texture technique from
//   Tools/GazePreview/Tests/CompanionCapture.swift (frame approach).
//
// Nothing here re-draws the Gaze character: every face tile is encoded through
// SoftFaceGPU.encode with SoftFaceUniforms, exactly as the app renders it.
// Only the compositing (canvas layout, monochrome SF Symbols, arrows) is new.
//
// No app launch, no camera, no screenshots, no network. Output is deterministic:
// fixed poses at fixed sample times; Metal output for fixed uniforms is stable.

import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

// MARK: - Phase stub (compile shim only)

// GazeFaceMark.swift references NotchCapsuleModel.Phase for its motion-from-phase
// mapping. The generator never exercises that path; this stub exists only so the
// real GazeFaceMark.swift compiles verbatim into this tool. Case list mirrors
// Sources/LockScreen/NotchCapsule.swift.
final class NotchCapsuleModel {
    enum Phase: Equatable {
        case locked
        case scanning
        case notRecognised
        case spoofRejected
        case challenge(prompt: String, symbol: String, hintX: CGFloat, hintY: CGFloat,
            pulses: Bool, isReturningToRest: Bool = false)
        case pending
        case success
        case unlocked
    }
}

// MARK: - Generator

@main
enum OnboardingArt {
    static let canvasWidth = 1440
    static let canvasHeight = 900
    static let faceMaterial = GazeCompanionMaterial.charcoal
    static let symbolOpacity: CGFloat = 0.62
    static let arrowOpacity: CGFloat = 0.50

    // The exact command that reproduces this run (also recorded in manifest.json).
    static let deterministicCommand = "./Tools/OnboardingArt/run.sh"

    static let sourcePaths = [
        "Tools/OnboardingArt/Generate.swift",
        "Sources/Companion/GazeCompanionShader.swift",
        "Sources/Companion/GazeCompanionMotion.swift",
        "Sources/Companion/GazeCompanionRenderer.swift",
        "Sources/Companion/GazeCompanionView.swift",
        "Sources/Companion/GazeRenderDiagnostics.swift",
        "Sources/LockScreen/GazeFaceMark.swift",
    ]

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3 else {
            throw GenerationError.usage("usage: OnboardingArtGenerate <Resources/Art dir> <work dir>")
        }
        let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
        let workDir = URL(fileURLWithPath: args[2], isDirectory: true)
        let root = outDir.deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let gpu = try SoftFaceGPU()

        var records: [(file: String, sha: String, width: Int, height: Int, note: String)] = []
        func emit(_ name: String, note: String, _ build: (CGContext) throws -> Void) throws {
            let context = newCanvas()
            try build(context)
            guard let image = context.makeImage() else { throw GenerationError.render(name) }
            let url = outDir.appendingPathComponent(name)
            try writePNG(image, to: url)
            let info = try verify(url: url, name: name)
            records.append((name, info.sha, info.width, info.height, note))
            print("wrote \(name) \(info.width)x\(info.height) sha256:\(info.sha)")
        }

        // -- Single-face cards: 360px native face centred at (720, 310). --
        let centre = CGPoint(x: 720, y: 310)
        try emit("onboarding-recognition.png", note: "resting pose, charcoal, 360px at (720,310)") {
            try placeFace($0, gpu: gpu, pose: GazeCompanionPose(), side: 360, centre: centre)
        }
        try emit("onboarding-success.png", note: "accepted stillPose (expression +1), charcoal, 360px at (720,310)") {
            try placeFace($0, gpu: gpu, pose: GazeCompanionPose(face: GazeFaceMotion.accepted.stillPose),
                side: 360, centre: centre)
        }
        try emit("onboarding-failure.png", note: "rejected stillPose (expression -1), charcoal, 360px at (720,310)") {
            try placeFace($0, gpu: gpu, pose: GazeCompanionPose(face: GazeFaceMotion.rejected.stillPose),
                side: 360, centre: centre)
        }

        // -- Two-subject cards. --
        try emit("onboarding-local.png", note: "resting face 320px at (560,310) + lock.fill ~150px at (880,310)") { ctx in
            try placeFace(ctx, gpu: gpu, pose: GazeCompanionPose(), side: 320, centre: CGPoint(x: 560, y: 310))
            try placeSymbol(ctx, name: "lock.fill", side: 150, centre: CGPoint(x: 880, y: 310),
                opacity: symbolOpacity)
        }
        try emit("onboarding-choice.png", note: "resting face 320px at (560,310) + key.fill ~150px at (880,310); no toggle") { ctx in
            try placeFace(ctx, gpu: gpu, pose: GazeCompanionPose(), side: 320, centre: CGPoint(x: 560, y: 310))
            try placeSymbol(ctx, name: "key.fill", side: 150, centre: CGPoint(x: 880, y: 310),
                opacity: symbolOpacity)
        }

        // -- Unlock sequence: camera -> face -> key. --
        try emit("onboarding-unlock.png",
            note: "camera.fill 130px at (330,300) -> resting face 300px at (720,300) -> key.fill 130px at (1110,300); arrow.right 56px connectors") { ctx in
            try placeSymbol(ctx, name: "camera.fill", side: 130, centre: CGPoint(x: 330, y: 300),
                opacity: symbolOpacity)
            try placeFace(ctx, gpu: gpu, pose: GazeCompanionPose(), side: 300, centre: CGPoint(x: 720, y: 300))
            try placeSymbol(ctx, name: "key.fill", side: 130, centre: CGPoint(x: 1110, y: 300),
                opacity: symbolOpacity)
            try placeSymbol(ctx, name: "arrow.right", side: 56, centre: CGPoint(x: 525, y: 300),
                opacity: arrowOpacity)
            try placeSymbol(ctx, name: "arrow.right", side: 56, centre: CGPoint(x: 915, y: 300),
                opacity: arrowOpacity)
        }

        // -- Movement cards: resting / peak motion / resting, 280px at x 330/720/1110, y 310. --
        let movements: [(file: String, motion: GazeFaceMotion, note: String)] = [
            ("movement-left.png", .turnLeft, "peak guidance pose for .turnLeft at t=1.35s"),
            ("movement-right.png", .turnRight, "peak guidance pose for .turnRight at t=1.35s"),
            ("movement-nod.png", .nod, "peak guidance pose for .nod at t=0.95s"),
            ("movement-blink.png", .blink, "peak guidance pose for .blink at t=0.95s"),
            ("movement-mouth.png", .openMouth, "peak guidance pose for .openMouth at t=1.35s"),
        ]
        for movement in movements {
            try emit(movement.file, note: "resting / \(movement.note) / resting; 280px at x 330/720/1110 y 310; arrow.right 48px connectors") { ctx in
                let mid = peakPose(movement.motion)
                try placeFace(ctx, gpu: gpu, pose: GazeCompanionPose(), side: 280,
                    centre: CGPoint(x: 330, y: 310))
                try placeFace(ctx, gpu: gpu, pose: mid, side: 280, centre: CGPoint(x: 720, y: 310))
                try placeFace(ctx, gpu: gpu, pose: GazeCompanionPose(), side: 280,
                    centre: CGPoint(x: 1110, y: 310))
                try placeSymbol(ctx, name: "arrow.right", side: 48, centre: CGPoint(x: 525, y: 310),
                    opacity: arrowOpacity)
                try placeSymbol(ctx, name: "arrow.right", side: 48, centre: CGPoint(x: 915, y: 310),
                    opacity: arrowOpacity)
            }
        }

        try writeContactSheet(workDir: workDir, artDir: outDir, records: records.map { ($0.file, $0.note) })
        try writeManifest(root: root, records: records)
        print("contact sheet: \(workDir.appendingPathComponent("contact-sheet.png").path)")
    }

    // MARK: - Poses (real motion API)

    /// Peak of the in-app guidance loop for an action-demonstrating motion, via the
    /// real GazeCompanionMotion.pose(for:at:). GazeCompanionTiming.guidance runs on a
    /// 3.2s loop; these sample times sit on the movement plateau so the illustrated
    /// direction matches what the app demonstrates.
    static func peakPose(_ motion: GazeFaceMotion) -> GazeCompanionPose {
        let time: Double
        switch motion {
        case .turnLeft, .turnRight, .openMouth: time = 1.35
        case .nod, .blink: time = 0.95
        default: return GazeCompanionPose(face: motion.stillPose)
        }
        return GazeCompanionMotion.pose(for: motion, at: time)
    }

    // MARK: - Face tiles (real renderer, offscreen)

    /// Mirrors the frame rendering approach in CompanionCapture.frame: encode one
    /// SoftFaceUniforms through the real pipeline into a transparent texture and
    /// read the bytes back as an image.
    static func faceTile(gpu: SoftFaceGPU, pose: GazeCompanionPose, side: Int,
        material: GazeCompanionMaterial = faceMaterial) throws -> CGImage {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: side, height: side, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        guard let texture = gpu.device.makeTexture(descriptor: descriptor),
            let command = gpu.queue.makeCommandBuffer() else { throw SoftFaceError.textureUnavailable }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        try gpu.encode(SoftFaceUniforms(pose: pose, size: CGSize(width: side, height: side),
            material: material), pass: pass, command: command)
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        texture.getBytes(&pixels, bytesPerRow: side * 4,
            from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
        // Orientation: render-target row 0 is the image BOTTOM, but CGImage row 0
        // is the TOP. Verified empirically — without this the mouth renders above
        // the eyes (the shader puts the mouth at local.y ≈ −0.475, below the
        // eyes at +0.158, and the on-screen MTKView path agrees). Flip rows so
        // the tile is upright in CGImage convention.
        let rowBytes = side * 4
        var upright = [UInt8](repeating: 0, count: pixels.count)
        for row in 0..<side {
            let source = row * rowBytes
            let destination = (side - 1 - row) * rowBytes
            upright.replaceSubrange(destination..<(destination + rowBytes),
                with: pixels[source..<(source + rowBytes)])
        }
        let provider = CGDataProvider(data: Data(upright) as CFData)!
        guard let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                .union(.byteOrder32Little),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw SoftFaceError.textureUnavailable }
        return image
    }

    // MARK: - Monochrome SF Symbols

    /// Native SF Symbol rasterised white at a restrained opacity. No decorative
    /// glyphs: only camera / lock / key / arrows.
    static func symbolTile(name: String, side: CGFloat, opacity: CGFloat) throws -> CGImage {
        // Rasterise large (4x the layout size) so the downscale into the canvas
        // stays crisp; `side` is advisory here, the exact layout size is applied
        // by placeSymbol preserving aspect ratio.
        let configuration = NSImage.SymbolConfiguration(pointSize: side * 4, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration),
            symbol.size.width > 0, symbol.size.height > 0 else {
            throw GenerationError.symbol(name)
        }
        var proposed = CGRect(origin: .zero, size: symbol.size)
        guard let rep = symbol.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw GenerationError.symbol(name)
        }
        // Recolour to white at the target opacity via a source-in fill.
        let width = rep.width, height = rep.height
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw GenerationError.symbol(name)
        }
        // The rep is upright in CGImage convention (row 0 = top); drawing it into
        // an unflipped context would flip it (classic Quartz gotcha — verified:
        // lock.fill's shackle landed at the bottom). Flip the tile context so the
        // tile stays upright.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(rep, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setBlendMode(.sourceIn)
        context.setFillColor(CGColor(gray: 1, alpha: opacity))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw GenerationError.symbol(name) }
        return image
    }

    // MARK: - Canvas

    /// Transparent 1440x900 canvas, flipped so layout uses top-left coordinates
    /// matching the brief (e.g. face centre (720, 310)).
    static func newCanvas() -> CGContext {
        let context = CGContext(data: nil, width: canvasWidth, height: canvasHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: CGFloat(canvasHeight))
        context.scaleBy(x: 1, y: -1)
        // Flip back for image drawing: CGImages drawn into the flipped context land
        // upright, matching the offscreen Metal texture orientation.
        context.interpolationQuality = .high
        return context
    }

    static func placeFace(_ context: CGContext, gpu: SoftFaceGPU, pose: GazeCompanionPose,
        side: CGFloat, centre: CGPoint) throws {
        let tile = try faceTile(gpu: gpu, pose: pose, side: Int(side.rounded()))
        context.draw(tile, in: CGRect(x: centre.x - side / 2, y: centre.y - side / 2,
            width: side, height: side))
    }

    static func placeSymbol(_ context: CGContext, name: String, side: CGFloat,
        centre: CGPoint, opacity: CGFloat) throws {
        let tile = try symbolTile(name: name, side: side, opacity: opacity)
        // Preserve the symbol's aspect ratio; `side` bounds the longer edge.
        let tileAspect = CGFloat(tile.width) / CGFloat(max(1, tile.height))
        let drawSize: CGSize
        if tileAspect >= 1 {
            drawSize = CGSize(width: side, height: side / tileAspect)
        } else {
            drawSize = CGSize(width: side * tileAspect, height: side)
        }
        context.draw(tile, in: CGRect(x: centre.x - drawSize.width / 2,
            y: centre.y - drawSize.height / 2, width: drawSize.width, height: drawSize.height))
    }

    // MARK: - Output

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
            UTType.png.identifier as CFString, 1, nil) else {
            throw GenerationError.write(url.lastPathComponent)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw GenerationError.write(url.lastPathComponent)
        }
    }

    struct VerifiedImage { let sha: String; let width: Int; let height: Int }

    /// Reload each PNG from disk and prove: 1440x900, non-empty alpha, and a
    /// fully transparent bottom strip (rows 680..<900 from top) so TourKit's
    /// bottom fade has nothing to cover.
    static func verify(url: URL, name: String) throws -> VerifiedImage {
        let data = try Data(contentsOf: url)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw GenerationError.verify("\(name): unreadable")
        }
        guard image.width == canvasWidth, image.height == canvasHeight else {
            throw GenerationError.verify("\(name): \(image.width)x\(image.height)")
        }
        guard let providerData = image.dataProvider?.data as Data? else {
            throw GenerationError.verify("\(name): no pixels")
        }
        let bytes = [UInt8](providerData)
        let alphaInfo = image.alphaInfo
        let hasAlpha = alphaInfo == .premultipliedLast || alphaInfo == .premultipliedFirst
            || alphaInfo == .last || alphaInfo == .first
        guard hasAlpha, bytes.count == canvasWidth * canvasHeight * 4 else {
            throw GenerationError.verify("\(name): no alpha channel")
        }
        let alphaOffset = (alphaInfo == .premultipliedLast || alphaInfo == .last) ? 3 : 0
        var lit = 0
        for index in stride(from: alphaOffset, to: bytes.count, by: 4) {
            if bytes[index] > 0 { lit += 1 }
        }
        guard lit > 0 else { throw GenerationError.verify("\(name): fully transparent") }
        // Bottom strip: pixel rows 680..<900 (CGImage pixel space runs top-down
        // for these files, matching the canvas layout).
        let stripStart = 680 * canvasWidth * 4 + alphaOffset
        for index in stride(from: stripStart, to: bytes.count, by: 4) {
            if bytes[index] > 0 {
                throw GenerationError.verify("\(name): bottom strip not transparent")
            }
        }
        return VerifiedImage(sha: sha, width: image.width, height: image.height)
    }

    // MARK: - Contact sheet (inspection aid, ignored build output)

    static func writeContactSheet(workDir: URL, artDir: URL, records: [(file: String, note: String)]) throws {
        let thumbScale: CGFloat = 0.32
        let thumbWidth = CGFloat(canvasWidth) * thumbScale
        let thumbHeight = CGFloat(canvasHeight) * thumbScale
        let labelHeight: CGFloat = 44
        let columns = 3
        let rows = (records.count + columns - 1) / columns
        let sheetWidth = Int((CGFloat(columns) * thumbWidth).rounded())
        let sheetHeight = Int((CGFloat(rows) * (thumbHeight + labelHeight)).rounded())
        guard let context = CGContext(data: nil, width: sheetWidth, height: sheetHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw GenerationError.write("contact-sheet.png")
        }
        context.setFillColor(CGColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))
        context.interpolationQuality = .high
        let font = NSFont.systemFont(ofSize: 17)
        let cellHeight = thumbHeight + labelHeight
        for (index, record) in records.enumerated() {
            // Rows run top-down so thumbnails sit under the same label row as
            // their record. (CG origin is bottom-left: cellBottom is the cell's
            // low edge; the label sits above the thumb within the cell.)
            let column = index % columns
            let row = index / columns
            let cellBottom = CGFloat(sheetHeight) - CGFloat(row + 1) * cellHeight
            let originX = CGFloat(column) * thumbWidth
            if let source = CGImageSourceCreateWithURL(
                artDir.appendingPathComponent(record.file) as CFURL, nil),
                let thumb = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                context.draw(thumb, in: CGRect(x: originX, y: cellBottom,
                    width: thumbWidth, height: thumbHeight))
            }
            let label = "\(record.file)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: NSColor(white: 0.88, alpha: 1),
            ]
            NSGraphicsContext.saveGraphicsState()
            let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.current = nsContext
            // Label above its thumb: convert the cell's top-down position into
            // bottom-left coordinates for the non-flipped drawing context.
            label.draw(in: CGRect(x: originX + 8,
                y: cellBottom + thumbHeight + 10,
                width: thumbWidth - 16, height: 24), withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let image = context.makeImage() else { throw GenerationError.write("contact-sheet.png") }
        try writePNG(image, to: workDir.appendingPathComponent("contact-sheet.png"))
    }

    // MARK: - Manifest

    static func writeManifest(root: URL,
        records: [(file: String, sha: String, width: Int, height: Int, note: String)]) throws {
        var sources: [[String: String]] = []
        for path in sourcePaths {
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            sources.append(["path": path, "sha256": sha])
        }
        let assets = records.map { record in
            ["file": record.file, "sha256": record.sha,
                "dimensions": "\(record.width)x\(record.height)", "pose": record.note]
        }
        let manifest: [String: Any] = [
            "generator": "Tools/OnboardingArt/Generate.swift",
            "command": deterministicCommand,
            "canvas": "\(canvasWidth)x\(canvasHeight) RGBA, transparent",
            "faceMaterial": "charcoal (GazeCompanionMaterial.charcoal via SoftFaceUniforms)",
            "symbols": [
                "camera.fill, lock.fill, key.fill, arrow.right: native SF Symbols, white",
                "subject opacity 0.62, connector-arrow opacity 0.50",
            ],
            "sources": sources,
            "assets": assets,
            "disclaimer": "Instructional illustrations rendered from app code, not recordings or proof of a real face check.",
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("Tools/OnboardingArt/manifest.json"))
    }
}

enum GenerationError: Error, LocalizedError {
    case usage(String)
    case render(String)
    case symbol(String)
    case write(String)
    case verify(String)
    var errorDescription: String? {
        switch self {
        case .usage(let message): return message
        case .render(let name): return "could not render \(name)"
        case .symbol(let name): return "SF Symbol unavailable: \(name)"
        case .write(let name): return "could not write \(name)"
        case .verify(let name): return "verification failed: \(name)"
        }
    }
}