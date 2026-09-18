import AppKit
import Foundation

@main enum MovementMovie {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let gpu = try SoftFaceGPU()
        let motions: [GazeFaceMotion] = [.turnLeft, .turnRight, .nod, .blink, .openMouth]
        for (index, motion) in motions.enumerated() {
            for frame in 0..<192 {
                let context = CGContext(data: nil, width: 900, height: 560, bitsPerComponent: 8,
                    bytesPerRow: 3600, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.setFillColor(CGColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 900, height: 560))
                // faceTile corrects Metal's readback orientation; this is the same
                // app renderer and guidance sampler used by the live movement guide.
                let pose = GazeCompanionPresentation.standard.pose(for: motion, at: Double(frame) / 60)
                let tile = try OnboardingArt.faceTile(gpu: gpu, pose: pose, side: 360)
                context.translateBy(x: 0, y: 560)
                context.scaleBy(x: 1, y: -1)
                context.draw(tile, in: CGRect(x: 270, y: 100, width: 360, height: 360))
                let image = NSBitmapImageRep(cgImage: context.makeImage()!)
                try image.representation(using: .png, properties: [:])!
                    .write(to: output.appendingPathComponent(String(format: "%05d.png", index * 192 + frame)))
            }
            print("Rendered \(motion): 192 frames at 60 fps")
        }
    }
}
