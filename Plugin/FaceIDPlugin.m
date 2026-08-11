/*
 The Face ID authorization plugin.

 macOS loads this into SecurityAgent at the lock screen. Because a face match has to be
 able to unlock on its own, this mechanism is the *only* one in the rule — there is no
 `builtin:authenticate` behind it to fall back on. That means it also owns the password
 path, which is why PAM appears here.

 Two consequences worth stating plainly:

 - Every path must end in exactly one SetResult. A path that returns without one hangs
   the lock screen, which is the worst failure this code can have.
 - Anything unexpected falls back to the password field, never to Allow. Failing closed
   here means "you type your password", not "you are locked out", so there is no reason
   to ever guess in the other direction.
*/

#import "FaceIDCapsuleView.h"
#import "FaceIDUnlockProtocol.h"
#import "PeerTrust.h"

#import <Cocoa/Cocoa.h>
#import <Security/AuthorizationPlugin.h>
#import <SecurityInterface/SFAuthorizationPluginView.h>
#import <os/log.h>
#import <security/pam_appl.h>
#import <sys/stat.h>
#import <xpc/xpc.h>

static os_log_t FaceIDLog(void)
{
	static os_log_t log;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		log = os_log_create("app.faceid.plugin", "Mechanism");
	});
	return log;
}

/// Runs a block on the main thread, whether or not we are already on it.
///
/// `dispatch_sync` to the main queue from the main thread deadlocks the process outright.
/// SecurityAgent invokes mechanisms on the main thread, so every `dispatch_sync` in here
/// was a guaranteed hang — the mechanism entered, blocked forever, and the authorization
/// eventually failed with errAuthorizationInternal. That looked identical to the plugin
/// never loading, which is what sent me chasing code signing for hours.
static void FaceIDRunOnMain(dispatch_block_t block)
{
	if ([NSThread isMainThread]) {
		block();
	} else {
		dispatch_sync(dispatch_get_main_queue(), block);
	}
}

/*
 Reaching the agent's mach service across login-session boundaries.

 The agent registers `app.faceid.unlock` in the console user's GUI domain (`gui/501`).
 The plugin runs as `_securityagent`, in a different domain, so an ordinary lookup finds
 nothing and simply times out — which is indistinguishable from the agent being down.

 SecurityAgentHelper is entitled with `com.apple.private.xpc.launchd.per-user-lookup`
 precisely so it can cross that boundary; it just has to name the user. These are the SPI
 that do it. Declared here because libxpc exports them without a public header.
*/
extern void xpc_connection_set_target_uid(xpc_connection_t connection, uid_t uid);

/// The uid of whoever owns the console — the session whose agent we want.
static uid_t FaceIDConsoleUID(void)
{
	struct stat info;
	if (stat("/dev/console", &info) == 0) {
		return info.st_uid;
	}
	return 0;
}

#pragma mark - Agent query

