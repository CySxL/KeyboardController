/* Keyboard Controller - Control Keyboard on iOS/iPadOS
 * (c) Copyright 2020-2023 Tomasz Poliszuk
 *
 * Keyboard Controller is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3 of the License.
 *
 * Keyboard Controller is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Keyboard Controller. If not, see <https://www.gnu.org/licenses/>.
 */


#include "headers.h"
#include <dlfcn.h>

extern "C" NSString *PreferencesFilePath(void);

static bool enableTweak;

static int uiStyle;

#define kKeyboardTypeCount 12

static long long keyboardTypeMap[kKeyboardTypeCount];
static long long returnKeyTypeMap[kKeyboardTypeCount];

static NSString *const keyboardTypeKeys[kKeyboardTypeCount] = {
	@"defaultKeyboard",
	@"asciiCapableKeyboard",
	@"numbersAndPunctuationKeyboard",
	@"urlKeyboard",
	@"numberPadKeyboard",
	@"phonePadKeyboard",
	@"namePhonePadKeyboard",
	@"emailAddressKeyboard",
	@"decimalPadKeyboard",
	@"twitterKeyboard",
	@"webSearchKeyboard",
	@"asciiCapableNumberPadKeyboard"
};

static NSString *const returnKeyTypeKeys[kKeyboardTypeCount] = {
	@"returnKeyTypeDefault",
	@"returnKeyTypeGo",
	@"returnKeyTypeGoogle",
	@"returnKeyTypeJoin",
	@"returnKeyTypeNext",
	@"returnKeyTypeRoute",
	@"returnKeyTypeSearch",
	@"returnKeyTypeSend",
	@"returnKeyTypeYahoo",
	@"returnKeyTypeDone",
	@"returnKeyTypeEmergencyCall",
	@"returnKeyTypeContinue"
};

static long long keyboardDismissMode;

static int trackpadMode;

static int returnKeyStyling;

static int dictationButton;

static int shouldShowInternationalKey;

static int selectingSkinToneForEmoji;

static int oneHandedKeyboard;

static int oneHandedGestureLeft;
static int oneHandedGestureRight;
static int oneHandedGestureReturn;

static int oneHandedTools;

static int useBlueThemingForKey;

// A trait copy reads the source through these getters and writes the destination
// ivar raw, so mapping during one applies the map a second time on the next read.
static __thread int traitCopyDepth;

static BOOL canAskForAncestorController;

static NSDictionary *LoadSettings() {
	NSDictionary *tweakSettings = nil;
	CFArrayRef keyList = CFPreferencesCopyKeyList(CFSTR(kPackageName), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	if(keyList) {
		tweakSettings = (NSDictionary *)CFBridgingRelease(
			CFPreferencesCopyMultiple(
				keyList,
				CFSTR(kPackageName),
				kCFPreferencesCurrentUser,
				kCFPreferencesAnyHost
			)
		);
		CFRelease(keyList);
	}
	if ( !tweakSettings ) {
		tweakSettings = [NSDictionary dictionaryWithContentsOfFile:PreferencesFilePath()];
	}
	return tweakSettings;
}

// A plist value can be any class. NSNumber and NSString answer integerValue and
// boolValue, anything else throws, and this loads into every UIKit process.
static long long IntegerSetting(NSDictionary *settings, NSString *key, long long fallback) {
	id value = [settings objectForKey:key];
	if ( [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]] ) {
		return [value longLongValue];
	}
	return fallback;
}

// For values UIKit reads as an enum. Anything the settings page cannot write
// counts as unset.
static long long RangedSetting(NSDictionary *settings, NSString *key, long long min, long long max, long long fallback) {
	long long value = IntegerSetting(settings, key, fallback);
	return ( value >= min && value <= max ) ? value : fallback;
}

static bool BoolSetting(NSDictionary *settings, NSString *key, bool fallback) {
	id value = [settings objectForKey:key];
	if ( [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]] ) {
		return [value boolValue];
	}
	return fallback;
}

static void ApplySettings(NSDictionary *tweakSettings) {
	enableTweak = BoolSetting(tweakSettings, @"enableTweak", YES);

	uiStyle = RangedSetting(tweakSettings, @"uiStyle", 0, 2, 999);

	for ( int i = 0; i < kKeyboardTypeCount; i++ ) {
		keyboardTypeMap[i] = RangedSetting(tweakSettings, keyboardTypeKeys[i], 0, kKeyboardTypeCount - 1, i);
		returnKeyTypeMap[i] = RangedSetting(tweakSettings, returnKeyTypeKeys[i], 0, kKeyboardTypeCount - 1, i);
	}

	keyboardDismissMode = RangedSetting(tweakSettings, @"keyboardDismissMode", 0, 2, 999);

	trackpadMode = IntegerSetting(tweakSettings, @"trackpadMode", 999);

	returnKeyStyling = IntegerSetting(tweakSettings, @"returnKeyStyling", 999);

	dictationButton = IntegerSetting(tweakSettings, @"dictationButton", 999);

	shouldShowInternationalKey = IntegerSetting(tweakSettings, @"shouldShowInternationalKey", 999);

	selectingSkinToneForEmoji = IntegerSetting(tweakSettings, @"selectingSkinToneForEmoji", 999);

	oneHandedKeyboard = RangedSetting(tweakSettings, @"oneHandedKeyboard", 0, 2, 999);

	oneHandedGestureLeft = BoolSetting(tweakSettings, @"oneHandedGestureLeft", false);
	oneHandedGestureRight = BoolSetting(tweakSettings, @"oneHandedGestureRight", false);
	oneHandedGestureReturn = BoolSetting(tweakSettings, @"oneHandedGestureReturn", false);

	oneHandedTools = BoolSetting(tweakSettings, @"oneHandedTools", false);

	useBlueThemingForKey = IntegerSetting(tweakSettings, @"useBlueThemingForKey", 999);
}

