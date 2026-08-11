import AppKit
import Security

/*
 Shows the plugin's real SecurityAgent panel, without touching the lock screen.

 `security authorize` from a terminal never displays a panel — there is no GUI context, so
 `viewForType:` is never called and the capsule is nil. That left the panel and its
 password field completely untested, which is the one path that matters when a face is not
 recognised: our mechanism is the only one in its rule, so if the field does not work there
 is nothing behind it.

 This asks for the *throwaway* right from inside a real GUI application, which is enough
 for SecurityAgent to draw the panel. Same mechanism, same code path, no system
 authentication modified.

 Build:  ./build-paneltest.sh
 Run:    ./build/PanelTest.app/Contents/MacOS/PanelTest
*/

let right = "app.faceid.testunlock"

func requestRight() -> String {
	var authRef: AuthorizationRef?
	guard AuthorizationCreate(nil, nil, [], &authRef) == errAuthorizationSuccess,
		let authRef
	else { return "AuthorizationCreate failed" }
	defer { AuthorizationFree(authRef, []) }

	return right.withCString { name -> String in
		var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
		return withUnsafeMutablePointer(to: &item) { pointer in
			var rights = AuthorizationRights(count: 1, items: pointer)
			// interactionAllowed is what permits SecurityAgent to put UI on screen.
			let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
			let status = AuthorizationCopyRights(authRef, &rights, nil, flags, nil)

			switch status {
			case errAuthorizationSuccess: return "GRANTED — the panel resolved successfully"
			case errAuthorizationDenied: return "DENIED — the mechanism said no"
			case errAuthorizationCanceled: return "CANCELLED by the user"
			case errAuthorizationInternal:
				return "INTERNAL (-60008) — the mechanism failed to resolve"
			default: return "status \(status)"
			}
		}
	}
}

final class Delegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_ note: Notification) {
		NSApp.setActivationPolicy(.regular)
		NSApp.activate()

		// Off the main thread: AuthorizationCopyRights blocks until the panel resolves,
		// and blocking the main thread would stop the panel drawing at all.
		DispatchQueue.global(qos: .userInitiated).async {
			let result = requestRight()
			DispatchQueue.main.async {
				let alert = NSAlert()
				alert.messageText = "Panel test result"
				alert.informativeText = result
				alert.runModal()
				NSApp.terminate(nil)
			}
		}
	}
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.run()
