#
# Copyright (C) 2022-2025 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# MiuiCamera
$(call inherit-product-if-exists, device/xiaomi/miuicamera-$(shell echo -n $(TARGET_PRODUCT) | sed -e 's/^[a-z]*_//g')/device.mk)

ifeq ($(WITH_GMS),true)
# Google Sans
$(call inherit-product-if-exists, vendor/google_sans/product.mk)

# Pixel Clocks
$(call inherit-product-if-exists, vendor/pixel_clocks/product.mk)
endif
