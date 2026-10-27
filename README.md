# Reverse Pi

A customized [Pi Agent](https://github.com/earendil-works/pi) tailored to my personal reverse engineering workflow.

## Quick Start

1. Install Pi on Linux (Linux is required).
2. Review `config.toml` and adjust the tool paths and ports for your machine.
3. Make the `./pi` script executable: `chmod +x ./pi`.
4. Run `./pi`.

The `./pi` launcher runs Pi from `workdir/` so task files stay there, while the repository settings under `.pi/` are still applied: sessions are stored in `.pi/sessions/`, skills are loaded from `.pi/skills`, and MCP servers are loaded from `.pi/mcp.json`.

## Configuration

User-editable tool paths and service settings for the bundled skills live in the repository-level [`config.toml`](./config.toml):

Scripts read these values only from `config.toml`; environment variables do not override them. Values absent from the file fall back to built-in defaults. Path values may start with `~/`.

If `config.toml` is missing, the skill scripts exit with an error. Each skill's `scripts/config.sh` contains the same inline TOML reader, which supports tables, bare keys, strings, integers, booleans and comments. If you change a service port, update `.pi/mcp.json` to match.

## Features

* Automatically launches reverse engineering tools and supports MCP integration (in progress).
* Standardizes the reverse engineering workflow (in progress).
* Runs from `workdir/` and stores session history under `.pi/sessions/`. (easy cleanup of reverse engineering records?)

## Planned Features

* Automatic installation of required dependencies. (Maybe it's not necessary?)manage
