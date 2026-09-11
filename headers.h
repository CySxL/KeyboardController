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


#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

#define kPackageName "com.tomaszpoliszuk.keyboardcontroller"
#define kSettingsChanged @"com.tomaszpoliszuk.keyboardcontroller.settingschanged"
// Marks a settings field that holds its value in memory and never writes it.
#define kTransientField @"KeyboardControllerTransientField"

@interface UIView (KeyboardController)
-(id)_viewControllerForAncestor;
@end

@interface UIDevice (KeyboardController)
- (bool)_supportsForceTouch;
@end

@interface PSSpecifier (KeyboardController)
+ (id)groupSpecifierWithHeader:(id)arg1 footer:(id)arg2;
+ (id)emptyGroupSpecifier;
- (void)setValues:(id)arg1 titles:(id)arg2;
- (void)setKeyboardType:(long long)arg1 autoCaps:(int)arg2 autoCorrection:(int)arg3;
@end

@interface PSTextFieldSpecifier : PSSpecifier
- (void)setPlaceholder:(id)arg1;
@end

@interface KeyboardControllerHeaderCell : PSTableCell
@end

@interface KeyboardControllerMainSettings : PSListController
@property (nonatomic, strong) NSMutableArray *standardSpecifiers;
@end

@interface KeyboardControllerKeyboardTypeSettings : PSListController
@end

@interface KeyboardControllerReturnKeyTypeSettings : PSListController
@end

@interface KeyboardControllerKeyboardOptions : PSListController
@end

@interface KeyboardControllerBetaOptions : PSListController
@end



