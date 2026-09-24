#!/bin/bash
set -e

work_dir=$(pwd)
FILE_PATH=$(ls ${work_dir}/out/*.zip 2>/dev/null | head -1)

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
    echo "❌ Không tìm thấy file ROM trong thư mục out/"
    exit 1
fi

FILE_NAME=$(basename "$FILE_PATH")
echo "==> [UPLOADING] Đang chuẩn bị tải $FILE_NAME lên Gofile.io..."

# 1. Lấy server khả dụng từ Gofile API
SERVER_RESP=$(curl -s https://api.gofile.io/servers)
SERVER=$(echo "$SERVER_RESP" | jq -r '.data.servers[0].name' 2>/dev/null)

if [[ -z "$SERVER" || "$SERVER" == "null" ]]; then
    SERVER="store1" # Fallback server mặc định nếu không lấy được danh sách
fi

echo "--> Server tiếp nhận: $SERVER"

# 2. Upload file lên Gofile (kèm token nếu có, hoặc tài khoản ẩn danh)
# GOFILE_TOKEN là tùy chọn (nếu có tài khoản để quản lý file lâu dài)
CURL_ARGS=("-F" "file=@${FILE_PATH}")
if [[ -n "$GOFILE_TOKEN" ]]; then
    CURL_ARGS+=("-H" "Authorization: Bearer ${GOFILE_TOKEN}")
fi

echo "--> Đang truyền file..."
UPLOAD_RESP=$(curl --progress-bar "${CURL_ARGS[@]}" "https://${SERVER}.gofile.io/contents/uploadfile")

# 3. Phân tích kết quả trả về
STATUS=$(echo "$UPLOAD_RESP" | jq -r '.status' 2>/dev/null)

if [[ "$STATUS" == "ok" ]]; then
    DOWNLOAD_PAGE=$(echo "$UPLOAD_RESP" | jq -r '.data.downloadPage' 2>/dev/null)
    DIRECT_LINK=$(echo "$UPLOAD_RESP" | jq -r '.data.directLink // empty' 2>/dev/null)
    FILE_ID=$(echo "$UPLOAD_RESP" | jq -r '.data.fileId' 2>/dev/null)

    FINAL_LINK="${DOWNLOAD_PAGE}"
    [[ -z "$FINAL_LINK" || "$FINAL_LINK" == "null" ]] && FINAL_LINK="https://gofile.io/d/${FILE_ID}"

    echo "✅ Upload Gofile thành công!"
    echo "🔗 Download Page: $FINAL_LINK"

    # Xuất biến để GitHub Actions hoặc Telegram bot đọc được
    echo "GOFILE_LINK=${FINAL_LINK}" >> $GITHUB_ENV
    echo "ARCHIVE_LINK=${FINAL_LINK}" >> $GITHUB_ENV
    echo "$FINAL_LINK" > "$work_dir/bin/ddevice/download_url.txt"
else
    echo "❌ Upload thất bại!"
    echo "Phản hồi API: $UPLOAD_RESP"
    exit 1
fi
