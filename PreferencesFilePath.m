#import <Foundation/Foundation.h>
#if __arm64__
#import <roothide.h>
#endif

NSString *PreferencesFilePath(void) {
#if __arm64__
	return [NSString stringWithUTF8String:jbroot("/var/mobile/Library/Preferences/com.tomaszpoliszuk.keyboardcontroller.plist")];
#else
	return @"/var/mobile/Library/Preferences/com.tomaszpoliszuk.keyboardcontroller.plist";
#endif
}
