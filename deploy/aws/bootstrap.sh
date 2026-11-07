#!/usr/bin/env bash
# Sets up an Amazon Linux 2023 server for the Dhaniverse town, once (safe to run again): a swap file, a user for the town,
# Node 24 and Caddy (both checksum-verified), the systemd units, the `town` command, and the updater that installs every
# push to main within a minute. The town itself is not started: `town start` does that.
#
#   sudo deploy/aws/bootstrap.sh <public host>       e.g. 13-201-102-25.sslip.io (any name pointing at this server)
#
# Secrets are not here: deploy/aws/push_secrets.sh writes /etc/dhaniverse/server.env and publisher.env from your machine.
set -euo pipefail

HOST="${1:?usage: bootstrap.sh <public host>}"
REPO="${REPO:-Gursimrxn/dhaniverse}"
NODE_VERSION=24.22.2
CADDY_VERSION=2.11.7
HERE="$(cd "$(dirname "$0")" && pwd)"
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

echo "== packages"
dnf install -y -q tar xz gzip >/dev/null

echo "== swap (the server has under 1 GB of memory)"
if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
  [[ -f /swapfile ]] || { fallocate -l 1G /swapfile; chmod 600 /swapfile; mkswap /swapfile >/dev/null; }
  swapon /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

echo "== users and folders"
id dhaniverse >/dev/null 2>&1 || useradd --system --home-dir /var/lib/dhaniverse --shell /sbin/nologin dhaniverse
id caddy >/dev/null 2>&1 || useradd --system --home-dir /var/lib/caddy --shell /sbin/nologin caddy
install -d -o dhaniverse -g dhaniverse -m 750 /var/lib/dhaniverse
install -d -o caddy -g caddy -m 750 /var/lib/caddy
install -d -m 755 /opt/dhaniverse /opt/dhaniverse/releases /opt/dhaniverse/bin /etc/caddy
install -d -m 700 /etc/dhaniverse

echo "== Node $NODE_VERSION"
if [[ "$(/opt/node/bin/node --version 2>/dev/null || true)" != "v$NODE_VERSION" ]]; then
  tmp="$(mktemp -d)"
  tarball="node-v$NODE_VERSION-linux-x64.tar.xz"
  curl -fsSL -o "$tmp/$tarball" "https://nodejs.org/dist/v$NODE_VERSION/$tarball"
  curl -fsSL -o "$tmp/SHASUMS256.txt" "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt"
  (cd "$tmp" && grep " $tarball\$" SHASUMS256.txt | sha256sum -c --quiet)
  rm -rf "/opt/node-v$NODE_VERSION" && mkdir -p "/opt/node-v$NODE_VERSION"
  tar -xJf "$tmp/$tarball" -C "/opt/node-v$NODE_VERSION" --strip-components=1
  ln -sfn "/opt/node-v$NODE_VERSION" /opt/node
  rm -rf "$tmp"
fi
/opt/node/bin/node --version

echo "== Caddy $CADDY_VERSION"
if [[ "$(/usr/local/bin/caddy version 2>/dev/null | cut -d' ' -f1)" != "v$CADDY_VERSION" ]]; then
  tmp="$(mktemp -d)"
  tarball="caddy_${CADDY_VERSION}_linux_amd64.tar.gz"
  curl -fsSL -o "$tmp/$tarball" "https://github.com/caddyserver/caddy/releases/download/v$CADDY_VERSION/$tarball"
  curl -fsSL -o "$tmp/sums" "https://github.com/caddyserver/caddy/releases/download/v$CADDY_VERSION/caddy_${CADDY_VERSION}_checksums.txt"
  (cd "$tmp" && grep " $tarball\$" sums | sha512sum -c --quiet)
  tar -xzf "$tmp/$tarball" -C "$tmp" caddy
  install -m 755 "$tmp/caddy" /usr/local/bin/caddy
  rm -rf "$tmp"
fi
/usr/local/bin/caddy version

echo "== the town's files"
install -m 755 "$HERE/update.sh" /opt/dhaniverse/bin/update
install -m 755 "$HERE/town" /usr/local/bin/town
install -m 644 "$HERE/Caddyfile" /etc/caddy/Caddyfile
for unit in dhaniverse-server.service dhaniverse-publisher.service dhaniverse-update.service dhaniverse-update.timer caddy.service; do
  install -m 644 "$HERE/$unit" "/etc/systemd/system/$unit"
done
echo "DHANIVERSE_HOST=$HOST" > /etc/dhaniverse/caddy.env
echo "$REPO" > /etc/dhaniverse/repo
systemctl daemon-reload

echo "== HTTPS and the updater"
systemctl enable --now caddy.service dhaniverse-update.timer
systemctl reload caddy.service || true
echo
echo "Done. https://$HOST/ once a build is published and the town started (town start). town status shows where it is."
