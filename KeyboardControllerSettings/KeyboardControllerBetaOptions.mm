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

@implementation KeyboardControllerBetaOptions {
	NSMutableDictionary *_transientValues;
}
- (instancetype)init {
	self = [super init];
	if ( self ) {
		_transientValues = [NSMutableDictionary new];
	}
	return self;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
	if ( [specifier propertyForKey:kTransientField] ) {
		return _transientValues[[specifier propertyForKey:@"key"]];
	}
	return [super readPreferenceValue:specifier];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	if ( [specifier propertyForKey:kTransientField] ) {
		NSString *key = [specifier propertyForKey:@"key"];
		if ( key ) {
			_transientValues[key] = value ?: @"";
		}
		return;
	}
	[super setPreferenceValue:value specifier:specifier];
}
- (PSSpecifier *)createGroupSpecifierNamed:(NSString *)name key:(NSString *)key {
	PSSpecifier *specifier = [PSSpecifier groupSpecifierWithName:name];
	[specifier setProperty:name forKey:@"label"];
	[specifier setProperty:key forKey:@"key"];
	[specifier setProperty:key forKey:@"id"];
	return specifier;
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
- (PSTextFieldSpecifier *)createEditTextSpecifierNamed:(NSString *)name key:(NSString *)key placeholder:(NSString *)placeholder {
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
	[specifier setPlaceholder:placeholder];
	[specifier setProperty:@YES forKey:kTransientField];
	return specifier;
}
- (NSArray *)specifiers {
	if ( !_specifiers ) {
		_specifiers = [NSMutableArray new];


		PSSpecifier *oneHandedKeyboardGroup = [self createGroupSpecifierNamed:@"One-Handed Keyboard" key:@"oneHandedKeyboardGroup"];
		[_specifiers addObject:oneHandedKeyboardGroup];

		PSSpecifier *oneHandedKeyboard = [self createSegmentSpecifierNamed:@"oneHandedKeyboard" key:@"oneHandedKeyboard" default:@"999"];
		[oneHandedKeyboard setValues:@[ @"999", @"2", @"1" ] titles:@[ @"Default", @"Force Left", @"Force Right" ]];
		[_specifiers addObject:oneHandedKeyboard];

		PSSpecifier *oneHandedGestureLeftGroup = [self createGroupSpecifierNamed:@"Left One-Handed Keyboard" footer:@"Swipe downward on the 123 key to switch to the left one-handed keyboard. Swipe down again to return to center." key:@"oneHandedGestureLeftGroup"];
		[_specifiers addObject:oneHandedGestureLeftGroup];

		PSSpecifier *oneHandedGestureLeft = [self createSwitchSpecifierNamed:@"Swipe down on 123 key" key:@"oneHandedGestureLeft" default:@"0"];
		[_specifiers addObject:oneHandedGestureLeft];

		PSSpecifier *oneHandedGestureRightGroup = [self createGroupSpecifierNamed:@"Right One-Handed Keyboard" footer:@"Swipe downward on the delete key or the enter/return key to switch to the right one-handed keyboard. Swipe down again on the same key to return to center. Each key has its own switch, so the one you leave off keeps working normally." key:@"oneHandedGestureRightGroup"];
		[_specifiers addObject:oneHandedGestureRightGroup];

		PSSpecifier *oneHandedGestureRight = [self createSwitchSpecifierNamed:@"Swipe down on delete key" key:@"oneHandedGestureRight" default:@"0"];
		[_specifiers addObject:oneHandedGestureRight];

		PSSpecifier *oneHandedGestureReturn = [self createSwitchSpecifierNamed:@"Swipe down on enter/return key" key:@"oneHandedGestureReturn" default:@"0"];
		[_specifiers addObject:oneHandedGestureReturn];

		PSSpecifier *useBlueThemingForKeyGroup = [self createGroupSpecifierNamed:@"Blue Theming of Keyboard" key:@"useBlueThemingForKeyGroup"];
		[_specifiers addObject:useBlueThemingForKeyGroup];

		PSSpecifier *useBlueThemingForKey = [self createSegmentSpecifierNamed:@"useBlueThemingForKey" key:@"useBlueThemingForKey" default:@"999"];
		[useBlueThemingForKey setValues:@[ @"999", @"0", @"1" ] titles:@[ @"Default", @"Disable", @"Enable" ]];
		[_specifiers addObject:useBlueThemingForKey];

		PSSpecifier *testKeyboardGroup = [self createGroupSpecifierNamed:@"Testing area" footer:@"Changes show here straight away. Other apps pick up an option switched on from Default the next time they open." key:@"testKeyboardGroup"];
		[_specifiers addObject:testKeyboardGroup];

		PSTextFieldSpecifier *testKeyboard = [self createEditTextSpecifierNamed:@"" key:@"testKeyboard" placeholder:@"Test keyboard here"];
		[_specifiers addObject:testKeyboard];
	}
	return _specifiers;
}
@end
