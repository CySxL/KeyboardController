INSTALL_TARGET_PROCESSES = SpringBoard

# Rootful is not built here. The thread-local in the keyboard type hook is
# rejected for armv7 and armv7s, and rootful users are served by upstream.
ifneq ($(filter rootless roothide,$(THEOS_PACKAGE_SCHEME)),)
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:14.5:15.0
else
$(error set THEOS_PACKAGE_SCHEME to rootless or roothide)
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KeyboardController

$(TWEAK_NAME)_FILES = $(TWEAK_NAME).xm PreferencesFilePath.m
$(TWEAK_NAME)_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += KeyboardControllerSettings
include $(THEOS_MAKE_PATH)/aggregate.mk
