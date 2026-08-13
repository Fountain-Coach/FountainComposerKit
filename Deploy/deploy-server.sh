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
  -o ConnectTimeout=15 -i "$ssh_key" "$archive" root@"$TARGET_IP":/var/lib/fountain-composer/deploy.tar

ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o HostKeyAlias="$TARGET_IP" \
  -o ConnectTimeout=15 -i "$ssh_key" root@"$TARGET_IP" \
  "set -euo pipefail; root=$REMOTE_ROOT; release=\$root/releases/code-$commit; staging=\$(mktemp -d \$root/releases/.staging-code-$commit.XXXXXX); trap 'rm -rf \"\$staging\" \"\$root/deploy.tar\"' EXIT; test ! -e \"\$release\"; test \"\$(sha256sum \$root/deploy.tar | awk '{print \$1}')\" = '$archive_sha'; mkdir -p \"\$root/releases\" \"\$root/attachments\"; tar -xf \$root/deploy.tar -C \"\$staging\"; swift_root=/opt/swift-6.3.3/swift-6.3.3-RELEASE-ubuntu24.04; export PATH=\"\$swift_root/usr/bin:\$PATH\"; export LD_LIBRARY_PATH=\"\$swift_root/usr/lib/swift/linux\"; cd \"\$staging\"; swift build -c release --product fountain-composer-cloud-server; install -d /etc/fountain-composer; install -m 0644 Deploy/fountain-composer.service /etc/systemd/system/fountain-composer.service; mv \"\$staging\" \"\$release\"; staging=; previous=\$(readlink \$root/current || true); ln -sfn \"\$previous\" \$root/previous 2>/dev/null || true; ln -sfn \"\$release\" \$root/current; python3 - <<'PY'\nfrom pathlib import Path\np=Path('/etc/caddy/Caddyfile')\ns=p.read_text()\nold='library.fountain.coach {\\n\\thandle_path /images/* {'\nnew='library.fountain.coach {\\n\\thandle /v1/attachments/* {\\n\\t\\treverse_proxy 127.0.0.1:$PORT\\n\\t}\\n\\thandle_path /images/* {'\nif old not in s: raise SystemExit('expected library Caddy block not found')\nif 'reverse_proxy 127.0.0.1:$PORT' not in s:\n    p.with_suffix('.Caddyfile.before-composer').write_text(s)\n    p.write_text(s.replace(old,new,1))\nPY\ncaddy validate --config /etc/caddy/Caddyfile; systemctl daemon-reload; systemctl restart fountain-composer.service; systemctl is-active --quiet fountain-composer.service; systemctl reload caddy; curl --fail --silent --show-error --max-time 10 http://127.0.0.1:$PORT/v1/attachments/admit -o /dev/null -w '%{http_code}\\n' -X POST || test \"\$?\" = 22; printf 'deployed commit=%s current=%s previous=%s\\n' '$commit' \"\$(readlink \$root/current)\" \"\$(readlink \$root/previous 2>/dev/null || true)\""

echo "deployed Fountain Composer Attachment Cloud commit $commit"
