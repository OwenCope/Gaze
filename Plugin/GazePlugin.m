/*
 The Gaze authorization plugin.

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

#import "GazeCapsuleView.h"
#import "GazeUnlockProtocol.h"
#import "PeerTrust.h"

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Security/AuthorizationPlugin.h>
#import <SecurityInterface/SFAuthorizationPluginView.h>
#import <os/log.h>
#import <security/pam_appl.h>
#import <pwd.h>
#import <sys/stat.h>
#import <xpc/xpc.h>

static os_log_t GazeLog(void)
{
	static os_log_t log;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		log = os_log_create("com.gazeunlock.Gaze.plugin", "Mechanism");
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
static void GazeRunOnMain(dispatch_block_t block)
{
	if ([NSThread isMainThread]) {
		block();
	} else {
		dispatch_sync(dispatch_get_main_queue(), block);
	}
}

/*
 Reaching the agent's mach service across login-session boundaries.

 The agent registers `com.gazeunlock.Gaze.unlock` in the console user's GUI domain (`gui/501`).
 The plugin runs as `_securityagent`, in a different domain, so an ordinary lookup finds
 nothing and simply times out — which is indistinguishable from the agent being down.

 SecurityAgentHelper is entitled with `com.apple.private.xpc.launchd.per-user-lookup`
 precisely so it can cross that boundary; it just has to name the user. These are the SPI
 that do it. Declared here because libxpc exports them without a public header.
*/
extern void xpc_connection_set_target_uid(xpc_connection_t connection, uid_t uid);

/// The uid of whoever owns the console — the session whose agent we want.
static uid_t GazeConsoleUID(void)
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
 GazeUnlockProtocol.h for why neither check alone is enough.
*/
static GazeVerdict GazeAskAgent(const char *username, const char *peerRequirement)
{
	__block GazeVerdict verdict = kGazeVerdictUnavailable;

	uint8_t nonce[kGazeNonceLength];
	if (SecRandomCopyBytes(kSecRandomDefault, sizeof(nonce), nonce) != errSecSuccess) {
		os_log_error(GazeLog(), "Could not generate a nonce; refusing to ask.");
		return kGazeVerdictUnavailable;
	}
	// A block cannot capture an array, so compare through a pointer. It stays valid for
	// the block's lifetime because this function waits on the semaphore below before
	// returning, so the stack frame outlives the reply.
	const uint8_t *sentNonce = nonce;

	xpc_connection_t connection = xpc_connection_create_mach_service(
		kGazeMachServiceName, NULL, 0);
	if (connection == NULL) {
		return kGazeVerdictUnavailable;
	}

	// Target the console user's domain before resuming — after resume it is too late.
	uid_t consoleUID = GazeConsoleUID();
	xpc_connection_set_target_uid(connection, consoleUID);
	os_log(GazeLog(), "Asking the agent in session uid %d.", consoleUID);

	xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
		(void)event;  // Errors surface as a nil reply below.
	});
	xpc_connection_resume(connection);

	xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_string(request, kGazeKeyCommand, kGazeCommandAuthenticate);
	xpc_dictionary_set_data(request, kGazeKeyNonce, nonce, sizeof(nonce));
	if (username != NULL) {
		xpc_dictionary_set_string(request, kGazeKeyUsername, username);
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
			if (!GazePeerSatisfiesRequirement(connection, peerRequirement)) {
				os_log_error(GazeLog(), "Reply from an untrusted peer; discarding.");
				dispatch_semaphore_signal(done);
				return;
			}

			size_t replyNonceLength = 0;
			const void *replyNonce =
				xpc_dictionary_get_data(reply, kGazeKeyNonce, &replyNonceLength);
			if (replyNonce == NULL || replyNonceLength != kGazeNonceLength
				|| timingsafe_bcmp(replyNonce, sentNonce, kGazeNonceLength) != 0) {
				os_log_error(GazeLog(), "Reply nonce mismatch; discarding.");
				dispatch_semaphore_signal(done);
				return;
			}

			verdict = (GazeVerdict)xpc_dictionary_get_int64(reply, kGazeKeyVerdict);
			dispatch_semaphore_signal(done);
		});

	dispatch_time_t deadline = dispatch_time(
		DISPATCH_TIME_NOW, (int64_t)kGazeAuthenticateTimeoutSeconds * NSEC_PER_SEC);
	if (dispatch_semaphore_wait(done, deadline) != 0) {
		os_log_error(GazeLog(), "Agent did not answer in time.");
		verdict = kGazeVerdictUnavailable;
	}

	xpc_connection_cancel(connection);
	return verdict;
}