/*
 Asks the session agent whether it recognises the user.

 The reply is only trusted when it (a) comes from a process satisfying the pinned code
 requirement and (b) carries back the nonce from this exact request. See PeerTrust.h and
 FaceIDUnlockProtocol.h for why neither check alone is enough.
*/
static FaceIDVerdict FaceIDAskAgent(const char *username, const char *peerRequirement)
{
	__block FaceIDVerdict verdict = kFaceIDVerdictUnavailable;

	uint8_t nonce[kFaceIDNonceLength];
	if (SecRandomCopyBytes(kSecRandomDefault, sizeof(nonce), nonce) != errSecSuccess) {
		os_log_error(FaceIDLog(), "Could not generate a nonce; refusing to ask.");
		return kFaceIDVerdictUnavailable;
	}
	// A block cannot capture an array, so compare through a pointer. It stays valid for
	// the block's lifetime because this function waits on the semaphore below before
	// returning, so the stack frame outlives the reply.
	const uint8_t *sentNonce = nonce;

	xpc_connection_t connection = xpc_connection_create_mach_service(
		kFaceIDMachServiceName, NULL, 0);
	if (connection == NULL) {
		return kFaceIDVerdictUnavailable;
	}

	// Target the console user's domain before resuming — after resume it is too late.
	uid_t consoleUID = FaceIDConsoleUID();
	xpc_connection_set_target_uid(connection, consoleUID);
	os_log(FaceIDLog(), "Asking the agent in session uid %d.", consoleUID);

	xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
		(void)event;  // Errors surface as a nil reply below.
	});
	xpc_connection_resume(connection);

	xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_string(request, kFaceIDKeyCommand, kFaceIDCommandAuthenticate);
	xpc_dictionary_set_data(request, kFaceIDKeyNonce, nonce, sizeof(nonce));
	if (username != NULL) {
		xpc_dictionary_set_string(request, kFaceIDKeyUsername, username);
	}

	dispatch_semaphore_t done = dispatch_semaphore_create(0);

	xpc_connection_send_message_with_reply(
		connection, request, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
		^(xpc_object_t reply) {
			if (xpc_get_type(reply) != XPC_TYPE_DICTIONARY) {
				dispatch_semaphore_signal(done);
				return;
			}

			// Identity first. An unverified peer's answer is discarded without being read,
			// so a hostile responder cannot influence anything below.
			if (!FaceIDPeerSatisfiesRequirement(connection, peerRequirement)) {
				os_log_error(FaceIDLog(), "Reply from an untrusted peer; discarding.");
				dispatch_semaphore_signal(done);
				return;
			}

			size_t replyNonceLength = 0;
			const void *replyNonce =
				xpc_dictionary_get_data(reply, kFaceIDKeyNonce, &replyNonceLength);
			if (replyNonce == NULL || replyNonceLength != kFaceIDNonceLength
				|| timingsafe_bcmp(replyNonce, sentNonce, kFaceIDNonceLength) != 0) {
				os_log_error(FaceIDLog(), "Reply nonce mismatch; discarding.");
				dispatch_semaphore_signal(done);
				return;
			}

			verdict = (FaceIDVerdict)xpc_dictionary_get_int64(reply, kFaceIDKeyVerdict);
			dispatch_semaphore_signal(done);
		});

	dispatch_time_t deadline = dispatch_time(
		DISPATCH_TIME_NOW, (int64_t)kFaceIDAuthenticateTimeoutSeconds * NSEC_PER_SEC);
	if (dispatch_semaphore_wait(done, deadline) != 0) {
		os_log_error(FaceIDLog(), "Agent did not answer in time.");
		verdict = kFaceIDVerdictUnavailable;
	}

	xpc_connection_cancel(connection);
	return verdict;
}

#pragma mark - Password

struct FaceIDPamContext {
	const char *password;
};

static int FaceIDPamConverse(
	int count, const struct pam_message **messages,
	struct pam_response **responses, void *context)
{
	if (count <= 0 || messages == NULL || responses == NULL) {
		return PAM_CONV_ERR;
	}

	struct FaceIDPamContext *ctx = (struct FaceIDPamContext *)context;
	struct pam_response *replies = calloc((size_t)count, sizeof(struct pam_response));
	if (replies == NULL) {
		return PAM_BUF_ERR;
	}

	for (int i = 0; i < count; i++) {
		if (messages[i]->msg_style == PAM_PROMPT_ECHO_OFF && ctx->password != NULL) {
			replies[i].resp = strdup(ctx->password);
		}
	}

	*responses = replies;
	return PAM_SUCCESS;
}

/// Verifies an account password through the same PAM service the screen lock uses.
///
/// Deliberately not a hand-rolled check: PAM is what enforces password policy, account
/// expiry and directory lookups, so anything less thorough here would authorise logins
/// the system itself would refuse.
static BOOL FaceIDPasswordIsValid(const char *username, const char *password)
{
	if (username == NULL || password == NULL) {
		return NO;
	}

	struct FaceIDPamContext context = { .password = password };
	struct pam_conv conversation = { FaceIDPamConverse, &context };
	pam_handle_t *handle = NULL;

	if (pam_start("screensaver", username, &conversation, &handle) != PAM_SUCCESS) {
		return NO;
	}

	// Hand PAM the password and the requester directly, rather than relying on the
	// conversation callback.
	//
	// `/etc/pam.d/screensaver` declares pam_opendirectory with **use_first_pass**, which
	// means it takes the password from a previous module instead of prompting. There is no
	// previous module, so the conversation function is never called and the password never
	// arrives — authentication fails for *every* password, including the correct one.
	//
	// The account stack then uses pam_self and pam_group with "ruser", which need to know
	// who is asking; without PAM_RUSER they fail even after a successful authentication.
	//
	// This was verified against the real PAM stack before being written here: without
	// PAM_AUTHTOK the correct password is rejected, and without PAM_RUSER account
	// management is. Both were silent failures that would only have surfaced at a locked
	// screen, with no way in.
	pam_set_item(handle, PAM_AUTHTOK, password);
	pam_set_item(handle, PAM_RUSER, username);
	pam_set_item(handle, PAM_TTY, "console");

	int status = pam_authenticate(handle, 0);
	if (status == PAM_SUCCESS) {
		status = pam_acct_mgmt(handle, 0);
	}
	pam_end(handle, status);

	return status == PAM_SUCCESS;
}

