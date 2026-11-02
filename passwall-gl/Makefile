# PassWall GL.iNet fork: page for the GL.iNet 4.x admin panel.
#
# This is free software, licensed under the GNU General Public License v3.
#
# Build the page first (needs Node.js): npm --prefix ui ci && npm --prefix ui run build
# That writes root/www/views/gl-sdk4-ui-passwall.common.js.gz, which this
# package installs as-is.

include $(TOPDIR)/rules.mk

PKG_NAME:=passwall-gl
PKG_VERSION:=0.1.1
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-only

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=net
  CATEGORY:=Network
  TITLE:=PassWall page for the GL.iNet admin panel
  DEPENDS:=+luci-app-passwall
  PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
  Adds a PassWall page under VPN in the GL.iNet 4.x admin panel.
  It drives the same PassWall engine and settings as the LuCI pages.
endef

define Build/Compile
endef

Package/$(PKG_NAME)/preinst = $(file < $(CURDIR)/preinst.sh)
Package/$(PKG_NAME)/postinst = $(file < $(CURDIR)/postinst.sh)

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/share/oui/menu.d
	$(INSTALL_DATA) ./root/usr/share/oui/menu.d/passwall.json $(1)/usr/share/oui/menu.d/
	$(INSTALL_DIR) $(1)/usr/lib/oui-httpd/rpc
	$(INSTALL_DATA) ./root/usr/lib/oui-httpd/rpc/passwall $(1)/usr/lib/oui-httpd/rpc/
	$(INSTALL_DIR) $(1)/usr/share/gl-validator.d
	$(INSTALL_DATA) ./root/usr/share/gl-validator.d/passwall.lua $(1)/usr/share/gl-validator.d/
	$(INSTALL_DIR) $(1)/usr/share/passwall-gl
	$(INSTALL_DATA) ./root/usr/share/passwall-gl/api.lua $(1)/usr/share/passwall-gl/
	$(INSTALL_BIN) ./root/usr/share/passwall-gl/uninstall.sh $(1)/usr/share/passwall-gl/
	$(INSTALL_DIR) $(1)/www/views
	$(INSTALL_DATA) ./root/www/views/gl-sdk4-ui-passwall.common.js.gz $(1)/www/views/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
