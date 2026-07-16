#!/usr/bin/env bash
# Resolves a Linode API token for the "linode" provider, in this order:
#   1. LINODE_TOKEN environment variable (documented, primary mechanism).
#   2. The default user's token in ~/.config/linode-cli (linode-cli's own
#      config file), so a machine that already has `linode-cli configure`'d
#      does not need a separate export.
#
# Outputs a JSON object {"token": "..."} for the "external" data source.
# Emits {"token": ""} (never fails) when no token can be found, so `tofu
# validate`/`plan` in CI (no LINODE_TOKEN, no linode-cli config) still works;
# the linode provider will simply error clearly later if a token is actually
# required for the operation being run.
set -euo pipefail

if [ -n "${LINODE_TOKEN:-}" ]; then
  printf '{"token":"%s"}\n' "${LINODE_TOKEN}"
  exit 0
fi

CONFIG_FILE="${HOME}/.config/linode-cli"

if [ -f "${CONFIG_FILE}" ]; then
  TOKEN="$(python3 - "$CONFIG_FILE" <<'PY'
import configparser
import sys

config_file = sys.argv[1]
parser = configparser.ConfigParser()
parser.read(config_file)

default_user = parser.get("DEFAULT", "default-user", fallback=None)
if default_user and parser.has_section(default_user):
    print(parser.get(default_user, "token", fallback=""))
PY
)"
  if [ -n "${TOKEN}" ]; then
    printf '{"token":"%s"}\n' "${TOKEN}"
    exit 0
  fi
fi

printf '{"token":""}\n'