// True while any keyboard type or return key type is mapped to something other
// than itself. Decides whether the trait hooks are worth installing at all.
static bool MapsAreActive() {
	for ( int i = 0; i < kKeyboardTypeCount; i++ ) {
		if ( keyboardTypeMap[i] != i || returnKeyTypeMap[i] != i ) {
			return true;
		}
	}
	return false;
}

// Two synchronous trips to cfprefsd, in every UIKit process, for every change a
// settings page posts. Read on a serial queue so the order survives a burst,
// publish on the main thread so the hooks never read a half written map.
static void ReloadSettings() {
	static dispatch_once_t onceToken;
	static dispatch_queue_t settingsQueue;
	dispatch_once(&onceToken, ^{
		settingsQueue = dispatch_queue_create(kPackageName ".settings", DISPATCH_QUEUE_SERIAL);
	});
	dispatch_async(settingsQueue, ^{
		NSDictionary *loaded = LoadSettings();
		dispatch_async(dispatch_get_main_queue(), ^{
			ApplySettings(loaded);
		});
	});
}

static void receivedNotification(
	CFNotificationCenterRef center,
	void *observer,
	CFStringRef name,
	const void *object,
	CFDictionaryRef userInfo
) {
	ReloadSettings();
}

enum { keyNone = 0, keyMore = 1, keyDelete = 2, keyReturn = 3 };

static const CGFloat biasSwipeThreshold = 18.0;

@interface UIKeyboardLayoutStar : UIView
- (id)keyHitTest:(CGPoint)point;
- (void)setKeyboardBias:(long long)bias;
- (id)keyplane;
- (id)renderConfig;
@end

@interface UIKeyboardPreferencesController : NSObject
+ (instancetype)sharedPreferencesController;
- (long long)handBias;
- (void)setHandBias:(long long)bias;
@end

@interface UIKBTree : NSObject
- (NSString *)representedString;
- (NSString *)displayString;
- (NSArray *)keys;
- (bool)visible;
- (CGRect)frame;
- (void)setState:(int)state;
@end

@interface UIKBKeyplaneView : UIView
- (id)factory;
- (id)viewForKey:(id)key;
@end

@interface UIKBRenderFactory : NSObject
- (id)traitsForKey:(id)key onKeyplane:(id)keyplane;
@end

@interface UIKBRenderTraits : NSObject
- (id)geometry;
- (id)backgroundGradient;
- (NSArray *)renderEffects;
- (bool)controlOpacities;
@end

@interface UIKBRenderGeometry : NSObject
- (CGRect)paddedFrame;
- (double)roundRectRadius;
@end

@interface UIKBGradient : NSObject
- (NSString *)flatColorName;
@end

@interface UIKBEdgeEffect : NSObject
- (unsigned long long)edges;
- (UIEdgeInsets)insets;
@end

@interface UIKBRenderConfig : NSObject
- (bool)lightKeyboard;
@end

@interface CALayer (KeyboardController)
- (void)setAllowsGroupBlending:(BOOL)allowsGroupBlending;
@end

static int classifyKey(id key) {
	if ( !key ) {
		return keyNone;
	}
	NSString *rep = [key respondsToSelector:@selector(representedString)] ? [key representedString] : nil;
	if ( [rep isEqualToString:@"Delete"] ) {
		return keyDelete;
	}
	if ( [rep isEqualToString:@"\n"] || [rep isEqualToString:@"\r"] || [rep isEqualToString:@"Return"] ) {
		return keyReturn;
	}
	if ( [rep isEqualToString:@"More"] ) {
		return keyMore;
	}
	NSString *disp = [key respondsToSelector:@selector(displayString)] ? [key displayString] : nil;
	if ( [disp isEqualToString:@"123"] || [disp isEqualToString:@"#+="] || [disp isEqualToString:@"ABC"] ) {
		return keyMore;
	}
	return keyNone;
}

@interface KeyboardControllerHandBiasGesture : UIPanGestureRecognizer <UIGestureRecognizerDelegate>
@property (nonatomic, assign) int startKind;
@property (nonatomic, assign) BOOL canHitTest;
@end

@implementation KeyboardControllerHandBiasGesture
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
	// self.view is the layout this was added to, and costs no weak table lock.
	UIKeyboardLayoutStar *layout = (UIKeyboardLayoutStar *)self.view;
	if ( !enableTweak || oneHandedKeyboard != 999 || !layout || !self.canHitTest ) {
		self.startKind = keyNone;
		return NO;
	}
	CGPoint point = [touch locationInView:layout];
	int kind = classifyKey([layout keyHitTest:point]);
	if ( ( kind == keyMore && !oneHandedGestureLeft )
		|| ( kind == keyDelete && !oneHandedGestureRight )
		|| ( kind == keyReturn && !oneHandedGestureReturn ) ) {
		kind = keyNone;
	}
	self.startKind = kind;
	return kind != keyNone;
}

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gestureRecognizer {
	CGPoint velocity = [gestureRecognizer velocityInView:gestureRecognizer.view];
	if ( fabs(velocity.x) > fabs(velocity.y) ) {
		return NO;
	}
	if ( velocity.y < 50.0 ) {
		return NO;
	}
	return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
	return YES;
}
@end

@interface UIKeyboardImpl : UIView
+ (instancetype)activeInstance;
- (void)moveCursorLeftShifted:(bool)shifted;
- (void)moveCursorRightShifted:(bool)shifted;
- (void)pasteOperation;
- (id)delegateAsResponder;
@end

