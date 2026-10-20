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


#include "../headers.h"

#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
#define PACKAGE_SCHEME "roothide"
#elif defined(THEOS_PACKAGE_SCHEME_ROOTLESS)
#define PACKAGE_SCHEME "rootless"
#elif defined(THEOS_PACKAGE_SCHEME_ROOTFUL)
#define PACKAGE_SCHEME "rootful"
#else
#error theos defined no package scheme
#endif

static const CGFloat kHeaderIconSide = 80.0;
static const CGFloat kHeaderGap = 16.0;
// The largest that fits beside the icon on a 14 Pro Max (254 pt), so the text
// is drawn unscaled there.
static const CGFloat kHeaderNameSize = 27.0;
static const CGFloat kHeaderVersionSize = 15.0;
static const CGFloat kHeaderSchemeSize = 13.0;
static const CGFloat kHeaderNameToVersion = 24.0;
static const CGFloat kHeaderVersionToScheme = 19.0;

static UIFont *HeaderNameFont(CGFloat size) {
	UIFontDescriptor *bold = [[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleLargeTitle]
		fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
	return [UIFont fontWithDescriptor:bold size:size];
}

// Where the name's baseline sits against the icon's middle, the block centred
// on it, so a larger name would grow upward only.
static CGFloat HeaderNameBaselineOffset(CGFloat scale) {
	UIFont *reference = HeaderNameFont(kHeaderNameSize * scale);
	UIFont *scheme = [UIFont systemFontOfSize:kHeaderSchemeSize * scale];
	CGFloat height = reference.ascender + (kHeaderNameToVersion + kHeaderVersionToScheme) * scale - scheme.descender;
	return reference.ascender - height / 2.0;
}

// The icons are loose files in a subdirectory, so imageNamed: does not find
// them and imageWithContentsOfFile: does no scale search. Pick the suffix from
// the screen and let UIImage read the scale back off the filename.
static UIImage *KeyboardControllerIcon(NSString *name) {
	NSBundle *bundle = [NSBundle bundleForClass:[KeyboardControllerMainSettings class]];
	for ( NSInteger scale = (NSInteger)[UIScreen mainScreen].scale; scale >= 1; scale-- ) {
		NSString *suffix = scale > 1 ? [NSString stringWithFormat:@"@%ldx", (long)scale] : @"";
		NSString *path = [bundle pathForResource:[name stringByAppendingString:suffix] ofType:@"png" inDirectory:@"icons"];
		if ( path ) {
			return [UIImage imageWithContentsOfFile:path];
		}
	}
	return nil;
}

@implementation KeyboardControllerHeaderCell {
	UILabel *_name;
	UILabel *_version;
	UILabel *_scheme;
	UIStackView *_text;
	NSLayoutConstraint *_nameBaseline;
	CGFloat _scale;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
	self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
	if ( !self ) {
		return nil;
	}

	UIImageView *icon = [[UIImageView alloc] initWithImage:KeyboardControllerIcon(@"KeyboardController")];
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	icon.clipsToBounds = YES;
	icon.layer.cornerCurve = kCACornerCurveContinuous;
	icon.layer.cornerRadius = kHeaderIconSide * 0.225;
	[self.contentView addSubview:icon];

	_name = [[UILabel alloc] init];
	_name.text = @"Keyboard Controller";
	// The icon's grey, sampled from it.
	_name.textColor = [UIColor colorWithRed:0x75 / 255.0 green:0x75 / 255.0 blue:0x75 / 255.0 alpha:1.0];

	_version = [[UILabel alloc] init];
	_version.text = @"Version " PACKAGE_VERSION;
	_version.textColor = [UIColor systemGrayColor];

	_scheme = [[UILabel alloc] init];
	_scheme.text = @PACKAGE_SCHEME.capitalizedString;
	_scheme.textColor = [UIColor systemGrayColor];

	// Spacing is baseline to baseline, so the large name does not push the two
	// lines under it away with its own leading.
	_text = [[UIStackView alloc] initWithArrangedSubviews:@[ _name, _version, _scheme ]];
	_text.axis = UILayoutConstraintAxisVertical;
	_text.alignment = UIStackViewAlignmentLeading;
	_text.baselineRelativeArrangement = YES;
	_text.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:_text];
	_nameBaseline = [_name.firstBaselineAnchor constraintEqualToAnchor:icon.centerYAnchor];
	[self applyTextScale:1.0];

	UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[icon.widthAnchor constraintEqualToConstant:kHeaderIconSide],
		[icon.heightAnchor constraintEqualToConstant:kHeaderIconSide],
		[icon.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[icon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_text.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:kHeaderGap],
		_nameBaseline
	]];

	return self;
}

