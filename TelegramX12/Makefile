TARGET = iphone:clang:12.4:12.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = TelegramX12

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TelegramX12

TelegramX12_FILES = $(wildcard Sources/*.m) Sources/compat.c
TelegramX12_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
TelegramX12_RESOURCE_FILES = Info.plist
TelegramX12_RESOURCE_DIRS = Resources

TelegramX12_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
	-I$(THEOS_PROJECT_DIR)/Vendor/TDLibFramework.framework/Headers
TelegramX12_LDFLAGS = -F$(THEOS_PROJECT_DIR)/Vendor \
	-framework TDLibFramework -lc++ -lz
TelegramX12_CODESIGN_FLAGS = -S

include $(THEOS_MAKE_PATH)/application.mk
