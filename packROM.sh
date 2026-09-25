#!/bin/bash
work_dir=$(pwd)
source $work_dir/functions.sh 2>/dev/null || true

# Sửa lỗi dính dòng PATH
tools_dir="${work_dir}/bin/$(uname)/$(uname -m)"
export PATH="${tools_dir}:$PATH"

super_list="vendor mi_ext odm odm_dlkm system system_dlkm vendor_dlkm product product_dlkm system_ext"
os_type=$(cat $work_dir/bin/ddevice/os_type.txt 2>/dev/null)
base_rom_code=$(cat $work_dir/bin/ddevice/base_rom_code.txt 2>/dev/null || echo "OS")
androidVER=$(cat $work_dir/bin/ddevice/androidver.txt 2>/dev/null)
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt 2>/dev/null)
regionTYPE=$(cat $work_dir/bin/ddevice/device_type.txt 2>/dev/null)
device_code=$(cat $work_dir/bin/ddevice/device_code.txt 2>/dev/null || echo "ANNIBALE")
getvar=$(cat $work_dir/bin/ddevice/device_f.txt 2>/dev/null || echo "$device_code" | tr '[:upper:]' '[:lower:]')
PACK_TYPE=$(cat $work_dir/bin/ddevice/fstype.txt 2>/dev/null || echo "EROFS")

if [[ $(git branch --show-current 2>/dev/null) == "beta" ]]; then
    polyxver="$(cat Version 2>/dev/null || echo "1.1")"
    status="Development"
else
    polyxver="$(cat Version 2>/dev/null || echo "1.1")"
    status="Official"
fi

if [[ $rom_os == "MIUI" ]]; then
    os_type="MIUI"
else
    os_type="HyperOS"
fi

# 1. Generate Super.img
superSize=$(bash $work_dir/bin/getSuperSize.sh $getvar 2>/dev/null || echo "9126805504")
repack "Super image size: ${superSize}"
repack "Packing sub-partitions into img..."

for pname in ${super_list}; do
    if [ -d "$work_dir/build/baserom/images/$pname" ]; then
        thisSize=$(du -sb $work_dir/build/baserom/images/${pname} | awk '{print $1}')
        if [[ $androidVER == "12" ]]; then
           case $pname in
             odm) addSize=104217728 ;;
             system) addSize=114217728 ;;
             vendor) addSize=104217728 ;;
             system_ext) addSize=104217728 ;;
             product) addSize=104217728 ;;
             *) addSize=8054432 ;;
           esac
        else
           case $pname in
             mi_ext) addSize=4094304 ;;
             odm) addSize=104217728 ;;
             system) addSize=104217728 ;;
             vendor) addSize=104217728 ;;
             system_ext) addSize=104217728 ;;
             product) addSize=114217728 ;;
             *) addSize=8054432 ;;
           esac
        fi
         
        thisSize=$(echo "$thisSize + $addSize" | bc)
        if [[ "$PACK_TYPE" == "EXT" ]]; then
            python3 $work_dir/bin/fspatch.py $work_dir/build/baserom/images/${pname} $work_dir/build/baserom/images/config/${pname}_fs_config >/dev/null 2>&1
            python3 $work_dir/bin/contextpatch.py $work_dir/build/baserom/images/${pname} $work_dir/build/baserom/images/config/${pname}_file_contexts >/dev/null 2>&1
            make_ext4fs -J -T $(date +%s) -S $work_dir/build/baserom/images/config/${pname}_file_contexts -l $thisSize -C $work_dir/build/baserom/images/config/${pname}_fs_config -L ${pname} -a ${pname} $work_dir/build/baserom/images/${pname}.img $work_dir/build/baserom/images/${pname} >/dev/null 2>&1
        else
            python3 $work_dir/bin/fspatch.py $work_dir/build/baserom/images/${pname} $work_dir/build/baserom/images/config/${pname}_fs_config >/dev/null 2>&1
            python3 $work_dir/bin/contextpatch.py $work_dir/build/baserom/images/${pname} $work_dir/build/baserom/images/config/${pname}_file_contexts >/dev/null 2>&1
            mkfs.erofs --quiet -zlz4hc,9 --mount-point ${pname} --fs-config-file=$work_dir/build/baserom/images/config/${pname}_fs_config --file-contexts=$work_dir/build/baserom/images/config/${pname}_file_contexts $work_dir/build/baserom/images/${pname}.img $work_dir/build/baserom/images/${pname} >/dev/null 2>&1
        fi

        if [ -f "$work_dir/build/baserom/images/${pname}.img" ]; then
            repack "Packing [${pname}.img] success"
        else
            repack "Packing [${pname}] failed!"
        fi
    fi
