import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
	FileHandle.standardError.write(Data(("verify-profile: " + message + "\n").utf8))
	exit(1)
}

guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 else {
	fail("Usage: verify-profile.swift <decoded-profile.plist> <team-id> [signing-identity-sha1]")
}

let profileURL = URL(fileURLWithPath: CommandLine.arguments[1])
let team = CommandLine.arguments[2]
let identityHash = CommandLine.arguments.count == 4 ? CommandLine.arguments[3].lowercased() : nil
if let hash = identityHash, hash.range(of: "^[0-9a-f]{40}$", options: .regularExpression) == nil {
	fail("Signing identity is not a 40-character certificate SHA-1 hash.")
}

let data: Data
do {
	data = try Data(contentsOf: profileURL)
} catch {
	fail("Could not read decoded profile plist: \(error.localizedDescription)")
}
guard let profile = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
	fail("Decoded profile is not a plist dictionary. Decode with: security cms -D -i <profile> -o <plist>")
}

let profileName = profile["Name"] as? String ?? "(unnamed profile)"

guard let expiry = profile["ExpirationDate"] as? Date else {
	fail("'\(profileName)' has no ExpirationDate.")
}
guard expiry > Date() else {
	fail("'\(profileName)' expired on \(expiry). Renew it through Xcode; never remove Keychain entitlements as a workaround.")
}
if expiry < Date().addingTimeInterval(30 * 24 * 3600) {
	FileHandle.standardError.write(Data("verify-profile: warning: '\(profileName)' expires on \(expiry); plan renewal through Xcode.\n".utf8))
}

if let platforms = profile["Platform"] as? [String], !platforms.contains("OSX") {
	fail("'\(profileName)' does not authorize macOS (Platform is \(platforms.joined(separator: ", "))).")
}

guard let teams = profile["TeamIdentifier"] as? [String], teams.contains(team) else {
	fail("'\(profileName)' does not authorize team \(team).")
}

guard let entitlements = profile["Entitlements"] as? [String: Any] else {
	fail("'\(profileName)' has no Entitlements dictionary.")
}
let expectedAppID = team + ".com.gazeunlock.Passwords"
guard entitlements["com.apple.developer.team-identifier"] as? String == team else {
	fail("The profile's team entitlement does not match the signing team.")
}
guard let application = entitlements["com.apple.application-identifier"] as? String else {
	fail("'\(profileName)' has no application-identifier entitlement.")
}
guard application == expectedAppID else {
	fail("'\(profileName)' authorizes application identifier '\(application)', not '\(expectedAppID)'. Wildcard profiles are refused for the protected vault build.")
}

let expectedGroup = team + ".com.gazeunlock.Passwords"
let groups = entitlements["keychain-access-groups"] as? [String] ?? []
guard groups.contains(expectedGroup) || groups.contains(team + ".*") else {
	fail("'\(profileName)' does not authorize Keychain group '\(expectedGroup)'.")
}

if let hash = identityHash {
	guard let certificates = profile["DeveloperCertificates"] as? [Data], !certificates.isEmpty else {
		fail("'\(profileName)' lists no DeveloperCertificates; it cannot authorize any signing identity.")
	}
	let authorized = certificates.map { Data(Insecure.SHA1.hash(data: $0)).map { String(format: "%02x", $0) }.joined() }
	guard authorized.contains(hash) else {
		fail("'\(profileName)' does not list the selected signing certificate. Sign with a certificate the profile authorizes, or renew the profile through Xcode.")
	}
	print("Provisioning profile '\(profileName)' authorizes \(expectedAppID), Keychain group \(expectedGroup), and the selected signing certificate.")
} else {
	print("Provisioning profile '\(profileName)' authorizes \(expectedAppID) and Keychain group \(expectedGroup). Certificate matching was skipped (no identity hash given).")
}
