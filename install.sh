#!/bin/sh
# zqwall - Minimal VLESS Reality transparent proxy for OpenWrt
# One-command install: curl -sSL <url> | sh

set -e
echo ""
echo "  zqwall — VLESS Reality Proxy"
echo "  ============================="
echo ""

SBOX="/usr/bin/sing-box"
CONF_DIR="/etc/zqwall"
VAR_DIR="/var/etc/zqwall"
GH="https://raw.githubusercontent.com/zqferr/zqwall/main"
GH_REL="https://github.com/zqferr/zqwall/releases/download/sing-box"

# ---- Arch detect ----
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)   SBOX_ARCH="amd64" ;;
    aarch64)  SBOX_ARCH="arm64" ;;
    armv7l)   SBOX_ARCH="armv7" ;;
    mips)     SBOX_ARCH="mips" ;;
    mipsel)   SBOX_ARCH="mipsle" ;;
    *) echo "[!] Unknown arch: $ARCH"; exit 1 ;;
esac

# ---- Install dependencies ----
echo "[1/4] Installing dependencies..."
opkg update >/dev/null 2>&1 || true
for pkg in kmod-nft-tproxy; do
    opkg list-installed "$pkg" >/dev/null 2>&1 || opkg install "$pkg" >/dev/null 2>&1 || true
done

# ---- Install sing-box (custom minimal build) ----
echo "[2/4] Installing sing-box (VLESS-only, ~5MB)..."
if [ ! -x "$SBOX" ]; then
    SBOX_URL="$GH_REL/sing-box-${SBOX_ARCH}"
    wget -q -O "$SBOX" "$SBOX_URL" || {
        # Fallback: official build
        echo "     Custom build not found, trying official..."
        SBOX_VER="1.11.6"
        wget -q -O - "https://github.com/SagerNet/sing-box/releases/download/v${SBOX_VER}/sing-box-${SBOX_VER}-linux-${SBOX_ARCH}.tar.gz" | tar -xz -C /tmp
        cp "/tmp/sing-box-${SBOX_VER}-linux-${SBOX_ARCH}/sing-box" "$SBOX"
        rm -rf "/tmp/sing-box-${SBOX_VER}-linux-${SBOX_ARCH}"
    }
    chmod +x "$SBOX"
fi
echo "     sing-box: $($SBOX version 2>&1 | head -1)"

# ---- Create files ----
echo "[3/4] Creating config files..."

mkdir -p "$CONF_DIR" "$VAR_DIR" /usr/libexec/zqwall

# UCI config
cat > /etc/config/zqwall << 'UCI'
config zqwall 'settings'
	option enabled '0'
	option uuid ''
	option address ''
	option port '443'
	option flow 'xtls-rprx-vision'
	option sni ''
	option pbk ''
	option sid ''
	option fp 'chrome'
	option spx '/'
	option tproxy_port '10105'
	option dns_port '10153'
	option mixed_port '2080'
	option dns_server 'https://1.1.1.1/dns-query'
UCI

