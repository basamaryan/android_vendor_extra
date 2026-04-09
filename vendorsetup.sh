#!/bin/bash

export WITH_GMS=true
export GMS_MAKEFILE=gms.mk
export TARGET_UNOFFICIAL_BUILD_ID=GMS

SF_USER="aryannn999"
SF_HOST="frs.sourceforge.net"
SF_PROJECT_ROOT="/home/frs/project/noprincesshere"
JOBS=14

convertsecs() {
    ((h=${1}/3600))
    ((m=(${1}%3600)/60))
    ((s=${1}%60))
    printf "%02d:%02d:%02d\n" $h $m $s
}

get_device_name() {
    case "$1" in
        "martini") echo "OnePlus 9RT" ;;
        "sweet")   echo "Xiaomi Redmi Note 10 Pro / Redmi Note 10 Pro Max" ;;
        "kiev")    echo "Motorola moto g 5G / moto one 5G ace" ;;
        "davinci") echo "Xiaomi Redmi K20 / Mi 9T" ;;
        "Q25")     echo "Zinwa Q25" ;;
        "odin2thor") echo "AYN Thor" ;;
        *)         echo "$1" ;; 
    esac
}

notify_chat() {
    local message="$1"
    if [[ -n "${TELEGRAM_TOKEN}" && -n "${TELEGRAM_CHAT}" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT}" \
            -d text="${message}" \
            -d parse_mode="Markdown" \
            -d disable_web_page_preview="true" > /dev/null
    else
        echo "[WARN] Chat credentials not set."
    fi
}

notify_channel() {
    local message="$1"
    if [[ -n "${TELEGRAM_TOKEN}" && -n "${TELEGRAM_CHANNEL}" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHANNEL}" \
            -d text="${message}" \
            -d parse_mode="Markdown" \
            -d disable_web_page_preview="true" > /dev/null
    else
        echo "[WARN] Channel credentials not set."
    fi
}

upload_error_log() {
    local device="$1"
    local message="$2"
    local log_file="out/error.log"

    if [[ -n "${TELEGRAM_TOKEN}" && -n "${TELEGRAM_CHAT}" ]]; then
        if [[ -f "${log_file}" ]]; then
            curl -s -F chat_id="${TELEGRAM_CHAT}" \
                 -F document=@"${log_file}" \
                 -F caption="${message}" \
                 -F parse_mode="Markdown" \
                 "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" > /dev/null
        else
            notify_chat "${message}"
        fi
    fi
}

generate_changelog() {
    local device="$1"
    local target_file="$2"
    local repo_dir="${ANDROID_BUILD_TOP:-$PWD}"
    local days=14

    : >| "${target_file}"

    for i in $(seq "$days"); do
        local after_date=$(date -u --date="$i days ago" +%F)
        local until_date=$(date -u --date="$((i - 1)) days ago" +%F)
        local day_header_written=false

        if [[ -f "${repo_dir}/.repo/project.list" ]]; then
            while read -r project_path; do
                local full_path="${repo_dir}/${project_path}"
                
                if [[ -d "${full_path}/.git" ]]; then
                    local git_log=$(git --git-dir "${full_path}/.git" log \
                        --after="${after_date} 00:00:00" \
                        --until="${until_date} 23:59:59" \
                        --format=tformat:"%h %s [%an]")

                    if [[ -n "${git_log}" ]]; then
                        if [[ "$day_header_written" == "false" ]]; then
                            echo "====================" >> "${target_file}"
                            echo "     $until_date    " >> "${target_file}"
                            echo "====================" >> "${target_file}"
                            day_header_written=true
                        fi

                        echo "* ${project_path}" >> "${target_file}"
                        echo "${git_log}" >> "${target_file}"
                        echo "" >> "${target_file}"
                    fi
                fi
            done < "${repo_dir}/.repo/project.list"
        fi
    done
}

sync_repo() {
    local local_path="$1"
    local remote="$2"
    local branch="${3:-lineage-23.2}"
    local top="${ANDROID_BUILD_TOP:-$PWD}"

    echo "==> Syncing ${local_path} (${branch})"
    cd "${top}" || return 1

    if [[ -d "${local_path}/.git" ]]; then
        cd "${local_path}"
        git fetch "${remote}" "${branch}"
        git checkout -B "${branch}" FETCH_HEAD
    else
        mkdir -p "$(dirname "${local_path}")"
        git clone -b "${branch}" "${remote}" "${local_path}"
    fi

    cd "${top}"
}

sync() {
    local top="${ANDROID_BUILD_TOP:-$PWD}"
    local lineage="https://github.com/LineageOS"
    local pixelos="https://github.com/PixelOS-AOSP"

    cd "${top}" || return 1

    repo sync --force-sync -d -j"${JOBS}" || return 1

    sync_repo hardware/xiaomi                "${lineage}/android_hardware_xiaomi"
    sync_repo hardware/motorola              "${lineage}/android_hardware_motorola"
    sync_repo hardware/oplus                 "${lineage}/android_hardware_oplus"
    sync_repo hardware/sony/timekeep         "${lineage}/android_hardware_sony_timekeep"
    sync_repo hardware/pixelworks/interfaces "${lineage}/android_hardware_pixelworks_interfaces"
    #sync_repo hardware/ayn                   "${lineage}/android_hardware_ayn"
    sync_repo hardware/mediatek              "${lineage}/android_hardware_mediatek"
    sync_repo device/mediatek/sepolicy_vndr  "${lineage}/android_device_mediatek_sepolicy_vndr"
    sync_repo packages/apps/ParanoidSense    "${pixelos}/android_packages_apps_ParanoidSense"    "sixteen-qpr2"
    sync_repo packages/apps/DolbyAtmos       "${pixelos}/android_packages_apps_DolbyAtmos"       "sixteen-qpr2"

    apply_patches

    echo "==> Sync complete."
}

apply_patches() {
    local top="${ANDROID_BUILD_TOP:-$PWD}"
    local patches_path="${top}/vendor/extra/patches"

    cd "${top}" || return 1

    #./vendor/lineage/build/tools/repopick.py -p -t B_asb_2026-04

    if [[ -d "${patches_path}" ]]; then
        for project_name in $(cd "${patches_path}"; echo */); do
            [[ "${project_name}" == "*/" ]] && continue
            local project_path="$(tr _ / <<<"${project_name}")"
            project_path="${project_path%/}"

            cd "${top}/${project_path}" || continue

            echo "Applying patches for project: ${project_name}"
            if ! git am "${patches_path}/${project_name}"*.patch --no-gpg-sign; then
                echo "Failed to apply patches for project: ${project_name}. Aborting."
                git am --abort &>/dev/null
            fi

            cd "${top}"
        done
    else
        echo "[INFO] No patches directory found, skipping local patches."
    fi

    [[ -x "./picks" ]] && ./picks
}

function release() {
    local devices=()
    local skip_sync=false
    local skip_picks=false
    local skip_ota=false
    local use_vanilla=false
    local top="${ANDROID_BUILD_TOP:-$PWD}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-sync)  skip_sync=true; shift ;;
            --no-picks) skip_picks=true; shift ;;
            --no-ota)   skip_ota=true; shift ;;
            --vanilla)  use_vanilla=true; shift ;;
            -j*)        JOBS="${1#-j}"; shift ;;
            *)          devices+=("$1"); shift ;;
        esac
    done

    if [[ ${#devices[@]} -eq 0 ]]; then
        echo "Usage: release [flags] <device> ... [-j18]"
        return 1
    fi

    if [[ "${use_vanilla}" == "true" ]]; then
        unset WITH_GMS
        unset GMS_MAKEFILE
        unset TARGET_UNOFFICIAL_BUILD_ID
        local variant_name="VANILLA"
        skip_ota=true
    else
        export WITH_GMS=true
        export GMS_MAKEFILE=gms.mk
        export TARGET_UNOFFICIAL_BUILD_ID=GMS
        local variant_name="GMS"
    fi

    cd "${top}" || return 1

    if [[ "${skip_sync}" == "false" ]]; then
        repo sync --force-sync -d -j"${JOBS}" || return 1
    fi

    if [[ "${skip_picks}" == "false" ]]; then
        apply_patches
    fi

    for device in "${devices[@]}"; do

        case "${device}" in
            martini)
                export UNSAFE_DISABLE_HIDDENAPI_FLAGS=true
                ;;
            *)
                unset UNSAFE_DISABLE_HIDDENAPI_FLAGS
                ;;
        esac

        if [[ "${use_vanilla}" == "false" ]]; then
            export WITH_GMS=true
            export GMS_MAKEFILE=gms.mk
            export TARGET_UNOFFICIAL_BUILD_ID=GMS
        fi

        local project_name=$(basename "$PWD")
        
        notify_chat "*(i)* \`${project_name}\` compilation for \`${device}\` *started* on ${HOSTNAME}."
        
        local build_start=$(date +%s)

        rm -rf "out/target/product/${device}"
        breakfast "${device}"

        if [[ $? -ne 0 ]]; then
             local fail_msg="*(i)* \`${project_name}\` compilation for \`${device}\` *failed* during breakfast on ${HOSTNAME}."
             upload_error_log "${device}" "${fail_msg}"
             echo "[WARN] Breakfast failed. Cleaning up and skipping ${device}."
             rm -rf "out/target/product/${device}"
             continue
        fi
        
        m bacon -j"${JOBS}"
        local result=$?
        local build_end=$(date +%s)
        local diff=$((build_end - build_start))
        local build_time=$(convertsecs "${diff}")

        if [[ ${result} -ne 0 ]]; then
            local fail_msg="*(i)* \`${project_name}\` compilation for \`${device}\` *failed* on ${HOSTNAME}. Build variant: \`${variant_name}\`. Build time: \`${build_time}\`."
            upload_error_log "${device}" "${fail_msg}"
            echo "[WARN] Build failed. Cleaning up and skipping ${device}."
            rm -rf "out/target/product/${device}"
            continue
        fi
        
        notify_chat "*(i)* \`${project_name}\` compilation for \`${device}\` *completed successfully* on ${HOSTNAME}. Build variant: \`${variant_name}\`. Build time: \`${build_time}\`."

        local out="${OUT:?OUT not set}"

        local lineage_ver=$(cat "${out}/system/build.prop" "${out}/product/etc/build.prop" | grep "ro.lineage.build.version=" | head -n 1)
        lineage_ver="${lineage_ver#*=}"
        
        if [[ -z "${lineage_ver}" ]]; then
            echo "[WARN] Could not detect Lineage version, defaulting to Unknown"
            lineage_ver="Unknown"
        fi

        local filename=""
        local ver_line=$(cat "${out}/system/build.prop" "${out}/product/etc/build.prop" | grep "ro.lineage.version=" | head -n 1)
        ver_line="${ver_line#*=}"

        [[ -n "${ver_line}" ]] && filename="lineage-${ver_line}.zip"

        if [[ -z "${filename}" || ! -f "${out}/${filename}" ]]; then
            filename=$(cd "${out}" && ls -1t lineage-*.zip 2>/dev/null | head -n1)
        fi

        local romtype=$(cat "${out}/system/build.prop" "${out}/product/etc/build.prop" | grep "ro.lineage.releasetype=" | head -n 1)
        romtype="${romtype#*=}"
        romtype="${romtype:-UNOFFICIAL}"

        [[ -f "${out}/${filename}.sha256sum" ]] || (cd "${out}" && sha256sum "${filename}" > "${filename}.sha256sum")
        
        local id=$(awk '{print $1}' "${out}/${filename}.sha256sum")
        local datetime=$(sed -n 's/^ro\.build\.date\.utc=//p' "${out}/system/build.prop"); datetime="${datetime:-$(date -u +%s)}"
        local security_patch=$(sed -n 's/^ro\.build\.version\.security_patch=//p' "${out}/system/build.prop")
        local date_pretty=$(date -u -d @${datetime} +%F)
        local size=$(stat -c%s "${out}/${filename}")

        local tag_name=$(date -u -d @"${datetime}" +%m%d%Y)

        local sf_folder_url="https://sourceforge.net/projects/noprincesshere/files/lineage-${lineage_ver}/${device}/${tag_name}"
        local sf_direct_url="${sf_folder_url}/$(basename "${filename}")/download"

        if [[ "${skip_ota}" == "false" ]]; then
            local ota_entry=$(jq -n \
                --arg datetime "${datetime}" \
                --arg filename "${filename}" \
                --arg id "${id}" \
                --arg romtype "${romtype}" \
                --argjson size "${size}" \
                --arg version "${lineage_ver}" \
                --arg release_url "${sf_direct_url}" \
                '{response:[{datetime:$datetime,filename:$filename,id:$id,romtype:$romtype,size:$size,url:$release_url,version:$version}]}')

            (
                cd "${top}/ota" || exit 1
                git checkout master && git pull --rebase origin master || true
                echo "${ota_entry}" >| "${device}.json"
                generate_changelog "${device}" "${device}.txt"
                git add "${device}.json" "${device}.txt"
                if ! git diff --cached --quiet; then
                    git commit -m "${device}: OTA update ${tag_name}"
                    git push origin master
                fi
            )
        fi

        local remote_dir="${SF_PROJECT_ROOT}/lineage-${lineage_ver}/${device}/${tag_name}"

        {
            echo "-mkdir ${SF_PROJECT_ROOT}/lineage-${lineage_ver}"
            echo "-mkdir ${SF_PROJECT_ROOT}/lineage-${lineage_ver}/${device}"
            echo "-mkdir ${remote_dir}"
        } | sftp -b - "${SF_USER}@${SF_HOST}" >/dev/null 2>&1 || true

        echo "[INFO] Uploading main zip..."
        rsync -Ph "${out}/${filename}" "${out}/${filename}.sha256sum" "${SF_USER}@${SF_HOST}:${remote_dir}/"

        # Only upload additional images if NOT vanilla
        if [[ "${use_vanilla}" == "false" ]]; then
            local standard_images=("boot.img" "dtbo.img" "recovery.img")
            for img in "${standard_images[@]}"; do
                if [[ -f "${out}/${img}" ]]; then
                    echo "Found ${img}, uploading..."
                    rsync -Ph "${out}/${img}" "${SF_USER}@${SF_HOST}:${remote_dir}/"
                fi
            done

            local has_vendor_boot=false
            if [[ -f "${out}/vendor_boot.img" ]]; then
                 echo "Found vendor_boot.img, uploading..."
                 rsync -Ph "${out}/vendor_boot.img" "${SF_USER}@${SF_HOST}:${remote_dir}/"
                 has_vendor_boot=true
            fi

            if [[ -f "${out}/vbmeta.img" ]]; then
                if [[ "${has_vendor_boot}" == "true" ]]; then
                    echo "Found vbmeta.img and vendor_boot present, uploading..."
                    rsync -Ph "${out}/vbmeta.img" "${SF_USER}@${SF_HOST}:${remote_dir}/"
                else
                    echo "Skipping vbmeta.img because vendor_boot.img was not found."
                fi
            fi
        else
            echo "[INFO] Vanilla build: Skipping upload of boot/recovery images."
        fi

        local changelog_link="https://raw.githubusercontent.com/basamaryan/ota/master/${device}.txt"
        local full_device_name=$(get_device_name "$device")
        
        local release_msg="*LineageOS ${lineage_ver} for ${full_device_name} (${device})*

📅 Build date: \`${date_pretty}\`
🛡️ Security patch: \`${security_patch}\`
💬 Variant: \`${variant_name}\`

🗒️ [Changelog](${changelog_link})

*Download*
⬇️ [${project_name}](${sf_direct_url})
⛭ [Additional files](${sf_folder_url})

*SHA-256 checksum*
\`${id}\`

#${device}"

        notify_channel "${release_msg}"
        
        rm -rf "out/target/product/${device}"
    done
}
