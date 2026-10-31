# ChargeGuardSettings — Theos PreferenceBundle (deb only, NOT an Xcode target).
# Build:  make THEOS=/opt/theos
# Output: .theos/obj/debug-iphoneos/ChargeGuardSettings.bundle
# The deb build script (scripts/build_packages.sh, stage_settings_bundle)
# copies the built bundle into Library/PreferenceBundles. If this build
# fails, the deb build fails fast instead of shipping a deb with no UI.
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:13.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ChargeGuardSettings
ChargeGuardSettings_FILES = CLChargeGuardPrefsController.m
ChargeGuardSettings_INSTALL_PATH = /Library/PreferenceBundles
ChargeGuardSettings_FRAMEWORKS = UIKit Foundation
ChargeGuardSettings_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk
