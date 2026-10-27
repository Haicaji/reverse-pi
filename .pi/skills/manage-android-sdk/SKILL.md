---
name: manage-android-sdk
description: 安装、检测、更新、卸载 Android SDK（Command-line Tools + platform-tools + Build Tools）。当需要确认 Android SDK 是否已安装、在用户指定路径安装 SDK、接受 SDK 许可证、更新 SDK 组件、卸载组件，或配置 ANDROID_HOME/PATH 以便使用 adb、aapt、aapt2、apksigner、zipalign、sdkmanager 时使用本 Skill。
license: MIT
metadata:
  author: Haicaji
  version: "1.0"
---

# Android SDK（命令行工具）

本 Skill 使用 Google 官方 Command-line Tools（`sdkmanager`）安装并维护 Android SDK，不安装 Android Studio，也不使用 apt 管理 Android SDK。

| 工具 | 用途 |
| --- | --- |
| `adb` | 连接 Android 设备、安装 APK、调试 |
| `aapt` | 查看 APK 包名、版本、资源信息 |
| `aapt2` | Android 资源编译与链接 |
| `apksigner` | APK 签名与验证 |
| `zipalign` | APK 文件布局优化 |
| `sdkmanager` | 安装、更新和管理 SDK 组件 |

**SDK 安装位置由用户决定。** 本 Skill 不假定 `~/Android/Sdk`，也不使用其他默认路径。

## 规则

- SDK 路径必须以用户指定为准：先运行 `check-android-sdk.sh`；若返回 `10`，**必须询问用户**希望安装到哪个目录，禁止自行编造路径。
- 安装、更新、卸载只使用本 Skill 自带脚本，不要手写 `sdkmanager` 命令。
- 不安装 JDK、`curl`、`unzip` 等系统依赖；缺失时停止操作并报告用户。
- 不使用 `sudo`，不修改 SDK 目录以外的系统文件。
- 除 `uninstall-android-sdk-package.sh --confirm` 的包级卸载外，不删除 SDK 目录内容；严禁对用户目录执行 `rm -rf`。
- 默认不自动接受 Android SDK 许可证；只有用户同意后才传 `--accept-licenses`。
- 环境变量写入用户 shell 配置（默认 `~/.bashrc`）的托管块；修改前自动备份，只替换托管块内容，不改动其他行（`--replace-legacy` 除外，它会把冲突的 Android 环境变量行注释掉）。
- 下载只允许来自 `https://dl.google.com/android/repository/`（仓库索引与官方压缩包）。
- 除非用户明确要求调试本 Skill，否则不要修改自带脚本。

## 运行状态

本 Skill **不创建任何状态目录**（不会在仓库生成 `tools/android-sdk`，也不会创建缓存目录或日志目录）。

| 位置 | 说明 |
| --- | --- |
| 用户 shell 配置（默认 `~/.bashrc`）的托管块 | 唯一的持久记录：`ANDROID_HOME` 等环境变量，也是后续查找 SDK 的路径来源 |
| `${TMPDIR:-/tmp}/android-sdk-*` | 仓库索引与 `sdkmanager` 输出等临时文件；成功即删除，失败时保留并在输出中打印路径 |
| SDK 内 `cmdline-tools/latest.bak.*` | 替换 Command-line Tools 时在其旁边生成的备份 |

仓库索引每次都重新下载（约几 MB），不落地缓存。托管块所在文件可用 `--bashrc FILE` 或 `ANDROID_SDK_BASHRC` 指定，查找 SDK 时也从同一个文件读取。

环境变量**不存放在仓库或 Pi 专属文件里**，而是写入用户 shell 配置（默认 `~/.bashrc`）的托管块：

```bash
# >>> reverse-pi android-sdk >>>
export ANDROID_HOME="/path/to/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/<ver>:$PATH"
# <<< reverse-pi android-sdk <<<
```

## 路径解析顺序

1. 命令行 `--sdk-root PATH`
2. 用户 shell 配置（默认 `~/.bashrc`）托管块中的 `ANDROID_HOME`，且目录仍存在
3. `ANDROID_SDK_ROOT` / `ANDROID_HOME` 且目录存在

以上都不可用时返回 `10`，并提示向用户询问路径。因此运行 `install-android-sdk.sh` 前，先确认用户已经给出了目标目录。

## 检查是否安装

执行：`scripts/check-android-sdk.sh [--sdk-root PATH]`

只读检测，打印 JDK、SDK 根目录、`sdkmanager`、`adb`、`build-tools` 及 `aapt/aapt2/apksigner/zipalign` 的版本与绝对路径。

| 退出码 | 含义 |
| --- | --- |
| `0` | SDK 可用，核心工具齐全 |
| `1` | SDK 存在，但缺少 platform-tools 或 build-tools 等组件 |
| `10` | 未配置 / 未安装 SDK（需要询问用户安装路径） |
| `11` | JDK 缺失或低于 17 |

