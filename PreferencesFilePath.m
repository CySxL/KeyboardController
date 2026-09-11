#import <Foundation/Foundation.h>
#import <roothide.h>

NSString *PreferencesFilePath(void) {
	return [NSString stringWithUTF8String:jbroot("/var/mobile/Library/Preferences/com.tomaszpoliszuk.keyboardcontroller.plist")];
}
