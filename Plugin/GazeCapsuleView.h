/*
 The capsule shown on the lock screen while Gaze runs.

 States follow the iPhone: it scans, and on a face it does not recognise it shakes and
 says so, then scans again. After the attempt budget is spent it stops and hands over to
 the password field. On a match it turns into a checkmark and the Mac unlocks.

 The one rule that shapes everything here: the capsule only ever appears when recognition
 is genuinely running. If nothing is enrolled, the camera is unavailable, the agent is
 unreachable or the user is locked out, this view is never created and the panel shows a
 plain password field. An animation that implies the Mac is looking at you when it isn't
 is a lie, and it trains you to trust a signal that means nothing.
*/

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, GazeCapsuleState) {
	/// Looking for a face.
	GazeCapsuleStateScanning,
	/// A face was seen and rejected. Shakes, then returns to scanning.
	GazeCapsuleStateNotRecognised,
	/// Matched. Morphs to a checkmark.
	GazeCapsuleStateSuccess,
};

@interface GazeCapsuleView : NSView

@property (nonatomic, assign) GazeCapsuleState state;

/// Plays the rejection shake, then calls back so the caller can resume scanning.
- (void)playRejectionThen:(void (^)(void))completion;

/// Plays the success morph, then calls back so the caller can allow the unlock.
- (void)playSuccessThen:(void (^)(void))completion;

@end