## 安装

首次安装（路径由用户给出）：

```bash
scripts/install-android-sdk.sh --sdk-root "/home/<user>/Android/Sdk" --accept-licenses
```

安装成功后脚本会**自动**把 `ANDROID_HOME`/`ANDROID_SDK_ROOT`/`PATH` 写入 `~/.bashrc`，无需再单独执行配置脚本。

脚本依次执行：

1. 检查 JDK 17+、`curl`、`unzip`、`sha1sum` 等；
2. 解析并创建用户指定的 SDK 目录（不写 SDK 以外位置）；
3. 下载 Google 仓库索引，解析 `cmdline-tools;latest` 的版本、大小、SHA-1；
4. 下载官方 ZIP、校验 SHA-1、解压到 `cmdline-tools/latest`（不会多套一层 `cmdline-tools` 目录）；
5. 按需接受许可证（仅 `--accept-licenses`）；
6. 安装组件（默认 `platform-tools` + 最新稳定 `build-tools`）；
7. 验证工具、写入 shell 配置（`~/.bashrc` 托管块，同时作为路径记录）。

默认组件：

- `platform-tools`：提供 `adb`；
- `build-tools;<最新稳定版>`：提供 `aapt`、`aapt2`、`apksigner`、`zipalign`；
- 默认**不安装** `platforms;android-XX`，纯 APK 分析不需要；确需编译时用 `--platform latest` 或 `--platform 36`。

| 选项 | 说明 |
| --- | --- |
| `--sdk-root PATH` | 用户指定的 SDK 目录（首次必须） |
| `--build-tools VERSION` | `latest`（默认）、`none` 或具体版本，如 `36.0.0` |
| `--platform API` | `latest`、`none`（默认）或 `36` / `android-36` |
| `--components "PKG ..."` | 追加组件，如 `"emulator"`；逗号或空格分隔 |
| `--accept-licenses` | 向 `sdkmanager --licenses` 自动输入 `y`（需用户同意） |
| `--bashrc FILE` | 要写入的 shell 配置文件，默认 `~/.bashrc` |
| `--replace-legacy` | 更新配置时把冲突的非托管 `ANDROID_HOME`/`ANDROID_SDK_ROOT`/`PATH` 行注释掉 |
| `--no-write-shell` | 不修改 shell 配置（不留下任何记录） |
| `--skip-cmdline-tools` | 不下载/替换 Command-line Tools |
| `--skip-packages` | 只安装 Command-line Tools |
| `--skip-platform-tools` | 不装 `platform-tools` |
| `--force` | 版本相同也重新安装 Command-line Tools |
| `--dry-run` | 只打印计划，不写入 SDK 目录 |

说明：

- Command-line Tools 下载约 170 MB，来自官方仓库；ZIP 的 SHA-1 会与仓库索引比对。
- 替换已有的 `cmdline-tools/latest` 前会重命名为 `latest.bak.<时间>-<PID>`，确认新版本可用后不自动删除备份；空间不足时由用户决定清理。
- 组件版本不写死：`latest` 从 Google 仓库索引解析，避免文档中的 `36.0.0` 之类版本过期。

## 许可证

`sdkmanager` 安装组件前需要接受 Android SDK License。未传 `--accept-licenses` 时脚本会跳过该步骤并警告；若安装因许可证失败，脚本以 `13` 退出。此时先向用户确认，再加 `--accept-licenses` 重试，不要绕过。

## 环境变量与 PATH

**安装/更新后环境变量已写入 `~/.bashrc`**，新开终端即生效；当前终端执行：

```bash
source ~/.bashrc
```

托管块之外的旧配置（例如自己手写的 `export ANDROID_HOME=...`）会与托管块冲突，需要时用 `--replace-legacy` 注释掉：

```bash
scripts/configure-android-sdk-shell.sh --sdk-root "/home/<user>/Android/Sdk" --replace-legacy
```

单独维护 shell 配置时：

```bash
scripts/configure-android-sdk-shell.sh [--sdk-root PATH] [--bashrc FILE] [--print] [--replace-legacy]
```

- 默认**直接写入** `~/.bashrc`（先备份、生成带标记的托管块、`bash -n` 校验）；
- `--print` 只打印要写入的内容；
- 内容与现有文件一致时不做任何修改（幂等，不产生多余备份）。

需要在不读取 shell 配置的非交互环境（例如 agent 的一次性 bash 调用、CI）中使用时，可显式加载：

```bash
eval "$(.pi/skills/manage-android-sdk/scripts/env-android-sdk.sh --sdk-root "/home/<user>/Android/Sdk")"
```

