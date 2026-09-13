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
- (double)biasedKeyboardWidthRatio;
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
@end

@interface UIKBKeyplaneView : UIView
- (id)factory;
@end

@interface UIKBRenderFactory : NSObject
- (double)keyCornerRadius;
- (id)controlKeyBackgroundColorName;
@end

@interface UIKBRenderConfig : NSObject
- (bool)lightKeyboard;
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

// One tool drawn as a key, the symbol in a fixed slot so the names line up.
@interface KeyboardControllerToolButton : UIButton
@property (nonatomic, readonly) UIImageView *symbolView;
@property (nonatomic, readonly) UILabel *nameLabel;
@end

@implementation KeyboardControllerToolButton
- (instancetype)initWithSymbol:(NSString *)symbol name:(NSString *)name {
	self = [super initWithFrame:CGRectZero];
	if ( self ) {
		_symbolView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
		_symbolView.contentMode = UIViewContentModeCenter;
		_nameLabel = [[UILabel alloc] init];
		_nameLabel.text = name;
		_nameLabel.adjustsFontSizeToFitWidth = YES;
		_nameLabel.minimumScaleFactor = 0.5;
		[self addSubview:_symbolView];
		[self addSubview:_nameLabel];
		self.clipsToBounds = YES;
	}
	return self;
}
@end

// Fills the gap beside the one-handed keyboard, on whichever side the escape
// arrow is.
@interface KeyboardControllerToolsView : UIView
@property (nonatomic, weak) UIView *escapeButton;
@property (nonatomic, assign) CGFloat spacing;
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
- (void)setSpacing:(CGFloat)spacing {
	if ( spacing != _spacing ) {
		_spacing = spacing;
		[self setNeedsLayout];
	}
}
- (void)applyBackground:(UIColor *)background foreground:(UIColor *)foreground cornerRadius:(CGFloat)radius {
	for ( KeyboardControllerToolButton *button in self.subviews ) {
		button.backgroundColor = background;
		button.layer.cornerRadius = radius;
		button.symbolView.tintColor = foreground;
		button.nameLabel.textColor = foreground;
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
	CGFloat spacing = MIN(_spacing, size.height / count);
	CGFloat height = ( size.height - spacing * ( count - 1 ) ) / count;
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

// Apple's width ratio gives the gap beside the keys. The keys give the rest:
// the top of the first row to the bottom of the last, the gap between rows,
// and their margin to the far edge, used on the outer side of the tools.
static void LayOutTools(KeyboardControllerToolsView *tools, UIKeyboardLayoutStar *layout, id keyplaneView) {
	UIView *escapeButton = tools.escapeButton;
	CGRect bounds = layout.bounds;
	CGRect area = escapeButton.frame;
	CGFloat spacing = 0;
	UIView *plane = [keyplaneView isKindOfClass:[UIView class]] ? keyplaneView : nil;
	double ratio = [layout respondsToSelector:@selector(biasedKeyboardWidthRatio)] ? [layout biasedKeyboardWidthRatio] : 0;
	UIKBTree *keyplane = [layout respondsToSelector:@selector(keyplane)] ? [layout keyplane] : nil;
	NSArray *keys = [keyplane respondsToSelector:@selector(keys)] ? [keyplane keys] : nil;
	if ( ratio > 0 && ratio < 1 && [keys isKindOfClass:[NSArray class]] ) {
		CGFloat minX = CGFLOAT_MAX, maxX = -CGFLOAT_MAX;
		CGFloat top = CGFLOAT_MAX, bottom = -CGFLOAT_MAX, topHeight = 0, secondTop = CGFLOAT_MAX;
		for ( UIKBTree *key in keys ) {
			if ( ![key respondsToSelector:@selector(visible)] || ![key respondsToSelector:@selector(frame)] || ![key visible] ) {
				continue;
			}
			CGRect frame = plane ? [plane convertRect:[key frame] toView:layout] : [key frame];
			minX = MIN(minX, CGRectGetMinX(frame));
			maxX = MAX(maxX, CGRectGetMaxX(frame));
			bottom = MAX(bottom, CGRectGetMaxY(frame));
			CGFloat y = CGRectGetMinY(frame);
			if ( y < top - 0.5 ) {
				secondTop = top;
				top = y;
				topHeight = frame.size.height;
			} else if ( y <= top + 0.5 ) {
				topHeight = MAX(topHeight, frame.size.height);
			} else if ( y < secondTop ) {
				secondTop = y;
			}
		}
		if ( bottom > top ) {
			if ( secondTop < CGFLOAT_MAX ) {
				spacing = MAX(0, secondTop - top - topHeight);
			}
			CGFloat gap = bounds.size.width * ( 1 - ratio );
			BOOL left = CGRectGetMidX(escapeButton.frame) < CGRectGetMidX(bounds);
			CGFloat outer = MAX(0, left ? CGRectGetMaxX(bounds) - maxX : minX - CGRectGetMinX(bounds));
			CGFloat width = gap - outer - spacing;
			if ( width > 0 ) {
				CGFloat x = left ? CGRectGetMinX(bounds) + outer : CGRectGetMaxX(bounds) - gap + spacing;
				area = CGRectMake(x, top, width, bottom - top);
			}
		}
	}
	tools.frame = area;
	tools.spacing = spacing;

	UIKBRenderFactory *factory = [plane respondsToSelector:@selector(factory)] ? [(UIKBKeyplaneView *)plane factory] : nil;
	UIColor *background = [factory respondsToSelector:@selector(controlKeyBackgroundColorName)] ? NamedKeyboardColor([factory controlKeyBackgroundColorName]) : nil;
	CGFloat radius = [factory respondsToSelector:@selector(keyCornerRadius)] ? [factory keyCornerRadius] : 0;
	UIKBRenderConfig *config = [layout respondsToSelector:@selector(renderConfig)] ? [layout renderConfig] : nil;
	BOOL light = [config respondsToSelector:@selector(lightKeyboard)] ? [config lightKeyboard] : tools.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark;
	[tools applyBackground:background foreground:( light ? [UIColor blackColor] : [UIColor whiteColor] ) cornerRadius:radius];
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
	LayOutTools(tools, layout, keyplaneViewIvar ? object_getIvar(layout, keyplaneViewIvar) : nil);
	escapeButton.alpha = 0;
	escapeButton.userInteractionEnabled = NO;
	tools.hidden = escapeButton.hidden;
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
