import AppKit
import SwiftUI

@main
struct LiveLayoutTests {
	@MainActor static func main() async throws {
		_ = NSApplication.shared
		let store = LocalPasswordStore(authenticate: { _ in fatalError("Layout must not authenticate") },
			loadArchive: { _ in fatalError("Layout must not read credentials") },
			saveArchive: { _, _, _ in fatalError("Layout must not save credentials") })
		let browser = PasswordBrowserService(store: store)
		let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
		try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
		for scheme in [ColorScheme.light, .dark] {
			try capture(LiveSettingsView(store: store, browser: browser), size: CGSize(width: 530, height: 720),
				scheme: scheme, path: output.appendingPathComponent("settings-\(scheme).png"))
			try capture(LiveSettingsView(store: store, browser: browser), size: CGSize(width: 530, height: 720),
				scheme: scheme, path: output.appendingPathComponent("settings-browser-\(scheme).png"), scrollToBottom: true)
			try capture(LiveImportView(store: store), size: CGSize(width: 590, height: 610),
				scheme: scheme, path: output.appendingPathComponent("import-\(scheme).png"))
			try capture(LiveVaultView(store: store, browser: browser), size: CGSize(width: 1080, height: 760),
				scheme: scheme, path: output.appendingPathComponent("vault-locked-\(scheme).png"))
		}
		let emptyStore = LocalPasswordStore(authenticate: { _ in true }, loadArchive: { _ in nil },
			saveArchive: { _, _, _ in fatalError("Layout must not save credentials") }, applicationIsActive: { true })
		await emptyStore.unlock()
		precondition(!emptyStore.isLocked && emptyStore.archive?.entries.isEmpty == true)
		let emptyBrowser = PasswordBrowserService(store: emptyStore)
		for scheme in [ColorScheme.light, .dark] {
			try capture(LiveVaultView(store: emptyStore, browser: emptyBrowser), size: CGSize(width: 1080, height: 760),
				scheme: scheme, path: output.appendingPathComponent("vault-empty-\(scheme).png"))
		}
		emptyStore.lock()
		precondition(store.isLocked && !store.busy && browser.request == nil)
		let origin = try BrowserOrigin("https://example.invalid")
		var fixture = PasswordEntry(title: "Example login", origin: origin, username: "demo@example.invalid", password: "synthetic-example-only")
		fixture.verificationCode = try VerificationCode(input: "JBSWY3DPEHPK3PXP")
		var duplicate = fixture
		duplicate.id = UUID()
		duplicate.title = "Second example"
		let fixtureStore = LocalPasswordStore(authenticate: { _ in true }, loadArchive: { _ in PasswordArchive(version: 2, entries: [fixture, duplicate]) },
			saveArchive: { _, _, _ in fatalError("Layout must not save") }, applicationIsActive: { true })
		await fixtureStore.unlock()
		precondition(!fixtureStore.isLocked)
		let fixtureBrowser = PasswordBrowserService(store: fixtureStore)
		for scheme in [ColorScheme.light, .dark] {
			try capture(LiveVaultView(store: fixtureStore, browser: fixtureBrowser), size: CGSize(width: 1080, height: 760),
				scheme: scheme, path: output.appendingPathComponent("vault-\(scheme).png"))
			try capture(PasswordEntryEditor(store: fixtureStore, original: fixture), size: CGSize(width: 460, height: 610),
				scheme: scheme, path: output.appendingPathComponent("editor-\(scheme).png"))
			try capture(VerificationCodeEditor(store: fixtureStore), size: CGSize(width: 480, height: 440),
				scheme: scheme, path: output.appendingPathComponent("code-chooser-\(scheme).png"))
			fixtureStore.collection = .codes
			try capture(LiveVaultView(store: fixtureStore, browser: fixtureBrowser), size: CGSize(width: 1080, height: 760),
				scheme: scheme, path: output.appendingPathComponent("codes-\(scheme).png"))
			fixtureStore.collection = .all
		}
		fixtureStore.lock()
		print("Rendered Settings, Import, locked/empty/synthetic unlocked vault in light/dark. No real authentication, vault reads, browser connection or file picker opened.")
	}

	@MainActor private static func capture<Content: View>(_ view: Content, size: CGSize, scheme: ColorScheme, path: URL, scrollToBottom: Bool = false) throws {
		NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
		let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme).environment(\.notchReduceMotion, true))
		let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
		window.appearance = NSApp.appearance
		window.isReleasedWhenClosed = false
		window.contentView = host
		host.frame = CGRect(origin: .zero, size: size)
		host.layoutSubtreeIfNeeded()
		if scrollToBottom {
			func scrollView(in view: NSView) -> NSScrollView? {
				if let scroll = view as? NSScrollView { return scroll }
				return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
			}
			guard let scroll = scrollView(in: host), let document = scroll.documentView else {
				fatalError("Settings must expose its scrollable browser section")
			}
			let y = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
			scroll.contentView.scroll(to: CGPoint(x: 0, y: y))
			scroll.reflectScrolledClipView(scroll.contentView)
			host.layoutSubtreeIfNeeded()
		}
		guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Cannot render layout") }
		host.cacheDisplay(in: host.bounds, to: bitmap)
		guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode layout") }
		try data.write(to: path)
		window.contentView = nil
		window.close()
	}
}