static UIKeyboardImpl *ActiveKeyboard() {
	Class implClass = %c(UIKeyboardImpl);
	return [implClass respondsToSelector:@selector(activeInstance)] ? [implClass activeInstance] : nil;
}

// How the keyboard draws a control key, read from the render factory.
@interface KeyboardControllerKeyStyle : NSObject
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, strong) UIColor *pressedColor;
@property (nonatomic, strong) id filter;
@property (nonatomic, strong) id pressedFilter;
@property (nonatomic, strong) UIColor *edgeColor;
@property (nonatomic, assign) CGFloat edgeOffset;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, strong) UIColor *foreground;
@end

@implementation KeyboardControllerKeyStyle
@end

// One tool drawn as a key, the symbol in a fixed slot so the names line up.
@interface KeyboardControllerToolButton : UIButton
@property (nonatomic, readonly) UIImageView *symbolView;
@property (nonatomic, readonly) UILabel *nameLabel;
@property (nonatomic, readonly) CALayer *keyLayer;
@property (nonatomic, readonly) CALayer *edgeLayer;
@property (nonatomic, readonly) CAShapeLayer *edgeMask;
@property (nonatomic, strong) KeyboardControllerKeyStyle *style;
@end

@implementation KeyboardControllerToolButton
- (instancetype)initWithSymbol:(NSString *)symbol name:(NSString *)name {
	self = [super initWithFrame:CGRectZero];
	if ( self ) {
		// As on UIKBKeyView, so the key's blend reaches the keyboard backdrop
		// instead of the transparent group, which burns to black.
		if ( [self.layer respondsToSelector:@selector(setAllowsGroupBlending:)] ) {
			[self.layer setAllowsGroupBlending:NO];
		}
		_edgeLayer = [CALayer layer];
		_edgeMask = [CAShapeLayer layer];
		_edgeLayer.mask = _edgeMask;
		_keyLayer = [CALayer layer];
		[self.layer addSublayer:_edgeLayer];
		[self.layer addSublayer:_keyLayer];
		_symbolView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
		_symbolView.contentMode = UIViewContentModeCenter;
		_nameLabel = [[UILabel alloc] init];
		_nameLabel.text = name;
		_nameLabel.adjustsFontSizeToFitWidth = YES;
		_nameLabel.minimumScaleFactor = 0.5;
		[self addSubview:_symbolView];
		[self addSubview:_nameLabel];
	}
	return self;
}
- (void)applyStyle {
	KeyboardControllerKeyStyle *style = _style;
	BOOL pressed = self.highlighted;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	_keyLayer.backgroundColor = ( pressed ? style.pressedColor : style.color ).CGColor;
	_keyLayer.compositingFilter = pressed ? style.pressedFilter : style.filter;
	_keyLayer.cornerRadius = style.cornerRadius;
	_edgeLayer.backgroundColor = style.edgeColor.CGColor;
	_edgeLayer.compositingFilter = _keyLayer.compositingFilter;
	_edgeLayer.cornerRadius = style.cornerRadius;
	[CATransaction commit];
	_symbolView.tintColor = style.foreground;
	_nameLabel.textColor = style.foreground;
}
- (void)setStyle:(KeyboardControllerKeyStyle *)style {
	_style = style;
	[self applyStyle];
}
- (void)setHighlighted:(BOOL)highlighted {
	BOOL changed = highlighted != self.highlighted;
	[super setHighlighted:highlighted];
	if ( changed ) {
		[self applyStyle];
	}
}
- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect bounds = self.bounds;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	_keyLayer.frame = bounds;
	CGFloat offset = _style.edgeOffset;
	_edgeLayer.frame = CGRectOffset(bounds, 0, offset);
	// The edge shows only below the key, so none of it sits under the key's
	// blend or rims its top corners.
	CGFloat width = CGRectGetWidth(bounds), height = CGRectGetHeight(bounds);
	CGFloat bottom = height - offset;
	CGFloat radius = MAX(0, MIN(_style.cornerRadius, MIN(width / 2, bottom)));
	UIBezierPath *path = [UIBezierPath bezierPath];
	[path moveToPoint:CGPointMake(0, bottom - radius)];
	[path addArcWithCenter:CGPointMake(radius, bottom - radius) radius:radius startAngle:M_PI endAngle:M_PI_2 clockwise:NO];
	[path addLineToPoint:CGPointMake(width - radius, bottom)];
	[path addArcWithCenter:CGPointMake(width - radius, bottom - radius) radius:radius startAngle:M_PI_2 endAngle:0 clockwise:NO];
	[path addLineToPoint:CGPointMake(width, height)];
	[path addLineToPoint:CGPointMake(0, height)];
	[path closePath];
	_edgeMask.frame = _edgeLayer.bounds;
	_edgeMask.path = path.CGPath;
	[CATransaction commit];
}
@end

// Fills the gap beside the one-handed keyboard, on whichever side the escape
// arrow is.
@interface KeyboardControllerToolsView : UIView
@property (nonatomic, weak) UIView *escapeButton;
@property (nonatomic, assign) BOOL layoutPending;
@end

