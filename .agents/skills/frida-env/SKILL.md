---
name: frida-env
description: Set up the environment for Frida
license: Apache-2.0
metadata:
  author: Haicaji
  version: "1.0"
---

---
name: frida-env
description: Set up the environment for Frida
license: Apache-2.0
metadata:
  author: Haicaji
  version: "1.0"
---

# Frida Environment

The following environment must be used to run Frida on this machine.

## Frida Client

The `frida` Miniconda environment must be used. Activate it with:

```bash
conda activate frida
```

Only after activating this environment should you run commands such as `frida` and `frida-ps`.

## Frida Server

The `frida-server` version matching the one installed in the Miniconda environment is located under `$HOME/Program/Frida`. If it cannot be found, please report it.

If `frida-server` is not present in `/data/local/tmp/` on the device, upload it to the device, grant it executable permissions, and then start it.

## Notes

- If there is a version mismatch between the Frida Client and Frida Server, please report it.