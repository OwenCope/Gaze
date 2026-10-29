import Foundation

private enum TestError: Error { case failed(String) }

/// Runs the real install and uninstall scripts through `osascript`, the same
/// AppleScript path Gaze uses, but without administrator privileges and
/// against a temporary folder whose path has spaces and an apostrophe.
@main
enum SudoInstallScriptTests {
	static var checks = 0
	static func expect(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
		guard try condition() else { throw TestError.failed(name) }
		checks += 1
		print("PASS \(name)")
	}

	static func run(_ shellScript: String) throws -> Int32 {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
		process.arguments = ["-e", SudoInstallScript.appleScript(shellScript, administrator: false)]
		try process.run()
		process.waitUntilExit()
		return process.terminationStatus
	}

	static func main() throws {
		let fm = FileManager.default
		let root = fm.temporaryDirectory.appendingPathComponent("Gaze sudo 'test' \(UUID().uuidString)").path
		defer { try? fm.removeItem(atPath: root) }
		let pamDir = root + "/etc/pam.d"
		try fm.createDirectory(atPath: pamDir, withIntermediateDirectories: true)
		let source = root + "/Gaze copy.app/Contents/Resources/pam_gaze.so"
		try fm.createDirectory(atPath: (source as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
		try Data("module".utf8).write(to: URL(fileURLWithPath: source))
		var paths = SudoInstallScript.Paths()
		paths.moduleFolder = root + "/usr/local/lib/pam"
		paths.modulePath = paths.moduleFolder + "/pam_gaze.so"
		paths.requirementPath = paths.moduleFolder + "/pam_gaze.requirement"
		paths.sudoLocalPath = pamDir + "/sudo_local"
		paths.sudoLocalTemplate = pamDir + "/sudo_local.template"
		paths.setRootOwner = false
		// An existing sudo_local, read-only like the system's, with an old-style Gaze line.
		let existing = "# Added by Gaze. Remove this line.\nauth       sufficient     /usr/local/lib/pam/pam_gaze.so\nauth       sufficient     pam_tid.so\n"
		try existing.write(toFile: paths.sudoLocalPath, atomically: true, encoding: .utf8)
		try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: paths.sudoLocalPath)
		let requirement = #"identifier "com.gazeunlock.Gaze" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: a@b.c (Y6LG3Q6HV4)" and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */"#

		try expect(try run(SudoInstallScript.install(source: source, requirement: requirement, paths: paths)) == 0,
			"install script succeeds")
		let local = try String(contentsOfFile: paths.sudoLocalPath, encoding: .utf8)
		try expect(SudoInstallScript.routesThroughGaze(local), "auth line present")
		try expect(local.hasPrefix(SudoInstallScript.authLine + "\n"), "auth line first")
		try expect(local.components(separatedBy: "pam_gaze.so").count == 2, "auth line not duplicated")
		try expect(local.contains("pam_tid.so"), "other lines kept")
		try expect(try String(contentsOfFile: paths.requirementPath, encoding: .utf8) == requirement + "\n",
			"requirement written verbatim")
		try expect(fm.contentsEqual(atPath: source, andPath: paths.modulePath), "module copied")

		// Running again (a reinstall over read-only files) must still succeed.
		try expect(try run(SudoInstallScript.install(source: source, requirement: requirement, paths: paths)) == 0,
			"reinstall succeeds")

		try expect(try run(SudoInstallScript.uninstall(paths: paths)) == 0, "uninstall script succeeds")
		let after = try String(contentsOfFile: paths.sudoLocalPath, encoding: .utf8)
		try expect(!SudoInstallScript.routesThroughGaze(after) && after.contains("pam_tid.so"), "uninstall keeps other lines")
		try expect(!fm.fileExists(atPath: paths.modulePath) && !fm.fileExists(atPath: paths.requirementPath),
			"uninstall removes module and requirement")

		try expect(SudoInstallScript.routesThroughGaze("auth\tsufficient   /usr/local/lib/pam/pam_gaze.so\n"),
			"spacing-insensitive match")
		try expect(!SudoInstallScript.routesThroughGaze("#auth sufficient /usr/local/lib/pam/pam_gaze.so\n"),
			"commented line ignored")
		print("\(checks) checks passed")
	}
}