@implementation KeyboardControllerToolsView
- (instancetype)initWithEscapeButton:(UIView *)escapeButton {
	self = [super initWithFrame:CGRectZero];
	if ( self ) {
		_escapeButton = escapeButton;
		[self addTool:@"chevron.left" name:@"Left" label:@"Move cursor left" action:@selector(cursorLeft)];
		[self addTool:@"chevron.right" name:@"Right" label:@"Move cursor right" action:@selector(cursorRight)];
		[self addTool:@"doc.on.doc" name:@"Copy" label:@"Copy" action:@selector(copyText)];
		[self addTool:@"doc.on.clipboard" name:@"Paste" label:@"Paste" action:@selector(pasteText)];
		[self addTool:@"selection.pin.in.out" name:@"Select All" label:@"Select all" action:@selector(selectAllText)];
	}
	return self;
}
- (void)addTool:(NSString *)symbol name:(NSString *)name label:(NSString *)label action:(SEL)action {
	KeyboardControllerToolButton *button = [[KeyboardControllerToolButton alloc] initWithSymbol:symbol name:name];
	button.accessibilityLabel = label;
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	[self addSubview:button];
}
- (void)applyStyle:(KeyboardControllerKeyStyle *)style {
	for ( KeyboardControllerToolButton *button in self.subviews ) {
		button.style = style;
		[button setNeedsLayout];
	}
}
- (void)layoutSubviews {
	[super layoutSubviews];
	NSArray *buttons = self.subviews;
	NSUInteger count = buttons.count;
	if ( !count ) {
		return;
	}
	CGSize size = self.bounds.size;
	// Each gap a quarter of a block, as Zhuyin's five rows split, so the blocks
	// are the same height beside any keyboard of the same height.
	CGFloat height = size.height / ( count + ( count - 1 ) * 0.25 );
	CGFloat spacing = height * 0.25;
	// Symbol and name at four tenths of the block height. The symbol's slot is
	// twice that, so it and the name's trailing margin are both a fifth.
	CGFloat glyph = height * 0.4;
	CGFloat slot = glyph * 2;
	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:glyph];
	UIFont *font = [UIFont systemFontOfSize:glyph];
	[buttons enumerateObjectsUsingBlock:^(KeyboardControllerToolButton *button, NSUInteger index, BOOL *stop) {
		button.frame = CGRectMake(0, index * ( height + spacing ), size.width, height);
		button.symbolView.frame = CGRectMake(0, 0, slot, height);
		button.symbolView.preferredSymbolConfiguration = config;
		button.nameLabel.frame = CGRectMake(slot, 0, MAX(0, size.width - slot - height * 0.2), height);
		button.nameLabel.font = font;
	}];
}
- (void)cursorLeft {
	UIKeyboardImpl *keyboard = ActiveKeyboard();
	if ( [keyboard respondsToSelector:@selector(moveCursorLeftShifted:)] ) {
		[keyboard moveCursorLeftShifted:NO];
	}
}
- (void)cursorRight {
	UIKeyboardImpl *keyboard = ActiveKeyboard();
	if ( [keyboard respondsToSelector:@selector(moveCursorRightShifted:)] ) {
		[keyboard moveCursorRightShifted:NO];
	}
}
- (void)copyText {
	UIKeyboardImpl *keyboard = ActiveKeyboard();
	id responder = [keyboard respondsToSelector:@selector(delegateAsResponder)] ? [keyboard delegateAsResponder] : nil;
	if ( [responder isKindOfClass:[UIResponder class]] && [responder canPerformAction:@selector(copy:) withSender:nil] ) {
		[responder copy:nil];
	}
}
- (void)pasteText {
	UIKeyboardImpl *keyboard = ActiveKeyboard();
	if ( [keyboard respondsToSelector:@selector(pasteOperation)] ) {
		[keyboard pasteOperation];
	}
}
- (void)selectAllText {
	UIKeyboardImpl *keyboard = ActiveKeyboard();
	id responder = [keyboard respondsToSelector:@selector(delegateAsResponder)] ? [keyboard delegateAsResponder] : nil;
	if ( [responder isKindOfClass:[UIResponder class]] && [responder canPerformAction:@selector(selectAll:) withSender:nil] ) {
		[responder selectAll:nil];
	}
}
@end

static UIColor *NamedKeyboardColor(id name) {
	static CGColorRef (*getNamedColor)(NSString *);
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		getNamedColor = (CGColorRef (*)(NSString *))dlsym(RTLD_DEFAULT, "UIKBGetNamedColor");
	});
	if ( !getNamedColor || ![name isKindOfClass:[NSString class]] ) {
		return nil;
	}
	CGColorRef color = getNamedColor(name);
	return color ? [UIColor colorWithCGColor:color] : nil;
}

static UIKBRenderTraits *TraitsForKey(UIKBRenderFactory *factory, id key, id keyplane) {
	if ( !key || ![factory respondsToSelector:@selector(traitsForKey:onKeyplane:)] ) {
		return nil;
	}
	id traits = [factory traitsForKey:key onKeyplane:keyplane];
	return [traits respondsToSelector:@selector(geometry)] ? traits : nil;
}

// The key as drawn, which is inset from the key's frame.
static CGRect DrawnFrame(UIKBRenderTraits *traits, UIView *plane, UIView *layout) {
	UIKBRenderGeometry *geometry = [traits geometry];
	if ( ![geometry respondsToSelector:@selector(paddedFrame)] ) {
		return CGRectNull;
	}
	CGRect frame = [geometry paddedFrame];
	return plane ? [plane convertRect:frame toView:layout] : frame;
}

static UIColor *BackgroundColor(UIKBRenderTraits *traits) {
	UIKBGradient *gradient = [traits respondsToSelector:@selector(backgroundGradient)] ? [traits backgroundGradient] : nil;
	return NamedKeyboardColor([gradient respondsToSelector:@selector(flatColorName)] ? [gradient flatColorName] : nil);
}

static BOOL ControlOpacities(UIKBRenderTraits *traits) {
	return [traits respondsToSelector:@selector(controlOpacities)] && [traits controlOpacities];
}