done

if grep -q "ro.build.ab_update=true" $work_dir/build/baserom/images/vendor/build.prop 2>/dev/null; then
    is_ab_device=true
else
    is_ab_device=false
fi

# 2. Pack super.img bằng lpmake
if [[ "$is_ab_device" == false ]]; then
    repack "Packing super.img for A-only device"
    lpargs="-F --output $work_dir/build/baserom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 2 --block-size 4096 --device super:$superSize --group=qti_dynamic_partitions:$superSize"
    for pname in odm mi_ext system system_ext product vendor; do
        if [ -f "$work_dir/build/baserom/images/${pname}.img" ]; then
            subsize=$(du -sb $work_dir/build/baserom/images/${pname}.img | tr -cd 0-9)
            args="--partition ${pname}:none:${subsize}:qti_dynamic_partitions --image ${pname}=$work_dir/build/baserom/images/${pname}.img"
            lpargs="$lpargs $args"
        fi
    done
else
    repack "Packing super.img for V-AB device"
    lpargs="-F --virtual-ab --output $work_dir/build/baserom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 3 --device super:$superSize --group=qti_dynamic_partitions_a:$superSize --group=qti_dynamic_partitions_b:$superSize"
    for pname in ${super_list}; do
        if [ -f "$work_dir/build/baserom/images/${pname}.img" ]; then
            subsize=$(du -sb $work_dir/build/baserom/images/${pname}.img | awk '{print $1}')
            args="--partition ${pname}_a:none:${subsize}:qti_dynamic_partitions_a --image ${pname}_a=$work_dir/build/baserom/images/${pname}.img --partition ${pname}_b:none:0:qti_dynamic_partitions_b"
            lpargs="$lpargs $args"
        fi
    done
fi

lpmake $lpargs
if [ -f "$work_dir/build/baserom/images/super.img" ]; then
    repack "Successfully packed super.img."
else
    repack "Unable to pack super.img."
    exit 1
fi

# Xóa các file .img phân vùng con để giải phóng bộ nhớ
for pname in ${super_list}; do
    rm -rf $work_dir/build/baserom/images/${pname}.img
done

# 3. ĐÓNG GÓI THÀNH FILE ROM ZIP HOÀN CHỈNH VÀO THƯ MỤC out/
repack "Preparing flashable zip package..."
mkdir -p "$work_dir/out"

# Chuẩn bị cấu trúc ROM zip (chép META-INF, script flash nếu có)
if [ -d "$work_dir/bin/script2flash" ]; then
    cp -r $work_dir/bin/script2flash/* "$work_dir/build/baserom/" 2>/dev/null || true
fi

# Đặt tên file ROM chuẩn
ZIP_NAME="BugOS_${device_code}_${base_rom_code}_$(date +%Y%m%d).zip"
repack "Compressing ROM package into: out/${ZIP_NAME}"

cd "$work_dir/build/baserom"

# Ưu tiên dùng 7z nếu có, nếu không thì dùng zip
if command -v 7z >/dev/null 2>&1; then
    7z a -tzip -mx=1 "$work_dir/out/${ZIP_NAME}" ./* >/dev/null
else
    zip -r -1 "$work_dir/out/${ZIP_NAME}" ./* >/dev/null
fi

cd "$work_dir"

if [ -f "$work_dir/out/${ZIP_NAME}" ]; then
    echo "========================================="
    echo "✅ ROM ZIP PACKED SUCCESSFULLY:"
    echo "Path: $work_dir/out/${ZIP_NAME}"
    echo "Size: $(du -sh $work_dir/out/${ZIP_NAME} | awk '{print $1}')"
    echo "========================================="
else
    echo "❌ Pack ROM Zip thất bại!"
    exit 1
fi