// The text block at a fraction of its full size: fonts and spacing together, so
// the three lines keep their proportions. The icon is never scaled.
- (void)applyTextScale:(CGFloat)scale {
	if ( scale == _scale ) {
		return;
	}
	_scale = scale;
	_name.font = HeaderNameFont(kHeaderNameSize * scale);
	_version.font = [UIFont systemFontOfSize:kHeaderVersionSize * scale];
	_scheme.font = [UIFont systemFontOfSize:kHeaderSchemeSize * scale];
	[_text setCustomSpacing:kHeaderNameToVersion * scale afterView:_name];
	[_text setCustomSpacing:kHeaderVersionToScheme * scale afterView:_version];
	_nameBaseline.constant = HeaderNameBaselineOffset(scale);
}

// Full size wherever the name fits beside the icon; a narrower phone shrinks the
// whole block by the name's overflow rather than truncating it.
- (void)layoutSubviews {
	CGFloat available = CGRectGetWidth(self.contentView.layoutMarginsGuide.layoutFrame) - kHeaderIconSide - kHeaderGap;
	CGFloat natural = [_name.text sizeWithAttributes:@{ NSFontAttributeName: HeaderNameFont(kHeaderNameSize) }].width;
	[self applyTextScale:( available > 0 && natural > available ) ? available / natural : 1.0];
	[super layoutSubviews];
}

- (void)setSeparatorStyle:(UITableViewCellSeparatorStyle)style {
	[super setSeparatorStyle:UITableViewCellSeparatorStyleNone];
}

- (void)setBackgroundColor:(UIColor *)color {
	[super setBackgroundColor:[UIColor clearColor]];
}

- (UITableViewCellSelectionStyle)selectionStyle {
	return UITableViewCellSelectionStyleNone;
}

@end

// Removes what was typed into the test fields by versions that stored it.
static void ClearStoredTestFields(void) {
	NSArray *keys = @[
		@"testKeyboard",
		@"defaultKeyboardTry",
		@"asciiCapableKeyboardTry",
		@"numbersAndPunctuationKeyboardTry",
		@"urlKeyboardTry",
		@"numberPadKeyboardTry",
		@"phonePadKeyboardTry",
		@"namePhonePadKeyboardTry",
		@"emailAddressKeyboardTry",
		@"decimalPadKeyboardTry",
		@"twitterKeyboardTry",
		@"webSearchKeyboardTry",
		@"asciiCapableNumberPadKeyboardTry",
	];
	NSUserDefaults *tweakSettings = [[NSUserDefaults alloc] initWithSuiteName:@kPackageName];
	BOOL removedAny = NO;
	for ( NSString *key in keys ) {
		if ( [tweakSettings objectForKey:key] ) {
			[tweakSettings removeObjectForKey:key];
			removedAny = YES;
		}
	}
	if ( removedAny ) {
		[tweakSettings synchronize];
	}
}

