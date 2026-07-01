include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-openclash-sync
PKG_VERSION:=1.2.8
PKG_RELEASE:=1
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

define Package/$(PKG_NAME)
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI app for OpenClash realtime sync
  DEPENDS:=+luci-base +luci-compat +rsync +inotifywait +openssh-client +sshpass
  PKGARCH:=all
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/openclash_sync
endef

define Package/$(PKG_NAME)/description
  Realtime OpenClash config sync to another OpenWrt/iStoreOS device.
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
