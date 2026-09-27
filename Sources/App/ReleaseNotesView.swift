import SwiftUI

/// Release notes rendered as structure instead of raw Markdown.
struct ReleaseNotesView: View {
	let markdown: String

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			ForEach(blocks.indices, id: \.self) { index in
				blockView(blocks[index])
			}
		}
	}

	private enum Block {
		case headline(String)
		case subhead(String)
		case bullet(String)
		case code(String)
		case image(alt: String, url: URL?)
		case paragraph(String)
	}

	/// One block per line; a trailing Install section is the app itself, so it is dropped.
	private var blocks: [Block] {
		var result: [Block] = []
		var code: [String] = []
		var inCode = false
		for rawLine in markdown.components(separatedBy: "\n") {
			let line = rawLine.trimmingCharacters(in: .whitespaces)
			if line.hasPrefix("```") {
				if inCode {
					result.append(.code(code.joined(separator: "\n")))
					code = []
				}
				inCode.toggle()
				continue
			}
			if inCode {
				code.append(rawLine)
				continue
			}
			if line.isEmpty { continue }
			if line == "## Install" || line.hasPrefix("## Install ") { break }
			if line.hasPrefix("### ") {
				result.append(.subhead(String(line.dropFirst(4))))
			} else if line.hasPrefix("## ") {
				result.append(.headline(String(line.dropFirst(3))))
			} else if line.hasPrefix("- ") {
				result.append(.bullet(String(line.dropFirst(2))))
			} else if let image = parseImage(line) {
				result.append(image)
			} else {
				result.append(.paragraph(line))
			}
		}
		if inCode, !code.isEmpty { result.append(.code(code.joined(separator: "\n"))) }
		return result
	}

	private func parseImage(_ line: String) -> Block? {
		guard line.hasPrefix("!["),
			let close = line.firstIndex(of: "]"),
			line[line.index(after: close)...].hasPrefix("("),
			line.hasSuffix(")")
		else { return nil }
		let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<close])
		let urlText = String(line[line.index(after: close)...].dropFirst().dropLast())
		return .image(alt: alt, url: URL(string: urlText))
	}

	@ViewBuilder
	private func blockView(_ block: Block) -> some View {
		switch block {
		case .headline(let text):
			styledLine(text)
				.font(.headline)
		case .subhead(let text):
			styledLine(text)
				.font(.subheadline.weight(.semibold))
				.padding(.top, 4)
		case .bullet(let text):
			HStack(alignment: .top, spacing: 6) {
				Text("•")
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
				styledLine(text)
					.font(Typography.detail)
					.foregroundStyle(Theme.secondaryLabel)
			}
		case .code(let text):
			Text(text)
				.font(.system(.body, design: .monospaced))
				.padding(8)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
		case .image(let alt, let url):
			if let url {
				AsyncImage(url: url) { image in
					image.resizable().scaledToFit()
				} placeholder: {
					RoundedRectangle(cornerRadius: 10)
						.fill(Color.secondary.opacity(0.12))
						.frame(height: 120)
				}
				.scaledToFit()
				.frame(maxWidth: .infinity)
				.cornerRadius(10)
				.accessibilityLabel(alt)
			}
		case .paragraph(let text):
			styledLine(text)
				.font(Typography.detail)
				.foregroundStyle(Theme.secondaryLabel)
		}
	}

	private func styledLine(_ line: String) -> Text {
		if let attributed = try? AttributedString(
			markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
		{
			return Text(attributed)
		}
		return Text(line)
	}
}
