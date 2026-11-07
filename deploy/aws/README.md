# The live town on AWS

One small Amazon Linux 2023 server (13.201.102.25) runs the town on Ethereum Sepolia: the game server, the Arkiv
publisher, and Caddy for HTTPS. Every push to `main` deploys itself.

| Address | What |
|---|---|
| `https://13-201-102-25.sslip.io/play/` | the browser game |
| `https://13-201-102-25.sslip.io/verify` | the Town Pass (World ID) page, linked from the game |
| `wss://13-201-102-25.sslip.io` | the game server's WebSocket (the game finds it by itself) |
| `https://13-201-102-25.sslip.io/health` | is it up |

## How a push gets there

1. `.github/workflows/deploy.yml` builds the server inside Amazon Linux 2023 (so its C library matches the server's), bundles
   it with the publisher, the web pages and `contracts/deployments/sepolia.json`, and publishes it as the `live-server`
   release. When `game/` changed, it also exports the browser game and publishes it as `live-game`.
2. On the server, `dhaniverse-update.timer` runs `update.sh` every minute: a new commit in a release's `VERSION` means
   download, check the SHA-256, unpack, switch, and restart what's running.

GitHub holds no key to the server, and the server holds none to GitHub: it only reads public releases.

## On the server

```
town status     what's running, which builds are installed, health
town start      start the town (and keep it on across reboots)
town stop       stop it
town logs       follow the logs
town update     install the newest build now
town reset      archive this town and begin a new city (nothing deleted; wallets never handed out twice)
```

Connect with `ssh -i dhaniverse.pem ec2-user@13.201.102.25` (the key stays out of git: `*.pem` is ignored).

## Setting up a server from scratch

```
scp -i dhaniverse.pem deploy/aws/* ec2-user@<ip>:~/dhaniverse-deploy/
ssh -i dhaniverse.pem ec2-user@<ip> 'sudo ~/dhaniverse-deploy/bootstrap.sh <host>'
deploy/aws/push_secrets.sh dhaniverse.pem ec2-user@<ip> <host>
```

`<host>` is any name pointing at the server; `<ip with dashes>.sslip.io` works with no DNS setup. The security group must
allow ports 80 and 443 (Caddy gets the certificate through them) and 22. `push_secrets.sh` copies only what the server and
the publisher use from your `.env`, never the deployer's, team's or ops keys.

Files: `bootstrap.sh` (one-time setup), `update.sh` (the installer), `town` (the command), the systemd units, `Caddyfile`.