@implementation KeyboardControllerMainSettings {
	NSMutableDictionary *_transientValues;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
	if ( [specifier propertyForKey:kTransientField] ) {
		return _transientValues[[specifier propertyForKey:@"key"]];
	}
	return [super readPreferenceValue:specifier];
}
- (PSSpecifier *)createGroupSpecifierNamed:(NSString *)name footer:(NSString *)footer key:(NSString *)key {
	PSSpecifier *specifier = [PSSpecifier groupSpecifierWithHeader:name footer:footer];
	[specifier setProperty:name forKey:@"label"];
	[specifier setProperty:key forKey:@"key"];
	[specifier setProperty:key forKey:@"id"];
	return specifier;
}
- (PSSpecifier *)createSwitchSpecifierNamed:(NSString *)name key:(NSString *)key default:(NSString *)defaultValue {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
		target:self
		set:@selector(setPreferenceValue:specifier:)
		get:@selector(readPreferenceValue:)
		detail:nil
		cell:PSSwitchCell
		edit:nil
	];
	[specifier setProperty:name forKey:@"label"];
	[specifier setProperty:key forKey:@"key"];
	[specifier setProperty:key forKey:@"id"];
	[specifier setProperty:defaultValue forKey:@"default"];
	[specifier setProperty:@kPackageName forKey:@"defaults"];
	[specifier setProperty:kSettingsChanged forKey:@"PostNotification"];
	return specifier;
}
- (PSSpecifier *)createSegmentSpecifierNamed:(NSString *)name key:(NSString *)key default:(NSString *)defaultValue {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
		target:self
		set:@selector(setPreferenceValue:specifier:)
		get:@selector(readPreferenceValue:)
		detail:nil
		cell:PSSegmentCell
		edit:nil
	];
	[specifier setProperty:name forKey:@"label"];
	[specifier setProperty:key forKey:@"key"];
	[specifier setProperty:key forKey:@"id"];
	[specifier setProperty:defaultValue forKey:@"default"];
	[specifier setProperty:@kPackageName forKey:@"defaults"];
	[specifier setProperty:kSettingsChanged forKey:@"PostNotification"];
	[specifier setProperty:@"55" forKey:@"height"];
	return specifier;
}
- (PSSpecifier *)createLinkListSpecifierNamed:(NSString *)name key:(NSString *)key default:(NSString *)defaultValue detail:(NSString *)detail {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
		target:self
		set:@selector(setPreferenceValue:specifier:)
		get:@selector(readPreferenceValue:)
		detail:NSClassFromString(detail)
		cell:PSLinkListCell
		edit:nil
	];
	[specifier setProperty:name forKey:@"label"];
	[specifier setProperty:key forKey:@"key"];
	[specifier setProperty:key forKey:@"id"];
	[specifier setProperty:defaultValue forKey:@"default"];
	[specifier setProperty:@kPackageName forKey:@"defaults"];
	[specifier setProperty:kSettingsChanged forKey:@"PostNotification"];
	return specifier;
}
- (PSTextFieldSpecifier *)createEditTextSpecifierNamed:(NSString *)name key:(NSString *)key default:(NSString *)defaultValue {
	PSTextFieldSpecifier *specifier = [PSTextFieldSpecifier preferenceSpecifierNamed:name
		target:self
		set:@selector(setPreferenceValue:specifier:)
		get:@selector(readPreferenceValue:)
		detail:nil
		cell:PSEditTextCell
		edit:nil
	];
	[specifier setProperty:name forKey:@"label"];
	[specifier setProperty:key forKey:@"key"];
	[specifier setProperty:key forKey:@"id"];
	[specifier setProperty:defaultValue forKey:@"default"];
	[specifier setProperty:@YES forKey:kTransientField];
	return specifier;
}
- (PSSpecifier *)createButtonSpecifierNamed:(NSString *)name {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
		target:self
		set:nil
		get:nil
		detail:nil
		cell:PSButtonCell
		edit:nil
	];
	return specifier;
}
- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [NSMutableArray new];

		PSSpecifier *header = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:NULL get:NULL detail:nil cell:PSStaticTextCell edit:nil];
		[header setProperty:[KeyboardControllerHeaderCell class] forKey:@"cellClass"];
		[header setProperty:@142 forKey:@"height"];
		[_specifiers addObject:header];
		[_specifiers addObject:[PSSpecifier emptyGroupSpecifier]];

		PSSpecifier *enableTweak = [self createSwitchSpecifierNamed:@"Enable Tweak" key:@"enableTweak" default:@"1"];
		[enableTweak setProperty:KeyboardControllerIcon(@"KeyboardController") forKey:@"iconImage"];
		[enableTweak setProperty:@"55" forKey:@"height"];
		[_specifiers addObject:enableTweak];

		PSSpecifier *uiStyleGroup = [self createGroupSpecifierNamed:@"UI Style" footer:nil key:@"uiStyleGroup"];
		[_specifiers addObject:uiStyleGroup];

		PSSpecifier *uiStyle = [self createSegmentSpecifierNamed:@"UI Style" key:@"uiStyle" default:@"999"];
		[uiStyle setValues:@[ @"999", @"2", @"1" ] titles:@[ @"Default", @"Light", @"Dark" ]];
		[_specifiers addObject:uiStyle];

		PSSpecifier *selectTypesGroup = [self createGroupSpecifierNamed:@"Select Types" footer:nil key:@"selectTypesGroup"];
		[_specifiers addObject:selectTypesGroup];

		PSSpecifier *selectKeyboardType = [self createLinkListSpecifierNamed:@"Keyboard Type" key:@"selectKeyboardType" default:nil detail:@"KeyboardControllerKeyboardTypeSettings"];
		[_specifiers addObject:selectKeyboardType];

		PSSpecifier *selectTypesReturnKey = [self createLinkListSpecifierNamed:@"Return Key Type" key:@"selectTypesReturnKey" default:nil detail:@"KeyboardControllerReturnKeyTypeSettings"];
		[_specifiers addObject:selectTypesReturnKey];

		PSSpecifier *keyboardDismissModeGroup = [self createGroupSpecifierNamed:@"Swipe to dismiss keyboard" footer:@"Disabled:\nThe keyboard does not get dismissed with a drag.\n\nImmediately:\nThe keyboard is dismissed when a drag begins.\n\nInteractive:\nThe keyboard follows the dragging touch offscreen, and can be pulled upward again to cancel the dismiss." key:@"keyboardDismissModeGroup"];
		[_specifiers addObject:keyboardDismissModeGroup];

		PSSpecifier *keyboardDismissMode = [self createSegmentSpecifierNamed:@"" key:@"keyboardDismissMode" default:@"999"];
		[keyboardDismissMode setValues:@[ @"999", @"0", @"1", @"2" ] titles:@[ @"Default", @"Disabled", @"Immediately", @"Interactive" ]];
		[_specifiers addObject:keyboardDismissMode];

		NSArray *trackpadModeTitles = @[ @"Default", @"Disabled", @"Spacebar only", @"Enabled" ];
		NSArray *trackpadModeValues = @[ @"999", @"404", @"505", @"1" ];

		NSString *trackpadModeFooter = @"Default: only the spacebar activates the trackpad.\nDisabled: the trackpad is off on the whole keyboard.\nEnabled: the whole keyboard activates the trackpad.";

		BOOL supportsForceTouch = [[UIDevice currentDevice] respondsToSelector:@selector(_supportsForceTouch)]
			&& [[UIDevice currentDevice] _supportsForceTouch];
		if ( !supportsForceTouch ) {
			trackpadModeTitles = @[ @"Default", @"Disabled", @"Enabled" ];
			trackpadModeValues = @[ @"999", @"404", @"505" ];
		} else {
			trackpadModeFooter = @"Default: system default.\nDisabled: the trackpad is off on the whole keyboard.\nSpacebar only: only the spacebar activates the trackpad.\nEnabled: the whole keyboard activates the trackpad.";
		}

		PSSpecifier *trackpadModeGroup = [self createGroupSpecifierNamed:@"Trackpad Mode" footer:trackpadModeFooter key:@"trackpadModeGroup"];
		[_specifiers addObject:trackpadModeGroup];

		PSSpecifier *trackpadMode = [self createSegmentSpecifierNamed:@"" key:@"trackpadMode" default:@"999"];
		[trackpadMode setValues:trackpadModeValues titles:trackpadModeTitles];
		[_specifiers addObject:trackpadMode];

		PSSpecifier *dictationButtonGroup = [self createGroupSpecifierNamed:@"Dictation Button" footer:nil key:@"dictationButtonGroup"];
		[_specifiers addObject:dictationButtonGroup];

		PSSpecifier *dictationButton = [self createSegmentSpecifierNamed:@"dictationButton" key:@"dictationButton" default:@"999"];
		[dictationButton setValues:@[ @"999", @"0" ] titles:@[ @"Default", @"Disable" ]];
		[_specifiers addObject:dictationButton];

		PSSpecifier *shouldShowInternationalKeyGroup = [self createGroupSpecifierNamed:@"Globe Button" footer:nil key:@"shouldShowInternationalKeyGroup"];
		[_specifiers addObject:shouldShowInternationalKeyGroup];

		PSSpecifier *shouldShowInternationalKey = [self createSegmentSpecifierNamed:@"shouldShowInternationalKey" key:@"shouldShowInternationalKey" default:@"999"];
		[shouldShowInternationalKey setValues:@[ @"999", @"0" ] titles:@[ @"Default", @"Disable" ]];
		[_specifiers addObject:shouldShowInternationalKey];

		PSSpecifier *returnKeyStylingGroup = [self createGroupSpecifierNamed:@"Return Key Styling" footer:nil key:@"returnKeyStylingGroup"];
		[_specifiers addObject:returnKeyStylingGroup];

		PSSpecifier *returnKeyStyling = [self createSegmentSpecifierNamed:@"returnKeyStyling" key:@"returnKeyStyling" default:@"999"];
		[returnKeyStyling setValues:@[ @"999", @"0", @"1" ] titles:@[ @"Default", @"Disable", @"Enable" ]];
		[_specifiers addObject:returnKeyStyling];

		PSSpecifier *selectingSkinToneForEmojiGroup = [self createGroupSpecifierNamed:@"Selecting skin tone for emoji" footer:nil key:@"selectingSkinToneForEmojiGroup"];
		[_specifiers addObject:selectingSkinToneForEmojiGroup];

		PSSpecifier *selectingSkinToneForEmoji = [self createSegmentSpecifierNamed:@"selectingSkinToneForEmoji" key:@"selectingSkinToneForEmoji" default:@"999"];
		[selectingSkinToneForEmoji setValues:@[ @"999", @"1" ] titles:@[ @"Default", @"Disable" ]];
		[_specifiers addObject:selectingSkinToneForEmoji];

		if ( [UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPad ) {
			PSSpecifier *emptyGroup = [PSSpecifier emptyGroupSpecifier];
			[_specifiers addObject:emptyGroup];

			PSSpecifier *betaOptions = [self createLinkListSpecifierNamed:@"Beta Options" key:@"betaOptions" default:nil detail:@"KeyboardControllerBetaOptions"];
			[_specifiers addObject:betaOptions];
		}

		NSArray *testKeyboardTitles = @[ @"Default", @"ASCII Capable", @"Numbers and Punctuation", @"URL", @"Number Pad", @"Phone Pad", @"Name Phone Pad", @"Email Address", @"Decimal Pad", @"Twitter", @"Web Search", @"ASCII Capable Number Pad" ];
		NSArray *testKeyboardValues = @[ @"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"10", @"11" ];
		PSSpecifier *testKeyboardGroup = [self createGroupSpecifierNamed:@"Testing area" footer:@"Changes show here straight away. Other apps pick up an option switched on from Default the next time they open." key:@"testKeyboardGroup"];
		[_specifiers addObject:testKeyboardGroup];

		PSSpecifier *testKeyboardSelected = [self createLinkListSpecifierNamed:@"Test keyboard type:" key:@"testKeyboardSelected" default:@"0" detail:@"PSListItemsController"];
		[testKeyboardSelected setValues:testKeyboardValues titles:testKeyboardTitles];
		// Only this page reads it, so it wakes no other process.
		[testKeyboardSelected removePropertyForKey:@"PostNotification"];
		[_specifiers addObject:testKeyboardSelected];


		PSTextFieldSpecifier *testKeyboard = [self createEditTextSpecifierNamed:@"" key:@"testKeyboard" default:nil];
		[testKeyboard setPlaceholder:@"Test keyboard here"];
		int testKeyboardSelectedValue = [[self readPreferenceValue:testKeyboardSelected] integerValue];
		[testKeyboard setKeyboardType:testKeyboardSelectedValue autoCaps:NO autoCorrection:NO];
		[_specifiers addObject:testKeyboard];

		for( PSSpecifier *specifier in _standardSpecifiers ) {
			[_specifiers addObject:specifier];
		}
	}
	return _specifiers;
}
- (instancetype)init {
	self = [super init];
	if (self) {
		_transientValues = [NSMutableDictionary new];
		ClearStoredTestFields();
		[self createStandardSpecifiers];
	}
	return self;
}
- (void)createStandardSpecifiers {
	_standardSpecifiers = [NSMutableArray new];

	PSSpecifier *emptyGroup = [PSSpecifier emptyGroupSpecifier];
	[_standardSpecifiers addObject:emptyGroup];

	PSSpecifier *resetSettings = [self createButtonSpecifierNamed:@"Reset Settings"];
	resetSettings->action = @selector(resetSettings);

//	1 = left, 2 = center, 3 = right
	[resetSettings setProperty:@2 forKey:@"alignment"];
	[resetSettings setProperty:@YES forKey:@"hasIcon"];
	[_standardSpecifiers addObject:resetSettings];

	PSSpecifier* relatedLinks = [PSSpecifier groupSpecifierWithName:@"Related Links"];
	[_standardSpecifiers addObject:relatedLinks];

	PSSpecifier *sourceCode = [self createButtonSpecifierNamed:@"Source Code"];
	sourceCode->action = @selector(sourceCode);
	[sourceCode setProperty:KeyboardControllerIcon(@"code") forKey:@"iconImage"];
	[sourceCode setProperty:@YES forKey:@"hasIcon"];
	[_standardSpecifiers addObject:sourceCode];

	PSSpecifier *knownIssues = [self createButtonSpecifierNamed:@"Known Issues"];
	knownIssues->action = @selector(knownIssues);
	[knownIssues setProperty:KeyboardControllerIcon(@"bug") forKey:@"iconImage"];
	[knownIssues setProperty:@YES forKey:@"hasIcon"];
	[_standardSpecifiers addObject:knownIssues];

	PSSpecifier *linkBigboss = [self createButtonSpecifierNamed:@"Tomasz Poliszuk @ BigBoss"];
	linkBigboss->action = @selector(TomaszPoliszukAtBigBoss);
	[linkBigboss setProperty:KeyboardControllerIcon(@"packages") forKey:@"iconImage"];
	[linkBigboss setProperty:@YES forKey:@"hasIcon"];
	[_standardSpecifiers addObject:linkBigboss];

	PSSpecifier *linkGithub = [self createButtonSpecifierNamed:@"Tomasz Poliszuk @ Github"];
	linkGithub->action = @selector(TomaszPoliszukAtGithub);
	[linkGithub setProperty:KeyboardControllerIcon(@"github") forKey:@"iconImage"];
	[linkGithub setProperty:@YES forKey:@"hasIcon"];
	[_standardSpecifiers addObject:linkGithub];

	PSSpecifier *linkCySxLGithub = [self createButtonSpecifierNamed:@"CySxL @ Github (iOS 16 maintainer)"];
	linkCySxLGithub->action = @selector(CySxLAtGithub);
	[linkCySxLGithub setProperty:KeyboardControllerIcon(@"github") forKey:@"iconImage"];
	[linkCySxLGithub setProperty:@YES forKey:@"hasIcon"];
	[_standardSpecifiers addObject:linkCySxLGithub];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier*)specifier {
	if ( [specifier propertyForKey:kTransientField] ) {
		NSString *key = [specifier propertyForKey:@"key"];
		if ( key ) {
			_transientValues[key] = value ?: @"";
		}
		return;
	}
	[super setPreferenceValue:value specifier:specifier];

	PSSpecifier *testKeyboardSelected = [self specifierForID:@"testKeyboardSelected"];
	if (specifier == testKeyboardSelected) {
		PSSpecifier *testKeyboard = [self specifierForID:@"testKeyboard"];
		[testKeyboard setKeyboardType:[[self readPreferenceValue:testKeyboardSelected] integerValue] autoCaps:NO autoCorrection:NO];
		[self reloadSpecifier:testKeyboard];
	}
}
- (void)resetSettings {
	NSUserDefaults *tweakSettings = [[NSUserDefaults alloc] initWithSuiteName:@kPackageName];
	UIAlertController *resetSettingsAlert = [UIAlertController alertControllerWithTitle:@"Reset Keyboard Controller Settings" message:@"Do you want to reset settings?" preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction *confirm = [UIAlertAction actionWithTitle:@"Confirm" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_Nonnull action) {
		for(NSString *key in [[tweakSettings dictionaryRepresentation] allKeys]) {
			[tweakSettings removeObjectForKey:key];
		}
		[tweakSettings synchronize];
		CFNotificationCenterPostNotification(
			CFNotificationCenterGetDarwinNotifyCenter(),
			(__bridge CFStringRef)kSettingsChanged,
			NULL,
			NULL,
			YES
		);
		[self reloadSpecifiers];
	}];
	UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
	[resetSettingsAlert addAction:cancel];
	[resetSettingsAlert addAction:confirm];
	[self presentViewController:resetSettingsAlert animated:YES completion:nil];
}
- (void)sourceCode {
	NSURL *sourceCode = [NSURL URLWithString:@"https://github.com/tomaszpoliszuk/KeyboardController"];
	[[UIApplication sharedApplication] openURL:sourceCode options:@{} completionHandler:nil];
}
- (void)knownIssues {
	NSURL *knownIssues = [NSURL URLWithString:@"https://github.com/tomaszpoliszuk/KeyboardController/issues"];
	[[UIApplication sharedApplication] openURL:knownIssues options:@{} completionHandler:nil];
}
- (void)TomaszPoliszukAtBigBoss {
	UIApplication *application = [UIApplication sharedApplication];
	NSString *tweakName = @"Keyboard Controller";
	tweakName = [tweakName stringByReplacingOccurrencesOfString:@" " withString:@"+"];
	NSURL *packageDescriptionURL = [NSURL URLWithString:[@"http://apt.thebigboss.org/developer-packages.php?name=" stringByAppendingString:tweakName]];
	[application openURL:packageDescriptionURL options:@{} completionHandler:nil];
}
- (void)TomaszPoliszukAtGithub {
	UIApplication *application = [UIApplication sharedApplication];
	NSURL *githubProfileURL = [NSURL URLWithString:@"https://github.com/tomaszpoliszuk/"];
	[application openURL:githubProfileURL options:@{} completionHandler:nil];
}
- (void)CySxLAtGithub {
	UIApplication *application = [UIApplication sharedApplication];
	NSURL *githubProfileURL = [NSURL URLWithString:@"https://github.com/CySxL/"];
	[application openURL:githubProfileURL options:@{} completionHandler:nil];
}
@end
