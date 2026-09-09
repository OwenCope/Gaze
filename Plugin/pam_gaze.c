/*
 A PAM module that authorises `sudo` with your face.

 This is the third client of the same agent the lock screen uses. It does not look at a
 camera, hold any credential, or decide anything on its own: it asks the Gaze agent "is
 this them?", checks that the answer really came from the agent and really belongs to this
 attempt, and reports yes or no to PAM. The protocol, the nonce and the peer check are the
 ones already documented in GazeUnlockProtocol.h and PeerTrust.h.

 WHY THIS IS SAFE TO INSTALL

 It is configured as `auth sufficient` in /etc/pam.d/sudo_local, which is Apple's own
 extension point — the same one the system's Touch ID template uses, and the first line of
 the stock /etc/pam.d/sudo is `auth include sudo_local`. Two properties follow, and both
 matter more than anything else in this file:

   - `sufficient` means success short-circuits and *failure falls through*. Every way this
     module can fail — agent not running, wrong face, camera busy, module deleted, XPC
     unavailable — lands on the next line of the stack, which is the ordinary password
     prompt. There is no failure mode that denies sudo to someone who knows their password.

   - Editing sudo_local leaves /etc/pam.d/sudo untouched and Apple-managed, so a system
     update cannot half-apply our change, and our change cannot break an updated sudo.

 So the module fails closed on security and open on availability, which is the only
 combination that is honest for something standing in front of root.

 It returns PAM_AUTH_ERR rather than PAM_IGNORE on failure. Both fall through under
 `sufficient`; PAM_AUTH_ERR is the truthful one, because "I looked and it was not them" is
 a different statement from "I have no opinion", and the distinction shows up in logs.
*/

#include <Security/Security.h>
#include <dispatch/dispatch.h>
#include <security/pam_appl.h>
#include <security/pam_modules.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <xpc/xpc.h>

#include "GazeUnlockProtocol.h"
#include "PeerTrust.h"

/*
 Where the installer writes the agent's pinned code requirement.

 Not compiled in. The requirement contains the running app's cdhash, which changes on every
 rebuild, so baking it into the module would mean recompiling the module every time the app
 is rebuilt — and, far worse, a stale build would carry a requirement matching an *old*
 binary that an attacker could keep on disk and run.

 The file lives beside the module in a root-owned directory. If it cannot be read, the
 module fails: no requirement means no way to know who answered, and an unauthenticated
 "yes" to a sudo prompt is the worst possible default.
*/
#define kGazeRequirementPath "/usr/local/lib/pam/pam_gaze.requirement"

static bool read_requirement(char *buffer, size_t length) {
	FILE *file = fopen(kGazeRequirementPath, "r");
	if (file == NULL) {
		return false;
	}
	char *line = fgets(buffer, (int)length, file);
	fclose(file);
	if (line == NULL) {
		return false;
	}
	// Trim the trailing newline the installer's `echo` leaves behind; a requirement string
	// with one on the end does not parse.
	size_t used = strlen(buffer);
	while (used > 0 && (buffer[used - 1] == '\n' || buffer[used - 1] == '\r')) {
		buffer[--used] = '\0';
	}
	return used > 0;
}

