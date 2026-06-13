# Nightly Electron Docker 构建说明

Nightly 版本已经切换到 Electron，不再使用 NW.js。为了避免构建脚本在本机仓库中生成或删除 `node/`、`electron/`、`package.electron/`、`package.nw/`、`nwjs/`、`cache/`、`tmp/` 等目录，Docker 构建应使用 `/tmp` 下的源码副本作为工作区。

本项目保留稳定版 NW.js 构建路径，Nightly 通过 `--channel nightly` 进入独立 Electron 路径：

- 配置入口：`conf/config.json` 中的 `devtools.channels.nightly` 和 `electron.urls.x64`；
- 配置解析：`tools/parse-config.js --channel nightly --get-runtime` 应输出 `electron`；
- Electron 运行时下载：`tools/update-electron.sh`；
- Nightly 安装包解包：`tools/update-wechat-devtools.sh --channel nightly`，会从 Windows 安装包提取 `resources/app.asar` 与完整 `resources/app.asar.unpacked` 到 `package.electron/app`；
- Electron ABI 重编：`tools/rebuild-electron-node-modules.sh <electron-version>`；
- GUI 启动器：`bin/wechat-devtools-nightly`；
- CLI 启动器：`bin/wechat-devtools-cli-nightly`。

## 直接构建 Nightly

如果允许当前仓库目录生成构建产物，可以直接运行：

```bash
./tools/setup-wechat-devtools.sh --channel nightly
```

构建完成后会生成：

- `electron/`：Linux Electron 运行时；
- `package.electron/app/`：从 Nightly 安装包提取并修补后的 Electron 应用；
- `bin/wechat-devtools-nightly`：Nightly GUI 启动器；
- `bin/wechat-devtools-cli-nightly`：Nightly CLI 启动器。

如需打 tar 包：

```bash
./tools/build-tar.sh v2.02.2606122-1 x86_64
```

## 隔离构建流程

不要直接使用当前仓库的 `tools/build-with-docker.sh` 构建 nightly。该脚本会把当前仓库读写挂载为容器内 `/workspace`，构建过程会修改当前仓库内容。

推荐流程：

```bash
rm -rf /tmp/wechat-devtools-nightly-docker-src /tmp/wechat-devtools-nightly-output
mkdir -p /tmp/wechat-devtools-nightly-docker-src /tmp/wechat-devtools-nightly-output
git ls-files -z | rsync -a --files-from=- --from0 ./ /tmp/wechat-devtools-nightly-docker-src/
mkdir -p /tmp/wechat-devtools-nightly-docker-src/bin /tmp/wechat-devtools-nightly-docker-src/tools
cp bin/wechat-devtools-nightly bin/wechat-devtools-cli-nightly /tmp/wechat-devtools-nightly-docker-src/bin/
cp tools/update-electron.sh tools/rebuild-electron-node-modules.sh /tmp/wechat-devtools-nightly-docker-src/tools/
cp wechat_devtools_2.02.2606122_win32_x64.exe /tmp/wechat-devtools-nightly-docker-src/

docker run --rm -i \
  -u "$(id -u):$(id -g)" \
  -e "ACTION_MODE=false" \
  -e "npm_config_prefix=/workspace/cache/npm/node_global" \
  -e "npm_config_cache=/workspace/cache/npm/node_cache" \
  -e "CXXFLAGS=-std=c++17" \
  -w /workspace \
  -v "/tmp/wechat-devtools-nightly-docker-src:/workspace" \
  "msojocs/wechat-devtools-build:v1.0.6" \
  bash ./tools/setup-wechat-devtools.sh --channel nightly

docker run --rm -i \
  -u "$(id -u):$(id -g)" \
  -w /workspace \
  -v "/tmp/wechat-devtools-nightly-docker-src:/workspace" \
  "msojocs/wechat-devtools-build:v1.0.6" \
  bash ./tools/build-tar.sh v2.02.2606122-1 x86_64

cp /tmp/wechat-devtools-nightly-docker-src/WeChat_Dev_Tools_v2.02.2606122-1_x86_64_linux.tar.gz \
  /tmp/wechat-devtools-nightly-output/
```

## 构建时的问题与解决方案

