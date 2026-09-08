include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = KeyboardControllerSettings

$(BUNDLE_NAME)_FILES = $(wildcard *.mm)
$(BUNDLE_NAME)_INSTALL_PATH = /Library/PreferenceBundles
$(BUNDLE_NAME)_FRAMEWORKS = UIKit
$(BUNDLE_NAME)_PRIVATE_FRAMEWORKS = Preferences
$(BUNDLE_NAME)_CFLAGS = -fobjc-arc

# Version shown in the settings footer, taken from control so there is one place
# a version number is written. An empty result means control lost its Version
# line, which must stop the build rather than ship a blank footer.
KC_VERSION := $(shell sed -n 's/^Version: //p' $(THEOS_PROJECT_DIR)/control)
ifeq ($(KC_VERSION),)
$(error no Version line in $(THEOS_PROJECT_DIR)/control)
endif
$(BUNDLE_NAME)_CFLAGS += -DPACKAGE_VERSION='"$(KC_VERSION)"'

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/$(BUNDLE_NAME).plist$(ECHO_END)
