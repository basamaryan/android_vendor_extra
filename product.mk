#
# Copyright (C) 2022 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# ih8sn
PRODUCT_PACKAGES += \
    ih8sn

PRODUCT_COPY_FILES += \
    vendor/extra/ih8sn.conf:$(TARGET_COPY_OUT_SYSTEM)/etc/ih8sn.conf

# MiuiCamera
$(call inherit-product-if-exists, device/xiaomi/miuicamera-$(shell echo -n $(TARGET_PRODUCT) | sed -e 's/^[a-z]*_//g')/device.mk)

# OTA
PRODUCT_PACKAGES += UpdaterOverlay

# Pixel Clocks
$(call inherit-product-if-exists, vendor/pixel_clocks/product.mk)

# Translations
PRODUCT_PACKAGES += \
    MotorTranslationsOverlay
