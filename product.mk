#
# Copyright (C) 2022-2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Face Unlock
TARGET_FACE_UNLOCK_SUPPORTED ?= $(TARGET_SUPPORTS_64_BIT_APPS)

ifeq ($(TARGET_FACE_UNLOCK_SUPPORTED),true)
PRODUCT_PACKAGES += \
    ParanoidSense

PRODUCT_SYSTEM_EXT_PROPERTIES += \
    ro.face.sense_service=true

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.biometrics.face.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/android.hardware.biometrics.face.xml
endif

# MiuiCamera
$(call inherit-product-if-exists, vendor/miuicamera-$(shell echo -n $(TARGET_PRODUCT) | sed -e 's/^[a-z]*_//g')/device.mk)

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
$(call inherit-product-if-exists, vendor/pixel-goodies/product.mk)
endif
