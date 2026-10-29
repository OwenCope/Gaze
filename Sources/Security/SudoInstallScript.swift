import Foundation

/// Builds the shell scripts that install and remove Gaze's sudo PAM module.
/// Pure string building, kept apart from SudoApproval so a test can run the
/// exact script against a temporary folder instead of the real system paths.
struct SudoInstallScript {
	struct Paths {
		var moduleFolder = "/usr/local/lib/pam"
		var modulePath = "/usr/local/lib/pam/pam_gaze.so"
		var requirementPath = "/usr/local/lib/pam/pam_gaze.requirement"
		var sudoLocalPath = "/etc/pam.d/sudo_local"
		var sudoLocalTemplate = "/etc/pam.d/sudo_local.template"
		/// Whether to set root ownership; off only for tests run as a normal user.
		var setRootOwner = true
	}

	static let authLine = "auth sufficient /usr/local/lib/pam/pam_gaze.so"

	/// Copies the module, writes the listener requirement and puts the auth
	/// line at the top of sudo_local, keeping every other line. The copied
	/// module is cleared of extended attributes (quarantine, provenance) so
	/// sudo loads it the same as any other root-owned file.
	static func install(source: String, requirement: String, paths: Paths = Paths()) -> String {
		let own = paths.setRootOwner
		let dir = (paths.sudoLocalPath as NSString).deletingLastPathComponent
		return """
		set -e
		mkdir -p \(q(paths.moduleFolder))
		rm -f \(q(paths.modulePath))
		cp \(q(source)) \(q(paths.modulePath))
		xattr -c \(q(paths.modulePath)) 2>/dev/null || true
		\(own ? "chown root:wheel \(q(paths.modulePath))" : ":")
		chmod 0444 \(q(paths.modulePath))
		rm -f \(q(paths.requirementPath))
		printf '%s\\n' \(q(requirement)) > \(q(paths.requirementPath))
		\(own ? "chown root:wheel \(q(paths.requirementPath))" : ":")
		chmod 0444 \(q(paths.requirementPath))
		line=\(q(authLine))
		f=\(q(paths.sudoLocalPath))
		t=\(q(paths.sudoLocalTemplate))
		if [ ! -f "$f" ]; then if [ -f "$t" ]; then cp "$t" "$f"; else : > "$f"; fi; fi
		tmp=$(mktemp \(q(dir))/.sudo_local.XXXXXX)
		printf '%s\\n' "$line" > "$tmp"
		grep -v 'pam_gaze\\.so' "$f" | grep -v '^# Added by Gaze' >> "$tmp" || true
		\(own ? "chown root:wheel \"$tmp\"" : ":")
		chmod 0444 "$tmp"
		mv -f "$tmp" "$f"
		"""
	}

	static func uninstall(paths: Paths = Paths()) -> String {
		let own = paths.setRootOwner
		let dir = (paths.sudoLocalPath as NSString).deletingLastPathComponent
		return """
		set -e
		f=\(q(paths.sudoLocalPath))
		if [ -f "$f" ]; then
		tmp=$(mktemp \(q(dir))/.sudo_local.XXXXXX)
		grep -v 'pam_gaze\\.so' "$f" | grep -v '^# Added by Gaze' > "$tmp" || true
		\(own ? "chown root:wheel \"$tmp\"" : ":")
		chmod 0444 "$tmp"
		mv -f "$tmp" "$f"
		fi
		rm -f \(q(paths.modulePath))
		rm -f \(q(paths.requirementPath))
		"""
	}

	/// Wraps a shell script in an AppleScript `do shell script` command.
	static func appleScript(_ shellScript: String, administrator: Bool = true) -> String {
		let escaped = shellScript
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
			.replacingOccurrences(of: "\n", with: "\\n")
		return "do shell script \"\(escaped)\"" + (administrator ? " with administrator privileges" : "")
	}

	/// Whether sudo_local text holds Gaze's auth line, ignoring spacing.
	static func routesThroughGaze(_ sudoLocal: String) -> Bool {
		func words(_ line: Substring) -> [Substring] { line.split(whereSeparator: \.isWhitespace) }
		let wanted = words(Substring(authLine))
		return sudoLocal.split(separator: "\n").contains { words($0) == wanted }
	}

	private static func q(_ value: String) -> String {
		"'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}
}