#pragma mark - View

@interface FaceIDPluginView : SFAuthorizationPluginView
@property (nonatomic, strong) NSView *container;
@property (nonatomic, strong) FaceIDCapsuleView *capsule;
@property (nonatomic, strong) NSSecureTextField *passwordField;
@property (nonatomic, copy) NSString *username;
/// NO when recognition cannot run, in which case the capsule is never shown.
@property (nonatomic, assign) BOOL faceIDAvailable;
@end

@implementation FaceIDPluginView

- (NSView *)viewForType:(SFViewType)type
{
	os_log_fault(FaceIDLog(), "viewForType: %ld called — SecurityAgent wants our view.",
		(long)type);

	if (self.container != nil) {
		return self.container;
	}

	self.container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 150)];

	if (self.faceIDAvailable) {
		self.capsule = [[FaceIDCapsuleView alloc]
			initWithFrame:NSMakeRect(0, 60, 320, 90)];
		self.capsule.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
		[self.container addSubview:self.capsule];
	}

	// The password field exists in both cases — it is the fallback after a rejected face
	// and the only option when Face ID cannot run — but it starts hidden while scanning
	// so the lock screen is not two competing prompts at once.
	self.passwordField = [[NSSecureTextField alloc]
		initWithFrame:NSMakeRect(40, 16, 240, 24)];
	self.passwordField.placeholderString = @"Password";
	self.passwordField.hidden = self.faceIDAvailable;
	[self.container addSubview:self.passwordField];

	return self.container;
}

- (NSView *)firstKeyView
{
	return self.passwordField;
}

- (NSResponder *)firstResponder
{
	return self.passwordField;
}

/// Reveals the password field once face recognition is out of attempts.
- (void)fallBackToPassword
{
	os_log_fault(FaceIDLog(), "fallBackToPassword: field=%{public}s window=%{public}s",
		self.passwordField != nil ? "exists" : "NIL",
		self.passwordField.window != nil ? "on screen" : "NO WINDOW");
	self.capsule.hidden = YES;
	self.passwordField.hidden = NO;
	[self.passwordField.window makeFirstResponder:self.passwordField];
}

/*
 Handles the panel's buttons.

 This is the only place a password is ever checked, and it is the reason the mechanism can
 be the sole entry in the rule: with no `builtin:authenticate` behind us, if this does not
 resolve the authorization then nothing does and the lock screen hangs. So both branches
 end in SetResult, and so does Cancel.
*/
- (void)buttonPressed:(SFButtonType)inButtonType
{
	const AuthorizationCallbacks *callbacks = [self callbacks];
	AuthorizationEngineRef engine = [self engineRef];

	if (inButtonType == SFButtonTypeCancel) {
		callbacks->SetResult(engine, kAuthorizationResultUserCanceled);
		return;
	}

	NSString *password = self.passwordField.stringValue ?: @"";
	const char *user = self.username.UTF8String;

	if (user != NULL && FaceIDPasswordIsValid(user, password.UTF8String)) {
		// Hand the password to the engine as well as allowing. Later mechanisms — and the
		// keychain unlock that follows a login — expect to find it in the context, and
		// omitting it leaves the session authenticated but the keychain locked.
		AuthorizationValue value = {
			.length = strlen(password.UTF8String),
			.data = (void *)password.UTF8String,
		};
		callbacks->SetContextValue(
			engine, kAuthorizationEnvironmentPassword, kAuthorizationContextFlagVolatile, &value);
		callbacks->SetResult(engine, kAuthorizationResultAllow);
		return;
	}

	// Clear the field and stay on the panel. Denying here would end the whole evaluation
	// on one typo rather than letting the user try again.
	self.passwordField.stringValue = @"";
	NSBeep();
}

@end

#pragma mark - Mechanism

