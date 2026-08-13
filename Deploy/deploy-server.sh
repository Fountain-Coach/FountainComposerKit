#!/usr/bin/env bash
set -euo pipefail

HOST="library.fountain.coach"
TARGET_IP="65.109.14.71"
REMOTE_ROOT="/var/lib/fountain-composer"
PORT="8789"
commit=""
apply=false
confirm=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit) commit="${2:?commit required}"; shift 2 ;;
    --apply) apply=true; shift ;;
    --confirm-deploy) confirm=true; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "full commit required" >&2; exit 2; }
[[ "$(git rev-parse HEAD)" == "$commit" ]] || { echo "working tree is not at requested commit" >&2; exit 2; }
[[ -z "$(git status --porcelain)" ]] || { echo "working tree must be clean" >&2; exit 2; }

echo "plan: Fountain Composer Attachment Cloud"
echo "host: $HOST ($TARGET_IP)"
echo "release: $commit"
echo "route: https://$HOST/v1/attachments/admit -> 127.0.0.1:$PORT"
echo "storage: $REMOTE_ROOT/attachments"
if ! $apply; then
  echo "dry run only — pass --apply --confirm-deploy to write"
  exit 0
fi
$confirm || { echo "--confirm-deploy is required with --apply" >&2; exit 2; }

ssh_key="${PUBLISHING_SSH_KEY:-$HOME/.ssh/id_rsa}"
archive="$(mktemp -t fountain-composer-deploy.XXXXXX.tar)"
trap 'rm -f "$archive"' EXIT
git archive --format=tar "$commit" > "$archive"
archive_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o HostKeyAlias="$TARGET_IP" \
  -o ConnectTimeout=15 -i "$ssh_key" root@"$TARGET_IP" "install -d $REMOTE_ROOT/releases $REMOTE_ROOT/attachments"
scp -q -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o HostKeyAlias="$TARGET_IP" \
  -o ConnectTimeout=15 -i "$ssh_key" "$archive" root@"$TARGET_IP":$REMOTE_ROOT/deploy.tar
scp -q -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o HostKeyAlias="$TARGET_IP" \
  -o ConnectTimeout=15 -i "$ssh_key" Deploy/remote-install.sh root@"$TARGET_IP":$REMOTE_ROOT/remote-install.sh
ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o HostKeyAlias="$TARGET_IP" \
  -o ConnectTimeout=15 -i "$ssh_key" root@"$TARGET_IP" \
  "bash $REMOTE_ROOT/remote-install.sh '$commit' '$archive_sha'"

echo "deployed Fountain Composer Attachment Cloud commit $commit"