// The last blocks measured on a keyplane with rows, for one without, such as
// emoji. Placed from the layout's bottom, which stays put when emoji grows it.
static BOOL toolsMeasured;
static CGSize toolsSize;
static CGFloat toolsMargin;
static CGFloat toolsBottomInset;
static KeyboardControllerKeyStyle *toolsStyle;

// Place and look come from the keys as the factory draws them: the top of the
// first row to the bottom of the last, the gap between keys, the margin to the
// outer edge, and the colours and blend of the bottom row's first key, which is
// 123 or ABC.
static void LayOutTools(KeyboardControllerToolsView *tools, UIKeyboardLayoutStar *layout, id keyplaneView) {
	UIView *escapeButton = tools.escapeButton;
	CGRect bounds = layout.bounds;
	UIKBKeyplaneView *plane = [keyplaneView isKindOfClass:[UIView class]] ? keyplaneView : nil;
	UIKBRenderFactory *factory = [plane respondsToSelector:@selector(factory)] ? [plane factory] : nil;
	UIKBTree *keyplane = [layout respondsToSelector:@selector(keyplane)] ? [layout keyplane] : nil;
	NSArray *keys = [keyplane respondsToSelector:@selector(keys)] ? [keyplane keys] : nil;
	if ( ![keys isKindOfClass:[NSArray class]] ) {
		keys = nil;
	}

	CGFloat top = CGFLOAT_MAX, bottom = -CGFLOAT_MAX;
	UIKBTree *bottomKey = nil;
	for ( UIKBTree *key in keys ) {
		if ( ![key respondsToSelector:@selector(visible)] || ![key respondsToSelector:@selector(frame)] || ![key visible] ) {
			continue;
		}
		CGRect frame = [key frame];
		top = MIN(top, CGRectGetMinY(frame));
		CGFloat maxY = CGRectGetMaxY(frame);
		if ( maxY > bottom + 0.5 || ( maxY >= bottom - 0.5 && CGRectGetMinX(frame) < CGRectGetMinX([bottomKey frame]) ) ) {
			bottom = maxY;
			bottomKey = key;
		}
	}
	UIKBTree *topLeft = nil, *topNext = nil, *topRight = nil;
	for ( UIKBTree *key in keys ) {
		if ( ![key respondsToSelector:@selector(visible)] || ![key respondsToSelector:@selector(frame)] || ![key visible] ) {
			continue;
		}
		CGRect frame = [key frame];
		if ( fabs(CGRectGetMinY(frame) - top) <= 0.5 ) {
			if ( !topLeft || CGRectGetMinX(frame) < CGRectGetMinX([topLeft frame]) ) {
				topNext = topLeft;
				topLeft = key;
			} else if ( !topNext || CGRectGetMinX(frame) < CGRectGetMinX([topNext frame]) ) {
				topNext = key;
			}
			if ( !topRight || CGRectGetMaxX(frame) > CGRectGetMaxX([topRight frame]) ) {
				topRight = key;
			}
		}
	}

	BOOL left = CGRectGetMidX(escapeButton.frame) < CGRectGetMidX(bounds);
	CGRect area = CGRectNull;
	UIKBRenderTraits *controlTraits = TraitsForKey(factory, bottomKey, keyplane);
	CGRect first = DrawnFrame(TraitsForKey(factory, topLeft, keyplane), plane, layout);
	CGRect next = DrawnFrame(TraitsForKey(factory, topNext, keyplane), plane, layout);
	CGRect last = DrawnFrame(TraitsForKey(factory, topRight, keyplane), plane, layout);
	CGRect lowest = DrawnFrame(controlTraits, plane, layout);
	if ( !CGRectIsNull(first) && !CGRectIsNull(next) && !CGRectIsNull(last) && !CGRectIsNull(lowest) ) {
		CGFloat keyGap = MAX(0, CGRectGetMinX(next) - CGRectGetMaxX(first));
		CGFloat x, width;
		if ( left ) {
			x = CGRectGetMinX(bounds) + MAX(0, CGRectGetMaxX(bounds) - CGRectGetMaxX(last));
			width = CGRectGetMinX(first) - keyGap - x;
		} else {
			x = CGRectGetMaxX(last) + keyGap;
			width = CGRectGetMaxX(bounds) - MAX(0, CGRectGetMinX(first) - CGRectGetMinX(bounds)) - x;
		}
		CGFloat height = CGRectGetMaxY(lowest) - CGRectGetMinY(first);
		if ( width > 0 && height > 0 ) {
			area = CGRectMake(x, CGRectGetMinY(first), width, height);
		}
	}
	if ( CGRectIsNull(area) ) {
		if ( !toolsMeasured ) {
			// Nothing to draw the tools from yet, so the system's arrow stays.
			tools.hidden = YES;
			escapeButton.alpha = 1;
			escapeButton.userInteractionEnabled = YES;
			return;
		}
		CGFloat x = left ? CGRectGetMinX(bounds) + toolsMargin : CGRectGetMaxX(bounds) - toolsMargin - toolsSize.width;
		tools.frame = CGRectMake(x, CGRectGetMaxY(bounds) - toolsBottomInset - toolsSize.height, toolsSize.width, toolsSize.height);
		[tools applyStyle:toolsStyle];
		return;
	}
	tools.frame = area;
	tools.hidden = escapeButton.hidden;
	toolsSize = area.size;
	toolsMargin = left ? CGRectGetMinX(area) - CGRectGetMinX(bounds) : CGRectGetMaxX(bounds) - CGRectGetMaxX(area);
	toolsBottomInset = CGRectGetMaxY(bounds) - CGRectGetMaxY(area);

	KeyboardControllerKeyStyle *style = [KeyboardControllerKeyStyle new];
	style.color = BackgroundColor(controlTraits);
	UIKBTree *pressedKey = [bottomKey respondsToSelector:@selector(copyWithZone:)] && [bottomKey respondsToSelector:@selector(setState:)] ? [bottomKey copy] : nil;
	// 4 is the pressed state; set on a copy so the key on screen is untouched.
	[pressedKey setState:4];
	UIKBRenderTraits *pressedTraits = TraitsForKey(factory, pressedKey, keyplane);
	style.pressedColor = BackgroundColor(pressedTraits) ?: style.color;
	id filter = nil;
	UIView *keyView = bottomKey && [plane respondsToSelector:@selector(viewForKey:)] ? [plane viewForKey:bottomKey] : nil;
	if ( [keyView isKindOfClass:[UIView class]] ) {
		for ( CALayer *sublayer in keyView.layer.sublayers ) {
			if ( sublayer.compositingFilter ) {
				filter = sublayer.compositingFilter;
				break;
			}
		}
	}
	style.filter = ControlOpacities(controlTraits) ? filter : nil;
	style.pressedFilter = ControlOpacities(pressedTraits) ? filter : nil;
	NSArray *effects = [controlTraits respondsToSelector:@selector(renderEffects)] ? [controlTraits renderEffects] : nil;
	for ( id effect in ( [effects isKindOfClass:[NSArray class]] ? effects : nil ) ) {
		if ( ![effect isKindOfClass:%c(UIKBEdgeEffect)] || ![effect respondsToSelector:@selector(edges)] || ![effect respondsToSelector:@selector(insets)] ) {
			continue;
		}
		if ( !( [(UIKBEdgeEffect *)effect edges] & UIRectEdgeBottom ) ) {
			continue;
		}
		id name = nil;
		@try {
			name = [effect valueForKey:@"colorName"];
		} @catch ( NSException *exception ) {
		}
		// A copy of the key moved down by the inset shows only as the bottom edge.
		style.edgeColor = NamedKeyboardColor(name);
		style.edgeOffset = MAX(0, -[(UIKBEdgeEffect *)effect insets].bottom);
		break;
	}
	UIKBRenderGeometry *geometry = [controlTraits geometry];
	style.cornerRadius = [geometry respondsToSelector:@selector(roundRectRadius)] ? [geometry roundRectRadius] : 0;
	UIKBRenderConfig *config = [layout respondsToSelector:@selector(renderConfig)] ? [layout renderConfig] : nil;
	BOOL light = [config respondsToSelector:@selector(lightKeyboard)] ? [config lightKeyboard] : tools.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark;
	style.foreground = light ? [UIColor blackColor] : [UIColor whiteColor];
	toolsStyle = style;
	toolsMeasured = YES;
	[tools applyStyle:style];
}