脚本只向 stdout 输出 `ANDROID_HOME`、`ANDROID_SDK_ROOT`、`PATH`，诊断信息走 stderr，可安全 `eval`。这只是辅助手段，日常使用以 `~/.bashrc` 为准。

## 日常更新

```bash
scripts/update-android-sdk.sh [--sdk-root PATH] [--accept-licenses] [--dry-run]
```

- 比较已安装 Command-line Tools 与 Google 仓库最新版本；有更新时重新下载并校验安装（保留备份）。
- 执行 `sdkmanager --update` 更新已安装组件。
- 结束后自动运行 `check-android-sdk.sh`（以其退出码返回），并刷新 `~/.bashrc` 托管块（`--no-write-shell` 可跳过）。
- `--cmdline-tools-only` / `--packages-only` 可只执行其中一步。

安装新版 Build Tools（可与旧版并存）：

```bash
scripts/install-android-sdk.sh --sdk-root "/home/<user>/Android/Sdk" --build-tools 36.0.0
```

安装后 `~/.bashrc` 托管块会自动指向最新安装的 Build Tools（`build-tools/<版本>` 已加入 PATH）。

## 查看与卸载组件

```bash
scripts/list-android-sdk-packages.sh [--all]
```

默认只列已安装组件（`sdkmanager --list_installed`），`--all` 列出已安装与可安装组件。

卸载某个组件（必须先获得用户同意，`--confirm` 为必填）：

```bash
scripts/uninstall-android-sdk-package.sh --confirm "build-tools;36.0.0"
```

- 脚本会先确认组件确实已安装，再调用 `sdkmanager --uninstall`，最后复核。
- 拒绝卸载 `cmdline-tools;*`（会导致 `sdkmanager` 不可用）。
- 若要彻底移除整个 SDK，只能由用户自行删除其指定目录；本 Skill 不执行整目录删除。

## 故障处理

遇到问题立即停止后续操作，把脚本输出和日志路径反馈给用户，由用户决定处理方式。

| 现象 | 处理 |
| --- | --- |
| 退出码 `11`（Java） | 用户需要 JDK 17+（`sdkmanager` 依赖）。本 Skill 不安装 JDK；用户坚持使用低版本时可显式设置 `ANDROID_SDK_MIN_JAVA` 后重试 |
| 退出码 `12`（命令缺失） | 缺少 `curl`/`unzip`/`sha1sum` 等，由用户准备 |
| 退出码 `13`（许可证） | 先取得用户同意，再传 `--accept-licenses` |
| 退出码 `14`（目录权限） | 目录无法创建或不可写；本 Skill 不使用 `sudo`，由用户处理权限 |
| 下载或 SHA-1 校验失败 | 检查网络/代理后重试（仓库索引每次都会重新下载，无需清缓存） |
| `sdkmanager` 输出了 deprecation 警告 | Command-line Tools 23.0 起 `sdkmanager` 是 Android CLI 的包装，警告正常；脚本仍会检查输出中的 `not found` 等错误，不只看退出码 |
| 找不到 `android`/`avdmanager` 等 | 属于 Command-line Tools 自带命令，确认 `cmdline-tools/latest/bin` 在 PATH 中 |
| `adb devices` 无设备 | 检查 USB 调试授权、数据线、udev 权限；设备问题由用户处理 |
| 托管块中的路径失效 | 脚本会忽略 `~/.bashrc` 托管块里不存在的路径并返回 `10`，重新询问用户路径 |

## 退出码汇总

| 退出码 | 含义 |
| --- | --- |
| `0` | 成功 |
| `1` | 参数错误、下载失败、`sdkmanager` 报错，或组件不完整 |
| `10` | 未确定/未安装 SDK 路径（需要询问用户） |
| `11` | JDK 缺失、过低，或 `sdkmanager` 无法运行 |
| `12` | 缺少基础命令 |
| `13` | SDK 许可证未接受 |
| `14` | SDK 目录无法创建或不可写 |

## 推荐流程

首次安装：

1. `check-android-sdk.sh`；
2. 返回 `10` 时询问用户安装目录（不要替用户决定）；
3. 取得用户对许可证的同意后运行 `install-android-sdk.sh --sdk-root ... --accept-licenses`（脚本会自动写入 `~/.bashrc`，旧配置冲突时加 `--replace-legacy`）；
4. 验证：`bash -lc 'adb version; aapt2 version; apksigner --version; sdkmanager --version'`，或 `eval "$(env-android-sdk.sh --sdk-root ...)"` 后直接运行工具；
5. 告知用户 `source ~/.bashrc` 或新开终端即可生效。

日常更新：

1. `check-android-sdk.sh` 确认现状；
2. `update-android-sdk.sh` 更新 Command-line Tools、已安装组件与 `~/.bashrc` 托管块；
3. 需要新版本 Build Tools 时再运行 `install-android-sdk.sh --build-tools <version>`。
