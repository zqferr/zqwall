# zqwall

Minimal VLESS Reality transparent proxy for OpenWrt. Uses sing-box + TPROXY.

## Install

```bash
curl -sSL https://raw.githubusercontent.com/zqfer/zqwall/main/install.sh | sh
```

## Usage

**LuCI:** Network → ZqWall  
**CLI:**
```bash
uci set zqwall.settings.enabled='1' && uci commit zqwall
/etc/init.d/zqwall start
```

## Features

- VLESS + XTLS Reality protocol
- TPROXY transparent proxy (all LAN traffic)
- DNS over HTTPS (Cloudflare)
- Auto-bypass private IPs & proxy server
- LuCI web interface with VLESS link import
- ~12MB total (sing-box binary)

## Requirements

- OpenWrt 23.05+
- `kmod-nft-tproxy` kernel module
