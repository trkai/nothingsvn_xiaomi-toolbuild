#!/bin/bash

baserom="$1"
work_dir=$(pwd)
mkdir -p "$work_dir/bin/ddevice"
source "$work_dir/functions.sh" 2>/dev/null || true

# 1. Xử lý tải ROM nếu đầu vào là link URL
if [[ ! -f "${baserom}" ]] && echo "${baserom}" | grep -qE "http://|https://"; then
    info "Download link detected, starting a download..."
    # Lấy tên file chuẩn, loại bỏ các tham số URL đằng sau dấu ?
    filename=$(basename "${baserom}" | cut -d '?' -f 1)
    aria2c --max-download-limit=1024M --file-allocation=none -s10 -x10 -j10 -o "$filename" "${baserom}"
    baserom="$filename"

    if [[ ! -f "${baserom}" ]]; then
        error "Download error: File not found!"
        exit 1
    fi
    info "BASEROM downloaded: ${baserom}"
elif [[ -f "${baserom}" ]]; then
    info "BASEROM local file: ${baserom}"
else
    error "BASEROM: Invalid parameter or file not found!"
    exit 1
fi

rom_filename=$(basename "$baserom")

# 2. Phân tích tên thiết bị (device_code) và mã phiên bản (base_rom_code)
if echo "$rom_filename" | grep -q "miui_"; then
    # Mẫu: miui_DEVICE_VERSION_HASH_ANDROID.zip
    device_code=$(echo "$rom_filename" | cut -d '_' -f 2)
    base_rom_code=$(echo "$rom_filename" | cut -d '_' -f 3)
elif echo "$rom_filename" | grep -q "xiaomi.eu_"; then
    # Mẫu: xiaomi.eu_multi_DEVICE_VERSION_HASH.zip
    device_code=$(echo "$rom_filename" | cut -d '_' -f 3)
    base_rom_code=$(echo "$rom_filename" | cut -d '_' -f 4)
elif echo "$rom_filename" | grep -qE '.*-ota_full-.*'; then
    # Mẫu: DEVICE-ota_full-VERSION-...zip
    device_code=$(echo "$rom_filename" | cut -d '-' -f 1)
    base_rom_code=$(echo "$rom_filename" | cut -d '-' -f 3)
else
    # Tìm kiếm chuỗi version trực tiếp qua regex nếu định dạng file lạ
    base_rom_code=$(echo "$rom_filename" | grep -oE "(OS[0-9]+(\.[0-9]+)+[\.A-Z0-9]*|V[0-9]+(\.[0-9]+)+[\.A-Z0-9]*)" | head -1)
    device_code=$(echo "$rom_filename" | cut -d '_' -f 1 | cut -d '-' -f 1)
    [[ -z "$base_rom_code" ]] && base_rom_code="Unknown"
    [[ -z "$device_code" ]] && device_code="YourDevice"
fi

# Chuẩn hóa định dạng device_code
device_code=$(echo "$device_code" | awk -F '_' '{
    if (NF == 1) {
        print toupper($1)
    } else if (NF == 2) {
        print toupper($1) toupper(substr($2, 1, 1)) substr($2, 2)
    } else if (NF >= 3) {
        printf toupper($1) toupper($2) toupper(substr($3, 1, 1)) substr($3, 2)
    }
}')

device_f=$(echo "$device_code" | sed 's/\(Global\|EEAGlobal\|INGlobal\|IDGlobal\|RUGlobal\|TWGlobal\|TRGlobal\|JPGlobal\)$//' | tr '[:upper:]' '[:lower:]')

# 3. Xác định loại thị trường thiết bị
info "Get Device Type"
if echo "$device_code" | grep -q 'EEAGlobal'; then
    DEVICE_TYPE="EEAGlobal"
elif echo "$device_code" | grep -q 'INGlobal'; then
    DEVICE_TYPE="INGlobal"
elif echo "$device_code" | grep -q 'IDGlobal'; then
    DEVICE_TYPE="IDGlobal"
elif echo "$device_code" | grep -q 'RUGlobal'; then
    DEVICE_TYPE="RUGlobal"
elif echo "$device_code" | grep -q 'JPGlobal'; then
    DEVICE_TYPE="JPGlobal"
elif echo "$device_code" | grep -q 'Global'; then
    DEVICE_TYPE="Global"
elif echo "$device_code" | grep -q 'TWGlobal'; then
    DEVICE_TYPE="TWGlobal"
elif echo "$device_code" | grep -q 'TRGlobal'; then
    DEVICE_TYPE="TRGlobal"
else
    DEVICE_TYPE="China"
fi

# 4. Kiểm tra và nhận diện hệ điều hành (Hỗ trợ linh hoạt từ OS1 tới OS9 và Android 17)
if [[ "$base_rom_code" =~ (OS[0-9]+) ]]; then
    ROM_OS="${BASH_REMATCH[1]}"
elif [[ "$rom_filename" =~ (OS[0-9]+) ]]; then
    ROM_OS="${BASH_REMATCH[1]}"
    [[ "$base_rom_code" == "Unknown" ]] && base_rom_code="${BASH_REMATCH[1]}"
elif echo "$base_rom_code" | grep -qE "V12|V13|V14|V15"; then
    ROM_OS="MIUI"
elif echo "$rom_filename" | grep -qE "V12|V13|V14|V15"; then
    ROM_OS="MIUI"
else
    # Fallback dự phòng: Nếu không phát hiện chuỗi trong tên, thử kiểm tra payload.bin
    if unzip -l "$baserom" 2>/dev/null | grep -q "payload.bin"; then
        warn "Không đọc được version từ tên file, nhưng tìm thấy payload.bin. Tiếp tục build..."
        ROM_OS="OS3"
        base_rom_code="AutoDetected"
    else
        echo "Unsupport ROM Exiting..."
        exit 1
    fi
fi

# 5. Lưu thông tin ra file cho các bước tiếp theo
echo "$base_rom_code" > "$work_dir/bin/ddevice/base_rom_code.txt"
echo "$base_rom_code" > "$work_dir/bin/ddevice/os_code.txt"
echo "$device_code"   > "$work_dir/bin/ddevice/device_code.txt"
echo "$device_f"      > "$work_dir/bin/ddevice/device_f.txt"
echo "$DEVICE_TYPE"   > "$work_dir/bin/ddevice/device_type.txt"
echo "$ROM_OS"        > "$work_dir/bin/ddevice/rom_os.txt"

info "Nhận diện thành công: Device=$device_code | Region=$DEVICE_TYPE | OS=$ROM_OS | Code=$base_rom_code"