#pragma mark - Password

struct GazePamContext {
	const char *password;
};

static int GazePamConverse(
	int count, const struct pam_message **messages,
	struct pam_response **responses, void *context)
{
	if (count <= 0 || messages == NULL || responses == NULL) {
		return PAM_CONV_ERR;
	}

	struct GazePamContext *ctx = (struct GazePamContext *)context;
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
static BOOL GazePasswordIsValid(const char *username, const char *password)
{
	if (username == NULL || password == NULL) {
		return NO;
	}

	struct GazePamContext context = { .password = password };
	struct pam_conv conversation = { GazePamConverse, &context };
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

#pragma mark - Panel window

/// A borderless window that can become key.
///
/// `NSWindow` returns NO from `canBecomeKeyWindow` for borderless windows by default, so
/// the password field could be focused but never received a keystroke — the field looked
/// live and simply ignored typing. Overriding both is what makes keyboard input reach it.
@interface GazePanelWindow : NSWindow
@end

@implementation GazePanelWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

#pragma mark - View

@interface GazePluginView : NSObject
@property (nonatomic, strong) NSView *container;
@property (nonatomic, strong) GazeCapsuleView *capsule;
@property (nonatomic, strong) NSSecureTextField *passwordField;
@property (nonatomic, copy) NSString *username;
/// NO when recognition cannot run, in which case the capsule is never shown.
@property (nonatomic, assign) BOOL gazeAvailable;
@property (nonatomic, strong) NSWindow *panelWindow;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSImageView *glyphView;
@property (nonatomic, strong) CAShapeLayer *panelBody;
@property (nonatomic, assign) CGFloat notchHeight;
@property (nonatomic, strong) NSView *fieldContainer;

/// Declared explicitly rather than relying on the call site sitting below the
/// @implementation — that works, but it means a typo becomes a runtime no-op instead of
/// a compile error.
- (void)presentOwnPanel;
- (void)expandForPassword;
- (void)dismissPanel;
- (void)showSuccess;
- (void)fallBackToPassword;

/// We hold the engine handles ourselves now, rather than inheriting them.
@property (nonatomic, assign) const AuthorizationCallbacks *callbacks;
@property (nonatomic, assign) AuthorizationEngineRef engineRef;
- (instancetype)initWithCallbacks:(const AuthorizationCallbacks *)callbacks
                     andEngineRef:(AuthorizationEngineRef)engineRef;
@end

@implementation GazePluginView

/*
 Plain NSObject, not SFAuthorizationPluginView.

 That base class's initialiser returns nil in this context, and because messaging nil is
 a silent no-op in Objective-C every subsequent call vanished without a trace: displayView
 appeared to "return immediately", `container` read as NIL, and presentOwnPanel was never
 entered. All three symptoms were one nil object.

 Nothing of it is missed — it never handed us a view (`viewForType:` was never called), and
 we draw our own window now.
*/
- (instancetype)initWithCallbacks:(const AuthorizationCallbacks *)callbacks
                     andEngineRef:(AuthorizationEngineRef)engineRef
{
	self = [super init];
	if (self) {
		_callbacks = callbacks;
		_engineRef = engineRef;
	}
	return self;
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
	os_log_fault(GazeLog(), "fallBackToPassword: field=%{public}s window=%{public}s",
		self.passwordField != nil ? "exists" : "NIL",
		self.passwordField.window != nil ? "on screen" : "NO WINDOW");
	self.statusLabel.stringValue = @"Face not recognised — enter your password";
	[self expandForPassword];
	self.fieldContainer.hidden = NO;
	[self.panelWindow makeKeyAndOrderFront:nil];
	[NSApp activateIgnoringOtherApps:YES];
	[self.panelWindow makeFirstResponder:self.passwordField];
	os_log_fault(GazeLog(), "Password field shown: key=%{public}s firstResponder=%{public}s",
		self.panelWindow.isKeyWindow ? "YES" : "NO",
		self.panelWindow.firstResponder == self.passwordField ? "field" : "other");
}

/*
 Handles the panel's buttons.

 This is the only place a password is ever checked, and it is the reason the mechanism can
 be the sole entry in the rule: with no `builtin:authenticate` behind us, if this does not
 resolve the authorization then nothing does and the lock screen hangs. So both branches
 end in SetResult, and so does Cancel.
*/
/// Builds and shows our own window, since SecurityAgent never requests a view.
- (void)presentOwnPanel
{
	os_log_fault(GazeLog(), "presentOwnPanel ENTERED (thread=%{public}s)",
		[NSThread isMainThread] ? "main" : "background");

	if (self.panelWindow != nil) {
		[self.panelWindow makeKeyAndOrderFront:nil];
		return;
	}

	NSScreen *screen = [NSScreen mainScreen];
	if (screen == nil) {
		return;
	}

	// Measured from the two menu bar fragments either side of the camera housing.
	// Falls back to a sensible width on a screen with no notch.
	CGFloat notchWidth = 180;
	NSRect left = screen.auxiliaryTopLeftArea;
	NSRect right = screen.auxiliaryTopRightArea;
	if (!NSIsEmptyRect(left) && !NSIsEmptyRect(right)) {
		CGFloat gap = NSMinX(right) - NSMaxX(left);
		if (gap > 0) {
			notchWidth = gap;
		}
	}
	self.notchHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32;

	// Wider than the cutout, matching what notch apps present, and tall enough that the
	// panel can grow downward when it needs a password field.
	const CGFloat width = notchWidth * 1.56;
	const CGFloat drop = 66;
	const CGFloat height = self.notchHeight + drop;

	NSWindow *window = [[GazePanelWindow alloc]
		initWithContentRect:NSMakeRect(NSMidX(screen.frame) - width / 2,
									   NSMaxY(screen.frame) - height,
									   width, height)
				  styleMask:NSWindowStyleMaskBorderless
					backing:NSBackingStoreBuffered
					  defer:NO];
	window.backgroundColor = [NSColor clearColor];
	window.opaque = NO;
	window.hasShadow = NO;
	window.level = NSScreenSaverWindowLevel + 1;
	window.releasedWhenClosed = NO;

	// The window spans the cutout as well as the visible drop, so the black runs
	// continuously out of the notch instead of butting against it with a seam.
	NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	content.wantsLayer = YES;
	window.contentView = content;

	CAShapeLayer *body = [CAShapeLayer layer];
	body.fillColor = [[NSColor blackColor] CGColor];
	body.path = [self panelPathForWidth:width height:height];
	// Dissolves toward the bottom rather than ending in a hard edge, so it reads as the
	// notch extending instead of a rectangle stuck underneath it.
	CAGradientLayer *fade = [CAGradientLayer layer];
	fade.frame = NSMakeRect(0, 0, width, height);
	fade.colors = @[ (id)[[NSColor clearColor] CGColor],
					 (id)[[NSColor blackColor] CGColor],
					 (id)[[NSColor blackColor] CGColor] ];
	fade.locations = @[ @0.0, @0.34, @1.0 ];
	body.mask = fade;
	[content.layer addSublayer:body];

	NSImageSymbolConfiguration *config =
		[NSImageSymbolConfiguration configurationWithPointSize:26
													   weight:NSFontWeightRegular
														scale:NSImageSymbolScaleMedium];
	NSImage *glyph = [[NSImage imageWithSystemSymbolName:@"faceid"
							   accessibilityDescription:nil]
		imageWithSymbolConfiguration:config];
	self.glyphView = [NSImageView imageViewWithImage:glyph];
	self.glyphView.contentTintColor = [NSColor whiteColor];
	self.glyphView.frame = NSMakeRect((width - 34) / 2, drop - 52, 34, 34);
	[content addSubview:self.glyphView];

	self.statusLabel = [NSTextField labelWithString:@""];
	self.statusLabel.font = [NSFont systemFontOfSize:11];
	self.statusLabel.textColor = [NSColor colorWithWhite:1.0 alpha:0.6];
	self.statusLabel.alignment = NSTextAlignmentCenter;
	self.statusLabel.frame = NSMakeRect(8, drop - 74, width - 16, 16);
	[content addSubview:self.statusLabel];

	// The field lives inside a rounded container. Setting cornerRadius on the text field
	// directly leaves the cell's own corners square, so the rounding never shows.
	self.fieldContainer = [[NSView alloc]
		initWithFrame:NSMakeRect(22, 16, width - 44, 30)];
	self.fieldContainer.wantsLayer = YES;
	self.fieldContainer.layer.backgroundColor =
		[[NSColor colorWithWhite:0.16 alpha:1.0] CGColor];
	self.fieldContainer.layer.cornerRadius = 15;
	self.fieldContainer.layer.cornerCurve = kCACornerCurveContinuous;
	self.fieldContainer.layer.borderWidth = 0.5;
	self.fieldContainer.layer.borderColor =
		[[NSColor colorWithWhite:1.0 alpha:0.10] CGColor];
	self.fieldContainer.hidden = YES;
	[content addSubview:self.fieldContainer];

	self.passwordField = [[NSSecureTextField alloc]
		initWithFrame:NSMakeRect(10, 6, NSWidth(self.fieldContainer.frame) - 20, 18)];
	self.passwordField.placeholderString = @"Password";
	self.passwordField.font = [NSFont systemFontOfSize:12];
	self.passwordField.alignment = NSTextAlignmentCenter;
	self.passwordField.bezeled = NO;
	self.passwordField.drawsBackground = NO;
	self.passwordField.textColor = [NSColor whiteColor];
	self.passwordField.focusRingType = NSFocusRingTypeNone;
	self.passwordField.target = self;
	self.passwordField.action = @selector(passwordEntered:);
	[self.fieldContainer addSubview:self.passwordField];

	self.panelBody = body;
	self.panelWindow = window;
	[window orderFrontRegardless];

	os_log_fault(GazeLog(), "Own panel presented at the notch: visible=%{public}s",
		window.isVisible ? "YES" : "NO");
}

/// Square across the top where it meets the cutout, rounded along the bottom.
- (CGPathRef)panelPathForWidth:(CGFloat)width height:(CGFloat)height
{
	const CGFloat radius = 16;
	CGMutablePathRef path = CGPathCreateMutable();
	CGPathMoveToPoint(path, NULL, 0, height);
	CGPathAddLineToPoint(path, NULL, 0, radius);
	CGPathAddArcToPoint(path, NULL, 0, 0, radius, 0, radius);
	CGPathAddLineToPoint(path, NULL, width - radius, 0);
	CGPathAddArcToPoint(path, NULL, width, 0, width, radius, radius);
	CGPathAddLineToPoint(path, NULL, width, height);
	CGPathCloseSubpath(path);
	return (CGPathRef)CFAutorelease(path);
}

/// Grows the panel downward to make room for the password field.
- (void)expandForPassword
{
	NSWindow *window = self.panelWindow;
	if (window == nil) {
		return;
	}

	NSRect frame = window.frame;
	// Enough that the field can sit clear of the bottom edge with room to dissolve
	// beneath it. At 58 the field ended up ~16pt from the edge, which left no space for
	// the fade — the panel just stopped.
	const CGFloat extra = 96;
	frame.origin.y -= extra;
	frame.size.height += extra;

	[window setFrame:frame display:YES animate:NO];
	self.panelBody.path = [self panelPathForWidth:NSWidth(frame) height:NSHeight(frame)];
	((CAGradientLayer *)self.panelBody.mask).frame =
		NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame));

