import SwiftUI

struct BrowserLoginChoices: View {
	let entries: [PasswordEntry]
	let verifying: Bool
	let choose: (UUID) -> Void
	@State private var query = ""
	private var matches: [PasswordEntry] {
		entries.filter { $0.matches(query) }.sorted {
			if $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedSame {
				if $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedSame {
					return $0.collection.localizedStandardCompare($1.collection) == .orderedAscending
				}
				return $0.title.localizedStandardCompare($1.title) == .orderedAscending
			}
			return $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if entries.isEmpty {
				Text("No logins saved for this website.")
					.font(.callout).foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
				Text("Add the login in Gaze Passwords first, then try again. Nothing was filled.")
					.font(.caption).foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
			} else {
				if entries.count > 3 {
					VaultSearchField(placeholder: "Find a login for this website", text: $query).disabled(verifying)
				}
				ScrollView {
					LazyVStack(spacing: 8) {
						ForEach(matches) { entry in
							Button { choose(entry.id) } label: {
								HStack(spacing: 12) {
									VStack(alignment: .leading, spacing: 4) {
										Text(entry.username.isEmpty ? entry.title : entry.username).font(.body.weight(.medium))
										Text(entry.collection).font(.caption).foregroundStyle(.secondary)
									}.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
									Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
								}.padding(.vertical, 5)
							}.gazeButton().disabled(verifying)
								.accessibilityLabel("Use \(entry.username.isEmpty ? entry.title : entry.username) from \(entry.collection)")
						}
						if matches.isEmpty {
							Text("No matching logins for this search.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
								.frame(maxWidth: .infinity, alignment: .leading)
							Button("Clear search") { query = "" }.gazeButton()
						}
					}.padding(4)
				}.scrollIndicators(.never).frame(height: min(CGFloat(max(matches.count, 1)) * 64 + 8, 220))
			}
		}
	}
}
