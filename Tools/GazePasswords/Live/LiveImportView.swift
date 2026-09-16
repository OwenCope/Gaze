import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LiveImportView: View {
	@ObservedObject var store: LocalPasswordStore
	@Environment(\.openWindow) private var openWindow
	@Environment(\.dismiss) private var dismiss
	@StateObject private var guide = PasswordsExportGuideController(canImport: true)
	@State private var choosingFile = false
	@State private var fileSession: UUID?
	@State private var review: PasswordCSVImport?
	@State private var importSession: UUID?
	@State private var wasInterruptedByLock = false
	@State private var message: String?
	@State private var failure: String?

	private var plan: PasswordImportPlan? {
		review.map { PasswordImportPlan(candidates: $0.entries, existing: store.archive?.entries ?? []) }
	}

	var body: some View {
		ScrollView {
		VStack(alignment: .leading, spacing: 20) {
			HStack(spacing: 16) {
				PasswordsCompanion(size: 64)
				VStack(alignment: .leading, spacing: 5) {
					Text("Import passwords").font(Typography.paneTitle)
					Text("Apple Passwords, Bitwarden or CSV").foregroundStyle(.secondary)
				}
				Spacer()
				InfoButton(title: "About importing passwords") {
					Text("Choose a CSV with URL, Username and Password columns. Only HTTPS logins are supported. Review the counts before saving; existing logins are never overwritten and passwords are never shown in the review.")
					Text("CSV exports contain readable passwords. Nothing is uploaded. Keep the source until you verify the import, then delete the export yourself.")
				}
			}
			HStack {
				Label("Apple Passwords", systemImage: "key.horizontal").foregroundStyle(.secondary)
				Spacer()
				Button("Show export guide") { guide.show() }.gazeButton()
			}
			Divider()
			if wasInterruptedByLock {
				Text(store.isLocked ? "The vault locked, so the import review was cleared. Choose the CSV again after unlocking." : "The vault locked, so the import review was cleared. Choose the CSV again.")
					.font(.callout).foregroundStyle(.secondary)
			}
			if store.isLocked {
				Text("Unlock to choose your export.").foregroundStyle(.secondary)
				Button(store.busy ? "Waiting for macOS…" : "Unlock Passwords") { Task { await store.unlock() } }
					.gazeButton(.primary).keyboardShortcut(.defaultAction).disabled(store.busy || PasswordsBuild.isUIReview)
				if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
			} else if let review, let plan {
				VStack(alignment: .leading, spacing: 12) {
					LabeledContent("Ready to import", value: "\(plan.entries.count)")
					LabeledContent("With verification codes", value: "\(plan.entries.filter { $0.verificationCode != nil }.count)")
					LabeledContent("Already saved", value: "\(plan.duplicates)")
					HStack {
						LabeledContent("Conflicts", value: "\(plan.conflicts)")
						InfoButton(title: "About conflicts") { Text("A login already exists for the same website and username, but its password or verification code differs. The existing entry is left unchanged.") }
					}
					HStack {
						LabeledContent("Skipped rows", value: "\(review.skippedRows.count)")
						InfoButton(title: "About skipped rows") {
							Text("Unsupported sites, invalid entries and unsupported verification codes are skipped entirely. The source file is not changed.")
							if !review.skippedRows.isEmpty { Text("CSV rows: " + review.skippedRows.prefix(12).map(String.init).joined(separator: ", ") + (review.skippedRows.count > 12 ? "…" : "")) }
							if !review.invalidCodeRows.isEmpty { Text("\(review.invalidCodeRows.count) rows contain unsupported verification-code data.") }
						}
					}
					if review.rowsWithExtraFields > 0 {
						HStack {
							LabeledContent("Logins with omitted fields", value: "\(review.rowsWithExtraFields)")
							InfoButton(title: "About omitted fields") { Text("Notes, passkeys, folders and custom fields are not imported. Keep the source until you have checked the result. Importing a password does not import its passkey.") }
						}
					}
				}.padding(20).glassSurface()
				HStack {
					Button("Choose another file") { wasInterruptedByLock = false; clearReview(); fileSession = store.sessionID; choosingFile = true }.gazeButton()
					Spacer()
					Button("Import \(plan.entries.count) passwords", action: commit)
						.gazeButton(.primary).keyboardShortcut(.defaultAction).disabled(plan.entries.isEmpty || store.busy)
				}
				if plan.entries.isEmpty {
					Text("Nothing new to import. Your existing logins are unchanged. Choose another file or close this window.")
						.font(.callout).foregroundStyle(.secondary)
				}
			} else {
				Button("Choose CSV file…") { wasInterruptedByLock = false; failure = nil; message = nil; fileSession = store.sessionID; choosingFile = true }
					.gazeButton(.primary).keyboardShortcut(.defaultAction).disabled(PasswordsBuild.isUIReview)
			}
			if let message {
				Label(message, systemImage: "checkmark.circle").foregroundStyle(.secondary)
				Button("View passwords") { openWindow(id: "vault"); dismiss() }.gazeButton()
			}
			if let failure { Text(failure).foregroundStyle(.red) }
			Label("On this Mac only", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
			Spacer(minLength: 0)
		}.padding(28)
		}.frame(width: 590, height: 610)
		.background { PasswordsWindowBackground() }
		.modifier(PasswordsAppearance())
		.fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
			do { try read(result.get()) }
			catch CocoaError.userCancelled { }
			catch { failure = "The export could not be opened. Choose a valid local CSV file and try again." }
		}
		.onChange(of: store.sessionID) { _, _ in wasInterruptedByLock = wasInterruptedByLock || review != nil || choosingFile; clearReview(); fileSession = nil; choosingFile = false }
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
			if !store.busy { store.lock() }
		}
		.onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in store.lock() }
		.onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in store.lock() }
		.onReceive(DistributedNotificationCenter.default().publisher(for: .init("com.apple.screenIsLocked"))) { _ in store.lock() }
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
			if (notification.object as? NSWindow)?.title == "Import passwords" { wasInterruptedByLock = false; clearReview(); fileSession = nil; guide.close() }
		}
		.onDisappear { wasInterruptedByLock = false; clearReview(); fileSession = nil; guide.close() }
	}

	private func read(_ url: URL) throws {
		defer { fileSession = nil }
		guard fileSession == store.sessionID, !store.isLocked, NSApp.isActive, !PasswordsBuild.isUIReview else { failure = VaultError.locked.localizedDescription; return }
		clearReview()
		let session = store.sessionID
		let scoped = url.startAccessingSecurityScopedResource()
		defer { if scoped { url.stopAccessingSecurityScopedResource() } }
		let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
		guard values.isRegularFile == true, let size = values.fileSize, size <= PasswordCSVImport.maximumBytes else {
			failure = PasswordCSVImport.ImportError.invalidFile.localizedDescription
			return
		}
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		let data = try handle.read(upToCount: PasswordCSVImport.maximumBytes + 1) ?? Data()
		do {
			let imported = try PasswordCSVImport(data: data)
			guard !store.isLocked, store.sessionID == session, NSApp.isActive else { throw VaultError.locked }
			review = imported
			importSession = session
		} catch { failure = error.localizedDescription }
	}

	private func commit() {
		guard let review, importSession == store.sessionID, !store.isLocked, NSApp.isActive else { clearReview(); return }
		do {
			let firstImportedID = plan?.entries.first?.id
			let count = try store.importEntries(review.entries)
			if count > 0, let firstImportedID { store.showEntry(firstImportedID) }
			clearReview()
			wasInterruptedByLock = false
			message = "Imported \(count) passwords. Check them in your vault before removing the CSV."
		} catch { failure = error.localizedDescription }
	}

	private func clearReview() { review = nil; importSession = nil; failure = nil; message = nil }
}
