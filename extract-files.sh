#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017-2020 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

DEVICE=axon7
VENDOR=zte

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --no-cleanup )
                CLEAN_VENDOR=false
                ;;
        -k | --kang )
                KANG="--kang"
                ;;
        -s | --section )
                SECTION="${2}"; shift
                CLEAN_VENDOR=false
                ;;
        * )
                SRC="${1}"
                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC=adb
fi

function blob_fixup() {
    case "${1}" in
    # Move telephony packages to /system_ext
    system_ext/etc/init/dpmd.rc)
        sed -i "s/\/system\/product\/bin\//\/system\/system_ext\/bin\//g" "${2}"
        ;;
    # Move telephony packages to /system_ext
    system_ext/etc/permissions/com.qti.dpmframework.xml|system_ext/etc/permissions/dpmapi.xml)
        sed -i "s/\/system\/product\/framework\//\/system\/system_ext\/framework\//g" "${2}"
        ;;
    # Move telephony packages to /system_ext
    system_ext/etc/permissions/qcrilhook.xml|system_ext/etc/permissions/lpa.xml|system_ext/etc/permissions/telephonyservice.xml)
        sed -i "s/\/system\/framework\//\/system\/system_ext\/framework\//g" "${2}"
        ;;
    # Provide shim for libdpmframework.so
    system_ext/lib64/libdpmframework.so)
        for  LIBCUTILS_SHIM in $(grep -L "libcutils_shim.so" "${2}"); do
            "${PATCHELF}" --add-needed "libcutils_shim.so" "$LIBCUTILS_SHIM"
        done
        ;;
    # Load NXP container profiles from vendor
    vendor/lib/libtfa9890.so)
        sed -i "s|/etc/settings/stereo_qcom_spk.cnt|/vendor/etc/tfa/stereo_qc_spk.cnt|g" "${2}"
        sed -i "s|/etc/settings/mono_qcom_rcv.cnt|/vendor/etc/tfa/mono_qc_rcv.cnt|g" "${2}"
        sed -i "s|/etc/settings/mono_qcom_spk_l.cnt|/vendor/etc/tfa/mono_qc_spk_l.cnt|g" "${2}"
        sed -i "s|/etc/settings/mono_qcom_spk_r.cnt|/vendor/etc/tfa/mono_qc_spk_r.cnt|g" "${2}"
        sed -i "s|/etc/settings/stereo_qcom_spk_l.cnt|/vendor/etc/tfa/stereo_qc_spk_l.cnt|g" "${2}"
        sed -i "s|/etc/settings/stereo_qcom_spk_r.cnt|/vendor/etc/tfa/stereo_qc_spk_r.cnt|g" "${2}"
        ;;
    # Correct VZW IMS library location
    vendor/etc/permissions/qti-vzw-ims-internal.xml)
        sed -i "s|/system/vendor/framework/qti-vzw-ims-internal.jar|/vendor/framework/qti-vzw-ims-internal.jar|g" "${2}"
        ;;
    # Correct android.hidl.manager@1.0-java jar name
    vendor/etc/permissions/qti_libpermissions.xml)
        sed -i "s|name=\"android.hidl.manager-V1.0-java|name=\"android.hidl.manager@1.0-java|g" "${2}"
        ;;
    # Shim libbase LogMessage functions
    vendor/bin/imsrcsd)
        "${PATCHELF}" --add-needed "libbase_shim.so" "${2}"
        ;;
    vendor/lib64/lib-uceservice.so)
        "${PATCHELF}" --add-needed "libbase_shim.so" "${2}"
        ;;
    # Shim libui GraphicBuffer lock functions
    lib/lib-imsvideocodec.so|lib64/lib-imsvideocodec.so|vendor/lib/libFNVfbEngineHAL.so|vendor/lib/libZEffectLib.so)
        "${PATCHELF}" --add-needed "libui_shim.so" "${2}"
        ;;
    # Patch service.bootanim.exit in camera HAL
    vendor/lib/hw/camera.msm8996.so)
        sed -i "s/service.bootanim.exit/service.bootanim.zzzz/g" "${2}"
        ;;
    # Patch fingerprint blobs for VNDK
    vendor/bin/gx_fpd)
        "${PATCHELF}" --remove-needed "libunwind.so" "${2}"
        "${PATCHELF}" --remove-needed "libbacktrace.so" "${2}"
        ;;
    # Patch crashing issue in RIL library
    vendor/lib64/libril-qc-qmi-1.so)
        sed -i 's|\xfc\x0f\x1e\xf8\xfd\x7b\x01\xa9|\x00\x00\x80\xd2\xc0\x03\x5f\xd6|' "${2}"
        ;;
    # Hex edit libaudcal.so to store acdbdata in new paths
    vendor/lib/libaudcal.so|vendor/lib64/libaudcal.so)
        sed -i "s|/data/vendor/misc/audio/acdbdata/delta/|/data/vendor/audio/acdbdata/delta/\x00\x00\x00\x00\x00|g" "${2}"
        ;;
    # Fix soname for Vulkan libraries
    vendor/lib/hw/vulkan.msm8996.so|vendor/lib64/hw/vulkan.msm8996.so)
        "${PATCHELF}" --set-soname "vulkan.msm8996.so" "${2}"
        ;;
    # Fix protobuf missing symbol
    vendor/lib64/libwvhidl.so)
        "${PATCHELF}" --replace-needed "libprotobuf-cpp-lite.so" "libprotobuf-cpp-lite-v28.so" "${2}"
        ;;
    vendor/lib64/libsettings.so)
        "${PATCHELF}" --replace-needed "libprotobuf-cpp-full.so" "libprotobuf-cpp-full-v28.so" "${2}"
        ;;
    esac
}

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"

"${MY_DIR}/setup-makefiles.sh"
