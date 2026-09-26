# Gaze recognition model: InsightFace evidence (2026-09-23)

Conclusion: `Resources/FaceEmbedding.mlmodelc` is InsightFace **buffalo_l `w600k_r50.onnx`**
(ResNet-50 trained on WebFace600K), converted to Core ML in fp16. Certainty: conclusive —
exact operator-count match plus cosine > 0.997 against the official ONNX weights on three
inputs. Licence: the weights are **non-commercial research only** per InsightFace; a free
public app shipping them needs InsightFace's permission (contact below) or a replacement
model. This file is the evidence; it gives facts, not legal advice.

## 1. Model interface (from source)

`Sources/Recognition/FaceEmbedder.swift` (`CoreMLEmbedder`):

- Input: one multi-array feature, planar `[1, 3, S, S]`; side `S` read from the model shape.
- Preprocessing (`tensor(from:side:)`): BGRA crop to RGB planes, `(x - 127.5) / 128.0`.
  Note the divisor is 128.0, where InsightFace's standard preprocessing divides by 127.5.
  The comparison below feeds byte-identical tensors to both runtimes, so this nuance does
  not affect the weight-equality test.
- Output: first multi-array feature (512-d), L2-normalised; cosine similarity, threshold 0.45.

`Sources/Recognition/FaceAligner.swift`: pupils warped to ArcFace reference points
(38.29, 51.69) / (73.53, 51.69) in a 112x112 frame. Input side is therefore 112.

Compiled-model metadata (`FaceEmbedding.mlmodelc/metadata.json`) confirms:
input `input_1` MultiArray Float32 `[1, 3, 112, 112]`, output `var_1110` `[1, 512]`,
storage fp16 (`"storagePrecision": "Float16"`), converted with coremltools 9.0 from
TorchScript (`torch==2.8.0`) on 2026-06-27, generated class name `ArcFace`.

## 2. Files, hashes, sizes

| File | Size (bytes) | SHA-256 |
| --- | --- | --- |
| `Resources/FaceEmbedding.mlmodelc/weights/weight.bin` | 87,197,184 | `c28620613d146a56565eadaacc22bbe9dd54533000ba79a6d666995a123c1545` |
| `buffalo_l.zip` (official release, see URL below) | 288,621,354 | `80ffe37d8a5940d59a7384c201a2a38d4741f2f3c51eef46ebb28218a7b0ca2f` |
| `w600k_r50.onnx` (extracted from that zip) | 174,383,860 | `4c06341c33c2ca1f86781dab0e829f88ad5b64be9fba56e56bc9ebdefc619e43` |
| `w600k_mbf.onnx` (buffalo_s; HF mirror, hash-verified §5) | 13,616,099 | `9cc6e4a75f0e2bf0b1aed94578f144d15175f357bdc05e815e5c4a02b319eb4f` |

Size check: 174,383,860 / 2 = 87,191,930, within ~5 KB of the 87,197,184-byte Core ML
weight file — exactly what a full fp32-to-fp16 conversion of `w600k_r50` looks like
(~43.6M parameters).

## 3. Architecture: exact operator-count match

ONNX graph of `w600k_r50.onnx` (input `input.1` `[?, 3, 112, 112]`, output `683` `[1, 512]`):

- 130 nodes: Conv 53, PRelu 25, BatchNormalization 26, Add 24, Flatten 1, Gemm 1.

`FaceEmbedding.mlmodelc/metadata.json` (`mlProgramOperationTypeHistogram`):

- Conv 53, Prelu 25, BatchNorm 26, Add 24, Linear 1 (= the Gemm), plus Cast/Reshape/
  ExpandDims/Squeeze bookkeeping from the conversion.

Every structural operator count matches exactly. A 53-convolution ResNet-50 with PReLU
is the InsightFace IResNet-50; it is not MobileFaceNet (which uses depthwise
convolutions and has roughly half the conv count).

## 4. Embedding comparison (weight-equality test)

Method: three 112x112 RGB inputs (synthetic face-like image, uniform random noise,
linear gradient), preprocessed byte-identically as Gaze does (`(x-127.5)/128.0`, RGB
planar, batch of 1). Reference embeddings from `w600k_r50.onnx` via onnxruntime 1.19.2
(CPU); Gaze embeddings from `FaceEmbedding.mlmodelc` via `CompiledMLModel`
(coremltools 9.0). Both L2-normalised, cosine similarity reported. Match bar: > 0.99
on every input; residual short of 1.0 is fp16 quantisation plus Core ML mixed-precision
compute.

| Input | cosine(Gaze mlmodelc, w600k_r50.onnx) |
| --- | --- |
| synthetic face | 0.998683 |
| random noise | 0.997173 |
| gradient | 0.998531 |

