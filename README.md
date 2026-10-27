# Reverse Pi

基于 [Pi Agent](https://github.com/earendil-works/pi) 定制的个人逆向工程 Agent

## 快速开始

1. 在 Linux 上安装 Pi（仅支持 Linux）。
2. 为 `./pi` 脚本添加可执行权限：`chmod +x ./pi`。
3. 运行 `./pi`。

`./pi` 启动器会从 `workdir/` 运行 Pi，使任务文件集中在该目录，同时仍然应用 `.pi/` 下的仓库配置：会话保存在 `.pi/sessions/`，Skill 从 `.pi/skills` 加载，MCP 服务器从 `.pi/mcp.json` 加载。

## 集成工具 & MCP

- https://github.com/ibotpeaches/apktool
- https://github.com/xjoker/delamain
- https://github.com/HexRaysSA/ida-mcp
