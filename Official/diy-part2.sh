#!/bin/bash
#
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# =============================================================================
# 1. 【核心备份】锁死配置
# =============================================================================
[ -f .config ] && cp .config .config.bak

# =============================================================================
# 2. 自动定位 Rust 的 Makefile 并关闭 CI LLVM 下载
# =============================================================================
# sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile

# =============================================================================
# 3. 物理清障与替换 (清理 clashoo)
# =============================================================================
rm -rf feeds/small/clashoo
rm -rf feeds/small/luci-app-clashoo

# =============================================================================
# 4. Fix MosDNS
# =============================================================================
rm -rf feeds/packages/net/mosdns
rm -rf package/luci-app-mosdns

# =============================================================================
# 5. reF1nd sing-box 整合
# =============================================================================

# -----------------------------------------------------------------------------
# 5.1 删除官方 sing-box，避免与 small 版本冲突
# -----------------------------------------------------------------------------
rm -rf feeds/packages/net/sing-box
rm -rf package/feeds/packages/sing-box

# -----------------------------------------------------------------------------
# 5.2 更新并重新安装 feeds
# ※※※ 重要 ※※※
# 必须先更新并安装 feeds，确保 small sing-box 正确注册，
# 否则构建系统可能找不到 sing-box。
# 更新操作可能覆盖此前的修改，因此必须在 feeds 更新安装完成后，
# 再修改 small sing-box Makefile。
# -----------------------------------------------------------------------------
./scripts/feeds update -a
./scripts/feeds install -a

# =============================================================================
# 5.3 暂时禁用 HomeProxy IPv6 DNS 补丁
# 原因：与当前 reF1nd 源码不兼容
# =============================================================================

PATCH_FILE="feeds/small/sing-box/patches/110-homeproxy-dns-ipv6-by-outbound.patch"
DISABLED_FILE="feeds/small/sing-box/110-homeproxy-dns-ipv6-by-outbound.patch.disabled"

if [ -f "$PATCH_FILE" ]; then
    mv "$PATCH_FILE" "$DISABLED_FILE"
    echo "已禁用 HomeProxy IPv6 DNS 补丁"
elif [ -f "$DISABLED_FILE" ]; then
    echo "HomeProxy IPv6 DNS 补丁已经处于禁用状态"
else
    echo "未找到 HomeProxy IPv6 DNS 补丁，跳过"
fi

# =============================================================================
# 5.4 修改 small sing-box Makefile，自动获取版本和 HASH
# =============================================================================

# 自动获取 reF1nd 最新版本 Tag
REF1ND_REPO="https://github.com/reF1nd/sing-box.git"

REF1ND_VERSION=$(
    git ls-remote --tags --refs "$REF1ND_REPO" |
    awk '{sub("refs/tags/","",$2); sub(/^v/,"",$2); if ($2 ~ /-reF1nd$/) print $2}' |
    sort -V |
    tail -n 1
)

if [ -z "$REF1ND_VERSION" ]; then
    echo "ERROR: 无法获取 reF1nd 最新版本！"
    exit 1
fi

echo "自动获取 reF1nd 版本：$REF1ND_VERSION"

SMALL_SB_MK="feeds/small/sing-box/Makefile"
SOURCE_URL="https://codeload.github.com/reF1nd/sing-box/tar.gz/v${REF1ND_VERSION}"

if [ ! -f "$SMALL_SB_MK" ]; then
    echo "ERROR: small sing-box Makefile 不存在！"
    exit 1
fi

# 自动下载源码并计算 SHA256
TMP_ARCHIVE=$(mktemp)

if ! wget -qO "$TMP_ARCHIVE" "$SOURCE_URL"; then
    echo "ERROR: reF1nd 源码下载失败！"
    rm -f "$TMP_ARCHIVE"
    exit 1
fi

REF1ND_HASH=$(sha256sum "$TMP_ARCHIVE" | awk '{print $1}')
rm -f "$TMP_ARCHIVE"

echo "reF1nd Version: $REF1ND_VERSION"
echo "reF1nd SHA256:  $REF1ND_HASH"

# 修改 small Makefile
sed -i \
    -e "s|^PKG_UPSTREAM_VERSION:=.*|PKG_UPSTREAM_VERSION:=${REF1ND_VERSION}|" \
    -e 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://codeload.github.com/reF1nd/sing-box/tar.gz/v$(PKG_UPSTREAM_VERSION)?|' \
    -e "s|^PKG_HASH:=.*|PKG_HASH:=${REF1ND_HASH}|" \
    "$SMALL_SB_MK"

# APK 版本号去掉 -reF1nd 后缀
if ! grep -q 'patsubst %-reF1nd' "$SMALL_SB_MK"; then
    sed -i '/^PKG_RELEASE/i PKG_VERSION:=$(patsubst %-reF1nd,%,$(PKG_VERSION))' \
        "$SMALL_SB_MK"
fi

echo "--- reF1nd sing-box Makefile 修改完成 ---"

# =============================================================================
# 6. 配置回填与依赖补全
# =============================================================================
if [ -f .config.bak ]; then
    cp .config.bak .config
    echo "--- 已恢复原始配置清单 ---"
fi

make defconfig

# =============================================================================
# 6.1 sing-box TUN auto_redirect 内核支持
# =============================================================================
for pkg in kmod-nfnetlink-queue kmod-nft-queue; do
    if grep -q "^# CONFIG_PACKAGE_${pkg} is not set" .config; then
        sed -i "s/^# CONFIG_PACKAGE_${pkg} is not set/CONFIG_PACKAGE_${pkg}=y/" .config
    elif grep -q "^CONFIG_PACKAGE_${pkg}=" .config; then
        sed -i "s/^CONFIG_PACKAGE_${pkg}=.*/CONFIG_PACKAGE_${pkg}=y/" .config
    else
        echo "CONFIG_PACKAGE_${pkg}=y" >> .config
    fi
done

# =============================================================================
# 7. 版本号与编译日期注入
# =============================================================================
build_date=$(date +'%Y-%m-%d')
sed -i -E "s/OPENWRT_RELEASE=.{1}%D %V %C.*/OPENWRT_RELEASE='%D %V %C nodexbit32 $build_date'/g" \
package/base-files/files/usr/lib/os-release

echo "build_date: $build_date"
