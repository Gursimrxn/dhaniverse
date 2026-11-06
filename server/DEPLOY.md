# Hosting a town

One small always-on machine runs one server, with one file as the whole city.

## What it needs

| | Needs | Evidence |
|---|---|---|
| **Machine** | 1 vCPU, 1 GB, any small VPS. Always on, with a real disk. No serverless, and nothing that sleeps, or wipes files on restart | All game logic runs on one thread. Memory was 15 MB after 341 city days with no players |
| **Disk** | 1 MB a day for an empty city, plus about 20 KB per hour per active player. 30 people playing 8 hours a day is about 6 MB a day, so 10 GB lasts years | 14.2 MB for 341 city days (each is one real hour), measured. The per-player figure was measured before the Dhaniverse cleanup, with the old economy |
| **Bandwidth** | About 25 KB/s per connected player with 30 on, so about 6 Mbit/s out at that peak, and up to 2 TB a month if it never stops. Pick a host with generous transfer | 12.2 KB/s measured with 10 players and 20 residents. The 30-player figure is scaled from that |
| **Ports** | 443 and 80 open, for the proxy. 7878 closed to the outside | |
| **Other** | A domain name pointing at the machine | |

**Tested on Windows only.** TLS through Caddy and the Linux build haven't been run. Everything else below was rehearsed locally with the release binary, except that the backup was only taken and restored on a young, nearly empty save.

## Run it

Build on a machine with the Linux toolchain, or on the VPS. Copy `server` and `rules.toml` into `/srv/town`.

```bash
cargo build -p server --release
```

`/etc/systemd/system/town.service`:

```ini
[Unit]
Description=Dhaniverse town
After=network.target

[Service]
WorkingDirectory=/srv/town
ExecStart=/srv/town/server --addr 127.0.0.1:7878 --behind-proxy --save /srv/town/town.jsonl
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
```

**Never add `--debug` or `--speed` on a public server:** `--debug` lets any client feed itself without paying.

## TLS

[Caddy](https://caddyserver.com) gets and renews the certificate by itself. This is its whole config, in `/etc/caddy/Caddyfile`:

```
town.example.com {
    reverse_proxy 127.0.0.1:7878
}
```

Players connect to `wss://town.example.com`, and the Town Terminal reads `https://town.example.com/city`. Both use the same rule. See "The public view" in `PROTOCOL.md`.

## Check it

```bash
curl https://town.example.com/health
```

It should answer `{"ok":true,...}`. Point an uptime monitor at it: a `503` means the city has stopped.

## Back it up

`town.jsonl` **is** the city. It only ever grows, so it's safe to copy while the server runs. A copy that ends in half a line just loses that line when it's loaded. Copy it off the machine at least daily:

```bash
cp /srv/town/town.jsonl /srv/backup/town-$(date +%F).jsonl && rclone copy /srv/backup remote:town
```

**Keep the backups private.** The save holds every player's balances and history. Secrets are in it only as hashes. The server never serves it.

## Recover

| What happened | What to do | What's lost |
|---|---|---|
| The process crashed or was killed | Nothing: systemd restarts it. It replays the save, which takes about a second for two weeks of city | Nothing, or at most one heartbeat of clock (5 seconds) on a power cut |
| The machine died | New machine, restore the latest backup as `town.jsonl`, start it | Whatever happened since that backup |
| The disk filled | The server stops rather than run on unsaved. Free space, and start it | Nothing |
| It stops at startup with "replays differently" | The save and the program don't match: see below. **The server refuses rather than guess,** and changes nothing | Nothing, until you choose |

## Updating the server

**A new build that changes the rules, the agents or `rules.toml`'s numbers can't load an old save.** It replays every line and refuses if any comes out differently. There's no migration yet.

- A change that doesn't affect what happens (networking, say) loads fine. Try it on a copy of the save first.
- If it won't load, you can go back to the old build, or start a new city. `--new-if-incompatible` starts a new city and moves the old save aside, never deleting it. **Every player's money and property start over,** so don't leave that flag on by default.
- Editing `rules.toml` changes nothing for an existing save, which keeps the rules it started with. The one exception is `[[offers]]`.

Players' clients must also match the server's `PROTOCOL.md`. A release is a server and a client together.

## Limits

One process holds everyone. About 30 players is what's been planned for, and it has been measured only up to 10. The per-address limits are in `crates/server/src/limits.rs`.