typedef struct {
	const AuthorizationCallbacks *callbacks;
	AuthorizationEngineRef engine;
	/// Held as an opaque pointer with an explicit retain: ARC will not manage an
	/// Objective-C pointer living inside a malloc'd C struct.
	void *view;
	char peerRequirement[512];
} FaceIDMechanism;

typedef struct {
	const AuthorizationCallbacks *callbacks;
	char peerRequirement[512];
} FaceIDPlugin;

/// Reads the username the lock screen is authenticating.
static const char *FaceIDCurrentUsername(FaceIDMechanism *mechanism)
{
	const AuthorizationValue *value = NULL;
	OSStatus status = mechanism->callbacks->GetContextValue(
		mechanism->engine, kAuthorizationEnvironmentUsername, NULL, &value);
	if (status != errSecSuccess || value == NULL || value->data == NULL) {
		return NULL;
	}
	return (const char *)value->data;
}

static OSStatus FaceIDMechanismCreate(
	AuthorizationPluginRef inPlugin, AuthorizationEngineRef inEngine,
	AuthorizationMechanismId mechanismId, AuthorizationMechanismRef *outMechanism)
{
	

	os_log_fault(FaceIDLog(), "MechanismCreate for id '%{public}s'.", mechanismId);

	FaceIDPlugin *plugin = (FaceIDPlugin *)inPlugin;
	FaceIDMechanism *mechanism = calloc(1, sizeof(FaceIDMechanism));
	if (mechanism == NULL) {
		return errAuthorizationInternal;
	}

	mechanism->callbacks = plugin->callbacks;
	mechanism->engine = inEngine;
	strlcpy(mechanism->peerRequirement, plugin->peerRequirement,
		sizeof(mechanism->peerRequirement));

	*outMechanism = (AuthorizationMechanismRef)mechanism;
	return errAuthorizationSuccess;
}

static OSStatus FaceIDMechanismInvoke(AuthorizationMechanismRef inMechanism)
{
	FaceIDMechanism *mechanism = (FaceIDMechanism *)inMechanism;
	os_log_fault(FaceIDLog(), "MechanismInvoke entered.");
	const char *username = FaceIDCurrentUsername(mechanism);

	// No pinned requirement means we cannot tell our agent from anything else claiming to
	// be it, so recognition is not offered at all — password only, no capsule.
	BOOL canUseFaceID = mechanism->peerRequirement[0] != '\0';

	FaceIDRunOnMain(^{
		if (mechanism->view == NULL) {
			FaceIDPluginView *view = [[FaceIDPluginView alloc]
				initWithCallbacks:mechanism->callbacks andEngineRef:mechanism->engine];
			view.faceIDAvailable = canUseFaceID;
			view.username = username != NULL
				? [NSString stringWithUTF8String:username] : nil;
			mechanism->view = (void *)CFBridgingRetain(view);
		}
		FaceIDPluginView *v = (__bridge FaceIDPluginView *)mechanism->view;
		os_log_fault(FaceIDLog(), "Calling displayView.");
		[v displayView];
		os_log_fault(FaceIDLog(), "displayView returned; container=%{public}s",
			v.container != nil ? "built" : "NIL");
	});

	if (!canUseFaceID) {
		// Nothing to ask. Wait on the password field rather than resolving here.
		os_log(FaceIDLog(), "Face ID unavailable; password only.");
		return errAuthorizationSuccess;
	}

	// Ask the agent asynchronously and return immediately.
	//
	// The query blocks for up to kFaceIDAuthenticateTimeoutSeconds waiting on a reply, and
	// mechanisms are invoked on the main thread — so doing it inline freezes the UI. The
	// capsule would sit motionless and the panel would look hung for the whole scan, which
	// is precisely the moment it needs to be animating.
	//
	// Returning without SetResult is correct and deliberate: the mechanism stays live
	// until something resolves it, either the verdict below or `buttonPressed:`.
	char *usernameCopy = username != NULL ? strdup(username) : NULL;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		FaceIDVerdict verdict = FaceIDAskAgent(usernameCopy, mechanism->peerRequirement);
		free(usernameCopy);

		if (verdict == kFaceIDVerdictMatch) {
			os_log(FaceIDLog(), "Face recognised; allowing unlock.");
			// The checkmark plays before the result lands, so the confirmation is seen
			// rather than skipped past.
			FaceIDRunOnMain(^{
				FaceIDPluginView *view = (__bridge FaceIDPluginView *)mechanism->view;

				// The result must not depend on the animation running.
				//
				// Messaging a nil object is a silent no-op in Objective-C, so if there is
				// no capsule — no panel was built, as when the right is exercised from a
				// terminal — the completion block is simply dropped and SetResult is never
				// called. The mechanism then waits forever, which on a real lock screen is
				// the worst possible outcome. Resolve directly when there is nothing to
				// animate.
				if (view.capsule == nil) {
					mechanism->callbacks->SetResult(
						mechanism->engine, kAuthorizationResultAllow);
					return;
				}

				[view.capsule playSuccessThen:^{
					mechanism->callbacks->SetResult(
						mechanism->engine, kAuthorizationResultAllow);
				}];
			});
			return;
		}

		// Everything else — no match, lockout, an unreachable agent, a timeout — lands on
		// the password field. None of these are grounds to deny outright: denying would
		// leave the user unable to get in at all.
		os_log(FaceIDLog(), "Face not accepted (verdict %d); falling back to password.",
			(int)verdict);

		FaceIDRunOnMain(^{
			FaceIDPluginView *view = (__bridge FaceIDPluginView *)mechanism->view;
			[view.capsule playRejectionThen:^{
				[view fallBackToPassword];
			}];
		});
	});

	return errAuthorizationSuccess;
}

