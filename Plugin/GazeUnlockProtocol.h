/*
 Shared contract between the authorization plugin (inside SecurityAgent) and the
 Gaze agent (in the logged-in user's session).

 The split exists because neither side can do the job alone. SecurityAgent runs as
 `_securityagent` and has no camera TCC approval — and there is no way to prompt for it
 from the lock screen — so it cannot look at a face. The user's session agent can, but it
 is unprivileged and cannot authorise anything.

 So the privileged side asks, the unprivileged side answers, and the privileged side
 decides. Everything below exists to stop that answer being forged.
*/

#ifndef FACEID_UNLOCK_PROTOCOL_H
#define FACEID_UNLOCK_PROTOCOL_H

#include <stdint.h>

/// Mach service vended by the user's session agent, registered via its LaunchAgent.
#define kGazeMachServiceName "com.gazeunlock.Gaze.unlock"

/// Message keys.
#define kGazeKeyCommand   "command"
#define kGazeKeyNonce     "nonce"
#define kGazeKeyVerdict   "verdict"
#define kGazeKeyReason    "reason"
#define kGazeKeyUsername  "username"

/// Commands sent by the plugin.
#define kGazeCommandAuthenticate "authenticate"
#define kGazeCommandCancel       "cancel"

/// Verdicts returned by the agent.
typedef enum {
	kGazeVerdictNoMatch = 0,
	kGazeVerdictMatch = 1,
	/// Too many failures — the agent refuses to look until a password is entered.
	kGazeVerdictLockedOut = 2,
	/// Nothing enrolled, camera unavailable, untrusted camera.
	kGazeVerdictUnavailable = 3,
} GazeVerdict;

/// Length of the challenge nonce, in bytes.
#define kGazeNonceLength 32

/*
 Why a nonce.

 Without one, the agent's "yes" is a constant, and anything that can produce that same
 reply once can produce it forever — recorded, replayed, or simply re-sent. The plugin
 generates fresh random bytes for every attempt and refuses any reply that does not carry
 them back, so an answer is only ever valid for the single attempt that asked for it.

 The nonce alone is not sufficient: it proves freshness, not authorship. Peer code-signature
 verification (see PeerTrust.h) is what proves the reply came from our agent. Both are
 required — freshness without authorship lets any local process answer, and authorship
 without freshness lets a captured reply be reused.
*/

/// How long the plugin waits for a verdict before giving up and falling back to a
/// password. Deliberately short: a lock screen that appears hung is worse than one that
/// asks for a password.
#define kGazeAuthenticateTimeoutSeconds 12

#endif /* FACEID_UNLOCK_PROTOCOL_H */
