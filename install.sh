#!/bin/sh
# shellcheck shell=dash
REPO="https://api.github.com/repos/mansar1337/ShadowProxy/releases/tags/release"
REPO_HUMAN_URL="https://github.com/mansar1337/ShadowProxy/releases/tag/release"
DOWNLOAD_DIR="/tmp/podkop"
COUNT=3
# Cached flag to switch between ipk or apk package managers
PKG_IS_APK=0
command -v apk >/dev/null 2>&1 && PKG_IS_APK=1
rm -rf "$DOWNLOAD_DIR"
mkdir -p "$DOWNLOAD_DIR"
msg() {
printf "\033[32;1m%s\033[0m\n" "$1"
}
pkg_is_installed () {
local pkg_name="$1"
if [ "$PKG_IS_APK" -eq 1 ]; then
apk list --installed | grep -q "$pkg_name"
else
opkg list-installed | grep -q "$pkg_name"
fi
}
pkg_remove() {
local pkg_name="$1"
if [ "$PKG_IS_APK" -eq 1 ]; then
apk del "$pkg_name"
else
opkg remove --force-depends "$pkg_name"
fi
}
pkg_list_update() {
if [ "$PKG_IS_APK" -eq 1 ]; then
apk update
else
opkg update
fi
}
pkg_install() {
local pkg_file="$1"
if [ "$PKG_IS_APK" -eq 1 ]; then
apk add --allow-untrusted "$pkg_file"
else
opkg install "$pkg_file"
fi
}
update_config() {
printf "\033[48;5;196m\033[1m╔══════════════════════════════════════════════════════════════════════╗\033[0m\n"
printf "\033[48;5;196m\033[1m║ ! Обнаружена старая версия podkop.                                   ║\033[0m\n"
printf "\033[48;5;196m\033[1m║ Если продолжите обновление, вам потребуется настроить Podkop заново. ║\033[0m\n"
printf "\033[48;5;196m\033[1m║ Старая конфигурация будет сохранена в /etc/config/podkop-070         ║\033[0m\n"
printf "\033[48;5;196m\033[1m║ Подробности: https://github.com/itdoginfo/podkop                     ║\033[0m\n"
printf "\033[48;5;196m\033[1m║ Точно хотите продолжить?                                             ║\033[0m\n"
printf "\033[48;5;196m\033[1m╚══════════════════════════════════════════════════════════════════════╝\033[0m\n"
echo ""
printf "\033[48;5;196m\033[1m╔══════════════════════════════════════════════════════════════════════╗\033[0m\n"
printf "\033[48;5;196m\033[1m║ ! Detected old podkop version.                                       ║\033[0m\n"
printf "\033[48;5;196m\033[1m║ If you continue the update, you will need to RECONFIGURE podkop.     ║\033[0m\n"
printf "\033[48;5;196m\033[1m║ Your old configuration will be saved to /etc/config/podkop-070       ║\033[0m\n"
printf "\033[48;5;196m\033[1m║ Details: https://github.com/itdoginfo/podkop                         ║\033[0m\n"
printf "\033[48;5;196m\033[1m║ Are you sure you want to continue?                                   ║\033[0m\n"
printf "\033[48;5;196m\033[1m╚══════════════════════════════════════════════════════════════════════╝\033[0m\n"
msg "Continue? (yes/no)"
while true; do
read -r -p '' CONFIG_UPDATE
case $CONFIG_UPDATE in
yes|y|Y)
mv /etc/config/podkop /etc/config/podkop-070
wget -O /etc/config/podkop https://raw.githubusercontent.com/itdoginfo/podkop/refs/heads/main/podkop/files/etc/config/podkop
msg "Podkop config has been reset to default. Your old config saved in /etc/config/podkop-070"
break
;;
*)
msg "Exit"
exit 1
;;
esac
done
}
main() {
check_system
sing_box
/usr/sbin/ntpd -q -p 194.190.168.1 -p 216.239.35.0 -p 216.239.35.4 -p 162.159.200.1 -p 162.159.200.123
pkg_list_update || { echo "Packages list update failed"; exit 1; }

if [ -f "/etc/init.d/podkop" ]; then
msg "Podkop is already installed. Upgrading..."
else
msg "Installing podkop..."
fi

if command -v curl >/dev/null 2>&1; then
check_response=$(curl -s "$REPO")
if echo "$check_response" | grep -q 'API rate limit '; then
msg "You've reached the GitHub rate limit. Repeat in five minutes."
exit 1
fi
fi

local grep_url_pattern
if [ "$PKG_IS_APK" -eq 1 ]; then
grep_url_pattern='https://[^"[:space:]]*\.apk'
else
grep_url_pattern='https://[^"[:space:]]*\.ipk'
fi

wget -qO- "$REPO" | grep -o "$grep_url_pattern" | while read -r url; do
filename=$(basename "$url")
filepath="$DOWNLOAD_DIR/$filename"
attempt=0
while [ $attempt -lt $COUNT ]; do
msg "Download $filename (count $((attempt+1)))..."
if wget -q -O "$filepath" "$url"; then
if [ -s "$filepath" ]; then
msg "$filename successfully downloaded"
break
fi
fi
msg "Download error for $filename. Retrying..."
rm -f "$filepath"
attempt=$((attempt+1))
done
if [ $attempt -eq $COUNT ]; then
msg "Failed to download $filename after $COUNT attempts"
fi
done

# Check if any files were downloaded
if ! ls "$DOWNLOAD_DIR"/*shadowproxy* "$DOWNLOAD_DIR"/*podkop* >/dev/null 2>&1; then
msg "No packages were downloaded successfully"
exit 1
fi

# Install main packages: shadowproxy and luci-app-shadowproxy
# We look for files containing 'shadowproxy' but NOT 'i18n' (language pack)
for pkg_pattern in shadowproxy luci-app-shadowproxy; do
file=""
# Find file that matches the pattern and is not a language pack
for f in "$DOWNLOAD_DIR"/${pkg_pattern}*; do
if [ -f "$f" ]; then
# Exclude language packs explicitly if they match the pattern loosely
echo "$f" | grep -q "i18n" && continue
file="$f"
break
fi
done

if [ -n "$file" ]; then
msg "Installing $(basename "$file")..."
if ! pkg_install "$file"; then
msg "Failed to install $(basename "$file")"
# Continue anyway, maybe optional
fi
sleep 2
fi
done

# Install Russian language pack
ru=""
for f in "$DOWNLOAD_DIR"/luci-i18n-podkop-ru* "$DOWNLOAD_DIR"/luci-i18n-shadowproxy-ru*; do
if [ -f "$f" ]; then
ru="$f"
break
fi
done

if [ -n "$ru" ]; then
if pkg_is_installed luci-i18n-podkop-ru || pkg_is_installed luci-i18n-shadowproxy-ru; then
msg "Upgrading Russian translation..."
pkg_remove luci-i18n-podkop-ru*
pkg_remove luci-i18n-shadowproxy-ru*
pkg_install "$ru"
else
msg "Русский язык интерфейса ставим? y/n (Install the Russian interface language?)"
while true; do
read -r -p '' RUS
case $RUS in
y|Y)
pkg_install "$ru"
break
;;
n|N)
break
;;
*)
echo "Введите y или n"
;;
esac
done
fi
fi

find "$DOWNLOAD_DIR" -type f -name '*podkop*' -exec rm {} \;
find "$DOWNLOAD_DIR" -type f -name '*shadowproxy*' -exec rm {} \;

msg "Installing OpenWRT sing-box extended..."
if ! wget -O - https://raw.githubusercontent.com/EikeiDev/OpenWRT-sing-box-extended/refs/heads/main/install.sh | sh; then
msg "OpenWRT sing-box extended installation failed"
exit 1
fi

msg "Done. Release source: $REPO_HUMAN_URL"
}
check_system() {
# Get router model
MODEL=$(cat /tmp/sysinfo/model)
msg "Router model: $MODEL"
# Check OpenWrt version
openwrt_version=$(cat /etc/openwrt_release | grep DISTRIB_RELEASE | cut -d"'" -f2 | cut -d'.' -f1)
if [ "$openwrt_version" = "23" ]; then
msg "OpenWrt 23.05 не поддерживается начиная с podkop 0.5.0"
msg "Для OpenWrt 23.05 используйте podkop версии 0.4.11 или устанавливайте зависимости и podkop вручную"
msg "Подробности: https://podkop.net/docs/install/#%d1%83%d1%81%d1%82%d0%b0%d0%bd%d0%be%d0%b2%d0%ba%d0%b0-%d0%bd%d0%b0-2305"
exit 1
fi
# Check available space
AVAILABLE_SPACE=$(df /overlay | awk 'NR==2 {print $4}')
REQUIRED_SPACE=15360 # 15MB in KB
if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
msg "Error: Insufficient space in flash"
msg "Available: $((AVAILABLE_SPACE/1024))MB"
msg "Required: $((REQUIRED_SPACE/1024))MB"
exit 1
fi
if ! nslookup google.com >/dev/null 2>&1; then
msg "DNS is not working."
exit 1
fi
# Check version
if command -v podkop > /dev/null 2>&1; then
local version
version=$(/usr/bin/podkop show_version 2> /dev/null)
if [ -n "$version" ]; then
version=$(echo "$version" | sed 's/^v//')
local major
local minor
local patch
major=$(echo "$version" | cut -d. -f1)
minor=$(echo "$version" | cut -d. -f2)
patch=$(echo "$version" | cut -d. -f3)
# Compare version: must be >= 0.7.0
if [ "$major" -gt 0 ] ||
[ "$major" -eq 0 ] && [ "$minor" -gt 7 ] ||
[ "$major" -eq 0 ] && [ "$minor" -eq 7 ] && [ "$patch" -ge 0 ]; then
msg "Podkop version >= 0.7.0"
break
else
msg "Podkop version < 0.7.0"
update_config
fi
else
msg "Unknown podkop version"
update_config
fi
fi
if pkg_is_installed https-dns-proxy; then
msg "Conflicting package detected: https-dns-proxy. Remove?"
while true; do
read -r -p '' DNSPROXY
case $DNSPROXY in
yes|y|Y)
pkg_remove luci-app-https-dns-proxy
pkg_remove https-dns-proxy
pkg_remove luci-i18n-https-dns-proxy*
break
;;
*)
msg "Exit"
exit 1
;;
esac
done
fi
}
sing_box() {
if ! pkg_is_installed "^sing-box"; then
return
fi
sing_box_version=$(sing-box version | head -n 1 | awk '{print $3}')
required_version="1.12.4"
if [ "$(printf '%s\n%s\n' "$sing_box_version" "$required_version" | sort -V | head -n 1)" != "$required_version" ]; then
msg "sing-box version $sing_box_version is older than the required version $required_version."
msg "Removing old version..."
service podkop stop
pkg_remove sing-box
fi
}
main
