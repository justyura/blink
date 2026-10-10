#!/bin/bash
#
# Blink Pro: push this Mac's SSH config, the keys it references and known_hosts
# to Blink Pro on an iPad/iPhone, then import them there with `ssh-import`.
#
# Usage: tools/sync-ssh-to-ipad.sh [--device <name|udid>] [--bundle-id <id>] [--no-keys]
#
# Requires Xcode (xcrun devicectl) and a device paired with this Mac.
# The files land in the app's Documents/ssh-sync folder; run `ssh-import`
# inside Blink Pro to finish (it moves the config to ~/.ssh and puts the keys
# in the keychain, then deletes the private key files from the sync folder).
#
set -euo pipefail

DEVICE="${BLINKPRO_DEVICE:-}"
BUNDLE_ID="${BLINKPRO_BUNDLE_ID:-com.yura.blinkpro}"
WITH_KEYS=1
SSH_DIR="$HOME/.ssh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --no-keys) WITH_KEYS=0; shift ;;
    -h|--help) sed -n 2,13p "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$DEVICE" ]]; then
  # Pick the first paired iPad/iPhone.
  DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/iPad|iPhone/ { for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-/) { print $i; exit } }')
  [[ -n "$DEVICE" ]] || { echo "No paired device found. Pass --device <udid>." >&2; exit 1; }
fi

[[ -f "$SSH_DIR/config" ]] || { echo "$SSH_DIR/config not found" >&2; exit 1; }

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/blinkpro-ssh-sync.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

# Rewrite the config for Blink:
#  - IdentityFile ~/.ssh/<name> becomes IdentityFile <name> (Blink resolves it from its keychain)
#  - Include lines are dropped (their targets usually point at Mac-only tools)
#  - macOS/OpenSSH-only options are dropped
python3 -I - "$SSH_DIR/config" "$STAGE/config" "$STAGE/keys.txt" "$SSH_DIR" <<'PY'
import re, sys, os
src, dst, keylist, sshdir = sys.argv[1:5]
drop = {"usekeychain", "addkeystoagent", "identityagent", "controlmaster", "controlpath",
        "controlpersist", "include", "identitiesonly"}
keys, out = [], []
for line in open(src, encoding="utf-8"):
    stripped = line.strip()
    m = re.match(r"^(\w+)\s*[=\s]\s*(.*)$", stripped)
    if m:
        k, v = m.group(1).lower(), m.group(2).strip()
        if k in drop:
            out.append("# [blinkpro] dropped: " + stripped + "\n")
            continue
        if k == "identityfile":
            path = os.path.expanduser(v.strip('"'))
            name = os.path.basename(path)
            if os.path.isfile(path):
                keys.append(path)
            else:
                out.append("# [blinkpro] missing key file: " + stripped + "\n")
            out.append(re.sub(re.escape(v), name, line, count=1))
            continue
    out.append(line)
open(dst, "w", encoding="utf-8").writelines(out)
open(keylist, "w").write("\n".join(sorted(set(keys))))
PY

echo "config: $(grep -c -i '^host ' "$STAGE/config") host entries"

if [[ $WITH_KEYS -eq 1 ]]; then
  while IFS= read -r key || [[ -n "$key" ]]; do
    [[ -n "$key" ]] || continue
    cp "$key" "$STAGE/$(basename "$key")"
    [[ -f "$key.pub" ]] && cp "$key.pub" "$STAGE/$(basename "$key").pub"
    echo "key:    $(basename "$key")"
  done < "$STAGE/keys.txt"
fi
rm -f "$STAGE/keys.txt"

if [[ -f "$SSH_DIR/known_hosts" ]]; then
  cp "$SSH_DIR/known_hosts" "$STAGE/known_hosts"
  echo "known_hosts: $(wc -l < "$STAGE/known_hosts" | tr -d ' ') entries"
fi

echo "Copying to $BUNDLE_ID on $DEVICE ..."
xcrun devicectl device copy to \
  --device "$DEVICE" \
  --source "$STAGE" \
  --destination "Documents/ssh-sync" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --remove-existing-content true \
  --quiet

cat <<MSG

Done. Now open Blink Pro on the device and run:

    ssh-import

It installs ~/.ssh/config, merges known_hosts and imports the keys into the keychain.
MSG
