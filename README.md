# OC Buddy — 带着OC学英语（R36S 掌机版）

Port of 「带着OC学英语」(upstream oc-english by yczz, Tauri desktop) to the R36S
handheld. Godot 3.5.3 + FRT runtime, PortMaster three-piece packaging.
<img width="640" height="480" alt="image" src="https://github.com/user-attachments/assets/e9d935cb-e93b-430e-b16a-ecc4f9323c4f" />

**Upstream**: https://github.com/yczz/oc-english — 学习英语赚积分，积分给 OC
捏脸换装。本仓库是其 R36S 移植版（Godot 3.5.3 + GDScript）。

## 功能

- **学习中心**：人教版英语 13 册教材（小学 3-6 年级 + 初中 7-9 年级），
  92 单元 / 3,493 个单词（含音标），每册配语法卡
- **跟练**：每个单词两张卡——词义四选一 + 听力辨词（MiMo TTS 云端读词），
  答对赚积分
- **单元考**：跟练全部完成后解锁，15 题（词义+听力混抽），通过线 12 题
- **积分经济**：新手礼包 +200 / 跟练答对 +2 / 单元考首过 +100 / 刷新纪录按差额 +10
- **商店 + 衣橱**：9 部位 50 件装扮（帽子/眼镜/上衣/下装/鞋子/手持/背饰/耳饰），
  积分购买后随时换装
- **捏脸工坊**：肤色 4 / 发型 8 / 发色 8 / 眼型 6 / 瞳色 6 / 嘴巴 5 / 腮红开关，
  实时预览分层渲染的 OC
- **听力**：MiMo 云端 TTS 读单词（需 WiFi + MiMo API Key，设置页查看状态）

## 内容来源

课程数据（13 册教材 JSON / 语法卡 / 衣橱装扮）来自上游 oc-english 仓库
（src-tauri/data），上游未附 LICENSE，内容仅供个人学习使用；角色与家具的
SVG 美术经上游生成器逐件栅格化为 400x600 PNG（9.3MB，1317 件）。

## 构建

```bash
python tools/extract_content.py       # 上游 data -> data/*.json
python tools/gen_oc_parts.mjs         # 角色部件 SVG（需 Node + 上游 src/js）
python tools/rasterize_oc.py          # SVG -> pngraw（resvg + PIL 差分）
python tools/prepare_fonts.py         # 字体子集 + 缺字审计
godot --headless --path . --script res://tools/smoke.gd   # 32 项断言
mkdir -p .build/oc-buddy
godot --headless --path . --export-pack "Linux/X11" .build/oc-buddy/oc-buddy.pck
```

## 掌机部署（PortMaster）

三件套（`oc-buddy.sh` + `oc-buddy/oc-buddy.pck` + `oc-buddy.gptk`）放入
`/roms/ports/`，chmod +x，重启 EmulationStation 后在 Ports 菜单启动。
需要 FRT_3.5.2 运行时。**首次使用需 WiFi + MiMo API Key**（听力题云端读词，
其他功能离线可用）。

## 按键

A(J/空格) 确认/换装 · B(K/Esc) 返回 · 左右键翻页/换样式 · Select(P) 首页 · Start(Esc) 退出

## 授权

代码无显式授权（继承上游仓库的默认版权）；课程数据仅供个人学习使用。
角色/装扮 SVG 美术由上游生成器绘制。
