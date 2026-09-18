import SwiftUI

struct LoginDetailView: View {
	@ObservedObject var vault: DemoVault
	let login: DemoLogin

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
				SettingsSection {
					HStack(spacing: 14) {
						LoginGlyph(login: login, size: 42)
						VStack(alignment: .leading, spacing: 3) {
							Text(login.title).font(Typography.heroTitle)
							Label(login.collection.rawValue, systemImage: login.collection.symbol)
								.font(Typography.detail).foregroundStyle(Theme.secondaryLabel)
						}
						Spacer(minLength: 8)
						Button { vault.toggleFavorite() } label: {
							Image(systemName: login.favorite ? "star.fill" : "star")
								.frame(width: 28, height: 28)
						}
						.gazeButton()
						.accessibilityLabel(login.favorite ? "Remove favorite" : "Add favorite")
						.help(login.favorite ? "Remove favorite" : "Add favorite")
					}
					.padding(.horizontal, Theme.rowInset).padding(.vertical, 14)
				}
				SettingsSection(title: "Login details", footer: "Built-in sample · Changes last until you quit") {
					PasswordFieldRow(title: "Username", value: login.username)
					RowDivider(inset: Theme.rowInset)
					HStack(spacing: 0) {
						PasswordFieldRow(title: "Password",
							value: vault.revealedID == login.id ? "DEMO-ONLY-not-a-secret" : "••••••••••••",
							monospaced: true)
						Button { vault.toggleReveal() } label: {
							Image(systemName: vault.revealedID == login.id ? "eye.slash" : "eye")
								.frame(width: 28, height: 28)
						}
						.buttonStyle(.borderless)
						.accessibilityLabel(vault.revealedID == login.id ? "Hide sample password" : "Reveal sample password")
						.help(vault.revealedID == login.id ? "Hide sample password" : "Reveal sample password")
						.padding(.trailing, Theme.rowInset)
					}
					RowDivider(inset: Theme.rowInset)
					PasswordFieldRow(title: "Website", value: login.host)
				}
				SettingsSection(title: "Gaze approval",
					footer: "Simulation only. No camera, face matching, or browser filling.",
					info: "This walkthrough uses sample data. Website identity is not verified. Finishing the demo does not authenticate you or release a credential.") {
					HStack(spacing: 14) {
						PasswordsCompanion()
						VStack(alignment: .leading, spacing: 10) {
							VStack(alignment: .leading, spacing: 3) {
								Text("Meet your companion").font(Typography.heroTitle)
								Text("Try Gaze’s approval preview.")
									.font(Typography.detail).foregroundStyle(Theme.secondaryLabel)
							}
							Button("Preview face approval") { vault.beginApproval() }
								.gazeButton(size: .large)
						}
						Spacer(minLength: 0)
					}
					.padding(Theme.rowInset)
				}
				if let receipt = vault.receipt {
					Label(receipt, systemImage: "info.circle")
						.font(Typography.detail).foregroundStyle(Theme.secondaryLabel)
				}
			}
			.padding(28)
			.frame(maxWidth: 620, alignment: .leading)
			.frame(maxWidth: .infinity, alignment: .top)
		}
	}
}