/// Tells the user what is happening, through PAM's conversation function.
///
/// Without it `sudo` sits silent for a second or two while the camera opens, which reads
/// as a hang rather than as the Mac looking at you. Failure to deliver the message is not
/// a failure to authenticate — it is ignored.
static void say(pam_handle_t *pamh, const char *text) {
	const struct pam_conv *conv = NULL;
	if (pam_get_item(pamh, PAM_CONV, (const void **)&conv) != PAM_SUCCESS) {
		return;
	}
	if (conv == NULL || conv->conv == NULL) {
		return;
	}

	// Cast because macOS declares `msg` as `char *` rather than `const char *`. The
	// conversation function does not write to it.
	struct pam_message message = {.msg_style = PAM_TEXT_INFO, .msg = (char *)text};
	const struct pam_message *messages[] = {&message};
	struct pam_response *response = NULL;
	conv->conv(1, messages, &response, conv->appdata_ptr);
	if (response != NULL) {
		free(response->resp);
		free(response);
	}
}

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv) {
	(void)flags;
	(void)argc;
	(void)argv;

	// A struct, not a bare array, for the same reason as the nonce below: the reply
	// handler is a block, and a block cannot capture a C array.
	struct { char text[2048]; } requirement;
	if (!read_requirement(requirement.text, sizeof(requirement.text))) {
		return PAM_AUTH_ERR;
	}

	// Wrapped in a struct, not a bare array: a block cannot capture a C array, and the
	// reply handler below has to compare against it.
	struct { uint8_t bytes[kGazeNonceLength]; } nonce;
	if (SecRandomCopyBytes(kSecRandomDefault, sizeof(nonce.bytes), nonce.bytes) != errSecSuccess) {
		return PAM_AUTH_ERR;
	}

	/*
	 No XPC_CONNECTION_MACH_SERVICE_PRIVILEGED.

	 The agent registers its service in the logged-in user's bootstrap namespace, not the
	 system one. `sudo` inherits the namespace of the shell that invoked it, so an
	 unqualified lookup finds the user's agent — which is the correct one, because the
	 face being checked is the face of whoever is sitting at this session. Asking the
	 privileged domain would look in a namespace the agent is deliberately not in.
	*/
	xpc_connection_t connection =
		xpc_connection_create_mach_service(kGazeMachServiceName, NULL, 0);
	if (connection == NULL) {
		return PAM_AUTH_ERR;
	}
	xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
		(void)event;
	});
	xpc_connection_resume(connection);

	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_string(message, kGazeKeyCommand, kGazeCommandAuthenticate);
	xpc_dictionary_set_data(message, kGazeKeyNonce, nonce.bytes, sizeof(nonce.bytes));

	__block int result = PAM_AUTH_ERR;
	dispatch_semaphore_t done = dispatch_semaphore_create(0);

	xpc_connection_send_message_with_reply(
		connection, message, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
		^(xpc_object_t reply) {
			if (xpc_get_type(reply) != XPC_TYPE_DICTIONARY) {
				dispatch_semaphore_signal(done);
				return;
			}

			// Authorship, then freshness, then the answer — in that order, and all three
			// before the verdict is allowed to mean anything. See GazeUnlockProtocol.h:
			// freshness without authorship lets any local process answer, authorship
			// without freshness lets a captured reply be replayed.
			xpc_connection_t peer = xpc_dictionary_get_remote_connection(reply);
			if (peer == NULL || !GazePeerSatisfiesRequirement(peer, requirement.text)) {
				dispatch_semaphore_signal(done);
				return;
			}

			size_t returned_length = 0;
			const void *returned = xpc_dictionary_get_data(reply, kGazeKeyNonce, &returned_length);
			if (returned == NULL || returned_length != sizeof(nonce.bytes) ||
				timingsafe_bcmp(returned, nonce.bytes, sizeof(nonce.bytes)) != 0) {
				dispatch_semaphore_signal(done);
				return;
			}

			int64_t verdict = xpc_dictionary_get_int64(reply, kGazeKeyVerdict);
			if (verdict == kGazeVerdictMatch) {
				result = PAM_SUCCESS;
			}
			dispatch_semaphore_signal(done);
		});

	say(pamh, "Look at your Mac to authorise…");

	dispatch_time_t deadline =
		dispatch_time(DISPATCH_TIME_NOW, (int64_t)kGazeAuthenticateTimeoutSeconds * NSEC_PER_SEC);
	if (dispatch_semaphore_wait(done, deadline) != 0) {
		// Timed out. Tell the agent to stop looking rather than leaving a camera open and
		// a panel on screen after sudo has already moved on to asking for a password.
		xpc_object_t cancel = xpc_dictionary_create(NULL, NULL, 0);
		xpc_dictionary_set_string(cancel, kGazeKeyCommand, kGazeCommandCancel);
		xpc_connection_send_message(connection, cancel);
		result = PAM_AUTH_ERR;
	}

	xpc_connection_cancel(connection);
	return result;
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv) {
	(void)pamh;
	(void)flags;
	(void)argc;
	(void)argv;
	// Nothing is granted that needs revoking. PAM requires the symbol to exist.
	return PAM_SUCCESS;
}