	// Everything shifts up by the amount the window grew downward, and re-centres for
	// the new width.
	NSView *content = window.contentView;
	const CGFloat newWidth = NSWidth(frame);
	for (NSView *view in content.subviews) {
		NSRect f = view.frame;
		f.origin.y += extra;
		if (view == self.statusLabel) {
			f.origin.x = 12;
			f.size.width = newWidth - 24;
		} else {
			f.origin.x = (newWidth - NSWidth(f)) / 2;
		}
		view.frame = f;
	}

	NSRect fieldFrame = self.fieldContainer.frame;
	fieldFrame.size.width = newWidth - 56;
	fieldFrame.origin.x = 28;
	fieldFrame.origin.y = 46;
	self.fieldContainer.frame = fieldFrame;

	NSRect inner = self.passwordField.frame;
	inner.size.width = NSWidth(fieldFrame) - 20;
	self.passwordField.frame = inner;

	// Pull the fade back once the field is showing. At its scanning extent the gradient
	// reaches well past the field and washes it out — the dissolve is there to soften an
	// empty bottom edge, not to erase content.
	// The dissolve now happens in the empty band below the field rather than across it.
	CAGradientLayer *fade = (CAGradientLayer *)self.panelBody.mask;
	fade.locations = @[ @0.0, @0.22, @1.0 ];
}

