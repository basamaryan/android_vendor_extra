#
# Copyright (C) 2022-2025 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

-include device/xiaomi/miuicamera-$(PRODUCT_DEVICE)/BoardConfig.mk

ifeq ($(WITH_GMS),true)
# Google Sans
-include vendor/google_sans/board.mk

# Pixel Clocks
-include vendor/pixel_clocks/board.mk

  ifneq (,$(filter lineage_sweet lineage_davinci,$(TARGET_PRODUCT)))
    BOARD_SYSTEMIMAGE_PARTITION_RESERVED_SIZE := 52428800
  endif
endif
