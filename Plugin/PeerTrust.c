#include "PeerTrust.h"

#include <Security/Security.h>
#include <Security/SecCode.h>
#include <Security/SecRequirement.h>
#include <bsm/libbsm.h>
#include <os/log.h>

/*
 Declared here because it is SPI — libxpc exports it but the SDK does not publish a
 header for it.

 There is no public alternative that is actually safe. `xpc_connection_get_pid` is the
 documented option, and it is unusable for a security decision: a PID can be recycled
 between the check and the use, so an attacker who gets the right number wins. The audit
 token is filled in by the kernel and identifies the peer unambiguously, which is why
 every serious peer check on this platform uses it.
*/
extern void xpc_connection_get_audit_token(xpc_connection_t connection, audit_token_t *token);

bool GazePeerSatisfiesRequirement(xpc_connection_t connection, const char *requirement)
{
	if (connection == NULL || requirement == NULL) {
		return false;
	}

	// The audit token is filled in by the kernel and cannot be set by the peer, unlike a
	// PID, which can be recycled and is racy to check against.
	audit_token_t token;
	xpc_connection_get_audit_token(connection, &token);

	CFDataRef tokenData = CFDataCreate(
		kCFAllocatorDefault, (const UInt8 *)&token, sizeof(audit_token_t));
	if (tokenData == NULL) {
		return false;
	}

	const void *keys[] = { kSecGuestAttributeAudit };
	const void *values[] = { tokenData };
	CFDictionaryRef attributes = CFDictionaryCreate(
		kCFAllocatorDefault, keys, values, 1,
		&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFRelease(tokenData);
	if (attributes == NULL) {
		return false;
	}

	SecCodeRef code = NULL;
	OSStatus status = SecCodeCopyGuestWithAttributes(NULL, attributes, kSecCSDefaultFlags, &code);
	CFRelease(attributes);
	if (status != errSecSuccess || code == NULL) {
		os_log_error(OS_LOG_DEFAULT, "Gaze: could not identify peer (%d)", (int)status);
		return false;
	}

	CFStringRef requirementString = CFStringCreateWithCString(
		kCFAllocatorDefault, requirement, kCFStringEncodingUTF8);
	if (requirementString == NULL) {
		CFRelease(code);
		return false;
	}

	SecRequirementRef parsed = NULL;
	status = SecRequirementCreateWithString(requirementString, kSecCSDefaultFlags, &parsed);
	CFRelease(requirementString);
	if (status != errSecSuccess || parsed == NULL) {
		os_log_error(OS_LOG_DEFAULT, "Gaze: bad peer requirement (%d)", (int)status);
		CFRelease(code);
		return false;
	}

	// kSecCSStrictValidate catches a bundle whose contents were altered after signing,
	// which a default check would let through.
	status = SecCodeCheckValidity(code, kSecCSDefaultFlags | kSecCSStrictValidate, parsed);

	CFRelease(parsed);
	CFRelease(code);

	if (status != errSecSuccess) {
		os_log_error(OS_LOG_DEFAULT, "Gaze: peer failed requirement (%d)", (int)status);
		return false;
	}

	return true;
}