/// Tears the panel down.
///
/// Must be called when the mechanism deactivates or is destroyed. The window lives in
/// SecurityAgentHelper, not in whatever asked for the authorization — so if the requester
/// quits or is killed, nothing else closes it and it stays on screen above everything,
/// unclosable. At a lock screen that would be considerably worse than a stray window.
- (void)dismissPanel
{
	if (self.panelWindow == nil) {
		return;
	}
	os_log_fault(GazeLog(), "Dismissing panel.");
	[self.panelWindow orderOut:nil];
	[self.panelWindow close];
	self.panelWindow = nil;
}

/// Shows the matched state on our own panel.
- (void)showSuccess
{
	self.statusLabel.stringValue = @"Face recognised";
	self.passwordField.hidden = YES;
	self.glyphView.image = [[NSImage imageWithSystemSymbolName:@"checkmark.circle.fill"
									 accessibilityDescription:nil]
		imageWithSymbolConfiguration:
			[NSImageSymbolConfiguration configurationWithPointSize:52
															weight:NSFontWeightSemibold
															 scale:NSImageSymbolScaleLarge]];
}

/// Return pressed in the password field.
- (void)passwordEntered:(id)sender
{
	NSString *entered = self.passwordField.stringValue ?: @"";
	const char *user = self.username.UTF8String;

	if (user != NULL && GazePasswordIsValid(user, entered.UTF8String)) {
		os_log_fault(GazeLog(), "Password accepted; allowing.");
		[self.panelWindow orderOut:nil];
		[self callbacks]->SetResult([self engineRef], kAuthorizationResultAllow);
		return;
	}

	os_log_fault(GazeLog(), "Password rejected (user=%{public}s).",
		user != NULL ? user : "NULL");
	self.passwordField.stringValue = @"";
	self.statusLabel.stringValue = @"Incorrect password";
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
} GazeMechanism;

