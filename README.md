# Mihomo/Clash Remote Server Manager

Core proxy functionality is provided by [@MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo). This repository only adds a lightweight management script for running mihomo on a remote Linux server.

Chinese documentation is available in [README_zh.md](README_zh.md).

This tool helps you manage `mihomo`/`clash` on a remote Linux server:

- Start the proxy in the background
- Check runtime status and logs
- Stop the proxy
- Download or refresh a Clash/Mihomo subscription config
- Replace the subscription token
- Print proxy environment variables for VSCode, Codex, and terminal commands

Default paths:

```text
~/.config/mihomo/clash-linux
~/.config/mihomo/config.yaml
~/.config/mihomo/mihomo.log
```

## 1. Prepare Mihomo Files

This setup flow is adapted from the [bannedbook/fanqiang Linux guide](https://github.com/bannedbook/fanqiang/blob/5cb11c6420a95cdc83c4a29ffc54e2cd9e4689d4/linux/readme.md). It prepares the working directory, mihomo binary, and geodata files.

Create and enter the program directory:

```bash
mkdir -p ~/.config/mihomo
cd ~/.config/mihomo
```

Download the Linux amd64 mihomo binary:

```bash
wget -O clash-linux.gz https://github.com/MetaCubeX/mihomo/releases/download/v1.17.0/mihomo-linux-amd64-v1.17.0.gz
```

If this release link no longer works, open [MetaCubeX/mihomo Releases](https://github.com/MetaCubeX/mihomo/releases), choose the correct `linux-amd64` or `linux-arm64` build for your server, and place the downloaded file at:

```text
~/.config/mihomo/clash-linux.gz
```

Decompress it and make it executable:

```bash
gzip -f clash-linux.gz -d
chmod +x clash-linux
```

Run mihomo once so it can generate default files. Wait briefly, then press `Ctrl+C` to stop it:

```bash
./clash-linux
```

Check the directory:

```bash
ls -rtl ~/.config/mihomo/
```

If `Country.mmdb` was not generated automatically, download it manually:

```bash
wget -O ~/.config/mihomo/Country.mmdb https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb
```

If `GeoSite.dat` was not generated automatically, you can later run `update-geodata` from this script, or download it manually:

```bash
wget -O ~/.config/mihomo/GeoSite.dat https://github.com/ewigl/mihomo/raw/master/GeoSite.dat
```

## 2. Clone This Manager

Clone this repository on the remote server:

```bash
cd ~/.config/mihomo
git clone https://github.com/BillyLiu312/mihomo-manager.git manager
```

Enter the repository and make the script executable:

```bash
cd ~/.config/mihomo/manager
chmod +x mihomoctl.sh
```

Run the following commands from this directory:

```bash
cd ~/.config/mihomo/manager
```

## 3. Configure The Subscription

Always quote the URL, because subscription URLs usually contain `&`.

```bash
./mihomoctl.sh init
./mihomoctl.sh set-url 'https://your-subscription-host/api/v1/client/subscribe?token=YOUR_TOKEN&flag=clash'
./mihomoctl.sh fetch
```

`set-url` automatically appends `flag=clash` when it is missing. The subscription URL is stored in:

```text
~/.config/mihomo/subscription.env
```

The file is written with `600` permissions.

## 4. Start In The Background

```bash
./mihomoctl.sh start
```

Check status:

```bash
./mihomoctl.sh status
```

View recent logs:

```bash
./mihomoctl.sh logs
```

Follow logs:

```bash
./mihomoctl.sh logs -f
```

## 5. Use The Proxy From Terminal, VSCode, Or Codex

After startup, the default mixed HTTP/SOCKS proxy is:

```text
127.0.0.1:7890
```

Set proxy variables in the current shell:

```bash
eval "$(~/.config/mihomo/manager/mihomoctl.sh env)"
```

Test connectivity:

```bash
curl https://api.openai.com/v1/models -I
```

`401`, `403`, or `404` means the network path is reachable but the API credentials or endpoint may not be valid. A timeout usually points to a proxy or network issue.

Run a single command through the proxy:

```bash
~/.config/mihomo/manager/mihomoctl.sh run curl https://api.openai.com/v1/models -I
```

To make remote VSCode/Codex inherit the proxy by default, add this line to `~/.bashrc`:

```bash
eval "$($HOME/.config/mihomo/manager/mihomoctl.sh env)"
```

Then reload the shell:

```bash
source ~/.bashrc
```

In VSCode, run this command from the command palette:

```text
Remote-SSH: Kill VS Code Server on Host...
```

Reconnect to the server so VSCode Server picks up the new environment.

## 6. Replace The VPN/Subscription Token

If only the token changed:

```bash
cd ~/.config/mihomo/manager
./mihomoctl.sh set-token NEW_TOKEN
./mihomoctl.sh fetch
./mihomoctl.sh restart
```

If the full subscription URL changed:

```bash
./mihomoctl.sh set-url 'https://new-subscription-url?token=NEW_TOKEN&flag=clash'
./mihomoctl.sh fetch
./mihomoctl.sh restart
```

## 7. Stop The Proxy

Stop the background mihomo process:

```bash
cd ~/.config/mihomo/manager
./mihomoctl.sh stop
```

Unset proxy variables in the current shell:

```bash
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY
unset http_proxy https_proxy all_proxy
```

If you added `eval "$($HOME/.config/mihomo/manager/mihomoctl.sh env)"` to `~/.bashrc`, remove or comment out that line to disable it permanently.

## 8. Update GeoSite / GeoIP

If your config depends on `GeoSite.dat` or `GeoIP.dat`:

```bash
cd ~/.config/mihomo/manager
./mihomoctl.sh update-geodata
./mihomoctl.sh restart
```

## 9. FAQ

### `cannot unmarshal !!str c3M6Ly9...`

The downloaded subscription is a base64/raw node list, not Clash/Mihomo YAML. Use a Clash/Mihomo subscription URL:

```bash
./mihomoctl.sh set-url 'YOUR_SUBSCRIPTION_URL&flag=clash'
./mihomoctl.sh fetch
```

### The command prints `[1] 12345`

The URL was not quoted, so the shell interpreted `&flag=clash` as a background-job operator. Always wrap subscription URLs in single quotes.

### The proxy is running, but Codex still cannot connect

Check the proxy first:

```bash
./mihomoctl.sh status
eval "$(./mihomoctl.sh env)"
curl https://api.openai.com/v1/models -I
```

If `curl` works but VSCode/Codex does not, restart VSCode Server:

```text
Remote-SSH: Kill VS Code Server on Host...
```

Then reconnect to the remote server.
