#!/usr/bin/env bash
#
# 一键安装：ibus-rime + 雾凇拼音 (rime-ice)
# 适用：Ubuntu (GNOME / Wayland)。22.04 实测；24.04 等新版按 librime 版本自动适配
#       （24.04 自带 librime>=1.8，会保留 Lua 全部功能）。
#
# 用法：  bash install-rime-ice.sh
# 说明：  会自动检测 librime 版本，老版本(<1.8)自动砍掉雾凇的 Lua 组件。
#         脚本【不会】重启 ibus（在 GNOME Wayland 上重启易把输入法搞挂），
#         装完后请【注销重新登录】生效。
#
set -euo pipefail

RIME_DIR="$HOME/.config/ibus/rime"
REPO="https://github.com/iDvel/rime-ice.git"
# 钉死 rime-ice 版本以保证可复现。想升级词库时把这里换成更新的 tag
# （tag 列表见 https://github.com/iDvel/rime-ice/tags），再重跑脚本即可。
RIME_ICE_TAG="2026.06.03"

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
say "下载雾凇拼音词库 (tag $RIME_ICE_TAG) 到 $RIME_DIR"
# 已有非空配置则先整目录备份，避免覆盖用户自定义（* 不含隐藏文件，正好跳过 .git）
if [ -d "$RIME_DIR" ] && [ -n "$(ls -A "$RIME_DIR" 2>/dev/null)" ]; then
  BACKUP="$RIME_DIR.bak.$(date +%Y%m%d%H%M%S)"
  cp -r "$RIME_DIR" "$BACKUP"
  echo "检测到已有 rime 配置，已备份到 $BACKUP"
fi
mkdir -p "$RIME_DIR"
TMP="$(mktemp -d)"
git clone --depth 1 --branch "$RIME_ICE_TAG" "$REPO" "$TMP/rime-ice"
cp -r "$TMP/rime-ice/"* "$RIME_DIR/"
rm -rf "$TMP"

# ---------- 3. 按 librime 版本决定是否砍 Lua ----------
# 查 librime-bin（脚本刚装的，和 librime 同源同版本）而非 soname 库包 librime1：
# 后者在 24.04 因 64-bit time_t 迁移被改名 librime1t64，查不到会误判版本。
LIBRIME_VER="$(dpkg-query -W -f='${Version}' librime-bin 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+' || echo 0.0)"
say "检测到 librime 版本：$LIBRIME_VER"

# 版本比较：major.minor < 1.8 视为老库
need_strip_lua() {
  awk -v v="$LIBRIME_VER" 'BEGIN{split(v,a,"."); exit !((a[1]<1)||(a[1]==1 && a[2]<8))}'
}

SCHEMA="$RIME_DIR/rime_ice.schema.yaml"
if need_strip_lua; then
  say "librime < 1.8，砍掉雾凇的 Lua 组件（否则会打不出字）"
  cp "$SCHEMA" "$SCHEMA.bak"
  # 缩进用 [[:space:]]* 而非写死 4 空格，避免上游改缩进后 sed 砍空、校验又漏判
  sed -i -E 's/^([[:space:]]*)- lua_/\1# 砍lua - lua_/' "$SCHEMA"
  if grep -qE '^[[:space:]]*- lua_' "$SCHEMA"; then
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
say "把 Rime 追加到 GNOME 输入源（保留你原有的布局/输入法，不覆盖）"
CUR="$(gsettings get org.gnome.desktop.input-sources sources)"
if printf '%s' "$CUR" | grep -q "'rime'"; then
  echo "输入源里已有 Rime，跳过。"
else
  # 含单引号 = 列表里已有条目（空列表的 "[]" / "@a(ss) []" 都无引号）
  if printf '%s' "$CUR" | grep -q "'"; then
    NEW="$(printf '%s' "$CUR" | sed "s/][[:space:]]*$/, ('ibus', 'rime')]/")"
  else
    NEW="[('ibus', 'rime')]"
  fi
  gsettings set org.gnome.desktop.input-sources sources "$NEW"
fi
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
回滚：删除 ~/.config/ibus/rime/（如有备份 .bak.* 可还原），并在
      设置→键盘→输入源里移除 Rime 即可。
=============================================
EOF
