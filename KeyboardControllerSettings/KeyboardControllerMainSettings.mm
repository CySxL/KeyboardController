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

static const CGFloat kCreditAvatarSide = 38.0;

// The row indents its text by the width of its image, so a symbol takes the
// same square as the avatar.
static UIImage *CreditSymbol(NSString *name) {
	UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightMedium];
	UIImage *symbol = [UIImage systemImageNamed:name withConfiguration:configuration] ?: [UIImage systemImageNamed:@"link" withConfiguration:configuration];
	if ( !symbol ) {
		return nil;
	}
	CGFloat side = kCreditAvatarSide;
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
	UIImage *padded = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
		[symbol drawInRect:CGRectMake((side - symbol.size.width) / 2.0, (side - symbol.size.height) / 2.0, symbol.size.width, symbol.size.height)];
	}];
	return [padded imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// A row carrying kcBranch hangs off the row above it: a line from that row's
// avatar bends into it, and the row above, carrying kcBranchBelow, drops its
// separator and draws the top of the line.
@implementation KeyboardControllerCreditCell {
	UIImageView *_avatarView;
	CAShapeLayer *_branch;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
	self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier specifier:specifier];
	if ( !self ) {
		return nil;
	}
	self.detailTextLabel.text = [specifier propertyForKey:@"subtitle"] ?: @"";
	self.detailTextLabel.textColor = [UIColor systemGrayColor];
	self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	BOOL branch = [[specifier propertyForKey:@"kcBranch"] isEqual:@YES];
	if ( branch || [[specifier propertyForKey:@"kcBranchBelow"] isEqual:@YES] ) {
		_branch = [CAShapeLayer layer];
		_branch.fillColor = nil;
		_branch.lineWidth = 1.5;
		_branch.lineCap = kCALineCapRound;
		[self.contentView.layer addSublayer:_branch];
	}
	if ( branch ) {
		// An empty slot as wide as the avatar, so the text lines up with the name above.
		UIGraphicsBeginImageContextWithOptions(CGSizeMake(kCreditAvatarSide, 16.0), NO, [UIScreen mainScreen].scale);
		[specifier setProperty:UIGraphicsGetImageFromCurrentImageContext() forKey:@"iconImage"];
		UIGraphicsEndImageContext();
		UIImageSymbolConfiguration *small = [UIImageSymbolConfiguration configurationWithPointSize:11.0 weight:UIImageSymbolWeightSemibold];
		NSString *symbol = [specifier propertyForKey:@"kcBranchSymbol"];
		if ( ![symbol isKindOfClass:[NSString class]] ) {
			symbol = @"chevron.left.forwardslash.chevron.right";
		}
		NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
		attachment.image = [[UIImage systemImageNamed:symbol withConfiguration:small] imageWithTintColor:[UIColor linkColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
		NSMutableAttributedString *title = [[NSMutableAttributedString alloc] init];
		if ( attachment.image ) {
			[title appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
		}
		[title appendAttributedString:[[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:specifier.name ?: @""]
			attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:13.0], NSForegroundColorAttributeName: [UIColor linkColor] }]];
		self.textLabel.attributedText = title;
		// nil rather than empty, so the subtitle style centres the one line.
		self.detailTextLabel.text = nil;
		return self;
	}
	UIImage *avatar = [specifier propertyForKey:@"kcAvatar"];
	if ( ![avatar isKindOfClass:[UIImage class]] ) {
		self.imageView.tintColor = [UIColor secondaryLabelColor];
		return self;
	}
	// An empty image of the right size, so the row lays out before the avatar is drawn into it.
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(kCreditAvatarSide, kCreditAvatarSide), NO, [UIScreen mainScreen].scale);
	[specifier setProperty:UIGraphicsGetImageFromCurrentImageContext() forKey:@"iconImage"];
	UIGraphicsEndImageContext();
	_avatarView = [[UIImageView alloc] initWithFrame:self.imageView.bounds];
	_avatarView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_avatarView.contentMode = UIViewContentModeScaleAspectFill;
	_avatarView.clipsToBounds = YES;
	_avatarView.layer.cornerRadius = kCreditAvatarSide * 0.5;
	_avatarView.layer.minificationFilter = kCAFilterTrilinear;
	_avatarView.image = avatar;
	[self.imageView addSubview:_avatarView];
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if ( !_branch ) {
		return;
	}
	BOOL branch = [[self.specifier propertyForKey:@"kcBranch"] isEqual:@YES];
	if ( !branch ) {
		for ( UIView *view in self.subviews ) {
			if ( [NSStringFromClass([view class]) hasSuffix:@"SeparatorView"] ) {
				view.hidden = YES;
			}
		}
	}
	_branch.strokeColor = [[UIColor systemGray3Color] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
	CGRect slot = [self.contentView convertRect:self.imageView.bounds fromView:self.imageView];
	CGFloat x = round(CGRectGetMidX(slot));
	UIBezierPath *path = [UIBezierPath bezierPath];
	if ( branch ) {
		CGFloat y = round(CGRectGetMidY(slot));
		CGFloat r = 6.0;
		[path moveToPoint:CGPointMake(x, 0)];
		[path addLineToPoint:CGPointMake(x, y - r)];
		[path addQuadCurveToPoint:CGPointMake(x + r, y) controlPoint:CGPointMake(x, y)];
		[path addLineToPoint:CGPointMake(CGRectGetMaxX(slot), y)];
	} else {
		[path moveToPoint:CGPointMake(x, CGRectGetMaxY(slot) + 3.0)];
		[path addLineToPoint:CGPointMake(x, CGRectGetMaxY(self.contentView.bounds))];
	}
	_branch.path = path.CGPath;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
	[super traitCollectionDidChange:previous];
	[self setNeedsLayout];
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

	PSSpecifier *credits = [PSSpecifier preferenceSpecifierNamed:@"Credits" target:self set:NULL get:NULL detail:nil cell:PSGroupCell edit:nil];
	[credits setProperty:@"© CySxL 2026" forKey:@"footerText"];
	[_standardSpecifiers addObject:credits];

	// Name, subtitle, action, picture, then an optional symbol. A row with no
	// picture is a branch of the row above it.
	NSArray *rows = @[
		@[ @"Tomasz Poliszuk", @"Original Developer", NSStringFromSelector(@selector(tomaszPoliszuk)), @"" ],
		@[ @"Source Code", @"", NSStringFromSelector(@selector(sourceCode)), @"", @"chevron.left.forwardslash.chevron.right" ],
		@[ @"CySxL", @"Maintainer · iOS 16 Port", NSStringFromSelector(@selector(cySxL)), @"avatar" ],
		@[ @"Tip on Ko-fi", @"", NSStringFromSelector(@selector(kofi)), @"", @"cup.and.saucer" ]
	];
	PSSpecifier *previous = nil;
	for ( NSArray *row in rows ) {
		PSSpecifier *credit = [PSSpecifier preferenceSpecifierNamed:row[0] target:self set:NULL get:NULL detail:nil cell:PSLinkCell edit:nil];
		[credit setProperty:[KeyboardControllerCreditCell class] forKey:@"cellClass"];
		[credit setProperty:row[1] forKey:@"subtitle"];
		if ( row.count > 4 ) {
			[credit setProperty:@YES forKey:@"kcBranch"];
			[credit setProperty:row[4] forKey:@"kcBranchSymbol"];
			[credit setProperty:@34 forKey:@"height"];
			[previous setProperty:@YES forKey:@"kcBranchBelow"];
		} else {
			UIImage *avatar = [row[3] length] ? [UIImage imageNamed:row[3] inBundle:[NSBundle bundleForClass:[self class]] withConfiguration:nil] : nil;
			if ( avatar ) {
				[credit setProperty:avatar forKey:@"kcAvatar"];
			} else {
				[credit setProperty:CreditSymbol(@"chevron.left.forwardslash.chevron.right") forKey:@"iconImage"];
			}
		}
		credit->action = NSSelectorFromString(row[2]);
		[_standardSpecifiers addObject:credit];
		previous = credit;
	}
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
- (void)openURLString:(NSString *)string {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:string] options:@{} completionHandler:nil];
}
- (void)tomaszPoliszuk {
	[self openURLString:@"https://github.com/tomaszpoliszuk"];
}
- (void)sourceCode {
	[self openURLString:@"https://github.com/tomaszpoliszuk/KeyboardController"];
}
- (void)cySxL {
	[self openURLString:@"https://github.com/CySxL"];
}
- (void)kofi {
	[self openURLString:@"https://ko-fi.com/cysxl"];
}
@end
