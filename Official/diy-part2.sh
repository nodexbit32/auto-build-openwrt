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
# ---------------------------------------------------------
sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile

# =============================================================================
# 3. 物理清障与替换 (SmartDNS 官方最新版)
# =============================================================================
# 1) 清理旧版 smartdns（含 feeds 和 package 本地历史残留）
rm -rf feeds/luci/applications/luci-app-smartdns
rm -rf feeds/packages/net/smartdns
rm -rf feeds/kenzo/luci-app-smartdns feeds/kenzo/smartdns
rm -rf feeds/small/luci-app-smartdns feeds/small/smartdns

rm -rf package/luci-app-smartdns
rm -rf package/smartdns

# 2) 拉取官方 LuCI 前端界面
git clone https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns

# 3) 拉取 SmartDNS 主仓库，提取 openwrt 目录
git clone --depth 1 https://github.com/pymumu/smartdns.git /tmp/smartdns_repo
mv /tmp/smartdns_repo/package/openwrt package/smartdns
rm -rf /tmp/smartdns_repo

# 4) 💥【外科手术】：彻底切除 Rust 与 UI 编译入口
# 删除 smartdns-ui 源码子目录
rm -rf package/smartdns/smartdns-ui

# 抹掉 Makefile 里对 Rust 打包文件的引用
sed -i '/rust-package.mk/d' package/smartdns/Makefile

# 精准删除 smartdns-ui 的构建过程定义，不留任何痕迹
sed -i '/Package\/smartdns-ui/,$d' package/smartdns/Makefile
echo '$(eval $(call BuildPackage,smartdns))' >> package/smartdns/Makefile

# =============================================================================
# 4. Fix MosDNS (sbwml 垂直打击版)
# =============================================================================
# 物理清理残留
rm -rf feeds/packages/net/mosdns
rm -rf package/luci-app-mosdns
rm -rf feeds/small/luci-app-mosdns feeds/small/mosdns


# 垂直拉取：直接进 package 目录，避开 feeds 软链接冲突
git clone --depth=1 https://github.com/sbwml/luci-app-mosdns package/luci-app-mosdns

# =============================================================================
# 5. 确权与刷新安装索引
# =============================================================================
./scripts/feeds install -a

# =============================================================================
# 6. 配置回填与依赖补全
# =============================================================================
if [ -f .config.bak ]; then
    cp .config.bak .config
    echo "--- 已恢复原始配置清单 ---"
fi

make defconfig

# =============================================================================
# 7. 版本号与编译日期注入
# =============================================================================
build_date=$(date +'%Y-%m-%d')
sed -i -E "s/OPENWRT_RELEASE=.{1}%D %V %C.*/OPENWRT_RELEASE='%D %V %C nodexbit32 $build_date'/g" \
package/base-files/files/usr/lib/os-release
