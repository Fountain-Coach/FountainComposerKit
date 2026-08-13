#!/usr/bin/env bash
set -euo pipefail

commit="${1:?commit required}"
archive_sha="${2:?archive sha required}"
root="/var/lib/fountain-composer"
release="$root/releases/code-$commit"
staging="$(mktemp -d "$root/releases/.staging-code-$commit.XXXXXX")"
trap 'rm -rf "$staging" "$root/deploy.tar" /var/lib/fountain-composer/remote-install.sh' EXIT

test ! -e "$release"
test "$(sha256sum "$root/deploy.tar" | awk '{print $1}')" = "$archive_sha"
tar -xf "$root/deploy.tar" -C "$staging"
swift_root=/opt/swift-6.3.3/swift-6.3.3-RELEASE-ubuntu24.04
export PATH="$swift_root/usr/bin:$PATH"
export LD_LIBRARY_PATH="$swift_root/usr/lib/swift/linux"
cd "$staging"
swift build -c release --product fountain-composer-cloud-server
install -d /etc/fountain-composer
install -m 0644 Deploy/fountain-composer.service /etc/systemd/system/fountain-composer.service
mv "$staging" "$release"
staging=
previous="$(readlink "$root/current" || true)"
ln -sfn "$previous" "$root/previous" 2>/dev/null || true
ln -sfn "$release" "$root/current"

python3 - <<'PY'
from pathlib import Path
p = Path('/etc/caddy/Caddyfile')
s = p.read_text()
old = 'library.fountain.coach {\n\thandle_path /images/* {'
new = 'library.fountain.coach {\n\thandle /v1/attachments/* {\n\t\treverse_proxy 127.0.0.1:8789\n\t}\n\thandle_path /images/* {'
if old not in s and 'reverse_proxy 127.0.0.1:8789' not in s:
    raise SystemExit('expected library Caddy block not found')
if 'reverse_proxy 127.0.0.1:8789' not in s:
    p.with_name('Caddyfile.before-composer').write_text(s)
    p.write_text(s.replace(old, new, 1))
PY

caddy validate --config /etc/caddy/Caddyfile
systemctl daemon-reload
systemctl restart fountain-composer.service
systemctl is-active --quiet fountain-composer.service
systemctl reload caddy
printf 'deployed commit=%s current=%s previous=%s\n' "$commit" "$(readlink "$root/current")" "$(readlink "$root/previous" 2>/dev/null || true)"
