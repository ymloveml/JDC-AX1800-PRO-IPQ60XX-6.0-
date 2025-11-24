#!/bin/sh
# shellcheck disable=SC2086,SC3043,SC2164,SC2103,SC2046,SC2155

# 设置默认值以确保脚本在不同环境中都能工作
BUILD_REPO=${BUILD_REPO:-"https://github.com/LiBwrt/openwrt-6.x"}

# 如果在GitHub Actions环境中，尝试使用环境变量
if [ -n "$GITHUB_WORKSPACE" ]; then
  # 如果REPO_URL存在（GitHub Actions环境变量），使用它
  if [ -n "$REPO_URL" ]; then
    BUILD_REPO=$REPO_URL
  fi
  # 简化分支选择逻辑，使用main分支作为默认值
  BRANCH_NAME=${REPO_BRANCH:-"main"}
else
  # 非GitHub Actions环境，直接使用main分支
  BRANCH_NAME="main"
fi

get_sources() {
  # the checkout actions will set $HOME to other directory,
  # we need to reset some necessary git configs again.
  git config --global user.name "OpenWrt Builder"
  git config --global user.email "buster-openwrt@ovvo.uk"

  echo "正在克隆仓库: $BUILD_REPO 分支: $BRANCH_NAME"
  git clone $BUILD_REPO --single-branch -b $BRANCH_NAME openwrt

  cd openwrt
  ./scripts/feeds update -a
  ./scripts/feeds install -a
  cd -
}

echo_version() {
  echo "[=============== openwrt version ===============]"
  cd openwrt && git log -1 && cd -
  echo
  echo "[=============== configs version ===============]"
  cd configs && git log -1 && cd -
}

apply_patches() {
  [ -d patches ] || return 0

  dirname $(find patches -type f -name "*.patch") | sort -u | while read -r dir; do
    local patch_dir="$(realpath $dir)"
    cd "$(echo $dir | sed 's|^patches/|openwrt/|')"
    find $patch_dir -type f -name "*.patch" | while read -r patch; do
      git am $patch
    done
    cd -
  done
}

build_firmware() {
  cd openwrt

  cp ${GITHUB_WORKSPACE}/configs/${BUILD_PROFILE} .config
  make -j$(($(nproc) + 1)) V=e || make -j1 V=sc || exit 1

  cd -
}

package_binaries() {
  local bin_dir="openwrt/bin"
  local tarball="${BUILD_PROFILE}.tar.gz"
  tar -zcvf $tarball -C $bin_dir $(ls $bin_dir -1)
}

package_dl_src() {
  [ -n "$BACKUP_DL_SRC" ] || return 0
  [ $BACKUP_DL_SRC = 1 ] || return 0

  local dl_dir="openwrt/dl"
  local tarball="${BUILD_PROFILE}_dl-src.tar.gz"
  tar -zcvf $tarball -C $dl_dir $(ls $dl_dir -1)
}

get_sources
echo_version
apply_patches
build_firmware
package_binaries
package_dl_src