All three clear the bar, including random noise (which rules out "similar because all
face embeddings look alike"). The bundled model is `w600k_r50` in fp16.

Reproduction (venv under /tmp, never in the repo):

```bash
python3 -m venv /tmp/mc && /tmp/mc/bin/pip install coremltools onnxruntime numpy pillow onnx
curl -sL -o /tmp/models/buffalo_l.zip \
  https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip
unzip -o -j /tmp/models/buffalo_l.zip w600k_r50.onnx -d /tmp/models/
# build the three inputs, preprocess as Sources/Recognition/FaceEmbedder.swift does,
# compare onnxruntime output against CompiledMLModel prediction after L2 normalisation
```

## 5. Glance cross-check (MobileFaceNet hypothesis) — confirmed

Glance (`/tmp/glance`, MIT) ships `glance/Models/ArcFace.mlpackage` (weight.bin
6,825,280 bytes; image input `input_image` 112x112 RGB, multi-array output `embedding`).
Its own toolchain states the lineage outright: `tools/convert_arcface.py` converts
InsightFace `w600k_mbf.onnx` ("buffalo_s pack, ~13MB, MobileFaceNet backbone") via
ONNX -> torch -> TorchScript -> Core ML fp16 with `(px-127.5)/127.5` preprocessing
baked in, and `glance/ArcFaceEmbedder.swift` names the model `"ArcFace (w600k_mbf)"`.
Glance's README credits "InsightFace — the ArcFace model doing the recognition."

Numeric check (same three inputs; ONNX side preprocessed `(x-127.5)/127.5`, Core ML side
given the raw image so its baked-in scale/bias applies; mlpackage compiled with Xcode
`coremlc` since coremltools cannot predict from an `.mlpackage` directly):

| Input | cosine(Glance ArcFace, w600k_mbf.onnx) |
| --- | --- |
| synthetic face | 0.999837 |
| random noise | 0.999941 |
| gradient | 0.998587 |

Negative control (rules out "everything matches everything"):

| Input | cosine(Gaze mlmodelc [r50], w600k_mbf.onnx) |
| --- | --- |
| synthetic face | 0.049764 |
| random noise | 0.012595 |
| gradient | 0.036581 |

Architecture: `w600k_mbf.onnx` has 98 nodes (Conv 49, PRelu 34, Add 12, BatchNorm 1,
Flatten 1, Gemm 1) — MobileFaceNet, not ResNet. The compiled Glance histogram agrees
(conv 49, prelu 34; batch-norm mostly folded, plus one mul from the baked-in input
scaling). Weight-scale check: 13,616,099-byte fp32 halves to ~6.8 MB in fp16, exactly
Glance's 6,825,280-byte weight file.

File integrity: `w600k_mbf.onnx` SHA-256 `9cc6e4a75f0e2bf0b1aed94578f144d15175f357bdc05e815e5c4a02b319eb4f`,
which matches the hash pinned in InsightFace's own server code
(`server/backend/insightface_server/models/packages.py`) and independently in
PhotoPrism's `internal/ai/face/models.go` (which tags it `LicenseNonFree`). Downloaded
via the deepghs HuggingFace mirror (fast CDN); hash verified, so the bytes are the
official file however they were fetched.

## 6. Licence (quoted verbatim, accessed 2026-09-23)

InsightFace README, `## License` (https://github.com/deepinsight/insightface#license):

> "The code of InsightFace is released under the MIT License. There is no limitation
> for both academic and commercial usage."
>
> "The training data containing the annotation (and the models trained with these data)
> are available for non-commercial research purposes only."
>
> "Both manual-downloading models from our github repo and auto-downloading models with
> our python-library follow the above license policy (which is for non-commercial
> research purposes only)."
>
> "`2025-11-24` Update: ... 2. For open-sourced face recognition models (e.g.,
> buffalo_l package), please contact recognition-oss-pack@insightface.ai for licensing."

Model-zoo README (https://github.com/deepinsight/insightface/tree/master/model_zoo):

> "🔔 ALL models are available for non-commercial research purposes only."

The same page identifies the pack contents: buffalo_l = ResNet50@WebFace600K (326 MB
pack), buffalo_s = MBF@WebFace600K.

What this means for Gaze (facts, not legal advice): the MIT licence covers InsightFace's
*code*, not the *weights*; the weights Gaze ships are expressly non-commercial research
only. Whether a free-of-charge public app counts as non-commercial research is an open
question the repo text does not answer — InsightFace's own update points buffalo_l
users at recognition-oss-pack@insightface.ai for licensing. Shariq's permission for the
Sapphire copy (SHARIQ-PERMISSION-20260918.md) is separate from InsightFace's upstream
rights and does not settle them.

## 7. Replacement candidates checked (own repos, accessed 2026-09-23)

Neither candidate verified as permissive — both fail the weight-licence check:

- facenet-pytorch (https://github.com/timesler/facenet-pytorch): code MIT (LICENSE.md,
  © 2019 Timothy Esler). Pretrained weights are trained on VGGFace2 and CASIA-Webface;
  the repo states no separate weight licence, so the weights inherit the datasets'
  research-only terms. Not a clean replacement.
- AdaFace (https://github.com/mk-minchul/AdaFace): code MIT (LICENSE, © 2022 Minchul
  Kim). Pretrained weights are trained on CASIA-WebFace, VGGFace2, WebFace4M/12M,
  MS1MV2/MS1MV3; no weight licence is stated in the repo. Same problem.

Honest position: no permissively-licensed drop-in weight file was found and verified.
The options are: (a) ask InsightFace for permission or a commercial licence at
recognition-oss-pack@insightface.ai (their README names that address for buffalo_l);
(b) switch to weights whose own repo grants a permissive weight licence — none of the
  two obvious candidates does, so this needs a wider search (or training on
  commercially-licensed data), not a rename.

## 8. Provenance note

The byte-identical Sapphire copy (AGPL-3.0 repo) is therefore a copy of InsightFace's
`w600k_r50` weights downstream: Sapphire's ArcFace file and Gaze's mlmodelc are both
fp16 conversions of the same upstream ONNX model. Sapphire's repo licence governs
Sapphire's code; it cannot grant rights InsightFace reserved on the weights.
