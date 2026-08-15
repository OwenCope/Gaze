/*
 Verifies that the process answering the plugin is really the Gaze agent.

 This is the load-bearing security check in the whole design. The plugin runs privileged
 and asks an unprivileged process a question whose answer unlocks the Mac. Anything that
 can register the mach service first, or otherwise get itself on the other end of that
 connection, can answer "yes" — unless the plugin checks who it is talking to.

 A mach service name is not a credential. Any process in the session can attempt to
 register one. So identity has to come from the kernel's view of the peer — its audit
 token — and be checked against a code-signing requirement.
*/

#ifndef FACEID_PEER_TRUST_H
#define FACEID_PEER_TRUST_H

#include <xpc/xpc.h>
#include <stdbool.h>

/*!
 @abstract Confirms the peer of an XPC connection satisfies the pinned code requirement.

 @param connection  The connection whose peer is being checked.
 @param requirement A code-signing requirement string. The installer writes this into the
                    plugin's Info.plist, pinning the agent's cdhash — ad-hoc signatures
                    carry no team identifier, so the binary hash is the only thing stable
                    enough to pin against.

 @result true only when the peer's signature is valid and satisfies the requirement.
         Fails closed on every error: an unreadable audit token, an unparseable
         requirement or a revoked signature all return false.
 */
bool GazePeerSatisfiesRequirement(xpc_connection_t connection, const char *requirement);

#endif /* FACEID_PEER_TRUST_H */
