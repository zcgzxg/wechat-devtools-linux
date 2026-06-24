#!/bin/bash
set -ex

notice() {
  echo -e "\033[36m $1 \033[0m "
}

fail() {
  echo -e "\033[41;37m 失败 \033[0m $1"
}

root_dir=$(cd "$(dirname "$0")/.." && pwd -P)
package_dir="$root_dir/package.electron/app"

if [ -n "$1" ]; then
  ELECTRON_VERSION=$1
fi
if [ -z "$ELECTRON_VERSION" ]; then
  fail "Electron 版本未指定！"
  exit 1
fi

if [ ! -d "$package_dir/node_modules" ]; then
  fail "未找到 Electron package node_modules: $package_dir/node_modules"
  exit 1
fi

arch=$(node "$root_dir/tools/parse-config.js" --get-arch "$@")

notice "Electron 原生模块需要按 Electron ABI 重编"
echo "Electron VERSION:  $ELECTRON_VERSION"
echo "arch:              $arch"
echo "node version:      $(node --version)"
echo "npm version:       $(npm --version)"

export npm_config_runtime=electron
export npm_config_target="$ELECTRON_VERSION"
export npm_config_disturl=https://electronjs.org/headers
export npm_config_arch="$arch"
export npm_config_target_arch="$arch"
export npm_config_target_platform=linux
export JOBS=$(nproc)

cd "$package_dir"

if [ -f package-lock.json ]; then
  npm install --ignore-scripts --registry=https://registry.npmmirror.com
fi

if [ -f node_modules/@swc/core/package.json ]; then
  swc_version=$(node -e 'process.stdout.write(require("./node_modules/@swc/core/package.json").version)')
  case "$arch" in
    x64)
      swc_native_package="@swc/core-linux-x64-gnu@${swc_version}"
      ;;
    arm64|aarch64)
      swc_native_package="@swc/core-linux-arm64-gnu@${swc_version}"
      ;;
    *)
      swc_native_package=""
      ;;
  esac

  if [ -n "$swc_native_package" ]; then
    notice "Installing Electron Linux SWC native binding: $swc_native_package"
    npm install --ignore-scripts --no-save --registry=https://registry.npmmirror.com "$swc_native_package"
  fi
fi

npx --yes @electron/rebuild@3.7.2 \
  --version "$ELECTRON_VERSION" \
  --arch "$arch" \
  --module-dir "$package_dir" \
  --force
