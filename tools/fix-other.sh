#!/bin/bash
set -ex
root_dir=$(cd `dirname $0`/.. && pwd -P)
srcdir=$root_dir
tmp_dir="$root_dir/tmp"
nwjs_dir="$root_dir/nwjs"
package_dir="$root_dir/package.nw"
runtime=$(node "$root_dir/tools/parse-config.js" --get-runtime $@)
if [ "$runtime" == "electron" ];then
  package_dir="$root_dir/package.electron/app"
fi

if [ "$runtime" == "electron" ];then
  echo "fix: electron direct-open appid context"
  node - "$package_dir" <<'NODE'
const fs = require('fs');
const path = require('path');

const packageDir = process.argv[2];
const jsDir = path.join(packageDir, 'js');
if (!fs.existsSync(jsDir)) process.exit(0);

const source = 'requestWithAppId({url:i,method:"get",needToken:1,forceLogin:-1})';
const target = 'requestWithAppId({url:i,method:"get",needToken:1,forceLogin:-1,appid:this.requestService._appid||process.env.WECHAT_DEVTOOLS_APPID})';

for (const entry of fs.readdirSync(jsDir)) {
  if (!entry.endsWith('.js')) continue;
  const file = path.join(jsDir, entry);
  const content = fs.readFileSync(file, 'utf8');
  if (content.includes(target)) {
    process.exit(0);
  }
  if (!content.includes(source)) continue;
  fs.writeFileSync(file, content.replace(source, target));
  console.log(`patched appid context: ${file}`);
  process.exit(0);
}
NODE
fi

if [ "$runtime" == "electron" ];then
  echo "fix: disable electron update checks"
  node - "$package_dir" <<'NODE'
const fs = require('fs');
const path = require('path');

const jsDir = path.join(process.argv[2], 'js');
if (!fs.existsSync(jsDir)) process.exit(0);

const fetchPattern = 'function fetchManifest(localManifest) {';
const startPattern = 'const startCheckUpdate = () => {';

let patched = false;
for (const entry of fs.readdirSync(jsDir)) {
  if (!entry.endsWith('.js')) continue;
  const file = path.join(jsDir, entry);
  let content;
  try { content = fs.readFileSync(file, 'utf8'); } catch (_) { continue; }
  if (!content.includes(fetchPattern) || !content.includes(startPattern)) continue;
  if (content.includes('[wechat-devtools] update checks disabled')) {
    patched = true;
    break;
  }
  const updated = content
    .replace(fetchPattern, `${fetchPattern}\n    logger.info('[wechat-devtools] update checks disabled');\n    return Promise.resolve({});`)
    .replace(startPattern, `${startPattern}\n    logger.info('[wechat-devtools] skip startCheckUpdate');\n    clearInterval(updateTimer);\n    return;`);
  fs.writeFileSync(file, updated);
  console.log(`patched update checks: ${file}`);
  patched = true;
  break;
}
if (!patched) console.log('disable update checks: nothing to patch (already fixed or pattern changed)');
NODE
fi

echo "replace: wcc,wcsc linux version"
compiler_version=$(node "$root_dir/tools/parse-config.js" --get-compiler-version $@)
arch=$(node "$root_dir/tools/parse-config.js" --get-arch $@)
if [ "$arch" == "x64" ];then
  arch="x86_64"
elif [ "$arch" == "loongarch64" ];then
  arch="loong64"
fi

mkdir -p "${srcdir}/cache/compiler/v${compiler_version}"
if [ ! -f "${srcdir}/cache/compiler/v${compiler_version}/wcc-${arch}" ];then
  wget -c "https://github.com/msojocs/wx-compiler/releases/download/v${compiler_version}/wcc-${arch}" -O "${srcdir}/cache/compiler/v${compiler_version}/wcc-${arch}.tmp"
  mv "${srcdir}/cache/compiler/v${compiler_version}/wcc-${arch}.tmp" "${srcdir}/cache/compiler/v${compiler_version}/wcc-${arch}"
  chmod +x "${srcdir}/cache/compiler/v${compiler_version}/wcc-${arch}"
fi

if [ ! -f "${srcdir}/cache/compiler/v${compiler_version}/wcsc-${arch}" ];then
  wget -c "https://github.com/msojocs/wx-compiler/releases/download/v${compiler_version}/wcsc-${arch}" -O "${srcdir}/cache/compiler/v${compiler_version}/wcsc-${arch}.tmp"
  mv "${srcdir}/cache/compiler/v${compiler_version}/wcsc-${arch}.tmp" "${srcdir}/cache/compiler/v${compiler_version}/wcsc-${arch}"
  chmod +x "${srcdir}/cache/compiler/v${compiler_version}/wcsc-${arch}"
