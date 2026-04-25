include $(TOPDIR)/rules.mk

PKG_NAME:=shadowproxy

PKG_VERSION:=1.0.0
SHADOWPROXY_METADATA_VERSION:=latest

PKG_RELEASE:=1

PKG_MAINTAINER:=ITDog <podkop@itdog.info>
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/shadowproxy
	SECTION:=net
	CATEGORY:=Network
	DEPENDS:=+sing-box +curl +jq +kmod-nft-tproxy +coreutils-base64 +bind-dig +openssl-util
	CONFLICTS:=https-dns-proxy nextdns luci-app-passwall luci-app-passwall2
	TITLE:=ShadowProxy domain routing app
	URL:=https://shadowproxy.net
	PKGARCH:=all
endef

define Package/shadowproxy/description
	Domain routing. Use of VLESS, Shadowsocks technologies
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/shadowproxy/prerm
#!/bin/sh

grep -q "105 podkop" /etc/iproute2/rt_tables && sed -i "/105 podkop/d" /etc/iproute2/rt_tables

/etc/init.d/podkop stop

exit 0
endef

define Package/shadowproxy/conffiles
/etc/config/podkop
/etc/config/shadowproxy
endef

define Package/shadowproxy/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/podkop $(1)/etc/init.d/podkop

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/podkop $(1)/etc/config/podkop
	$(INSTALL_CONF) ./files/etc/config/shadowproxy $(1)/etc/config/shadowproxy

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/podkop $(1)/usr/bin/podkop
	$(INSTALL_BIN) ./files/usr/bin/shadowproxy-subscription $(1)/usr/bin/shadowproxy-subscription

	$(INSTALL_DIR) $(1)/usr/lib/podkop
	$(CP) ./files/usr/lib/* $(1)/usr/lib/podkop/

	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(SHADOWPROXY_METADATA_VERSION)/g' $(1)/usr/lib/podkop/constants.sh
endef

$(eval $(call BuildPackage,shadowproxy))
