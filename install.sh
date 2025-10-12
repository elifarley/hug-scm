#!/usr/bin/env bash
CMD_BASE="$(readlink -f "$0" 2>/dev/null || greadlink -f "$0")" || CMD_BASE="$0"; CMD_BASE="$(dirname "$CMD_BASE")"
set -euo pipefail  # Exit on error, undefined vars, pipe failures

"$CMD_BASE"/git-config/install.sh "$@"