typedef struct {
	const AuthorizationCallbacks *callbacks;
	char peerRequirement[512];
} GazePlugin;

/// Reads the username being authenticated.
///
/// The lock screen puts it in the authorization context, but nothing sets it for a right
/// invoked from an ordinary application — and a nil username makes the password check
/// refuse every password, which reads as "incorrect" no matter what is typed. Fall back to
/// whoever owns the console, which is the person in front of the machine either way.
static const char *GazeCurrentUsername(GazeMechanism *mechanism)
{
	const AuthorizationValue *value = NULL;
	OSStatus status = mechanism->callbacks->GetContextValue(
		mechanism->engine, kAuthorizationEnvironmentUsername, NULL, &value);

	if (status == errSecSuccess && value != NULL && value->data != NULL
		&& ((const char *)value->data)[0] != '\0') {
		os_log_fault(GazeLog(), "Username from context: %{public}s",
			(const char *)value->data);
		return (const char *)value->data;
	}

	static char fallback[256];
	struct passwd *pw = getpwuid(GazeConsoleUID());
	if (pw != NULL && pw->pw_name != NULL) {
		strlcpy(fallback, pw->pw_name, sizeof(fallback));
		os_log_fault(GazeLog(), "No username in context; using console user %{public}s",
			fallback);
		return fallback;
	}

	os_log_error(GazeLog(), "No username available at all.");
	return NULL;
}

