TARGET := iphone:clang:latest:13.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GameBoost
GameBoost_FILES = Tweak.x
GameBoost_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
GameBoost_FRAMEWORKS = UIKit QuartzCore Metal

include $(THEOS_MAKE_PATH)/tweak.mk
