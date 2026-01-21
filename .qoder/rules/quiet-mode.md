---
trigger: model_decision
description: for commands that need to provide a behavior that is quiet (suppressing some verbose output)
---

Standardize quiet output behavior across all suitable CLI commands using `--quiet` and `-q` flags and honor the `HUG_QUIET` environment variable. When enabled, suppress non-essential output, similar to git-h-squash implementation.
Try to reuse function `parse_common_flags` (defined in file `hug-cli-flags`).