static OSStatus GazeMechanismCreate(
	AuthorizationPluginRef inPlugin, AuthorizationEngineRef inEngine,
	AuthorizationMechanismId mechanismId, AuthorizationMechanismRef *outMechanism)
{
	

	os_log_fault(GazeLog(), "MechanismCreate for id '%{public}s'.", mechanismId);

	GazePlugin *plugin = (GazePlugin *)inPlugin;
	GazeMechanism *mechanism = calloc(1, sizeof(GazeMechanism));
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

static OSStatus GazeMechanismInvoke(AuthorizationMechanismRef inMechanism)
{
	GazeMechanism *mechanism = (GazeMechanism *)inMechanism;
	os_log_fault(GazeLog(), "MechanismInvoke entered.");
	const char *username = GazeCurrentUsername(mechanism);

	// No pinned requirement means we cannot tell our agent from anything else claiming to
	// be it, so recognition is not offered at all — password only, no capsule.
	BOOL canUseGaze = mechanism->peerRequirement[0] != '\0';

	GazeRunOnMain(^{
		if (mechanism->view == NULL) {
			GazePluginView *view = [[GazePluginView alloc]
				initWithCallbacks:mechanism->callbacks andEngineRef:mechanism->engine];
			view.gazeAvailable = canUseGaze;
			view.username = username != NULL
				? [NSString stringWithUTF8String:username] : nil;
			mechanism->view = (void *)CFBridgingRetain(view);
		}
		GazePluginView *v = (__bridge GazePluginView *)mechanism->view;
		os_log_fault(GazeLog(), "View object is %{public}s",
			v != nil ? "alive" : "NIL — nothing will happen");

		// We draw our own window rather than relying on SFAuthorizationPluginView.
		//
		// `displayView` returns without ever calling `viewForType:` — SecurityAgent does
		// not ask for our view, so that API gives us no UI at all. But this process has a
		// window server connection and a live AppKit run loop (verified: a plain NSWindow
		// reports visible=YES), so the plugin can present its own panel. That is also
		// better than the original plan: we control every pixel instead of living inside
		// Apple's dialog.
		// Nothing is shown yet. The app renders the capsule at the notch while it looks —
		// it is doing the recognition, it has the polished SwiftUI panel, and it can put a
		// window on the lock screen through its own SkyLight space. A second panel drawn
		// here would just be a cruder duplicate on top of it.
		//
		// This only puts UI on screen if the face fails and a password is needed.
		(void)v;
	});

	if (!canUseGaze) {
		// Nothing to ask. Wait on the password field rather than resolving here.
		os_log(GazeLog(), "Gaze unavailable; password only.");
		return errAuthorizationSuccess;
	}

	// Ask the agent asynchronously and return immediately.
	//
	// The query blocks for up to kGazeAuthenticateTimeoutSeconds waiting on a reply, and
	// mechanisms are invoked on the main thread — so doing it inline freezes the UI. The
	// capsule would sit motionless and the panel would look hung for the whole scan, which
	// is precisely the moment it needs to be animating.
	//
	// Returning without SetResult is correct and deliberate: the mechanism stays live
	// until something resolves it, either the verdict below or `buttonPressed:`.
	char *usernameCopy = username != NULL ? strdup(username) : NULL;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		GazeVerdict verdict = GazeAskAgent(usernameCopy, mechanism->peerRequirement);
		free(usernameCopy);

		if (verdict == kGazeVerdictMatch) {
			os_log(GazeLog(), "Face recognised; allowing unlock.");
			// The checkmark plays before the result lands, so the confirmation is seen
			// rather than skipped past.
			GazeRunOnMain(^{
				GazePluginView *view = (__bridge GazePluginView *)mechanism->view;

				// The result must not depend on the animation running.
				//
				// Messaging a nil object is a silent no-op in Objective-C, so if there is
				// no capsule — no panel was built, as when the right is exercised from a
				// terminal — the completion block is simply dropped and SetResult is never
				// called. The mechanism then waits forever, which on a real lock screen is
				// the worst possible outcome. Resolve directly when there is nothing to
				// animate.
				[view showSuccess];
				mechanism->callbacks->SetResult(
					mechanism->engine, kAuthorizationResultAllow);
			});
			return;
		}

		// Everything else — no match, lockout, an unreachable agent, a timeout — lands on
		// the password field. None of these are grounds to deny outright: denying would
		// leave the user unable to get in at all.
		os_log(GazeLog(), "Face not accepted (verdict %d); falling back to password.",
			(int)verdict);

		GazeRunOnMain(^{
			GazePluginView *view = (__bridge GazePluginView *)mechanism->view;

			// Reveal the field directly rather than from an animation completion.
			//
			// This used to hang off [view.capsule playRejectionThen:], and `capsule` is
			// nil now that we build our own panel — so the completion was silently
			// dropped and the password field never appeared. Same nil-messaging trap as
			// the success path had: the animation is decoration, the fallback is not, so
			// the fallback must not depend on it.
			[view fallBackToPassword];
			[view.capsule playRejectionThen:nil];
		});
	});

	return errAuthorizationSuccess;
}

