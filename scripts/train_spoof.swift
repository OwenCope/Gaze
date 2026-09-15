// Trains a face-spoof OBJECT DETECTOR with CreateML and writes a standalone .mlmodel.
//
// Input: a Roboflow "CreateML JSON" export — a folder with train/ valid/ test/ subfolders,
// each holding the images plus a `_annotations.createml.json`. The detector learns to box
// the spoof cues in frame (a phone, a screen bezel, a held photo) rather than judge texture,
// so it catches the "held device" attack the passive model can't.
//
// Run:
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
//     xcrun swift scripts/train_spoof.swift <dataset-dir> [out.mlmodel]
//
// Then drop the result at Resources/Spoof.mlmodelc (or .mlpackage) and rebuild.

import CreateML
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
	FileHandle.standardError.write(Data("usage: train_spoof.swift <dataset-dir> [out.mlmodel]\n".utf8))
	exit(2)
}

let base = URL(fileURLWithPath: args[1], isDirectory: true)
let outURL = URL(fileURLWithPath: args.count >= 3 ? args[2] : "Spoof.mlmodel")

// Roboflow's CreateML export drops a `_annotations.createml.json` in each split folder;
// `.directoryWithImagesAndJsonAnnotation` picks it up automatically.
func ds(_ split: String) -> MLObjectDetector.DataSource {
	.directoryWithImagesAndJsonAnnotation(at: base.appendingPathComponent(split))
}

print("→ Training object detector from \(base.appendingPathComponent("train").path)")
print("  (transfer learning — minutes, not the multi-hour full-network run)")
// Transfer learning on Apple's ObjectPrint extractor: fast, compact, on-device friendly —
// the darknet full-network default took hours and got killed overnight. Validate on the
// real valid/ split. `.boundingBox()` defaults match Roboflow's CreateML JSON convention.
// maxIterations via env (SPOOF_ITERS) so a quick subset run can cap it; nil = CreateML default.
let iters = ProcessInfo.processInfo.environment["SPOOF_ITERS"].flatMap { Int($0) }
let params = MLObjectDetector.ModelParameters(
	validation: .dataSource(ds("valid")),
	maxIterations: iters,
	algorithm: .transferLearning(.objectPrint(revision: 1)))
let model = try MLObjectDetector(
	trainingData: ds("train"), parameters: params, annotationType: .boundingBox())

// Validation mAP, if the split exists — tells us whether it's worth shipping before we do.
let validDir = base.appendingPathComponent("valid")
if FileManager.default.fileExists(atPath: validDir.path) {
	let metrics = model.evaluation(on: ds("valid"))
	print("→ Validation metrics:\n\(metrics)")
}

let meta = MLModelMetadata(
	author: "Gaze",
	shortDescription: "Face-spoof object detector (Roboflow Face Spoof Detection, CC BY 4.0).",
	version: "1.0")
try model.write(to: outURL, metadata: meta)
print("✓ Wrote \(outURL.path)")
