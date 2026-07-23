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

NSMutableDictionary *tweakSettings;

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

static int feedbackType;

static int feedbackWhen;

static void SettingsChanged() {
	CFArrayRef keyList = CFPreferencesCopyKeyList(CFSTR(kPackageName), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	if(keyList) {
		tweakSettings = (NSMutableDictionary *)CFBridgingRelease(
			CFPreferencesCopyMultiple(
				keyList,
				CFSTR(kPackageName),
				kCFPreferencesCurrentUser,
				kCFPreferencesAnyHost
			)
		);
		CFRelease(keyList);
	} else {
		tweakSettings = nil;
	}
	if ( !tweakSettings ) {
		tweakSettings = [NSMutableDictionary dictionaryWithContentsOfFile:PreferencesFilePath()];
	}

	enableTweak = [([tweakSettings objectForKey:@"enableTweak"] ?: @(YES)) boolValue];

	uiStyle = [([tweakSettings objectForKey:@"uiStyle"] ?: @(999)) integerValue];

	for ( int i = 0; i < kKeyboardTypeCount; i++ ) {
		keyboardTypeMap[i] = [([tweakSettings objectForKey:keyboardTypeKeys[i]] ?: @(i)) integerValue];
		returnKeyTypeMap[i] = [([tweakSettings objectForKey:returnKeyTypeKeys[i]] ?: @(i)) integerValue];
	}

	keyboardDismissMode = [([tweakSettings objectForKey:@"keyboardDismissMode"] ?: @(999)) integerValue];

	trackpadMode = [([tweakSettings objectForKey:@"trackpadMode"] ?: @(999)) integerValue];

	returnKeyStyling = [([tweakSettings objectForKey:@"returnKeyStyling"] ?: @(999)) integerValue];

	dictationButton = [([tweakSettings objectForKey:@"dictationButton"] ?: @(999)) integerValue];

	shouldShowInternationalKey = [([tweakSettings objectForKey:@"shouldShowInternationalKey"] ?: @(999)) integerValue];

	selectingSkinToneForEmoji = [([tweakSettings objectForKey:@"selectingSkinToneForEmoji"] ?: @(999)) integerValue];

	oneHandedKeyboard = [([tweakSettings objectForKey:@"oneHandedKeyboard"] ?: @(999)) integerValue];

	oneHandedGestureLeft = [([tweakSettings objectForKey:@"oneHandedGestureLeft"] ?: @(0)) boolValue];
	oneHandedGestureRight = [([tweakSettings objectForKey:@"oneHandedGestureRight"] ?: @(0)) boolValue];
	oneHandedGestureReturn = [([tweakSettings objectForKey:@"oneHandedGestureReturn"] ?: @(0)) boolValue];

	useBlueThemingForKey = [([tweakSettings objectForKey:@"useBlueThemingForKey"] ?: @(999)) integerValue];

	feedbackType = [([tweakSettings objectForKey:@"feedbackType"] ?: @(0)) integerValue];

	feedbackWhen = [([tweakSettings objectForKey:@"feedbackWhen"] ?: @(0)) integerValue];
}

static void receivedNotification(
	CFNotificationCenterRef center,
	void *observer,
	CFStringRef name,
	const void *object,
	CFDictionaryRef userInfo
) {
	SettingsChanged();
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
	NSString *disp = [key respondsToSelector:@selector(displayString)] ? [key displayString] : nil;
	if ( [rep isEqualToString:@"More"] || [disp isEqualToString:@"123"] || [disp isEqualToString:@"#+="] || [disp isEqualToString:@"ABC"] ) {
		return keyMore;
	}
	if ( [rep isEqualToString:@"Delete"] ) {
		return keyDelete;
	}
	if ( [rep isEqualToString:@"\n"] || [rep isEqualToString:@"\r"] || [rep isEqualToString:@"Return"] ) {
		return keyReturn;
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

static int classifyKeyByGeometry(CGPoint point, CGRect bounds) {
	if ( bounds.size.width <= 0 || bounds.size.height <= 0 ) {
		return keyNone;
	}
	CGFloat x = point.x / bounds.size.width;
	CGFloat y = point.y / bounds.size.height;
	if ( y < 0.70 ) {
		return keyNone;
	}
	if ( x < 0.18 ) {
		return keyMore;
	}
	if ( x > 0.82 ) {
		return keyReturn;
	}
	return keyNone;
}

@interface KeyboardControllerHandBiasGesture : UIPanGestureRecognizer <UIGestureRecognizerDelegate>
@property (nonatomic, assign) int startKind;
@property (nonatomic, weak) UIKeyboardLayoutStar *layout;
@end

@implementation KeyboardControllerHandBiasGesture
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
	UIKeyboardLayoutStar *layout = self.layout;
	if ( !layout ) {
		self.startKind = keyNone;
		return NO;
	}
	CGPoint point = [touch locationInView:layout];
	int kind = keyNone;
	if ( [layout respondsToSelector:@selector(keyHitTest:)] ) {
		kind = classifyKey([layout keyHitTest:point]);
	}
	if ( kind == keyNone ) {
		kind = classifyKeyByGeometry(point, layout.bounds);
	}
	if ( ( kind == keyMore && !oneHandedGestureLeft )
		|| ( kind == keyDelete && !oneHandedGestureRight )
		|| ( kind == keyReturn && !oneHandedGestureReturn ) ) {
		kind = keyNone;
	}
	self.startKind = kind;
	return kind != keyNone;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
	return YES;
}
@end


%hook UITextInputTraits
- (long long)keyboardAppearance {
	long long origValue = %orig;
	if ( enableTweak && uiStyle != 999 ) {
		return uiStyle;
	}
	return origValue;
}
- (long long)keyboardType {
	long long origValue = %orig;
	if ( enableTweak && origValue >= 0 && origValue < kKeyboardTypeCount ) {
		return keyboardTypeMap[origValue];
	}
	return origValue;
}
- (void)setKeyboardType:(long long)keyboardType {
	if ( enableTweak && keyboardType >= 0 && keyboardType < kKeyboardTypeCount ) {
		keyboardType = keyboardTypeMap[keyboardType];
	}
	%orig(keyboardType);
}
- (long long)returnKeyType {
	long long origValue = %orig;
	if ( enableTweak && origValue >= 0 && origValue < kKeyboardTypeCount ) {
		return returnKeyTypeMap[origValue];
	}
	return origValue;
}
%end

%hook UIScrollView
- (long long)keyboardDismissMode {
	long long origValue = %orig;
	if ( enableTweak && keyboardDismissMode != 999 ) {
		if (
			![[self _viewControllerForAncestor] isKindOfClass:%c(UICompatibilityInputViewController)]
			&&
			![[self _viewControllerForAncestor] isKindOfClass:%c(UICandidateViewController)]
			&&
			![[self _viewControllerForAncestor] isKindOfClass:%c(UIInputViewController)]
		) {
			return keyboardDismissMode;
		}
	}
	return origValue;
}
%end

%hook UIKeyboardEmojiCollectionInputView
- (int)skinToneWasUsedForEmoji:(id)arg1 {
	int origValue = %orig;
	if ( enableTweak && selectingSkinToneForEmoji != 999 ) {
		return selectingSkinToneForEmoji;
	}
	return origValue;
}
%end

%hook UIKeyboardEmojiPreferences
- (int)hasDisplayedSkinToneHelp {
	int origValue = %orig;
	if ( enableTweak && selectingSkinToneForEmoji != 999 ) {
		return selectingSkinToneForEmoji;
	}
	return origValue;
}
%end

%hook UIKeyboardLayoutStar
- (long long)currentHandBias {
	long long origValue = %orig;
	if ( enableTweak && ( oneHandedGestureLeft || oneHandedGestureRight || oneHandedGestureReturn ) && gestureHandBias != -1 ) {
		return gestureHandBias;
	}
	if ( enableTweak && oneHandedKeyboard != 999 ) {
		return oneHandedKeyboard;
	}
	return origValue;
}
- (void)didMoveToWindow {
	%orig;
	if ( !enableTweak || ( !oneHandedGestureLeft && !oneHandedGestureRight && !oneHandedGestureReturn ) || !self.window ) {
		return;
	}
	for ( UIGestureRecognizer *recognizer in self.gestureRecognizers ) {
		if ( [recognizer isKindOfClass:[KeyboardControllerHandBiasGesture class]] ) {
			return;
		}
	}
	KeyboardControllerHandBiasGesture *pan = [[KeyboardControllerHandBiasGesture alloc] initWithTarget:self action:@selector(handleHandBiasPan:)];
	pan.minimumNumberOfTouches = 1;
	pan.maximumNumberOfTouches = 1;
	pan.layout = self;
	pan.delegate = pan;
	[self addGestureRecognizer:pan];
}
%new
- (void)handleHandBiasPan:(UIPanGestureRecognizer *)pan {
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
- (int)shouldShowDictationKey {
	int origValue = %orig;
	if ( enableTweak && dictationButton != 999 ) {
		return dictationButton;
	}
	return origValue;
}
%end

%hook UIKeyboardSplitTransitionView
- (int)showDictationKey {
	int origValue = %orig;
	if ( enableTweak && dictationButton != 999 ) {
		return dictationButton;
	}
	return origValue;
}
%end

%hook UIPeripheralHost
- (int)hasDictationKeyboard {
	int origValue = %orig;
	if ( enableTweak && dictationButton != 999 ) {
		return dictationButton;
	}
	return origValue;
}
%end

%hook UIInputSwitcherView
- (int)_isHandBiasSwitchVisible {
	int origValue = %orig;
	if ( enableTweak && oneHandedKeyboard != 999 ) {
		return 0;
	}
	return origValue;
}
%end

%hook UIKBRenderFactory
- (int)useBlueThemingForKey:(id)arg1 {
	int origValue = %orig;
	if ( enableTweak && useBlueThemingForKey != 999 ) {
		return useBlueThemingForKey;
	}
	return origValue;
}
%end


%group iOS8

%hook UITextInputTraits
- (int)suppressReturnKeyStyling {
	int origValue = %orig;
	if ( enableTweak && returnKeyStyling != 999 ) {
		return !returnKeyStyling;
	}
	return origValue;
}
%end

%end


%group iOS9_3_4

%hook UITextInputTraits
- (int)forceDisableDictation {
	int origValue = %orig;
	if ( enableTweak && dictationButton != 999 ) {
		return !dictationButton;
	}
	return origValue;
}
%end

%end


%group iOS10

%hook UITextInputTraits
- (int)forceEnableDictation {
	int origValue = %orig;
	if ( enableTweak && dictationButton != 999 ) {
		return dictationButton;
	}
	return origValue;
}
%end

%hook UIKeyboardImpl
- (bool)shouldShowDictationKey {
	int origValue = %orig;
	if ( enableTweak && dictationButton != 999 ) {
		return dictationButton;
	}
	return origValue;
}
%end

%end


%group iOS11

%hook UIKeyboardImpl
- (int)shouldShowInternationalKey {
	int origValue = %orig;
	if ( enableTweak && shouldShowInternationalKey != 999 ) {
		return shouldShowInternationalKey;
	}
	return origValue;
}
%end

%end


%group iOS12

%hook _UIKeyboardTextSelectionInteraction
- (bool)forceTouchGestureRecognizerShouldBegin:(id)arg1 {
	int origValue = %orig;
	if ( enableTweak && trackpadMode == 404 ) {
		return NO;
	} else if ( enableTweak && trackpadMode == 505 ) {
		return NO;
	} else if ( enableTweak && trackpadMode == 1 ) {
		return YES;
	}
	return origValue;
}
- (bool)gestureRecognizerShouldBegin:(id)arg1 {
	int origValue = %orig;
	if ( enableTweak && trackpadMode == 404 ) {
		return NO;
	} else if ( enableTweak && trackpadMode == 505 ) {
		return YES;
	} else if ( enableTweak && trackpadMode == 1 ) {
		return YES;
	}
	return origValue;
}
%end

%end

%ctor {
	if ( [ [ [ [NSProcessInfo processInfo] arguments] objectAtIndex:0] containsString:@"SpringBoard.app" ]
	||
	[ [ [ [NSProcessInfo processInfo] arguments] objectAtIndex:0] containsString:@"/Application" ] ) {
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
			SettingsChanged();
		});
		CFNotificationCenterAddObserver(
			CFNotificationCenterGetDarwinNotifyCenter(),
			NULL,
			receivedNotification,
			CFSTR("com.tomaszpoliszuk.keyboardcontroller.settingschanged"),
			NULL,
			CFNotificationSuspensionBehaviorDeliverImmediately
		);
		if (@available(iOS 8, *)) {
			%init(iOS8);
		}
		if (@available(iOS 9.3.4, *)) {
			%init(iOS9_3_4);
		}
		if (@available(iOS 10, *)) {
			%init(iOS10);
		}
		if (@available(iOS 11, *)) {
			%init(iOS11);
		}
		if (@available(iOS 12, *)) {
			%init(iOS12);
		}
		%init;
	}
}
