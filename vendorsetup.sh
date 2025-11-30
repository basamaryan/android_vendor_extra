#!/bin/bash

export WITH_GMS=true
export GMS_MAKEFILE=gms.mk
export TARGET_UNOFFICIAL_BUILD_ID=GMS

SF_USER="aryannn999"
SF_HOST="frs.sourceforge.net"
SF_PROJECT_ROOT="/home/frs/project/noprincesshere"

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
        *)         echo "$1" ;; 
    esac
}

telegram_notify() {
    local message="$1"
    if [[ -n "${TELEGRAM_TOKEN}" && -n "${TELEGRAM_CHAT}" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT}" \
            -d text="${message}" \
            -d parse_mode="Markdown" \
            -d disable_web_page_preview="true" > /dev/null
    else
        echo "[WARN] Telegram credentials not set."
    fi
}

generate_changelog() {
    local device="$1"
    local target_file="$2"
    local repo_dir="${ANDROID_BUILD_TOP:-$PWD}"
    local days=14

    : >| "${target_file}"

    for i in $(seq "$days"); do
        local after_date=$(date --date="$i days ago" +%F)
        local until_date=$(date --date="$((i - 1)) days ago" +%F)
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
            *)          devices+=("$1"); shift ;;
        esac
    done

    if [[ ${#devices[@]} -eq 0 ]]; then
        echo "Usage: release [flags] <device> ..."
        return 1
    fi

    if [[ "${use_vanilla}" == "true" ]]; then
        unset WITH_GMS
        unset GMS_MAKEFILE
        unset TARGET_UNOFFICIAL_BUILD_ID
        local variant_name="VANILLA"
    else
        export WITH_GMS=true
        export GMS_MAKEFILE=gms.mk
        export TARGET_UNOFFICIAL_BUILD_ID=GMS
        local variant_name="GMS"
    fi

    cd "${top}" || return 1

    if [[ "${skip_sync}" == "false" ]]; then
        repo sync --force-sync -d -j18 || return 1
    fi

    if [[ "${skip_picks}" == "false" && -x "./picks" ]]; then
        ./picks || return 1
    fi

    for device in "${devices[@]}"; do
        
        local project_name=$(basename "$PWD")
        
        telegram_notify "*(i)* \`${project_name}\` compilation for \`${device}\` *started* on ${HOSTNAME}."
        
        local build_start=$(date +%s)

        rm -rf "out/target/product/${device}"
        breakfast "${device}" || {
             telegram_notify "*(i)* \`${project_name}\` compilation for \`${device}\` *failed* on ${HOSTNAME}."
             return 1
        }
        
        m bacon -j14 
        local result=$?
        local build_end=$(date +%s)
        local diff=$((build_end - build_start))
        local build_time=$(convertsecs "${diff}")

        if [[ ${result} -ne 0 ]]; then
            telegram_notify "*(i)* \`${project_name}\` compilation for \`${device}\` *failed* on ${HOSTNAME}. Build variant: \`${variant_name}\`. Build time: \`${build_time}\`."
            return 1
        fi
        
        telegram_notify "*(i)* \`${project_name}\` compilation for \`${device}\` *completed successfully* on ${HOSTNAME}. Build variant: \`${variant_name}\`. Build time: \`${build_time}\`."

        local out="${OUT:?OUT not set}"
        local build_props="${out}/system/build.prop"
        
        local lineage_ver=$(sed -n 's/^ro\.lineage\.build\.version=//p' "${build_props}")
        if [[ -z "${lineage_ver}" ]]; then
            echo "[WARN] Could not detect Lineage version from build.prop, defaulting to Unknown"
            lineage_ver="Unknown"
        fi

        local filename=""
        if [[ -f "${build_props}" ]]; then
            local ver_line=$(sed -n 's/^ro\.lineage\.version=//p' "${build_props}")
            [[ -n "${ver_line}" ]] && filename="lineage-${ver_line}.zip"
        fi
        if [[ -z "${filename}" || ! -f "${out}/${filename}" ]]; then
            filename=$(cd "${out}" && ls -1t lineage-*.zip 2>/dev/null | head -n1)
        fi
        
        [[ -f "${out}/${filename}.sha256sum" ]] || (cd "${out}" && sha256sum "${filename}" > "${filename}.sha256sum")
        
        local raw_date=$(printf '%s\n' "${filename}" | grep -oE '[0-9]{8}' | head -n1)
        local tag_name
        if [[ "${raw_date}" =~ ^[0-9]{8}$ ]]; then
            tag_name="${raw_date:4:2}${raw_date:6:2}${raw_date:0:4}"
        else
            tag_name="$(date +%m%d%Y)"
        fi

        local id=$(awk '{print $1}' "${out}/${filename}.sha256sum")
        local romtype=$(sed -n 's/^ro\.lineage\.releasetype=//p' "${build_props}"); romtype="${romtype:-UNOFFICIAL}"
        local datetime=$(sed -n 's/^ro\.build\.date\.utc=//p' "${build_props}"); datetime="${datetime:-$(date -u +%s)}"
        local security_patch=$(sed -n 's/^ro\.build\.version\.security_patch=//p' "${build_props}")
        local date_pretty=$(date -d @${datetime} +%F)
        local size=$(stat -c%s "${out}/${filename}")

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

        local possible_images=("boot.img" "dtbo.img" "recovery.img" "vendor_boot.img" "vbmeta.img")
        for img in "${possible_images[@]}"; do
            if [[ -f "${out}/${img}" ]]; then
                echo "Found ${img}, uploading..."
                rsync -Ph "${out}/${img}" "${SF_USER}@${SF_HOST}:${remote_dir}/"
            fi
        done

        local changelog_link="https://raw.githubusercontent.com/basamaryan/ota/master/${device}.txt"
        local full_device_name=$(get_device_name "$device")
        
        local release_msg="LineageOS ${lineage_ver} for ${full_device_name} (${device})

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

        telegram_notify "${release_msg}"
        
        rm -rf "out/target/product/${device}"
    done
}
