include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-shadowproxy

PKG_VERSION:=1.0.0
SHADOWPROXY_METADATA_VERSION:=latest

PKG_RELEASE:=1

LUCI_TITLE:=LuCI ShadowProxy app
LUCI_DEPENDS:=+luci-base +shadowproxy
LUCI_PKGARCH:=all
LUCI_LANG.ru:=Русский (Russian)
LUCI_LANG.en:=English

PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=ShadowProxy Team <support@shadowproxy.net>

LUCI_LANGUAGES:=en ru

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)$(HTDOCS)
	$(CP) $(PKG_BUILD_DIR)/htdocs/* $(1)$(HTDOCS)/
	$(INSTALL_DIR) $(1)/
	$(CP) $(PKG_BUILD_DIR)/root/* $(1)/
	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(SHADOWPROXY_METADATA_VERSION)/g' $(1)$(HTDOCS)/luci-static/resources/view/podkop/main.js || true
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
