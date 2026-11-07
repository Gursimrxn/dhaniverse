#!/usr/bin/env bash
# Installs the newest build GitHub Actions published (.github/workflows/deploy.yml), when it isn't installed yet. Run every
# minute by dhaniverse-update.timer. Two parts, each a rolling release on GitHub: `live-server` (the server, the publisher, the
# web pages, the contract addresses) and `live-game` (the browser game). Each has VERSION (the commit), the tarball, and its
# SHA-256. Nothing here holds a key: the releases are public, and the server's secrets stay in /etc/dhaniverse.
set -euo pipefail

REPO="$(cat /etc/dhaniverse/repo)"
BASE="https://github.com/$REPO/releases/download"
ROOT=/opt/dhaniverse
KEEP=3

install_part() {
  local part="$1" want have tmp dest
  want="$(curl -fsSL --max-time 20 "$BASE/live-$part/VERSION" 2>/dev/null)" || return 0   # nothing published yet
  [[ "$want" =~ ^[0-9a-f]{40}$ ]] || { echo "live-$part: VERSION isn't a commit"; return 0; }
  have="$(cat "$ROOT/$part.version" 2>/dev/null || true)"
  [[ "$want" == "$have" ]] && return 0

  tmp="$(mktemp -d)"
  if ! curl -fsSL --max-time 600 -o "$tmp/$part.tar.gz" "$BASE/live-$part/$part.tar.gz" \
    || ! curl -fsSL --max-time 20 -o "$tmp/$part.sha256" "$BASE/live-$part/$part.tar.gz.sha256"; then
    echo "live-$part: download failed, trying again next minute"; rm -rf "$tmp"; return 0
  fi
  if ! (cd "$tmp" && echo "$(cut -d' ' -f1 "$part.sha256")  $part.tar.gz" | sha256sum -c --quiet); then
    echo "live-$part: checksum mismatch (a publish in progress?), trying again next minute"; rm -rf "$tmp"; return 0
  fi
  dest="$ROOT/releases/$part-$want"
  rm -rf "$dest" && mkdir -p "$dest"
  tar -xzf "$tmp/$part.tar.gz" -C "$dest"
  rm -rf "$tmp"
  if [[ "$(cat "$dest/VERSION" 2>/dev/null)" != "$want" ]]; then
    echo "live-$part: the tarball isn't $want yet (a publish in progress?)"; rm -rf "$dest"; return 0
  fi
  chown -R root:root "$dest"
  ln -sfn "$dest" "$ROOT/$part-current.new" && mv -T "$ROOT/$part-current.new" "$ROOT/$part-current"
  echo "$want" > "$ROOT/$part.version"
  echo "installed $part ${want:0:12}"
  if [[ "$part" == server ]]; then
    [[ -f "$dest/town" ]] && install -m 755 "$dest/town" /usr/local/bin/town    # the town command travels with each build
    # Only what's running is restarted: a stopped town stays stopped until `town start`.
    systemctl try-restart dhaniverse-server.service
    systemctl try-restart dhaniverse-publisher.service
  fi
  # the newest few releases of each part stay, for a quick look back
  ls -1dt "$ROOT"/releases/"$part"-* 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -rf
}

install_part server
install_part game