现有镜像 `msojocs/wechat-devtools-build:v1.0.6` 内部使用 Node `v16.20.2`。如果不固定版本，`npx --yes @electron/rebuild` 会拉取较新的 `@electron/rebuild@4.x`，该版本要求 Node `>=22.12.0`，在 Node 16 下会因为缺少 `node:util` 的 `styleText` 导出而失败。

尝试改用 Node 22 也不适合当前镜像，因为 Ubuntu 18.04 的 glibc 版本过旧，Node 22 官方二进制需要更高版本的 `GLIBC_2.25/2.27/2.28`。

最终可用方案是在 `tools/rebuild-electron-node-modules.sh` 中固定：

```bash
npx --yes @electron/rebuild@3.7.2
```

该版本可以在镜像内的 Node 16/npm 8 环境中完成 Electron 36.6.0 的原生模块重编。

Electron 版本来自 Nightly Windows 安装包中的运行时标识：`Electron/36.6.0`。对应 Node 运行时为 Electron 自带 Node，不要求宿主机安装 Node 才能启动 GUI/CLI。

## 已验证产物

本次隔离 Docker 构建已生成并验证：

- `WeChat_Dev_Tools_v2.02.2606122-1_x86_64_linux.tar.gz`
- 包内包含 `electron/electron`
- 包内包含 `package.electron/app/package.json`
- 包内包含 `package.electron/app/js/electron/main.js`
- 包内包含 `bin/wechat-devtools-nightly`
- 包内包含 `bin/wechat-devtools-cli-nightly`
- 包内包含 `package.electron/app/node_modules/wcc-electron/build/Release/wcc.node`
- 包内包含 `package.electron/app/node_modules/wcc-exec/wcc`

Nightly 启动器不依赖宿主机 Node.js。`APP_NAME` 会优先从 `package.electron/app/package.json` 的 `appname` 字段解析，解析失败时回退到 `wechatwebdevtools`。

## 启动与服务端口

启动 Nightly GUI：

```bash
./WeChat_Dev_Tools_v2.02.2606122-1_x86_64_linux/bin/wechat-devtools-nightly
```

在 Wayland 桌面环境下，Electron Nightly 可能只显示黑色窗口。已验证可用的启动方式是强制使用 X11/Ozone 兼容模式：

```bash
--ozone-platform=x11 --disable-features=UseOzonePlatform
```

这两个参数已经写入 `bin/wechat-devtools-nightly`，正常启动脚本即可。

如果从已打包 tar 解压运行，使用：

```bash
tar -xzf WeChat_Dev_Tools_v2.02.2606122-1_x86_64_linux.tar.gz
./WeChat_Dev_Tools_v2.02.2606122-1_x86_64_linux/bin/wechat-devtools-nightly
```

已验证可见窗口标题包括 `项目列表` / `WeChat Web Devtools`，GUI 可进入项目导入界面。

如果需要使用 CLI，请先在 GUI 中打开服务端口：

1. 打开 Nightly GUI；
2. 进入 `设置`；
3. 进入 `安全设置`；
4. 开启 `服务端口`。

开启后可验证：

```bash
./WeChat_Dev_Tools_v2.02.2606122-1_x86_64_linux/bin/wechat-devtools-cli-nightly islogin
```

CLI 启动器会预创建 Electron CLI 所需的用户目录，避免首次运行时报 `.cli` 路径不存在。服务端口仍必须由 GUI 的安全设置开启，这是微信开发者工具官方安全开关。

## 验证命令

修改 Nightly 相关脚本后，至少执行：

```bash
bash -n bin/wechat-devtools-nightly
bash -n bin/wechat-devtools-cli-nightly
bash -n tools/update-electron.sh
bash -n tools/rebuild-electron-node-modules.sh
node -c tools/parse-config.js
node -c tools/fix-package-name.js
node tools/parse-config.js --channel nightly --get-runtime
node tools/parse-config.js --channel nightly --get-electron-version
```

期望输出：

- runtime 为 `electron`；
- Electron 版本为 `36.6.0`；
- GUI 可显示真实界面，不只是黑色窗口；
- CLI `--help` 可以输出命令列表；
- `islogin` 若提示服务端口关闭，则进入 GUI 手动开启服务端口。

构建完成后，可用以下命令确认没有把构建产物写入当前仓库：

```bash
test ! -d package.electron && test ! -d electron && test ! -d node && test ! -d nwjs && test ! -d package.nw
```
