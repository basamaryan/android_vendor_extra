#
# Copyright (C) 2022-2025 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# MiuiCamera
$(call inherit-product-if-exists, device/xiaomi/miuicamera-$(shell echo -n $(TARGET_PRODUCT) | sed -e 's/^[a-z]*_//g')/device.mk)

# OplusCamera
ifeq ($(TARGET_PRODUCT),lineage_martini)
  $(call inherit-product-if-exists, vendor/oplus/camera/opluscamera.mk)
endif

ifeq ($(WITH_GMS),true)
# OTA
PRODUCT_PACKAGES += \
    UpdaterOverlay

# Overlay
PRODUCT_PACKAGES += \
    SettingsOverlayCustom

# Pixel Goodies
$(call inherit-product-if-exists, vendor/google/pixel-goodies/product.mk)
endif
