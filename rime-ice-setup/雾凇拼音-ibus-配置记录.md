# 在 Ubuntu 22.04 (GNOME/Wayland) 的 ibus 上配置雾凇拼音

> 目标：把默认的 ibus 拼音（libpinyin，错字多、不联想长句）换成
> **ibus-rime + 雾凇拼音 (rime-ice)** 词库，获得「整句输入 + 大词库 + 智能联想」。

> 💡 **想偷懒？** 直接跑同目录的一键脚本即可，它会自动完成下面所有步骤
> （并按 librime 版本自动决定是否砍 Lua）：
> ```bash
> bash install-rime-ice.sh    # 跑完后注销重新登录生效
> ```
> 想搞懂原理、手动分步操作、或排查问题，再往下看本文档。

---

## 0. 适用环境

本文基于以下环境实测通过：

| 项目 | 值 |
|------|-----|
| 系统 | Ubuntu 22.04.5 LTS |
| 桌面 | GNOME |
| 显示协议 | **Wayland** |
| 输入法框架 | **ibus**（GNOME 原生支持，**不要**在 GNOME Wayland 上换 fcitx5，有坑） |
| librime | 1.7.3（22.04 官方源最高版本，**偏老，是后面踩坑的根因**） |

确认自己环境的命令：

```bash
lsb_release -ds                                   # 系统版本
echo "$XDG_CURRENT_DESKTOP / $XDG_SESSION_TYPE"   # 桌面 / 协议
dpkg -l | grep -iE 'ibus|librime'                 # 已装的框架与库
```

> ⚠️ **关键前提**：本文方案针对 **librime 1.7.3 这种老版本**。雾凇默认大量依赖
> 新版 librime（1.8+）才有的 **Lua 接口**，老库上会崩。所以第 4 步必须
> **砍掉 Lua 组件**。如果你的 librime ≥ 1.8（如 Ubuntu 24.04），可**跳过第 4 步**，
> 直接享受全部功能。

---

## 1. 安装 ibus-rime 与部署工具

```bash
sudo apt update
sudo apt install ibus-rime librime-bin   # ibus 的 rime 引擎 + rime_deployer 预编译工具
```

> `librime-bin` 提供 `rime_deployer`，用来预先编译词库，避免第一次切换时卡顿。

---

## 2. 下载雾凇拼音词库 (rime-ice)

ibus-rime 的用户配置目录是 `~/.config/ibus/rime/`。

```bash
mkdir -p ~/.config/ibus/rime
cd /tmp
# 钉到具体 tag 保证可复现（tag 列表见 https://github.com/iDvel/rime-ice/tags）
git clone --depth 1 --branch 2026.06.03 https://github.com/iDvel/rime-ice.git
cp -r /tmp/rime-ice/* ~/.config/ibus/rime/
rm -rf /tmp/rime-ice          # 清理临时克隆
```

雾凇自带的 `default.yaml` 里 `schema_list` 第一个就是 `rime_ice`（全拼），
所以**默认方案就是全拼**，无需额外配置。想用双拼见文末「附录」。

---

## 3. 预编译词库

```bash
cd ~/.config/ibus/rime
rime_deployer --build ~/.config/ibus/rime ~/.config/ibus/rime/build
# 成功后 build/ 下会有 rime_ice.table.bin(约58M)、rime_ice.prism.bin 等
ls -lh build/rime_ice.table.bin
```

---

## 4. ⚠️ 砍掉 Lua 组件（仅 librime < 1.8 需要）

**症状**：切到 Rime 后**完全打不出中文**，日志里刷：

```
lua_gears.cc:167] LuaProcessor::ProcessKeyEvent of *select_character error(2): attempt to call a nil value
```

**原因**：雾凇的 Lua 脚本调用了新版 librime 才有的接口，老库里这些函数不存在，
每次按键 Lua 处理器就崩，把输入卡死。

**解决**：把主方案 `rime_ice.schema.yaml` 里 `engine:` 段的所有 `lua_*` 组件注释掉。

```bash
cd ~/.config/ibus/rime
cp rime_ice.schema.yaml rime_ice.schema.yaml.bak          # 先备份
sed -i -E 's/^([[:space:]]*)- lua_/\1# 砍lua - lua_/' rime_ice.schema.yaml   # 缩进用 [[:space:]]* 而非写死 4 空格，上游改缩进也不会砍空
grep -nE '^[[:space:]]*- lua_' rime_ice.schema.yaml && echo "还有残留!" || echo "已无生效 lua 组件"
```

被砍掉的是 processors / translators / filters 里的 Lua 项，包括：
以词定字、日期时间、农历、UUID、Unicode、数字大写、计算器、错音纠正、
英文自动大写、置顶/长词/降权过滤、部件拆字辅码等。

