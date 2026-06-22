#!/usr/bin/env bash
#
# 一键安装：ibus-rime + 雾凇拼音 (rime-ice)
# 适用：Ubuntu (GNOME / Wayland)，已在 22.04 实测
#
# 用法：  bash install-rime-ice.sh
# 说明：  会自动检测 librime 版本，老版本(<1.8)自动砍掉雾凇的 Lua 组件。
#         脚本【不会】重启 ibus（在 GNOME Wayland 上重启易把输入法搞挂），
#         装完后请【注销重新登录】生效。
#
set -euo pipefail

RIME_DIR="$HOME/.config/ibus/rime"
REPO="https://github.com/iDvel/rime-ice.git"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m错误: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- 0. 环境检查 ----------
say "检查环境"
[ "${XDG_SESSION_TYPE:-}" = "wayland" ] || echo "提示：当前不是 Wayland(${XDG_SESSION_TYPE:-未知})，脚本仍可继续。"
command -v gsettings >/dev/null || die "未找到 gsettings，本脚本需要 GNOME 环境。"

# ---------- 1. 安装依赖 ----------
say "安装 ibus-rime 与 librime-bin（需要 sudo）"
sudo apt update
sudo apt install -y ibus-rime librime-bin git

command -v rime_deployer >/dev/null || die "rime_deployer 未安装成功，请检查 librime-bin。"

# ---------- 2. 下载雾凇词库 ----------
say "下载雾凇拼音词库到 $RIME_DIR"
mkdir -p "$RIME_DIR"
TMP="$(mktemp -d)"
git clone --depth 1 "$REPO" "$TMP/rime-ice"
cp -r "$TMP/rime-ice/"* "$RIME_DIR/"
rm -rf "$TMP"

# ---------- 3. 按 librime 版本决定是否砍 Lua ----------
LIBRIME_VER="$(dpkg-query -W -f='${Version}' librime1 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+' || echo 0.0)"
say "检测到 librime 版本：$LIBRIME_VER"

# 版本比较：major.minor < 1.8 视为老库
need_strip_lua() {
  awk -v v="$LIBRIME_VER" 'BEGIN{split(v,a,"."); exit !((a[1]<1)||(a[1]==1 && a[2]<8))}'
}

SCHEMA="$RIME_DIR/rime_ice.schema.yaml"
if need_strip_lua; then
  say "librime < 1.8，砍掉雾凇的 Lua 组件（否则会打不出字）"
  cp "$SCHEMA" "$SCHEMA.bak"
  sed -i -E 's/^(    - lua_)/    # 砍lua \1/' "$SCHEMA"
  if grep -qE '^    - lua_' "$SCHEMA"; then
    die "仍有未注释的 lua 组件，请手动检查 $SCHEMA"
  fi
  echo "已砍 Lua（备份在 $SCHEMA.bak）。核心整句拼音+大词库保留，丢失的是日期/计算器/农历等锦上添花功能。"
else
  echo "librime >= 1.8，保留全部功能，无需砍 Lua。"
fi

# ---------- 4. 预编译词库 ----------
say "预编译词库（约 10-30 秒）"
rm -f "$RIME_DIR/build/rime_ice."*
rime_deployer --build "$RIME_DIR" "$RIME_DIR/build"
[ -f "$RIME_DIR/build/rime_ice.table.bin" ] || die "编译失败，未生成 rime_ice.table.bin"
echo "编译成功：$(ls -lh "$RIME_DIR/build/rime_ice.table.bin" | awk '{print $5}') 词库就位。"

# ---------- 5. 加入 GNOME 输入源 ----------
say "把 Rime 加进 GNOME 输入源（保留旧拼音 libpinyin 做保底）"
gsettings set org.gnome.desktop.input-sources sources \
  "[('xkb', 'cn'), ('ibus', 'rime'), ('ibus', 'libpinyin')]"
echo "当前输入源：$(gsettings get org.gnome.desktop.input-sources sources)"

# ---------- 完成 ----------
cat <<'EOF'

==================== 完成 ====================
请【注销并重新登录】（或重启）让输入法生效。
登录后：
  1. 按 Super+空格 切到「中文 (Rime)」
  2. 确认方案是「雾凇拼音」
  3. 打 nihaoshijie，应整句出「你好世界」

排错：切到 Rime 打不出字 → 在输入法菜单点「部署」，或再注销重登一次。
回滚：删除 ~/.config/ibus/rime/ 并把输入源 gsettings 改回 libpinyin 即可。
=============================================
EOF
