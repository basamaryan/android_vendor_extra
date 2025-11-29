# Always build GMS variant
export WITH_GMS=true
export GMS_MAKEFILE=gms.mk
export TARGET_UNOFFICIAL_BUILD_ID=GMS

apply_patches() {
    local top="${ANDROID_BUILD_TOP:-$PWD}"
    cd "$top" || return 1

    # Keep tree updated before picks
    repo sync --force-sync -d -j18 || return 1

    ./vendor/lineage/build/tools/repopick.py -p -t md3e-flags
    ./vendor/lineage/build/tools/repopick.py -p -t oplus-camera -f
    ./vendor/lineage/build/tools/repopick.py -p 458893
}

# Release function supports martini, sweet, davinci
release() {
    local device="${1:?usage: release <device>}"
    case "$device" in
        martini|sweet|davinci) ;;
        *) echo "[ERROR] Unsupported device: $device. Use martini, sweet, or davinci."; return 1 ;;
    esac

    local top="${ANDROID_BUILD_TOP:?ANDROID_BUILD_TOP not set}"

    echo "[INFO] Starting release for $device"

    # Clean only this device product dir
    rm -rf "out/target/product/${device}"

    # Picks and build
    apply_patches || return 1
    breakfast "$device" || return 1
    m bacon -j14 || return 1

    # OUT is set by the build system after breakfast/lunch
    local out="${OUT:?OUT not set}"
    local build_props="${out}/system/build.prop"

    # Locate ROM zip based on build.prop, fallback to latest lineage-*.zip
    local filename ver_line
    if [[ -f "$build_props" ]]; then
        ver_line="$(sed -n 's/^ro\.lineage\.version=//p' "$build_props")"
        if [[ -n "$ver_line" ]]; then
            filename="lineage-${ver_line}.zip"
        fi
    fi
    if [[ -z "$filename" || ! -f "${out}/${filename}" ]]; then
        filename="$(cd "$out" && ls -1t lineage-*.zip 2>/dev/null | head -n1)"
        [[ -n "$filename" ]] || { echo "[ERROR] Could not find lineage zip in $out"; return 1; }
    fi

    # Extract first 8 digits from the filename and convert YYYYMMDD -> MMDDYYYY (folder name only)
    local raw_date tag_name
    raw_date="$(printf '%s\n' "$filename" | grep -oE '[0-9]{8}' | head -n1)"
    if [[ "$raw_date" =~ ^[0-9]{8}$ ]]; then
        tag_name="${raw_date:4:2}${raw_date:6:2}${raw_date:0:4}"
    else
        tag_name="$(date +%m%d%Y)"
    fi

    # Ensure sha256sum exists
    [[ -f "${out}/${filename}.sha256sum" ]] || (cd "$out" && sha256sum "$filename" > "${filename}.sha256sum")

    # Pull fields without PCRE lookbehind
    local id romtype version datetime size
    id="$(awk '{print $1}' "${out}/${filename}.sha256sum")"
    romtype="$(sed -n 's/^ro\.lineage\.releasetype=//p' "$build_props")"; romtype="${romtype:-UNOFFICIAL}"
    version="$(sed -n 's/^ro\.lineage\.build\.version=//p' "$build_props")"; version="${version:-23.0}"
    datetime="$(sed -n 's/^ro\.build\.date\.utc=//p' "$build_props")"; datetime="${datetime:-$(date -u +%s)}"
    size="$(stat -c%s "${out}/${filename}")"

    # Build download URL for SourceForge with MMDDYYYY folder
    local release_url="https://sourceforge.net/projects/noprincesshere/files/lineage-23.0/${device}/${tag_name}/$(basename "${filename}")/download"

    # Check jq
    if ! command -v jq >/dev/null 2>&1; then
        echo "[ERROR] jq is required. Install with: sudo pacman -Syu jq"
        return 1
    fi

    # OTA JSON via jq
    local ota_entry
    ota_entry="$(
        jq -n \
           --arg datetime "$datetime" \
           --arg filename "$filename" \
           --arg id "$id" \
           --arg romtype "$romtype" \
           --argjson size "$size" \
           --arg version "$version" \
           --arg release_url "$release_url" \
           '{
              response: [
                {
                  datetime: $datetime,
                  filename: $filename,
                  id: $id,
                  romtype: $romtype,
                  size: $size,
                  url: $release_url,
                  version: $version
                }
              ]
            }'
    )"

    echo "[INFO] Updating local OTA repo JSON on master"
    (
        cd "${top}/ota" || exit 1
        local device_json="${device}.json"
        git checkout master || exit 1
        git pull --rebase origin master || true
        printf "%s\n" "$ota_entry" | tee "$device_json" >/dev/null
        if ! git diff --quiet -- "$device_json"; then
            git add "$device_json"
            git commit -m "${device}: OTA update ${tag_name}"
            git push origin master
            echo "[INFO] Pushed ${device_json} to master"
        else
            echo "[INFO] No changes in ${device_json}, skipping commit"
        fi
    ) || return 1

    # SourceForge upload
    local sf_user="aryannn999"
    local remote_base="/home/frs/project/noprincesshere/lineage-23.0/${device}/${tag_name}"

    # Create only the deepest folder, ignore error if exists
    { echo "mkdir ${remote_base}"; } | sftp "${sf_user}@frs.sourceforge.net" >/dev/null 2>&1 || true

    rsync -Ph "${out}/${filename}"           "${sf_user}@frs.sourceforge.net:${remote_base}/"
    rsync -Ph "${out}/${filename}.sha256sum" "${sf_user}@frs.sourceforge.net:${remote_base}/"

    # Extra images per device
    declare -a images
    if [[ "$device" == "martini" ]]; then
        images=( "boot.img" "dtbo.img" "vbmeta.img" "vendor_boot.img" )
    else
        images=( "boot.img" )
    fi

    for img in "${images[@]}"; do
        if [[ -f "${out}/${img}" ]]; then
            rsync -Ph "${out}/${img}" "${sf_user}@frs.sourceforge.net:${remote_base}/"
            echo "[INFO] Uploaded ${img}"
        else
            echo "[WARN] ${img} not found in ${out} for ${device}"
        fi
    done

    echo "[INFO] Release finished for ${device} at ${release_url}"
}

# Build and publish multiple devices sequentially.
# Frees out/target/product/<device> after each successful release to save space.
release_multiple() {
    if [[ $# -lt 1 ]]; then
        echo "usage: release_multiple <device> [<device> ...]"
        echo "       devices: martini sweet davinci"
        return 1
    fi

    # Allow comma separated input too
    local arg
    local devices=()
    for arg in "$@"; do
        IFS=',' read -r -a _tmp <<< "$arg"
        devices+=("${_tmp[@]}")
    done

    local d
    for d in "${devices[@]}"; do
        echo "[INFO] === Starting ${d} ==="
        if release "$d"; then
            echo "[INFO] ${d} done. Freeing its OUT to save space..."
            rm -rf "out/target/product/${d}" || true
        else
            echo "[ERROR] ${d} failed. Keeping OUT for debugging. Aborting batch."
            return 1
        fi
    done

    echo "[INFO] All requested releases completed."
}
