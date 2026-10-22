---
name: manage-jadx-mcp
description: Start, stop, restart, and check the JADX MCP server powered by jadx_mcp_server.py. Use this skill whenever an agent needs JADX MCP for reverse engineering, when the MCP service on port 8651 is unavailable, or when the service lifecycle needs to be managed.
license: Apache-2.0
metadata:
  author: Haicaji
  version: "1.1"
---

# JADX MCP

Manage the JADX MCP service through the scripts bundled with this Skill.

The MCP server uses port `8651`. It talks to the JADX-GUI MCP plugin on port `8650`.

The bundled start script also launches JADX-GUI with the target APK/DEX files when a target directory is passed; the bundled stop script stops both the MCP server and the JADX-GUI instance it launched.

## Rules

- Use the bundled scripts to manage the service.
- Do not reconstruct the check, start or stop commands manually.
- Do not inspect the scripts unless troubleshooting an actual script failure.
- Do not start duplicate instances.
- Do not stop the service unless needed or explicitly requested.
- Resolve scripts' path relative to this Skill. Do not `cd` into the Skill directory before executing it.

## Check status

Execute the bundled script:

```text
scripts/check-jadx-mcp.sh
```

## Start

Execute the bundled script with an optional target directory containing `*.apk` / `*.dex` files:

```text
scripts/start-jadx-mcp.sh [TARGET_DIR]
```

When `TARGET_DIR` is given, all `*.apk` and `*.dex` files inside it are opened in JADX-GUI automatically. Pass a directory whenever the user provides one.

The bundled script handles:

- duplicate-instance checking
- temporary-directory creation
- logging
- background process startup
- PID management
- startup verification
- optional JADX-GUI launch with all `*.apk` / `*.dex` files from `TARGET_DIR`

## Stop

Execute the bundled script:

```text
scripts/stop-jadx-mcp.sh
```

## Restart

Restart the service only when:

- the user explicitly requests a restart; or
- recovery from a real service failure requires it.

Execute the bundled stop script first:

```text
scripts/stop-jadx-mcp.sh
```

Then execute the bundled start script (pass the target directory again if one was used):

```text
scripts/start-jadx-mcp.sh [TARGET_DIR]
```

## Failure handling

If a bundled script exits with an error:

- Read the error output produced by the script.
- Report the actual failure.
- Do not modify the bundled scripts unless the user explicitly asks to debug or change them.