// The system shows and hides the escape arrow with hidden and leaves its alpha
// at 1, so alpha is free to hide it under the tools.
static void UpdateEscapeTools(UIKeyboardLayoutStar *layout) {
	static Ivar escapeIvar;
	static Ivar keyplaneViewIvar;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		escapeIvar = class_getInstanceVariable(%c(UIKeyboardLayoutStar), "_biasEscapeButton");
		keyplaneViewIvar = class_getInstanceVariable(%c(UIKeyboardLayoutStar), "_keyplaneView");
	});
	if ( !escapeIvar ) {
		return;
	}
	id escape = object_getIvar(layout, escapeIvar);
	if ( ![escape isKindOfClass:[UIView class]] ) {
		return;
	}
	UIView *escapeButton = (UIView *)escape;
	KeyboardControllerToolsView *tools = nil;
	for ( UIView *subview in layout.subviews ) {
		if ( [subview isKindOfClass:[KeyboardControllerToolsView class]] ) {
			tools = (KeyboardControllerToolsView *)subview;
			break;
		}
	}
	if ( tools && tools.escapeButton != escapeButton ) {
		[tools removeFromSuperview];
		tools = nil;
	}
	if ( !enableTweak || !oneHandedTools || escapeButton.superview != layout ) {
		if ( tools ) {
			[tools removeFromSuperview];
			escapeButton.alpha = 1;
			escapeButton.userInteractionEnabled = YES;
		}
		return;
	}
	if ( !tools ) {
		tools = [[KeyboardControllerToolsView alloc] initWithEscapeButton:escapeButton];
		[layout addSubview:tools];
	}
	// The arrow and the keys are not in place yet when the arrow is shown, so
	// the tools are sized on the next turn of the main queue.
	if ( !tools.layoutPending ) {
		tools.layoutPending = YES;
		__weak KeyboardControllerToolsView *weakTools = tools;
		__weak UIKeyboardLayoutStar *weakLayout = layout;
		Ivar planeIvar = keyplaneViewIvar;
		dispatch_async(dispatch_get_main_queue(), ^{
			KeyboardControllerToolsView *pendingTools = weakTools;
			UIKeyboardLayoutStar *pendingLayout = weakLayout;
			pendingTools.layoutPending = NO;
			if ( pendingTools && pendingLayout && pendingTools.superview == pendingLayout ) {
				LayOutTools(pendingTools, pendingLayout, planeIvar ? object_getIvar(pendingLayout, planeIvar) : nil);
			}
		});
	}
	escapeButton.alpha = 0;
	escapeButton.userInteractionEnabled = NO;
	tools.hidden = escapeButton.hidden || !toolsMeasured;
}


%group UIStyle

%hook UITextInputTraits
- (long long)keyboardAppearance {
	if ( enableTweak && uiStyle != 999 ) {
		return uiStyle;
	}
	return %orig;
}
%end

%end

%group TypeMaps

