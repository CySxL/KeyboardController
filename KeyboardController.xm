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

static long long gestureHandBias = -1;

enum { keyNone = 0, keyMore = 1, keyDelete = 2, keyReturn = 3 };

static const CGFloat biasSwipeThreshold = 18.0;

@interface UIKeyboardLayoutStar : UIView
- (id)keyHitTest:(CGPoint)point;
@end

@interface UIKBTree : NSObject
- (NSString *)representedString;
- (NSString *)displayString;
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

static void applyHandBias(UIView *layout) {
	Class implClass = %c(UIKeyboardImpl);
	id impl = nil;
	if ( [implClass respondsToSelector:@selector(activeInstance)] ) {
		impl = [implClass performSelector:@selector(activeInstance)];
	} else if ( [implClass respondsToSelector:@selector(sharedInstance)] ) {
		impl = [implClass performSelector:@selector(sharedInstance)];
	}
	if ( impl && [impl respondsToSelector:@selector(updateLayout)] ) {
		[impl performSelector:@selector(updateLayout)];
	}
	if ( layout ) {
		[layout setNeedsLayout];
		[layout layoutIfNeeded];
	}
}

@interface KeyboardControllerHandBiasGesture : UIPanGestureRecognizer <UIGestureRecognizerDelegate>
@property (nonatomic, assign) int startKind;
@property (nonatomic, assign) BOOL canHitTest;
@end

@implementation KeyboardControllerHandBiasGesture
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
	// self.view is the layout this was added to, and costs no weak table lock.
	UIKeyboardLayoutStar *layout = (UIKeyboardLayoutStar *)self.view;
	if ( !enableTweak || !layout || !self.canHitTest ) {
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
	if ( ![gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] ) {
		return YES;
	}
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
	if ( enableTweak && ( oneHandedGestureLeft || oneHandedGestureRight || oneHandedGestureReturn ) && gestureHandBias != -1 ) {
		return gestureHandBias;
	}
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
	if ( startKind == keyMore && oneHandedGestureLeft ) {
		gestureHandBias = ( gestureHandBias == 2 ) ? 0 : 2;
		applyHandBias(self);
	} else if ( ( startKind == keyDelete && oneHandedGestureRight ) || ( startKind == keyReturn && oneHandedGestureReturn ) ) {
		gestureHandBias = ( gestureHandBias == 1 ) ? 0 : 1;
		applyHandBias(self);
	}
}
- (void)_setBiasEscapeButtonVisible:(int)arg1 {
	if ( enableTweak && ( oneHandedKeyboard != 999 || ( ( oneHandedGestureLeft || oneHandedGestureRight || oneHandedGestureReturn ) && gestureHandBias > 0 ) ) ) {
		%orig(0);
	} else {
		%orig;
	}
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


%group iOS8

%hook UITextInputTraits
- (int)suppressReturnKeyStyling {
	if ( enableTweak && returnKeyStyling != 999 ) {
		return !returnKeyStyling;
	}
	return %orig;
}
%end

%end


%group iOS9_3_4

%hook UITextInputTraits
- (int)forceDisableDictation {
	if ( enableTweak && dictationButton != 999 ) {
		return !dictationButton;
	}
	return %orig;
}
%end

%end


%group iOS10

%hook UITextInputTraits
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


%group iOS11

%hook UIKeyboardImpl
- (int)shouldShowInternationalKey {
	if ( enableTweak && shouldShowInternationalKey != 999 ) {
		return shouldShowInternationalKey;
	}
	return %orig;
}
%end

%end


%group iOS12

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
		if ( !enableTweak ) {
			return;
		}
		if ( uiStyle != 999 ) {
			%init(UIStyle);
		}
		if ( MapsAreActive() ) {
			%init(TypeMaps);
		}
		if ( keyboardDismissMode != 999 && canAskForAncestorController ) {
			%init(DismissMode);
		}
		if ( selectingSkinToneForEmoji != 999 ) {
			%init(SkinTone);
		}
		if ( oneHandedKeyboard != 999 || oneHandedGestureLeft || oneHandedGestureRight || oneHandedGestureReturn ) {
			%init(OneHanded);
		}
		if ( oneHandedKeyboard != 999 ) {
			%init(HandBiasSwitch);
		}
		if ( useBlueThemingForKey != 999 ) {
			%init(BlueTheming);
		}
		if ( dictationButton != 999 ) {
			%init(Dictation);
			if (@available(iOS 9.3.4, *)) {
				%init(iOS9_3_4);
			}
			if (@available(iOS 10, *)) {
				%init(iOS10);
			}
		}
		if ( returnKeyStyling != 999 ) {
			if (@available(iOS 8, *)) {
				%init(iOS8);
			}
		}
		if ( shouldShowInternationalKey != 999 ) {
			if (@available(iOS 11, *)) {
				%init(iOS11);
			}
		}
		if ( trackpadMode != 999 ) {
			if (@available(iOS 12, *)) {
				%init(iOS12);
			}
		}
	}
}