static OSStatus GazeMechanismDeactivate(AuthorizationMechanismRef inMechanism)
{
	GazeMechanism *mechanism = (GazeMechanism *)inMechanism;

	GazeRunOnMain(^{
		[(__bridge GazePluginView *)mechanism->view dismissPanel];
	});
	return mechanism->callbacks->DidDeactivate(mechanism->engine);
}

static OSStatus GazeMechanismDestroy(AuthorizationMechanismRef inMechanism)
{
	GazeMechanism *mechanism = (GazeMechanism *)inMechanism;
	if (mechanism->view != NULL) {
		// Belt and braces: if the evaluation was torn down without a Deactivate, this is
		// the last chance to get the window off the screen.
		GazeRunOnMain(^{
			[(__bridge GazePluginView *)mechanism->view dismissPanel];
		});
		// Balances the CFBridgingRetain in Invoke.
		CFRelease(mechanism->view);
		mechanism->view = NULL;
	}
	free(mechanism);
	return errAuthorizationSuccess;
}

static OSStatus GazePluginDestroy(AuthorizationPluginRef inPlugin)
{
	free(inPlugin);
	return errAuthorizationSuccess;
}

static AuthorizationPluginInterface GazePluginInterface = {
	kAuthorizationPluginInterfaceVersion,
	GazePluginDestroy,
	GazeMechanismCreate,
	GazeMechanismInvoke,
	GazeMechanismDeactivate,
	GazeMechanismDestroy,
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
	os_log_fault(GazeLog(), "AuthorizationPluginCreate entered — the plugin IS loaded.");

	GazePlugin *plugin = calloc(1, sizeof(GazePlugin));
	if (plugin == NULL) {
		return errAuthorizationInternal;
	}
	plugin->callbacks = callbacks;

	// The requirement the agent must satisfy is written into the bundle at install time,
	// when the agent's cdhash is known. Without it we cannot identify the peer, so the
	// plugin degrades to password-only rather than trusting an unverifiable answer.
	NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.gazeunlock.Gaze.plugin"];
	NSString *requirement = [bundle objectForInfoDictionaryKey:@"GazeAgentRequirement"];
	if (requirement.length > 0) {
		strlcpy(plugin->peerRequirement, requirement.UTF8String,
			sizeof(plugin->peerRequirement));
	} else {
		os_log_error(GazeLog(), "No agent requirement pinned; Gaze disabled.");
	}

	*outPlugin = (AuthorizationPluginRef)plugin;
	*outPluginInterface = &GazePluginInterface;
	return errAuthorizationSuccess;
}
