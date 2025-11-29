#
# Copyright (C) 2022-2025 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# MiuiCamera
$(call inherit-product-if-exists, device/xiaomi/miuicamera-$(shell echo -n $(TARGET_PRODUCT) | sed -e 's/^[a-z]*_//g')/device.mk)

ifeq ($(WITH_GMS),true)
# OTA
PRODUCT_PACKAGES += \
    UpdaterOverlay

# Overlay
PRODUCT_PACKAGES += \
    SettingsOverlayCustom

# Pixel Goodies
$(call inherit-product-if-exists, device/google/pixel-goodies/product.mk)
endif
