---
name: manage-delamain
description: 安装、启动、停止、检查、更新并使用 delamain（headless JADX MCP 服务器），用于 Android APK/DEX 逆向分析。当 Pi 需要 Android 反编译、代码或资源搜索、交叉引用、Frida hook 生成，或 8651 端口上的 Delamain MCP 不可用时使用本 Skill。
license: MIT
metadata:
  author: Haicaji
  version: "1.1"
---

# delamain（JADX MCP）

delamain 是单 Docker 容器部署的 headless JADX MCP 服务器。MCP 端点：`http://127.0.0.1:8651/mcp`。

持久化状态位于 `tools/delamain/`。APK/DEX 从仓库的 `workdir/apks/` 挂载到容器内 `/apks`。

## 规则

- 使用本 Skill 自带的脚本，不要手动拼装 `docker run` 或 `docker compose` 命令。
- 查看容器日志直接执行 `docker logs reverse-pi-delamain --tail 200`（需要跟随输出时加 `-f`），不需要额外的脚本封装。
- 镜像跟随上游 `ghcr.io/xjoker/delamain:latest`。升级前先运行 `scripts/check-update-delamain.sh` 检查更新；需要临时固定版本时用 `DELAMAIN_IMAGE` 覆盖，不要修改脚本内置默认值，也不要用其他来源的镜像。
- 不要启动、停止或删除用户自己拥有的容器。本 Skill 只管理名为 `reverse-pi-delamain` 的容器。
- 不要打印、回显或粘贴 MCP bearer token。
- 除非用户明确要求调试或修改本 Skill，否则不要改动自带脚本。

## 检查运行

安装或启动前先运行：`scripts/check-delamain.sh`

退出码：

- `0`：容器运行中，`/health` 正常，MCP `tools/list` 可调用。
- `1`：容器、健康检查或 MCP 异常（查看脚本打印的日志路径）。
- `10`：Docker 守护进程不可访问。

## 安装或更新

执行 `scripts/install-delamain.sh [APK_DIR]`

`APK_DIR` 默认为 `workdir/apks/`。脚本会：

- 检查 Docker/Compose；守护进程不可访问时直接拒绝执行；
- 创建 `tools/delamain/` 和 APK 目录；
- 生成或复用 MCP bearer token；
- 以 `0600` 权限写入 `tools/delamain/.env` 和 `.pi/secrets/delamain.auth`；
- 在 `.pi/mcp.json` 中**添加或更新** `Delamain` 条目，保留其它已有 MCP 条目；修改前备份到 `tools/delamain/backups/`；
- 拉取 `latest` 镜像并启动容器，镜像有更新时重建容器；
- 等待 `/health`，确认未认证的 `/mcp` 返回 `401`，并验证认证后的 `tools/list`。

可用选项：`--apk-dir DIR`、`--rotate-token`、`--no-pull`、`--force`。

### 检查更新

执行 `scripts/check-update-delamain.sh`

退出码：

- `0`：本地镜像与上游 `latest` 一致，且容器正在使用该镜像。
- `20`：有可更新的镜像（本地未安装、上游有新版本，或容器仍运行旧镜像）。
- `1`：检查失败（通常是无法访问镜像仓库）。
- `10`：Docker 守护进程不可访问。

有更新时重新运行 `scripts/install-delamain.sh` 即可升级：脚本会拉取 `latest` 并重建使用旧镜像的容器，token、APK 目录和索引都会保留。

## 启动、停止与更新检查

```text
scripts/start-delamain.sh
scripts/stop-delamain.sh
scripts/check-update-delamain.sh [--quiet]
```

## 调用分析

1. 将目标 APK/DEX 放入 `workdir/apks/`。
2. 通过 Delamain MCP 调用 `list_available_files_tool` 查看可用文件，也可以直接调用 `load_file_tool`。
3. 调用 `load_file_tool(path="app.apk")` 加载目标。路径相对于容器内 `/apks`，因此只需填写文件名或 `workdir/apks/` 下的子目录。
4. 轮询 `get_decompile_status()` 直到就绪。大 APK 在进行重度搜索前还应检查 `get_warmup_status()`。
5. 按需使用 `search_classes_by_keyword`、`get_class_source`、`get_xrefs`、资源工具以及 Frida/安全分析工具。
6. 通过 MCP 调用 `get_jadx_guide(verbose=True)`，获取当前版本权威的工作流和工具列表。delamain 的工具名和参数可能随版本变化。

如果工具返回内容被截断，或 `decompile_quality` 信号较低，应缩小查询范围或回退到 smali/反编译诊断，不要盲目重复调用。

## 故障处理

delamain 使用过程中遇到问题, 直接停止任何操作, 向用户反馈问题, 让用户判断解决