fi

if [ ! -f "${srcdir}/cache/compiler/v${compiler_version}/wcc-${arch}.node" ];then
  wget -c "https://github.com/msojocs/wx-compiler/releases/download/v${compiler_version}/wcc-${arch}.node" -O "${srcdir}/cache/compiler/v${compiler_version}/wcc-${arch}.node.tmp"
  mv "${srcdir}/cache/compiler/v${compiler_version}/wcc-${arch}.node.tmp" "${srcdir}/cache/compiler/v${compiler_version}/wcc-${arch}.node"
fi

if [ ! -f "${srcdir}/cache/compiler/v${compiler_version}/wcsc-${arch}.node" ];then
  wget -c "https://github.com/msojocs/wx-compiler/releases/download/v${compiler_version}/wcsc-${arch}.node" -O "${srcdir}/cache/compiler/v${compiler_version}/wcsc-${arch}.node.tmp"
  mv "${srcdir}/cache/compiler/v${compiler_version}/wcsc-${arch}.node.tmp" "${srcdir}/cache/compiler/v${compiler_version}/wcsc-${arch}.node"
fi

if [ -d "${package_dir}/node_modules/wcc-exec" ];then
  cp "${srcdir}/cache/compiler/v${compiler_version}"/wcc-${arch} "${package_dir}/node_modules/wcc-exec/wcc"
  cp "${srcdir}/cache/compiler/v${compiler_version}"/wcsc-${arch} "${package_dir}/node_modules/wcc-exec/wcsc"
  cd "${package_dir}/node_modules/wcc-exec" && chmod +x wcc wcsc && rm -rf wcc.exe wcsc.exe
fi

# 修复 agent skill/skyline 的 glassEasel 编译：parser 路径在非mac平台误用 wcc.exe(Linux无此文件,spawn失败致 skill 运行时 not defined)，改为仅 win32 加 .exe
if [ "$runtime" == "electron" ];then
  echo "fix: glassEasel wxml/wxss parser path (wcc.exe -> wcc on linux)"
  node - "$package_dir" <<'NODE'
const fs = require('fs');
const path = require('path');
const jsDir = path.join(process.argv[2], 'js');
if (!fs.existsSync(jsDir)) process.exit(0);
const reWcc = /const e=h\?"wcc":"wcc\.exe";/;
const reWcsc = /const e=h\?"wcsc":"wcsc\.exe";/;
const newWcc = 'const e="win32"===process.platform?"wcc.exe":"wcc";';
const newWcsc = 'const e="win32"===process.platform?"wcsc.exe":"wcsc";';
let patched = false;
for (const entry of fs.readdirSync(jsDir)) {
  if (!entry.endsWith('.js')) continue;
  const file = path.join(jsDir, entry);
  let content;
  try { content = fs.readFileSync(file, 'utf8'); } catch (_) { continue; }
  if (!reWcc.test(content) && !reWcsc.test(content)) continue;
  const updated = content.replace(reWcc, newWcc).replace(reWcsc, newWcsc);
  if (updated !== content) {
    fs.writeFileSync(file, updated);
    console.log(`patched glassEasel parser path: ${file}`);
    patched = true;
  }
}
if (!patched) console.log('glassEasel parser path: nothing to patch (already fixed or pattern changed)');
NODE
fi

# 修复：可视化用的wcc,wcsc
echo "fix: wcc,wcsc"
if [ "$runtime" == "electron" ] && [ -d "${package_dir}/node_modules/wcc-electron/build/Release" ];then
  wcc_module_dir="${package_dir}/node_modules/wcc-electron/build/Release"
else
  wcc_module_dir="${package_dir}/node_modules/wcc/build/Release"
fi
if [ -d "$wcc_module_dir" ];then
  \cp "${srcdir}/cache/compiler/v${compiler_version}"/wcc-${arch}.node "$wcc_module_dir"
  cd "$wcc_module_dir" && rm -rf wcc.node && mv wcc-${arch}.node wcc.node
  \cp "${srcdir}/cache/compiler/v${compiler_version}"/wcsc-${arch}.node "$wcc_module_dir"
  cd "$wcc_module_dir" && rm -rf wcsc.node && mv wcsc-${arch}.node wcsc.node
fi

