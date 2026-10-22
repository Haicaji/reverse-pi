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

## Requirements

- `python3` (or `PYTHON` in `config.sh`), `ss`, and a working `java` for JADX-GUI.
- JADX-GUI needs a real graphical session (`DISPLAY` / `WAYLAND_DISPLAY`). Headless hosts are not supported.
- The GUI is launched with snap-runtime pollution removed automatically: snap-packaged terminals (VS Code, Chromium, ...) export `GTK_PATH`, `GTK_EXE_PREFIX`, `GTK_IM_MODULE_FILE`, `GIO_MODULE_DIR`, `LOCPATH`, ... pointing into `/snap/`, which makes any external JVM die with `symbol lookup error: .../libpthread.so.0: undefined symbol: __libc_pthread_init`. Do not "fix" this by exporting `LD_LIBRARY_PATH`; the script already strips every `/snap/` path fragment before starting JADX-GUI.

## Runtime state

Logs and PID files live in `${XDG_STATE_HOME:-~/.local/state}/jadx-mcp`, independent of the current directory, so `start`, `check` and `stop` can be run from anywhere.

Environment knobs (all optional):

- `JADX_MCP_STATE_DIR` – override the state/log directory.
- `JADX_GUI_START_TIMEOUT` – seconds to wait for the plugin port (default `240`).
- `JADX_GUI_ENV_KEEP` – space-separated variables that must never be scrubbed.

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

- duplicate-instance checking (both the MCP server and the JADX-GUI plugin port)
- snap-environment scrubbing before the GUI starts
- java preflight checks
- temporary-directory creation
- logging
- background process startup in its own session (`setsid`) so it can be stopped reliably
- PID management
- startup verification: it waits until the JADX AI MCP plugin on port `8650` actually accepts connections, and dumps the GUI log tail if it does not
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

- Read the error output produced by the script; it prints the failing layer and the relevant log tail.
- `start-jadx-mcp.sh` only reports success when **both** ports are served: `8651` (MCP server) and `8650` (JADX AI MCP plugin inside JADX-GUI).
- Do not modify the bundled scripts unless the user explicitly asks to debug or change them.

Common failures:

| Symptom | Cause / action |
| --- | --- |
| `java: symbol lookup error ... GLIBC_PRIVATE` | snap-injected GTK/LD paths. Should no longer happen; if it does, check `JADX_GUI_ENV_KEEP` and start from a non-snap terminal. |
| `Error: JADX-GUI exited during startup` | See the printed GUI log tail; usually a bad APK path or an incompatible JDK. |
| `did not open port 8650 within Ns` | APK is very large or the plugin is disabled in JADX-GUI preferences. Raise `JADX_GUI_START_TIMEOUT`. |
| `no DISPLAY` / `HeadlessException` in the GUI log | JADX-GUI needs a graphical session; headless hosts are unsupported. |
| `JADX-GUI MCP plugin is already serving` | Another instance owns port `8650`; run the stop script first. |