# sing-box config template
cat > "$CONF_DIR/config.json.template" << 'TMPL'
{
  "log": {"level": "warn"},
  "dns": {
    "strategy": "ipv4_only",
    "servers": [
      {"tag": "doh-proxy", "address": "__DNS_SERVER__", "detour": "proxy"},
      {"tag": "doh-direct", "address": "__DNS_SERVER__", "detour": "direct"}
    ],
    "rules": [
      {"domain_suffix": ["__VLESS_DOMAIN__"], "server": "doh-direct"}
    ],
    "final": "doh-proxy"
  },
  "inbounds": [
    {"type": "tproxy", "tag": "tproxy-in", "listen": "::", "listen_port": __TPROXY_PORT__, "sniff": true},
    {"type": "tproxy", "tag": "tproxy-dns", "listen": "::", "listen_port": __DNS_PORT__, "sniff": true},
    {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": __MIXED_PORT__}
  ],
  "outbounds": [
    {
      "type": "vless", "tag": "proxy",
      "server": "__VLESS_ADDR__", "server_port": __VLESS_PORT__,
      "uuid": "__VLESS_UUID__", "flow": "__VLESS_FLOW__",
      "tls": {
        "enabled": true, "server_name": "__VLESS_SNI__",
        "utls": {"enabled": true, "fingerprint": "__VLESS_FP__"},
        "reality": {"enabled": true, "public_key": "__VLESS_PBK__", "short_id": "__VLESS_SID__"}
      },
      "packet_encoding": "xudp"
    },
    {"type": "direct", "tag": "direct"},
    {"type": "dns", "tag": "dns-out"}
  ],
  "route": {
    "auto_detect_interface": true, "final": "proxy",
    "rules": [
      {"inbound": ["tproxy-dns"], "outbound": "dns-out"},
      {"ip_is_private": true, "outbound": "direct"},
      {"domain_suffix": ["__VLESS_DOMAIN__"], "outbound": "direct"},
      {"protocol": "dns", "outbound": "dns-out"}
    ]
  }
}
TMPL

# Config generator
cat > /usr/libexec/zqwall/gen-config.sh << 'GEN'
#!/bin/sh
. /lib/functions.sh
config_load zqwall
config_get enabled settings enabled
[ "$enabled" != "1" ] && { echo "zqwall disabled"; exit 0; }

config_get uuid   settings uuid
config_get addr   settings address
config_get port   settings port
config_get flow   settings flow
config_get sni    settings sni
config_get pbk    settings pbk
config_get sid    settings sid
config_get fp     settings fp
config_get spx    settings spx
config_get tproxy_port settings tproxy_port
config_get dns_port    settings dns_port
config_get mixed_port  settings mixed_port
config_get dns    settings dns_server

vless_domain=$(echo "$addr" | cut -d. -f2-)
[ -z "$vless_domain" ] && vless_domain="$addr"
[ -z "$tproxy_port" ] && tproxy_port="10105"
[ -z "$dns_port" ]    && dns_port="10153"
[ -z "$mixed_port" ]  && mixed_port="2080"
[ -z "$dns" ]         && dns="https://1.1.1.1/dns-query"

mkdir -p /var/etc/zqwall
sed \
    -e "s|__VLESS_UUID__|${uuid}|g" -e "s|__VLESS_ADDR__|${addr}|g" \
    -e "s|__VLESS_PORT__|${port}|g" -e "s|__VLESS_FLOW__|${flow}|g" \
    -e "s|__VLESS_SNI__|${sni}|g" -e "s|__VLESS_PBK__|${pbk}|g" \
    -e "s|__VLESS_SID__|${sid}|g" -e "s|__VLESS_FP__|${fp}|g" \
    -e "s|__TPROXY_PORT__|${tproxy_port}|g" -e "s|__DNS_PORT__|${dns_port}|g" \
    -e "s|__MIXED_PORT__|${mixed_port}|g" -e "s|__VLESS_DOMAIN__|${vless_domain}|g" \
    -e "s|__DNS_SERVER__|${dns}|g" \
    /etc/zqwall/config.json.template > /var/etc/zqwall/config.json
echo "zqwall config generated"
GEN
chmod +x /usr/libexec/zqwall/gen-config.sh

# Init script
cat > /etc/init.d/zqwall << 'INIT'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=90
STOP=10
PROG=/usr/bin/sing-box
CONF=/var/etc/zqwall/config.json
GENCONF=/usr/libexec/zqwall/gen-config.sh
NFT="inet zqwall"

setup_nft() {
    local tp dp addr
    . /lib/functions.sh
    config_load zqwall
    config_get tp settings tproxy_port; [ -z "$tp" ] && tp="10105"
    config_get dp settings dns_port;    [ -z "$dp" ] && dp="10153"
    config_get addr settings address

    nft add table $NFT 2>/dev/null
    nft add set $NFT bypass_v4 { type ipv4_addr\; flags interval\; } 2>/dev/null
    nft add element $NFT bypass_v4 { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8, 224.0.0.0/4 } 2>/dev/null
    nft add set $NFT bypass_dst { type ipv4_addr\; } 2>/dev/null
    for ip in $(nslookup "$addr" 2>/dev/null | awk '/^Address/{print $2}' | grep -v ':'); do
        nft add element $NFT bypass_dst { "$ip" } 2>/dev/null
    done
    nft add chain $NFT prerouting { type filter hook prerouting priority mangle\; } 2>/dev/null
    nft flush chain $NFT prerouting
    nft add rule $NFT prerouting ip daddr @bypass_v4 return
    nft add rule $NFT prerouting ip daddr @bypass_dst return
    nft add rule $NFT prerouting ip protocol udp udp dport 53 meta mark set 1 tproxy ip to :$dp accept
    nft add rule $NFT prerouting ip protocol tcp tcp dport 53 meta mark set 1 tproxy ip to :$dp accept
    nft add rule $NFT prerouting ip protocol tcp meta mark set 1 tproxy ip to :$tp accept
    nft add rule $NFT prerouting ip protocol udp meta mark set 1 tproxy ip to :$tp accept
    ip rule add fwmark 1 table 100 2>/dev/null
    ip route add local 0.0.0.0/0 dev lo table 100 2>/dev/null
}

teardown_nft() {
    nft delete table $NFT 2>/dev/null
    ip rule del fwmark 1 table 100 2>/dev/null
    ip route flush table 100 2>/dev/null
}

start_service() {
    . /lib/functions.sh
    config_load zqwall
    config_get enabled settings enabled
    [ "$enabled" != "1" ] && { echo "zqwall disabled: uci set zqwall.settings.enabled=1"; return 1; }
    mkdir -p /var/etc/zqwall
    [ -x "$GENCONF" ] && "$GENCONF"
    [ ! -f "$CONF" ] && { echo "Config not found"; return 1; }
    setup_nft
    procd_open_instance
    procd_set_param command "$PROG" run -c "$CONF"
    procd_set_param file "$CONF"
    procd_set_param respawn 3600 5 60
    procd_set_param stdout 1; procd_set_param stderr 1
    procd_close_instance
}

stop_service() { teardown_nft; service_stop "$PROG"; }
reload_service() {
    [ -x "$GENCONF" ] && "$GENCONF"
    teardown_nft; setup_nft
    procd_send_signal zqwall SIGHUP
}
INIT
chmod +x /etc/init.d/zqwall

# ---- Install LuCI ----
echo "[4/4] Installing LuCI interface..."

# ACL
mkdir -p /usr/share/rpcd/acl.d
cat > /usr/share/rpcd/acl.d/luci-app-zqwall.json << 'ACL'
{
    "luci-app-zqwall": {
        "description": "Grant access to zqwall operations",
        "read": {
            "uci": ["zqwall"],
            "ubus": { "service": ["list"], "uci": ["get"] }
        },
        "write": {
            "uci": ["zqwall"],
            "ubus": { "rc": ["init"], "uci": ["set","add","delete","commit","apply","confirm","order","rename"] }
        }
    }
}
ACL

# Menu
mkdir -p /usr/share/luci/menu.d
cat > /usr/share/luci/menu.d/luci-app-zqwall.json << 'MENU'
{"admin/services/zqwall": {"title": "ZqWall", "order": 50, "action": {"type": "view", "path": "zqwall/zqwall"}}}
MENU

# JS view
mkdir -p /www/luci-static/resources/view/zqwall
wget -q -O /www/luci-static/resources/view/zqwall/zqwall.js "$GH/htdocs/luci-static/resources/view/zqwall/zqwall.js" || {
    echo "[!] Could not download LuCI view from GitHub"
}

# Clean caches & restart
rm -rf /tmp/luci-*
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

echo ""
/etc/init.d/zqwall enable 2>/dev/null || true

echo "  === Installation complete ==="
echo ""
echo "  LuCI:  Network > ZqWall (or Services > ZqWall)"
echo "  CLI:   uci set zqwall.settings.enabled='1'"
echo "         uci commit zqwall"
echo "         /etc/init.d/zqwall start"
echo ""
echo "  Auto-start on boot: ENABLED"
echo "  DNS: through proxy (no leak)"
echo "  SNI disguise: set in LuCI (e.g. www.whatsapp.com)"
echo ""
