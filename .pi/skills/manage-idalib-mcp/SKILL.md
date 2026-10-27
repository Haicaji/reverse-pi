---
name: manage-idalib-mcp
description: Start, stop, restart, and check the IDAlib MCP server powered by idalib-mcp. Use this skill whenever an agent needs IDAlib MCP for reverse engineering, when the MCP service on port 13336 is unavailable, or when the service lifecycle needs to be managed.
license: Apache-2.0
metadata:
  author: Haicaji
  version: "1.1"
---

# IDAlib MCP

Manage the IDAlib MCP service through the scripts bundled with this Skill.

The MCP server uses port `13336`.

## Configuration

The server port is configured in the `[idalib]` table of the repository root `config.toml` (`port`). Values are read only from `config.toml`; environment variables do not override them.

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
scripts/check-idalib-mcp.sh
```

## Start

Execute the bundled script:

```text
scripts/start-idalib-mcp.sh
```

The bundled script handles:

- duplicate-instance checking
- temporary-directory creation
- logging
- background process startup
- PID management
- startup verification

## Stop

Execute the bundled script:

```text
scripts/stop-idalib-mcp.sh
```

## Restart

Restart the service only when:

- the user explicitly requests a restart; or
- recovery from a real service failure requires it.

Execute the bundled stop script first:

```text
scripts/stop-idalib-mcp.sh
```

Then execute the bundled start script:

```text
scripts/start-idalib-mcp.sh
```

## Failure handling

If a bundled script exits with an error:

- Read the error output produced by the script.
- Report the actual failure.
- Do not modify the bundled scripts unless the user explicitly asks to debug or change them.
