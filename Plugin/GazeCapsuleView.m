#import "GazeCapsuleView.h"

#import <QuartzCore/QuartzCore.h>

/// Side of the dark squircle, in points.
static const CGFloat kCapsuleSide = 62.0;
static const CGFloat kCapsuleCorner = 19.0;
/// The glyph occupies this fraction of the capsule.
static const CGFloat kGlyphInset = 17.0;

@interface GazeCapsuleView ()
@property (nonatomic, strong) CAShapeLayer *capsuleLayer;
@property (nonatomic, strong) CAShapeLayer *glyphLayer;
@property (nonatomic, strong) CAShapeLayer *checkLayer;
@property (nonatomic, strong) NSTextField *statusLabel;
@end

@implementation GazeCapsuleView

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self == nil) {
		return nil;
	}

	self.wantsLayer = YES;
	self.layer = [CALayer layer];

	// Dark squircle. Drawn rather than an image so it stays crisp at any backing scale
	// and so the corner curvature matches the glyph's.
	_capsuleLayer = [CAShapeLayer layer];
	_capsuleLayer.fillColor = [[NSColor colorWithWhite:0.09 alpha:1.0] CGColor];
	[self.layer addSublayer:_capsuleLayer];

	_glyphLayer = [CAShapeLayer layer];
	_glyphLayer.fillColor = nil;
	_glyphLayer.strokeColor = [[NSColor whiteColor] CGColor];
	_glyphLayer.lineWidth = 2.4;
	_glyphLayer.lineCap = kCALineCapRound;
	_glyphLayer.lineJoin = kCALineJoinRound;
	[self.layer addSublayer:_glyphLayer];

	_checkLayer = [CAShapeLayer layer];
	_checkLayer.fillColor = nil;
	_checkLayer.strokeColor = [[NSColor whiteColor] CGColor];
	_checkLayer.lineWidth = 2.8;
	_checkLayer.lineCap = kCALineCapRound;
	_checkLayer.lineJoin = kCALineJoinRound;
	_checkLayer.opacity = 0.0;
	[self.layer addSublayer:_checkLayer];

	_statusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
	_statusLabel.editable = NO;
	_statusLabel.bordered = NO;
	_statusLabel.drawsBackground = NO;
	_statusLabel.alignment = NSTextAlignmentCenter;
	_statusLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
	_statusLabel.textColor = [NSColor secondaryLabelColor];
	_statusLabel.stringValue = @"";
	[self addSubview:_statusLabel];

	_state = GazeCapsuleStateScanning;
	return self;
}

- (void)layout
{
	[super layout];

	CGRect bounds = self.bounds;
	CGRect capsule = CGRectMake(
		CGRectGetMidX(bounds) - kCapsuleSide / 2.0,
		CGRectGetMaxY(bounds) - kCapsuleSide,
		kCapsuleSide, kCapsuleSide);

	// Disable implicit animation, or every layout pass slides the layers around.
	[CATransaction begin];
	[CATransaction setDisableActions:YES];

	self.capsuleLayer.frame = self.layer.bounds;
	self.capsuleLayer.path = [self squirclePathInRect:capsule];

	CGRect glyphRect = CGRectInset(capsule, kGlyphInset, kGlyphInset);
	self.glyphLayer.frame = self.layer.bounds;
	self.glyphLayer.path = [self faceGlyphPathInRect:glyphRect];

	self.checkLayer.frame = self.layer.bounds;
	self.checkLayer.path = [self checkmarkPathInRect:glyphRect];

	self.statusLabel.frame = NSMakeRect(
		0, CGRectGetMinY(capsule) - 26, CGRectGetWidth(bounds), 18);

	[CATransaction commit];
}

// MARK: - Paths

- (CGPathRef)squirclePathInRect:(CGRect)rect
{
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect
														xRadius:kCapsuleCorner
														yRadius:kCapsuleCorner];
	return [path CGPath];
}

