---
name: manage-idapromcp
description: 检测、安装、升级并运行 IDA Pro MCP（官方 Hex-Rays ida-mcp）。当需要检查 ida-mcp 是否安装或版本、查询 ida-mcp 位置、通过 pip/GitHub 安装或升级 ida-mcp、启动/停止 HTTP 服务，或把 IDA MCP 注册到 .pi/mcp.json 时使用本 Skill。
license: MIT
metadata:
  author: Haicaji
  version: "1.0"
---

# IDA Pro MCP（ida-mcp）

ida-mcp 是 Hex-Rays 官方的 IDA MCP 服务器，通过 idalib 以无头方式运行，安装于 Python 环境，而不是 `tools/` 目录。

## 规则

- 只使用本 Skill 自带脚本管理 ida-mcp，不要手动拼装 `pip install` 命令。
- 缺少 Python 3.11+/pip/git 时停止操作并报告用户，不要自行安装运行时。
- 只写入用户指定的 Python 环境；不要修改系统 Python 或 PATH。
- 不要读取、打印或粘贴 `idapro.hexlic`、`ida.reg` 等许可证内容。
- HTTP 服务只管理命令行匹配 `ida-mcp http` 且端口一致的进程（本 Skill 启动或接管的进程）；停止前会校验 PID 文件与进程命令行。不要结束其他进程，也不要使用 `pkill`/`killall`。
- 除非用户明确要求调试本 Skill，否则不要修改自带脚本。

## 运行时状态

PID 文件位于 `tools/ida-mcp/`：

- `tools/ida-mcp/ida-mcp.pid`：HTTP 服务 PID

默认监听 `127.0.0.1:8737`，MCP 端点为 `http://127.0.0.1:8737/mcp`。

## 前置条件

- IDA Pro 9.4 或更高版本，且包含 idalib。
- Python 3.11 或更高版本，并带有 pip。
- Git、curl 与 jq（GitHub 安装、检查更新、HTTP 健康检查和写入 `.pi/mcp.json` 时使用）。

## 检测 IDA Pro

执行：`scripts/check-idapro.sh`

脚本以 `~/.idapro/` 是否存在作为 IDA Pro 是否安装判断依据。

| 退出码 | 含义 |
| --- | --- |
| `0` | 已检测到 IDA Pro |
| `10` | 未检测到 IDA Pro |

检测失败时停止后续操作，把脚本输出反馈给用户

## 检测 ida-mcp

执行：`scripts/check-idamcp.sh`

脚本检查当前 Python 环境中的 `ida-mcp` 包、入口命令和模块导入，并打印 Python 解释器路径。

| 退出码 | 含义 |
| --- | --- |
| `0` | 已安装 |
| `10` | 未安装 |
| `12` | Python 解释器缺失或低于 3.11 |

默认使用 `python3`。需要检查其他环境时设置 `IDA_MCP_PYTHON`：

```bash
IDA_MCP_PYTHON=/path/to/python scripts/check-idamcp.sh
```

## 检查上游更新

执行：`scripts/check-update-idamcp.sh`

脚本把已安装版本与上游 `main` 分支 `pyproject.toml` 中的版本比较。

| 退出码 | 含义 |
| --- | --- |
| `0` | 已是最新（或已安装版本高于上游 main） |
| `20` | 有新版本，执行 `scripts/install-idamcp.sh` 升级 |
| `10` | 尚未安装 |
| `12` | Python 解释器缺失或低于 3.11 |
| `1` | 无法访问 GitHub 读取上游版本 |

## 安装或升级

执行：`scripts/install-idamcp.sh [--ref REF] [--python PATH] [--force] [--no-register]`

脚本依次执行：

1. 调用 `scripts/check-idapro.sh` 检测 IDA Pro，未通过则退出 `11`；
2. 检查 Python 版本、pip 和 git，缺失时退出 `12` 或 `1`；
3. 执行 `python -m pip install --upgrade git+https://github.com/HexRaysSA/ida-mcp.git`；
4. 校验安装后的版本和 `ida-mcp` 入口命令；
5. 在 `.pi/mcp.json` 中添加或更新 `IDA` 条目（保留其他 MCP 服务器）。

选项：

- `--ref REF`：安装指定分支、标签或提交，默认 `main`。
- `--python PATH`：指定接收 ida-mcp 的 Python 解释器，默认 `python3`。
- `--force`：已是最新时也强制重装。
- `--no-register`：只安装，不修改 `.pi/mcp.json`。

pip 报告错误时不要绕过限制；停止操作并反馈给用户，由用户决定。

## 启动 HTTP 服务

执行：`scripts/start-idamcp-http.sh`

脚本在后台启动：

```text
ida-mcp http --host 127.0.0.1 --port 8737
```

启动后轮询 MCP `initialize` 请求，确认服务真正可用才返回成功。PID 写入 `tools/ida-mcp/ida-mcp.pid`，服务输出不保存。

| 退出码 | 含义 |
| --- | --- |
| `0` | 已运行且 MCP 可调用 |
| `10` | 未安装 ida-mcp |
| `12` | 缺少 `ss`/`curl`，或 Python 不可用 |
| `1` | 端口被其他进程占用，或启动失败 |

遇到端口冲突, 直接通知用户, 让用户处理

## 检查 HTTP 服务

执行：`scripts/check-idamcp-http.sh`

确认进程、端口和 MCP `initialize` 均正常。退出码 `0` 表示可用，`1` 表示未运行或不可用，`12` 表示缺少 `ss`/`curl`。

## 停止 HTTP 服务

执行：`scripts/stop-idamcp-http.sh`

只停止命令行同时包含 `ida-mcp`、`http` 和当前端口的进程；未运行时返回 `0`。

## 故障处理

遇到 pip 安装失败、IDA 未检测到、idalib 加载失败、端口冲突或 `ida-mcp` 启动等报错时，停止后续操作，把错误反馈给用户，由用户决定处理方式。