%hook UITextInputTraits
- (long long)keyboardType {
	long long origValue = %orig;
	if ( enableTweak && !traitCopyDepth && origValue >= 0 && origValue < kKeyboardTypeCount ) {
		return keyboardTypeMap[origValue];
	}
	return origValue;
}
- (long long)returnKeyType {
	long long origValue = %orig;
	if ( enableTweak && !traitCopyDepth && origValue >= 0 && origValue < kKeyboardTypeCount ) {
		return returnKeyTypeMap[origValue];
	}
	return origValue;
}
- (void)takeTraitsFrom:(id)arg1 {
	traitCopyDepth++;
	%orig;
	traitCopyDepth--;
}
- (void)takeTraitsFrom:(id)arg1 lightweight:(bool)arg2 {
	traitCopyDepth++;
	%orig;
	traitCopyDepth--;
}
%end

%end

%group DismissMode

%hook UIScrollView
- (long long)keyboardDismissMode {
	if ( enableTweak && keyboardDismissMode != 999 && canAskForAncestorController ) {
		id ancestor = [self _viewControllerForAncestor];
		// UICompatibilityInputViewController is a UIInputViewController subclass,
		// so the second check covers it. UICandidateViewController is not.
		if (
			![ancestor isKindOfClass:%c(UICandidateViewController)]
			&&
			![ancestor isKindOfClass:%c(UIInputViewController)]
		) {
			return keyboardDismissMode;
		}
	}
	return %orig;
}
%end

%end

%group SkinTone

%hook UIKeyboardEmojiCollectionInputView
- (int)skinToneWasUsedForEmoji:(id)arg1 {
	if ( enableTweak && selectingSkinToneForEmoji != 999 ) {
		return selectingSkinToneForEmoji;
	}
	return %orig;
}
%end

%hook UIKeyboardEmojiPreferences
- (int)hasDisplayedSkinToneHelp {
	if ( enableTweak && selectingSkinToneForEmoji != 999 ) {
		return selectingSkinToneForEmoji;
	}
	return %orig;
}
%end

%hook EMFEmojiToken
- (BOOL)supportsSkinToneVariants {
	if ( enableTweak && selectingSkinToneForEmoji != 999 ) {
		return NO;
	}
	return %orig;
}
%end

%end

%group OneHanded

%hook UIKeyboardLayoutStar
- (long long)currentHandBias {
	if ( enableTweak && oneHandedKeyboard != 999 ) {
		return oneHandedKeyboard;
	}
	return %orig;
}
- (void)didMoveToWindow {
	%orig;
	BOOL wanted = enableTweak
		&& ( oneHandedGestureLeft || oneHandedGestureRight || oneHandedGestureReturn )
		&& self.window != nil;
	KeyboardControllerHandBiasGesture *existing = nil;
	for ( UIGestureRecognizer *recognizer in self.gestureRecognizers ) {
		if ( [recognizer isKindOfClass:[KeyboardControllerHandBiasGesture class]] ) {
			existing = (KeyboardControllerHandBiasGesture *)recognizer;
			break;
		}
	}
	if ( !wanted ) {
		if ( existing ) {
			[self removeGestureRecognizer:existing];
		}
		return;
	}
	if ( existing ) {
		return;
	}
	KeyboardControllerHandBiasGesture *pan = [[KeyboardControllerHandBiasGesture alloc] initWithTarget:self action:@selector(handleHandBiasPan:)];
	pan.minimumNumberOfTouches = 1;
	pan.maximumNumberOfTouches = 1;
	pan.canHitTest = [self respondsToSelector:@selector(keyHitTest:)];
	pan.delegate = pan;
	[self addGestureRecognizer:pan];
}
%new
- (void)handleHandBiasPan:(UIPanGestureRecognizer *)pan {
	if ( !enableTweak ) {
		return;
	}
	if ( pan.state != UIGestureRecognizerStateEnded ) {
		return;
	}
	if ( ![pan isKindOfClass:[KeyboardControllerHandBiasGesture class]] ) {
		return;
	}
	int startKind = ((KeyboardControllerHandBiasGesture *)pan).startKind;
	CGPoint translation = [pan translationInView:self];
	BOOL swipedDown = ( translation.y > biasSwipeThreshold ) && ( fabs(translation.y) > fabs(translation.x) );
	if ( !swipedDown ) {
		return;
	}
	// The same two calls the globe key menu makes, so the dock follows and the
	// choice carries to other apps.
	Class prefsClass = %c(UIKeyboardPreferencesController);
	if ( oneHandedKeyboard != 999 || ![prefsClass respondsToSelector:@selector(sharedPreferencesController)] || ![self respondsToSelector:@selector(setKeyboardBias:)] ) {
		return;
	}
	UIKeyboardPreferencesController *prefs = [prefsClass sharedPreferencesController];
	if ( ![prefs respondsToSelector:@selector(handBias)] || ![prefs respondsToSelector:@selector(setHandBias:)] ) {
		return;
	}
	long long current = [prefs handBias];
	long long bias;
	if ( startKind == keyMore && oneHandedGestureLeft ) {
		bias = ( current == 2 ) ? 0 : 2;
	} else if ( ( startKind == keyDelete && oneHandedGestureRight ) || ( startKind == keyReturn && oneHandedGestureReturn ) ) {
		bias = ( current == 1 ) ? 0 : 1;
	} else {
		return;
	}
	[prefs setHandBias:bias];
	[self setKeyboardBias:bias];
}
- (void)_setBiasEscapeButtonVisible:(int)arg1 {
	if ( enableTweak && oneHandedKeyboard != 999 ) {
		%orig(0);
	} else {
		%orig;
	}
	UpdateEscapeTools(self);
}
%end

