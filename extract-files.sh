#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017 The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -e

DEVICE=axon7
VENDOR=zte

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

LINEAGE_ROOT="${MY_DIR}/../../.."

HELPER="${LINEAGE_ROOT}/vendor/lineage/build/tools/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

function blob_fixup() {
    case "${1}" in
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
        patchelf --add-needed "libbase_shim.so" "${2}"
        ;;
    vendor/lib64/lib-uceservice.so)
        patchelf --add-needed "libbase_shim.so" "${2}"
        ;;
    # Shim libui GraphicBuffer lock functions
    vendor/lib/libZEffectLib.so)
        patchelf --add-needed "libui_shim.so" "${2}"
        ;;
    vendor/lib/libFNVfbEngineHAL.so)
        patchelf --add-needed "libui_shim.so" "${2}"
        ;;
    # Patch service.bootanim.exit in camera HAL
    vendor/lib/hw/camera.msm8996.so)
        sed -i "s/service.bootanim.exit/service.bootanim.zzzz/g" "${2}"
        ;;
    # Patch fingerprint blobs for VNDK
    vendor/bin/gx_fpd)
        patchelf --remove-needed "libunwind.so" "${2}"
        patchelf --remove-needed "libbacktrace.so" "${2}"
        ;;
    # Patch crashing issue in RIL library
    vendor/lib64/libril-qc-qmi-1.so)
        sed -i 's|\xfc\x0f\x1e\xf8\xfd\x7b\x01\xa9|\x00\x00\x80\xd2\xc0\x03\x5f\xd6|' "${2}"
        ;;
    # Fix soname for Vulkan libraries
    vendor/lib/hw/vulkan.msm8996.so|vendor/lib64/hw/vulkan.msm8996.so)
        patchelf --set-soname "vulkan.msm8996.so" "${2}"
        ;;
    esac
}

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true
SECTION=
KANG=

while [ "$1" != "" ]; do
    case "$1" in
        -n | --no-cleanup )     CLEAN_VENDOR=false
                                ;;
        -k | --kang)            KANG="--kang"
                                ;;
        -s | --section )        shift
                                SECTION="$1"
                                CLEAN_VENDOR=false
                                ;;
        * )                     SRC="$1"
                                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC=adb
fi

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${LINEAGE_ROOT}" false "${CLEAN_VENDOR}"

extract "${MY_DIR}/proprietary-files.txt" "${SRC}" ${KANG} --section "${SECTION}"

"${MY_DIR}/setup-makefiles.sh"