# 修复mock按钮无反应
if [ -f "${package_dir}/js/ideplugin/devtools/index.js" ];then
  sed -i '1s/^/window.prompt = parent.prompt;\n/' "${package_dir}/js/ideplugin/devtools/index.js"
fi

nw_version=$(node "$root_dir/tools/parse-config.js" --get-nwjs-version $@)
# 修复视频无法播放
if [ "$runtime" != "electron" ] && [ "$arch" == "x64" ];then
  if [ ! -f "${srcdir}/cache/libffmpeg-${nw_version}-linux-x64.zip" ];then
    wget -c https://github.com/nwjs-ffmpeg-prebuilt/nwjs-ffmpeg-prebuilt/releases/download/${nw_version}/${nw_version}-linux-x64.zip -O "${srcdir}/cache/libffmpeg-${nw_version}-linux-x64.zip.tmp"
    mv "${srcdir}/cache/libffmpeg-${nw_version}-linux-x64.zip.tmp" "${srcdir}/cache/libffmpeg-${nw_version}-linux-x64.zip"
  fi
  rm -rf "${nwjs_dir}/lib/libffmpeg.so"
  unzip "${srcdir}/cache/libffmpeg-${nw_version}-linux-x64.zip" -d "${nwjs_dir}/lib"
fi

# Skyline解析插件修复
float_pigment_version="continuous"
if [ ! -f "${srcdir}/cache/float-pigment-${float_pigment_version}.node" ];then
  wget -c "https://github.com/msojocs/float-pigment-rust/releases/download/${float_pigment_version}/float-pigment.linux-x64-gnu.node" -O "${srcdir}/cache/float-pigment-${float_pigment_version}.node.tmp"
  mv "${srcdir}/cache/float-pigment-${float_pigment_version}.node.tmp" "${srcdir}/cache/float-pigment-${float_pigment_version}.node"
fi
rm -f "${package_dir}/node_modules/node-float-pigment-css/float-pigment-css-for-nodejs.node" "${package_dir}/node_modules/node-float-pigment-css/float-pigment-css-for-nwjs.node"
if [ -d "${package_dir}/node_modules/node-float-pigment-css" ];then
  cp "${srcdir}/cache/float-pigment-${float_pigment_version}.node" "${package_dir}/node_modules/node-float-pigment-css/float-pigment-css-for-nodejs.node"
  cp "${srcdir}/cache/float-pigment-${float_pigment_version}.node" "${package_dir}/node_modules/node-float-pigment-css/float-pigment-css-for-nwjs.node"
fi

# websocket找不到
if [ -d "${package_dir}/js/libs/vseditor/extensions/node_modules/ws/lib" ];then
cd "${package_dir}/js/libs/vseditor/extensions/node_modules/ws/lib"
if [ -f "WebSocket.js" ];then
  mv "WebSocket.js" "websocket.js"
  mv "Receiver.js" "receiver.js"
  mv "Sender.js" "sender.js"
  mv "Constants.js" "constants.js"
  mv "Validation.js" "validation.js"
fi
fi

# 阻止无限启动服务器
if [ -f "${package_dir}/js/core/entrance.js" ];then
  mv "${package_dir}/js/core/entrance.js" "${package_dir}/js/core/entrance.js.bak"
  cat "${srcdir}/res/scripts/entrance.js" > "${package_dir}/js/core/entrance.js"
  cat "${package_dir}/js/core/entrance.js.bak" >> "${package_dir}/js/core/entrance.js"
  rm "${package_dir}/js/core/entrance.js.bak"
fi

# 修复iframe导致的崩溃
if [ -f "${package_dir}/js/core/index.js" ];then
  sed -i 's#"use strict";##' "${package_dir}/js/core/index.js"
  mv "${package_dir}/js/core/index.js" "${package_dir}/js/core/index.js.bak"
  cat "${srcdir}/res/scripts/core_index.js" > "${package_dir}/js/core/index.js"
  cat "${package_dir}/js/core/index.js.bak" >> "${package_dir}/js/core/index.js"
  rm "${package_dir}/js/core/index.js.bak"
fi

# 修复编辑器不能覆盖粘贴
if [ -f "${package_dir}/js/libs/vseditor/bundled/editor.bundled.js" ];then
  sed -i 's#if(super(),l.isLinux){let#if(super(),l.isLinux){return;let#' "${package_dir}/js/libs/vseditor/bundled/editor.bundled.js"
fi

current=`date "+%Y-%m-%d %H:%M:%S"`
timeStamp=`date -d "$current" +%s`
echo $timeStamp > "${package_dir}/.build_time"


rm -rf "$tmp_dir/node_modules"
