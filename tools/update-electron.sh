#!/bin/bash
set -ex

root_dir=$(cd `dirname $0`/.. && pwd -P)

electron_url=$(node "$root_dir/tools/parse-config.js" --get-electron-url "$@")
electron_version=$(node "$root_dir/tools/parse-config.js" --get-electron-version "$@")
file_name=$(basename "$electron_url")
local_path="$root_dir/cache/$file_name"

mkdir -p "$root_dir/cache"
if [ ! -f "$local_path" ]; then
    wget -c -O "$local_path.tmp" "$electron_url"
    mv "$local_path.tmp" "$local_path"
fi

rm -rf "$root_dir/electron"
mkdir -p "$root_dir/electron"
unzip -q "$local_path" -d "$root_dir/electron"
chmod +x "$root_dir/electron/electron"
echo "$electron_version" > "$root_dir/electron/.version"
