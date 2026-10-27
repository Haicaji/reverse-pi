---
name: manage-apktool
description: 检测、安装、更新 apktool。当需要确认 tools 中是否已安装 apktool、检查 apktool 版本、查询 apktool 位置，或下载/升级 apktool、对 APK 执行 d/b 反编译回编译时使用本 Skill。
license: MIT
metadata:
  author: Haicaji
  version: "1.0"
---

# apktool（APK 反编译/回编译）

apktool 以仓库本地工具的形式安装在 `tools/apktool/`

## 安装位置

`tools/apktool/apktool.jar`: apktool 主程序，来自 GitHub Releases
`tools/apktool/VERSION`: 已安装版本号

调用方式：`java -jar tools/apktool/apktool.jar <子命令>`。

## 规则

- 只使用本 Skill 自带脚本管理 apktool
- 只写入 `tools/apktool/`，不要修改 PATH、shell 配置或系统目录。
- apktool 缺少 Java 时停止操作并向用户报告，不要自行安装 JDK。
- 除非用户明确要求调试本 Skill，否则不要修改自带脚本。

## 检查是否安装及版本

apktool 位于 `tools/apktool/apktool.jar`。确认安装并读取版本：

```bash
test -f tools/apktool/apktool.jar && java -jar tools/apktool/apktool.jar --version
```

## 检查上游版本

执行：`scripts/check-update-apktool.sh`

| 退出码 | 含义 |
| --- | --- |
| `0` | 已是最新（或本地版本高于最新发布） |
| `20` | 有新版本，执行 `scripts/install-apktool.sh` 升级 |
| `10` | 尚未安装 |
| `1` | 无法访问 GitHub Releases |

## 安装或更新

执行：`scripts/install-apktool.sh [--version VERSION] [--force]`

- 默认安装 GitHub 最新 release：`https://github.com/iBotPeaches/Apktool/releases/latest`。
- `--version 3.0.3` 可固定版本，`--force` 强制重装当前版本。

## 故障处理

遇到 Java 缺失、下载失败或 apktool 运行报错时，停止后续操作，把脚本输出的错误信息以及当前 apktool 位置、版本反馈给用户，由用户决定处理方式。
