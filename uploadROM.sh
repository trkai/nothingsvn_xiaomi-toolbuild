work_dir=$(pwd)
source $work_dir/functions.sh
RCLONE_CONFIG_1DRIVE="$work_dir/rclone.conf"

# Cấu hình Google Drive trỏ thẳng vào ID thư mục của bạn
GDRIVE_REMOTE="rclone"
GDRIVE_FOLDER_ID="1AeAHmwsEFmBLqFJuLC6K0KEpTM4KoQR8"

os_type=$(cat $work_dir/bin/ddevice/os_type.txt)
base_rom_code=$(cat $work_dir/bin/ddevice/base_rom_code.txt)
androidVER=$(cat $work_dir/bin/ddevice/androidver.txt)
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt)
regionTYPE=$(cat $work_dir/bin/ddevice/device_type.txt)
device_code=$(cat $work_dir/bin/ddevice/device_code.txt)
baserom_type=$(cat $work_dir/bin/ddevice/romtype.txt)
device_f=$(cat $work_dir/bin/ddevice/device_f.txt)

# Nếu device_code trống thì lấy từ device_f
if [ -z "$device_code" ]; then
    device_code="$device_f"
fi

if [[ $(git branch --show-current) == "beta" ]]; then
    polyxver="$(cat Version)"
    status="Development"
else
    polyxver="$(cat Version)"
    status="Official"
fi

# Nhận diện hệ điều hành
if [[ "$base_rom_code" == OS* ]]; then
    true_os="HalcyonOS"
else
    true_os="MIUI"
fi

os_type=$true_os

repack "Compressing super.img"
zstd --rm $work_dir/build/baserom/images/super.img -o $work_dir/build/baserom/images/super.img.zst > /dev/null 2>&1

repack "Generating flashing script"
mkdir -p $work_dir/out/${os_type}_${device_code}_${base_rom_code}/images/

# Xóa các file firmware không cần thiết
rm -f $work_dir/build/baserom/images/{abl,xbl,xbl_config,xbl_ramdump,tz,hyp,devcfg,keymaster,qupfw,uefisecapp,modem,dsp,bluetooth,cpucp,shrm,logo,featenabler,cmnlib,cmnlib64,tzdev,storsec,aop,multiimgoem,imagefv,apdp,msadp}.img 2>/dev/null || true
rm -f $work_dir/build/baserom/images/firmware* 2>/dev/null || true

# Di chuyển super.img.zst và các image còn lại
mv -f $work_dir/build/baserom/images/super.img.zst $work_dir/out/${os_type}_${device_code}_${base_rom_code}/ 2>/dev/null || true
mv -f $work_dir/build/baserom/images/*.img $work_dir/out/${os_type}_${device_code}_${base_rom_code}/images/ 2>/dev/null || true

# Copy script flash
cp -rf $work_dir/bin/script2flash/META-INF $work_dir/out/${os_type}_${device_code}_${base_rom_code}/
cp -rf $work_dir/bin/script2flash/*.bat $work_dir/out/${os_type}_${device_code}_${base_rom_code}/ 2>/dev/null || true
cp -rf $work_dir/bin/script2flash/*.sh $work_dir/out/${os_type}_${device_code}_${base_rom_code}/ 2>/dev/null || true
if [ -f "$work_dir/bin/script2flash/cust.img" ]; then
    cp -rf $work_dir/bin/script2flash/cust.img $work_dir/out/${os_type}_${device_code}_${base_rom_code}/images/
fi
echo $device_f > $work_dir/out/${os_type}_${device_code}_${base_rom_code}/META-INF/Data/DeviceCode
repack "Done"

# Nén thành file .zip
find out/${os_type}_${device_code}_${base_rom_code} | xargs touch
pushd out/${os_type}_${device_code}_${base_rom_code}/ || exit
zip -r ${os_type}_${device_code}_${base_rom_code}.zip ./*
mv ${os_type}_${device_code}_${base_rom_code}.zip ../
popd || exit

hash=$(md5sum out/${os_type}_${device_code}_${base_rom_code}.zip | head -c 5)
final_zip="${os_type}_${polyxver}_${device_code}_${base_rom_code}_${hash}_${status}.zip"
mv out/${os_type}_${device_code}_${base_rom_code}.zip out/${final_zip}

repack "Build completed"
repack "Output: $(pwd)/out/${final_zip}"
upload "Uploading"

output_file="out/${final_zip}"
echo "${final_zip}" > $work_dir/bin/ddevice/output_zip.txt

uploaddir=$true_os

# Upload thẳng lên Google Drive vào thư mục 1AeAHmwsEFmBLqFJuLC6K0KEpTM4KoQR8
upload "Uploading to Google Drive..."
rclone -v --config="$RCLONE_CONFIG_1DRIVE" copy "$output_file" "$GDRIVE_REMOTE:${uploaddir}/${polyxver}/${device_code}/" \
    --drive-root-folder-id "$GDRIVE_FOLDER_ID" \
    --drive-chunk-size 128M \
    --tpslimit 4 \
    --retries 3 \
    --timeout 15m \
    --contimeout 15m || {
    upload "Lỗi khi upload file lên Google Drive!"
    exit 1
}

upload "Clean Workflow.."
rm -rf $work_dir/out
rm -rf $work_dir/build

upload "Build ${os_type}_${polyxver} for ${device_code} successful!"