static OSStatus FaceIDMechanismDeactivate(AuthorizationMechanismRef inMechanism)
{
	FaceIDMechanism *mechanism = (FaceIDMechanism *)inMechanism;
	return mechanism->callbacks->DidDeactivate(mechanism->engine);
}

static OSStatus FaceIDMechanismDestroy(AuthorizationMechanismRef inMechanism)
{
	FaceIDMechanism *mechanism = (FaceIDMechanism *)inMechanism;
	if (mechanism->view != NULL) {
		// Balances the CFBridgingRetain in Invoke.
		CFRelease(mechanism->view);
		mechanism->view = NULL;
	}
	free(mechanism);
	return errAuthorizationSuccess;
}

static OSStatus FaceIDPluginDestroy(AuthorizationPluginRef inPlugin)
{
	free(inPlugin);
	return errAuthorizationSuccess;
}

static AuthorizationPluginInterface FaceIDPluginInterface = {
	kAuthorizationPluginInterfaceVersion,
	FaceIDPluginDestroy,
	FaceIDMechanismCreate,
	FaceIDMechanismInvoke,
	FaceIDMechanismDeactivate,
	FaceIDMechanismDestroy,
};

/// Entry point macOS looks up when loading the bundle.
OSStatus AuthorizationPluginCreate(
	const AuthorizationCallbacks *callbacks,
	AuthorizationPluginRef *outPlugin,
	const AuthorizationPluginInterface **outPluginInterface)
{
	// Fault level, unconditionally, as the very first thing.
	//
	// Apple's own guidance on the "library validation failed" dlopen error is that it is
	// misleading — the host logs it, then clears library validation and loads the plugin
	// anyway. Without a log on the *success* path there is no way to tell a plugin that
	// never loaded from one that loaded and then failed for an unrelated reason, and I
	// spent a long time assuming the former.
	os_log_fault(FaceIDLog(), "AuthorizationPluginCreate entered — the plugin IS loaded.");

	FaceIDPlugin *plugin = calloc(1, sizeof(FaceIDPlugin));
	if (plugin == NULL) {
		return errAuthorizationInternal;
	}
	plugin->callbacks = callbacks;

	// The requirement the agent must satisfy is written into the bundle at install time,
	// when the agent's cdhash is known. Without it we cannot identify the peer, so the
	// plugin degrades to password-only rather than trusting an unverifiable answer.
	NSBundle *bundle = [NSBundle bundleWithIdentifier:@"app.faceid.plugin"];
	NSString *requirement = [bundle objectForInfoDictionaryKey:@"FaceIDAgentRequirement"];
	if (requirement.length > 0) {
		strlcpy(plugin->peerRequirement, requirement.UTF8String,
			sizeof(plugin->peerRequirement));
	} else {
		os_log_error(FaceIDLog(), "No agent requirement pinned; Face ID disabled.");
	}

	*outPlugin = (AuthorizationPluginRef)plugin;
	*outPluginInterface = &FaceIDPluginInterface;
	return errAuthorizationSuccess;
}