> 这些都是**锦上添花**功能。核心的「整句拼音 + 58M 大词库」不依赖 Lua，照常工作。
> 想拿回全部功能，唯一正路是升级到带新版 librime 的系统（如 Ubuntu 24.04），
> 再把 `.bak` 还原即可。

砍完后**重新编译一次**：

```bash
cd ~/.config/ibus/rime
rm -f build/rime_ice.*
rime_deployer --build ~/.config/ibus/rime ~/.config/ibus/rime/build
```

---

## 5. 把 Rime 加进 GNOME 输入源

GNOME 设置里的图形「＋」有时**不刷新、看不到 Rime**。直接用命令写入最省事：

```bash
# 顺序：英文键盘 cn → Rime(主力) → libpinyin(旧拼音保底)
gsettings set org.gnome.desktop.input-sources sources \
  "[('xkb', 'cn'), ('ibus', 'rime'), ('ibus', 'libpinyin')]"
```

> ⚠️ 这条是**整体替换**输入源列表，会覆盖你原有的其它布局/输入法。
> 如果你之前有别的输入源想保留，先 `gsettings get org.gnome.desktop.input-sources sources`
> 看一眼现状，把要保留的项一起写进上面的列表里。（一键脚本用的是「追加」方式，不会覆盖。）

GNOME Shell 会实时生效，右上角输入法菜单里就能看到「中文 (Rime)」。

---

## 6. 让改动生效

**首选：注销重新登录**（或重启）。GNOME Wayland 由 Shell 自己干净地拉起 ibus，
最稳，新引擎一定加载到位。

如果不想重登，临时重启 ibus 守护进程：

```bash
ibus restart           # 优先用这个
# 若上面把 daemon 弄没了(进程查不到)，手动拉起：
pgrep -a ibus-daemon || (nohup ibus-daemon -drxR >/tmp/ibus.log 2>&1 &)
ibus list-engine | grep -i rime    # 确认 rime 引擎在线
```

> ⚠️ **踩过的坑**：在 GNOME Wayland 上直接 `ibus restart` 有时会把
> ibus-daemon 杀掉后**没起回来**，导致**所有中文都打不了**。
> 现象是 `pgrep ibus-daemon` 查不到进程。
> 救回办法就是上面那条 `nohup ibus-daemon -drxR &`。
> 最稳妥还是**注销重登**，别用命令重启。

---

## 7. 验证

按 **Super+空格** 切到「中文 (Rime)」，确认方案是「雾凇拼音」，打：

```
nihaoshijie                  → 你好世界
woquguofangjianlema          → 我去过房间了吗
rengongzhinengfazhanhenkuai  → 人工智能发展很快
```

整句直接出、不用逐字选，即成功。

排错日志（真报错才需留意，WARNING 可忽略）：

```bash
grep -hiE 'error' /tmp/*rime* 2>/dev/null | tail
```

---

## 8. 收尾 / 回滚

- **删掉旧拼音**（确认雾凇稳定后，可选）：
  ```bash
  gsettings set org.gnome.desktop.input-sources sources \
    "[('xkb', 'cn'), ('ibus', 'rime')]"
  ```
- **完全回滚**：恢复 `rime_ice.schema.yaml.bak`，或直接删 `~/.config/ibus/rime/` 整个目录，
  再把输入源 gsettings 改回 `[('xkb','cn'),('ibus','libpinyin')]`。

---

## 附录：改用双拼

编辑 `~/.config/ibus/rime/default.yaml`，把 `schema_list` 里想要的双拼方案
（如小鹤 `double_pinyin_flypy`、微软 `double_pinyin_mspy`）挪到**最前面**，
然后重新编译（第 3 步命令）并重启 ibus。雾凇内置的双拼方案：

```
double_pinyin          自然码      double_pinyin_flypy   小鹤
double_pinyin_mspy     微软        double_pinyin_sogou   搜狗
double_pinyin_abc      智能ABC     double_pinyin_ziguang 紫光
double_pinyin_jiajia   拼音加加
```

---

## 常用操作速查

| 操作 | 方法 |
|------|------|
| 切换输入法 | Super + 空格 |
| 选第 2/3 候选 | 数字键 `2` / `3` |
| 翻页 | `-` / `=` |
| 中英混输 | 大写开头智能识别，不行就切英文键盘 |
| 学习 | 常用词会自动靠前，用几天越来越顺 |

---

*记录日期：2026-06-22 ｜ 环境：Ubuntu 22.04.5 LTS / GNOME / Wayland / librime 1.7.3*