%end

%group Dictation

%hook UIKeyboardLayoutStar
- (int)shouldShowDictationKey {
	if ( enableTweak && dictationButton != 999 ) {
		return dictationButton;
	}
	return %orig;
}
%end

%hook UIKeyboardSplitTransitionView
- (int)showDictationKey {
	if ( enableTweak && dictationButton != 999 ) {
		return dictationButton;
	}
	return %orig;
}
%end

%hook UIPeripheralHost
- (int)hasDictationKeyboard {
	if ( enableTweak && dictationButton != 999 ) {
		return dictationButton;
	}
	return %orig;
}
%end

%hook UITextInputTraits
- (int)forceDisableDictation {
	if ( enableTweak && dictationButton != 999 ) {
		return !dictationButton;
	}
	return %orig;
}
- (int)forceEnableDictation {
	if ( enableTweak && dictationButton != 999 ) {
		return dictationButton;
	}
	return %orig;
}
%end

%hook UIKeyboardImpl
- (bool)shouldShowDictationKey {
	if ( enableTweak && dictationButton != 999 ) {
		return dictationButton;
	}
	return %orig;
}
%end

%end

%group HandBiasSwitch

%hook UIInputSwitcherView
- (int)_isHandBiasSwitchVisible {
	if ( enableTweak && oneHandedKeyboard != 999 ) {
		return 0;
	}
	return %orig;
}
%end

%end

%group BlueTheming

%hook UIKBRenderFactory
- (int)useBlueThemingForKey:(id)arg1 {
	if ( enableTweak && useBlueThemingForKey != 999 ) {
		return useBlueThemingForKey;
	}
	return %orig;
}
%end

%end


%group ReturnKeyStyling

%hook UITextInputTraits
- (int)suppressReturnKeyStyling {
	if ( enableTweak && returnKeyStyling != 999 ) {
		return !returnKeyStyling;
	}
	return %orig;
}
%end

%end


%group GlobeKey

%hook UIKeyboardImpl
- (int)shouldShowInternationalKey {
	if ( enableTweak && shouldShowInternationalKey != 999 ) {
		return shouldShowInternationalKey;
	}
	return %orig;
}
%end

%end


%group Trackpad

%hook _UIKeyboardTextSelectionInteraction
- (bool)forceTouchGestureRecognizerShouldBegin:(id)arg1 {
	if ( enableTweak && ( trackpadMode == 404 || trackpadMode == 505 ) ) {
		return NO;
	} else if ( enableTweak && trackpadMode == 1 ) {
		return YES;
	}
	return %orig;
}
- (bool)gestureRecognizerShouldBegin:(id)arg1 {
	if ( enableTweak && trackpadMode == 404 ) {
		return NO;
	} else if ( enableTweak && trackpadMode == 505 ) {
		return YES;
	} else if ( enableTweak && trackpadMode == 1 ) {
		return YES;
	}
	return %orig;
}
%end

%end

%ctor {
	NSArray *arguments = [[NSProcessInfo processInfo] arguments];
	NSString *executablePath = arguments.count > 0 ? arguments[0] : nil;
	// UIKit serves the colour picker out of process from its own PlugIns
	// directory, so that path matches neither of the other two. It is the only
	// bundle in there whose binary references UITextField.
	if ( [executablePath containsString:@"SpringBoard.app"]
	||
	[executablePath containsString:@"/Application"]
	||
	[executablePath containsString:@"com.apple.UIKit.ColorPicker"] ) {
		canAskForAncestorController = [UIView instancesRespondToSelector:@selector(_viewControllerForAncestor)];
		// Synchronous here, unlike every later reload: the %init calls below read
		// these values to decide which hooks to install at all.
		ApplySettings(LoadSettings());
		CFNotificationCenterAddObserver(
			CFNotificationCenterGetDarwinNotifyCenter(),
			NULL,
			receivedNotification,
			CFSTR("com.tomaszpoliszuk.keyboardcontroller.settingschanged"),
			NULL,
			CFNotificationSuspensionBehaviorDeliverImmediately
		);
		// Only the features that are switched on get hooked. Turning one on takes
		// effect the next time the process starts, not on the settings change.
		// Settings hooks everything, so its testing areas show a change at once.
		BOOL hookEverything = [[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.Preferences"];
		if ( !enableTweak && !hookEverything ) {
			return;
		}
		if ( hookEverything || uiStyle != 999 ) {
			%init(UIStyle);
		}
		if ( hookEverything || MapsAreActive() ) {
			%init(TypeMaps);
		}
		if ( ( hookEverything || keyboardDismissMode != 999 ) && canAskForAncestorController ) {
			%init(DismissMode);
		}
		if ( hookEverything || selectingSkinToneForEmoji != 999 ) {
			%init(SkinTone);
		}
		if ( hookEverything || oneHandedKeyboard != 999 || oneHandedGestureLeft || oneHandedGestureRight || oneHandedGestureReturn || oneHandedTools ) {
			%init(OneHanded);
		}
		if ( hookEverything || oneHandedKeyboard != 999 ) {
			%init(HandBiasSwitch);
		}
		if ( hookEverything || useBlueThemingForKey != 999 ) {
			%init(BlueTheming);
		}
		if ( hookEverything || dictationButton != 999 ) {
			%init(Dictation);
		}
		if ( hookEverything || returnKeyStyling != 999 ) {
			%init(ReturnKeyStyling);
		}
		if ( hookEverything || shouldShowInternationalKey != 999 ) {
			%init(GlobeKey);
		}
		if ( hookEverything || trackpadMode != 999 ) {
			%init(Trackpad);
		}
	}
}