/// The Gaze mark: four corner brackets around a simplified face.
- (CGPathRef)faceGlyphPathInRect:(CGRect)rect
{
	CGMutablePathRef path = CGPathCreateMutable();

	CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
	CGFloat x0 = CGRectGetMinX(rect), y0 = CGRectGetMinY(rect);
	CGFloat arm = w * 0.30, radius = w * 0.20;

	// Brackets, corner by corner.
	CGPathMoveToPoint(path, NULL, x0, y0 + arm);
	CGPathAddArcToPoint(path, NULL, x0, y0, x0 + arm, y0, radius);
	CGPathAddLineToPoint(path, NULL, x0 + arm, y0);

	CGPathMoveToPoint(path, NULL, x0 + w - arm, y0);
	CGPathAddArcToPoint(path, NULL, x0 + w, y0, x0 + w, y0 + arm, radius);
	CGPathAddLineToPoint(path, NULL, x0 + w, y0 + arm);

	CGPathMoveToPoint(path, NULL, x0 + w, y0 + h - arm);
	CGPathAddArcToPoint(path, NULL, x0 + w, y0 + h, x0 + w - arm, y0 + h, radius);
	CGPathAddLineToPoint(path, NULL, x0 + w - arm, y0 + h);

	CGPathMoveToPoint(path, NULL, x0 + arm, y0 + h);
	CGPathAddArcToPoint(path, NULL, x0, y0 + h, x0, y0 + h - arm, radius);
	CGPathAddLineToPoint(path, NULL, x0, y0 + h - arm);

	// Eyes.
	CGFloat eyeTop = y0 + h * 0.66, eyeBottom = y0 + h * 0.52;
	CGPathMoveToPoint(path, NULL, x0 + w * 0.33, eyeTop);
	CGPathAddLineToPoint(path, NULL, x0 + w * 0.33, eyeBottom);
	CGPathMoveToPoint(path, NULL, x0 + w * 0.67, eyeTop);
	CGPathAddLineToPoint(path, NULL, x0 + w * 0.67, eyeBottom);

	// Nose, then mouth.
	CGPathMoveToPoint(path, NULL, x0 + w * 0.50, y0 + h * 0.62);
	CGPathAddLineToPoint(path, NULL, x0 + w * 0.50, y0 + h * 0.40);
	CGPathAddQuadCurveToPoint(
		path, NULL, x0 + w * 0.50, y0 + h * 0.34, x0 + w * 0.60, y0 + h * 0.34);

	CGPathMoveToPoint(path, NULL, x0 + w * 0.32, y0 + h * 0.24);
	CGPathAddQuadCurveToPoint(
		path, NULL, x0 + w * 0.50, y0 + h * 0.10, x0 + w * 0.68, y0 + h * 0.24);

	return (CGPathRef)CFAutorelease(path);
}

- (CGPathRef)checkmarkPathInRect:(CGRect)rect
{
	CGMutablePathRef path = CGPathCreateMutable();
	CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
	CGFloat x0 = CGRectGetMinX(rect), y0 = CGRectGetMinY(rect);

	CGPathMoveToPoint(path, NULL, x0 + w * 0.16, y0 + h * 0.52);
	CGPathAddLineToPoint(path, NULL, x0 + w * 0.40, y0 + h * 0.28);
	CGPathAddLineToPoint(path, NULL, x0 + w * 0.86, y0 + h * 0.74);

	return (CGPathRef)CFAutorelease(path);
}

// MARK: - State

- (void)setState:(GazeCapsuleState)state
{
	_state = state;
	switch (state) {
	case GazeCapsuleStateScanning:
		self.statusLabel.stringValue = @"";
		self.glyphLayer.opacity = 1.0;
		self.checkLayer.opacity = 0.0;
		[self startScanPulse];
		break;
	case GazeCapsuleStateNotRecognised:
		self.statusLabel.stringValue = @"Face Not Recognized";
		break;
	case GazeCapsuleStateSuccess:
		self.statusLabel.stringValue = @"";
		[self.glyphLayer removeAllAnimations];
		break;
	}
}

/// A slow breathing pulse on the glyph while scanning.
///
/// Deliberately gentle: this runs for as long as the camera is looking, and anything
/// faster reads as urgency the situation does not have.
- (void)startScanPulse
{
	[self.glyphLayer removeAnimationForKey:@"pulse"];

	CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
	pulse.fromValue = @(1.0);
	pulse.toValue = @(0.45);
	pulse.duration = 0.9;
	pulse.autoreverses = YES;
	pulse.repeatCount = HUGE_VALF;
	pulse.timingFunction =
		[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
	[self.glyphLayer addAnimation:pulse forKey:@"pulse"];
}

- (void)playRejectionThen:(void (^)(void))completion
{
	self.state = GazeCapsuleStateNotRecognised;
	[self.glyphLayer removeAnimationForKey:@"pulse"];
	self.glyphLayer.opacity = 1.0;

	// The same lateral knock a rejected password field gives, for the same reason: it
	// reads as "no" without needing to be read.
	CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"position.x"];
	CGFloat centre = self.layer.position.x;
	shake.values = @[ @(centre), @(centre - 8), @(centre + 8), @(centre - 5), @(centre + 5), @(centre) ];
	shake.keyTimes = @[ @0.0, @0.15, @0.35, @0.55, @0.78, @1.0 ];
	shake.duration = 0.42;
	[self.layer addAnimation:shake forKey:@"shake"];

	dispatch_after(
		dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
			if (completion) {
				completion();
			}
		});
}

- (void)playSuccessThen:(void (^)(void))completion
{
	self.state = GazeCapsuleStateSuccess;

	[CATransaction begin];
	[CATransaction setAnimationDuration:0.28];

	self.glyphLayer.opacity = 0.0;
	self.checkLayer.opacity = 1.0;

	// Draw the tick on rather than fading it in — the stroke reads as confirmation.
	CABasicAnimation *draw = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
	draw.fromValue = @(0.0);
	draw.toValue = @(1.0);
	draw.duration = 0.26;
	draw.timingFunction =
		[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
	[self.checkLayer addAnimation:draw forKey:@"draw"];

	// A short settle on the capsule, echoing the Dynamic Island's spring.
	CAKeyframeAnimation *settle = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
	settle.values = @[ @(1.0), @(1.09), @(0.98), @(1.0) ];
	settle.keyTimes = @[ @0.0, @0.35, @0.7, @1.0 ];
	settle.duration = 0.34;
	[self.capsuleLayer addAnimation:settle forKey:@"settle"];

	[CATransaction commit];

	dispatch_after(
		dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.62 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
			if (completion) {
				completion();
			}
		});
}

@end
