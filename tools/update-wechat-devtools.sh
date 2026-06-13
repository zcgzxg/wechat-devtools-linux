#!/bin/bash
set -ex

root_dir=$(cd `dirname $0`/.. && pwd -P)

wechat_devtools_url=$(node "$root_dir/tools/parse-config.js" --get-devtools-url $@)
wechat_devtools_version=$(node "$root_dir/tools/parse-config.js" --get-devtools-version $@)
devtools_package=$(node "$root_dir/tools/parse-config.js" --get-devtools-package $@)
runtime=$(node "$root_dir/tools/parse-config.js" --get-runtime $@)

# 下载
local_path="$root_dir/cache/wechat_devtools_${wechat_devtools_version}_x64.exe"
root_local_path="$root_dir/wechat_devtools_${wechat_devtools_version}_win32_x64.exe"
if [ ! -f "$local_path" ] && [ -f "$root_local_path" ]; then
    mkdir -p "$root_dir/cache"
    cp "$root_local_path" "$local_path"
fi
if [ ! -f "$local_path" ]; then
    mkdir -p "$root_dir/cache"
    wget -c "$wechat_devtools_url" -O "$local_path.tmp"
    mv "$local_path.tmp" "$local_path"
fi

# 解压
extract_path="$root_dir/tmp/$(dirname $local_path)"
rm -rf "$extract_path"
mkdir -p "$extract_path"

if [ "$devtools_package" == "electron" ] || [ "$runtime" == "electron" ]; then
    7z x "$local_path" -o"$extract_path" "resources/app.asar" "resources/app.asar.unpacked" "wechatide.cmd" "wechatidecli.cmd" -y

    rm -rf "$root_dir/package.electron"
    mkdir -p "$root_dir/package.electron/app"
    npx --yes asar extract "$extract_path/resources/app.asar" "$root_dir/package.electron/app"
    if [ -d "$extract_path/resources/app.asar.unpacked" ]; then
        cp -a "$extract_path/resources/app.asar.unpacked/." "$root_dir/package.electron/app/"
    fi
    chmod -R 755 "$root_dir/package.electron"
    echo "electron" > "$root_dir/package.electron/.runtime"
else
    7z x "$local_path" -o"$extract_path" "code/package.nw" -y

    # 替换
    rm -rf "$root_dir/package.nw"
    mv "$extract_path/code/package.nw" "$root_dir/package.nw"
    chmod -R 755 "$root_dir/package.nw"
    echo "nwjs" > "$root_dir/package.nw/.runtime"

    if [ -d "$root_dir/nwjs" ]; then
        cd "$root_dir/nwjs"
        ln -sr ../package.nw package.nw
    fi
fi
rm -rf "$extract_path"

package_dir="$root_dir/package.nw"
if [ "$runtime" == "electron" ]; then
    package_dir="$root_dir/package.electron/app"
fi

if [ -f "$package_dir/js/common/miniprogram-builder/modules/fullcompiler/app/contactandlaunch/updateContactAndLaunch.js" ]; then
    mv "$package_dir/js/common/miniprogram-builder/modules/fullcompiler/app/contactandlaunch/updateContactAndLaunch.js" \
       "$package_dir/js/common/miniprogram-builder/modules/fullcompiler/app/contactandlaunch/updatecontactandlaunch.js"
fi

# 写入时间戳
timestamp=$(date +%s)
echo "$timestamp" > "$package_dir/.build_time"
