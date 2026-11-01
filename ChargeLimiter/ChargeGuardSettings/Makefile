# ChargeGuardSettings — Theos PreferenceBundle (deb only, NOT an Xcode target).
# Build:  make THEOS=/opt/theos
# Output: .theos/obj/debug-iphoneos/ChargeGuardSettings.bundle
# The deb build script (scripts/build_packages.sh, stage_settings_bundle)
# copies the built bundle into Library/PreferenceBundles. If this build
# fails, the deb build fails fast instead of shipping a deb with no UI.
ARCHS = arm64 arm64e
# 用 patched Theos SDK 16.5，因为 Xcode SDK 没有 PrivateFrameworks，链接 Preferences 会失败
# （build #10 的原因）。工作流会在构建前把 iPhoneOS16.5.sdk 装到 $THEOS/sdks，
# TARGET 16.5 会选中它。
TARGET = iphone:clang:16.5:13.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ChargeGuardSettings
ChargeGuardSettings_FILES = CLChargeGuardPrefsController.m
ChargeGuardSettings_INSTALL_PATH = /Library/PreferenceBundles
ChargeGuardSettings_FRAMEWORKS = UIKit Foundation
ChargeGuardSettings_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk
