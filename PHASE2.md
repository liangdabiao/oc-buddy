# OC Buddy 第二阶段（v2）开发交接文档

> 交接对象：接手 oc-buddy v2 开发的 AI/开发者
> 前置阅读：本仓库 README.md + 上游仓库 https://github.com/yczz/oc-english
> 当前代码状态：v1 已完成并发布 GitHub（liangdabiao/oc-buddy），掌机部署包已备好

---

## 一、当前已完成（v1，不要重做）

以下功能已实现并验证（smoke 32 项全绿 + tour 截图 13 张复核通过）：

| 系统 | 状态 | 关键文件 |
|---|---|---|
| 课程数据 | 13 册 / 92 单元 / 3,493 词，data/*.json | tools/extract_content.py |
| 学习中心 | 教材→单元→语法卡→单词表 分页浏览 | App.gd `_show_books/_show_units/_show_lesson` |
| 跟练 | 词义四选一 + 听力辨词（MiMo 云 TTS 读词），答对 +2 积分 | App.gd `_show_practice/_build_cards/_tts_word` |
| 单元考 | 15 题混抽（词义+听力），通过线 12 题，首过 +100 / 刷新纪录按差额 +10 | App.gd `_start_exam/_show_exam/_finish_exam` |
| 积分经济 | 新手 +200 / 答对 +2 / 首过 +100 / 刷新差额 +10 | ProgressStore.gd |
| 商店+衣橱 | 9 部位 50 件装扮，购买/穿上/脱下 | App.gd `_show_shop/_show_wardrobe` |
| 捏脸工坊 | 肤色4/发型8/发色8/眼型6/瞳色6/嘴巴5/腮红，实时预览 | App.gd `_show_face/_cycle_face` + OcView.gd |
| OC 分层渲染 | 27 槽位按上游 SVG paint order 叠加，pngraw File 直读 | OcView.gd（extends Control + TextureRect） |
| MiMo TTS | 云端读词（curl/HTTPRequest 双后端），user://tts_cache 缓存 | MimoClient.gd |

**v2 开发前的强制阅读**（每条都是踩过的真坑）：

1. **不要跑 `--headless --editor`**——在此环境会静默卡死（导入管线死锁），
   卡死时 Godot 进程内存不变（纯挂起）。资源导入的正确路径是
   `--export-pack`（export 进程内自动导入，实测正常）。
2. **`--script` 模式（含 --headless --script）下 ClassDB 不完整**：
   `Sprite2D`/`Node2D` 等 CanvasItem 类**不可见**，`load()` 含这些类引用的
   脚本会解析失败并导致脚本中止（quit 不执行 → 测试挂到 timeout）。
   smoke 必须保持纯 headless 安全版（不 boot Main.tscn）；
   需要视觉断言时用 App 内置 `--screenshot-tour`（正式运行模式）。
3. **python -c / heredoc 修改 GDScript 文件时**：
   - `"\\n"` 在 bash heredoc 里会变成字面换行，破坏 GDScript 字符串——
     用 `chr(10)` 或 Edit 工具
   - `str.replace()` 的 anchor 不匹配时**静默跳过**（不报错）——改完必须
     `grep` 验证替换生效
   - 多轮 patch 会把文件改得千疮百孔——**重要文件先 git init 提交保底**
4. **Godot 自带文件日志**（`user://logs/godot*.log`）捕获全部 stdout/stderr，
   是调试 --script 模式的可靠手段（print 管道输出可能丢失）。
5. **`File.READ_WRITE` 打开不存在的文件会失败**——trace/dump 文件先
   `File.WRITE` 创建，或用 file_exists 分支。

---

## 二、v2 待开发清单（按上游对齐 + 本项目规划）

### 2.1 2.5D 温馨小家（v2 核心，上游「小家」系统）

**上游形态**（src/js/room.js，PixiJS 等距 2.5D）：
- 等距视角：左墙 + 后墙（带窗户挂画）+ 菱形地砖
- 18 件家具（三张床/书桌/书架/沙发/电视/钢琴/地毯/猫窝…）
- 家具有贴地投影和立体层次
- 布置模式：拖动家具自由摆放，自动吸附网格；放不下回弹；右键收进收纳箱

**R36S 移植方案**：
- **美术**：上游 18 件家具 SVG → 沿用 tools/gen_oc_parts.mjs 的 Node 提取
  模式（上游 room.js 有家具 SVG 定义）→ resvg 栅格化为 pngraw
  （tools/rasterize_oc.py 加房间目录支持）
- **渲染**：Godot 2D 等距——房间背景一张图（上游 SVG 栅格化），
  家具为 Sprite2D（**注意：正式运行模式 Sprite2D 可用**，v2 掌机版
  用正式运行；如果要做 --script 自动测试则改 TextureRect）
- **交互**：拖动改方向键移动 + A 放置 + X 收回（掌机无鼠标）
- **数据**：OC 的家具摆放状态存 ProgressStore（`furniture_layout` 字典）
- **网格**：上游网格尺寸从 room.js 提取（等距菱形 tile）
- **入口**：首页加「我的小家」菜单项

**涉及文件**：
- 新增 scripts/RoomView.gd（房间渲染+家具交互）
- App.gd 加 `_show_room()` / 布置模式状态机
- tools/extract_content.py 加 furniture.json 转换（已在上游
  src-tauri/data/furniture.json，18 件，含 id/name/price/svg）
- 商店加家具分类（家具也是积分购买）

### 2.2 多 OC 支持

**上游形态**：可创建多只 OC，每只独立的脸蛋/衣柜/小家，人物栏一键切换。

**R36S 移植方案**：
- ProgressStore 的 `oc` 字典改为 `ocs: {oc_id: cfg}` + `current_oc_id`
- 每只 OC 的 owned/learned 独立还是共享？——上游共享积分，
  独立衣柜——**建议：共享积分，独立衣柜/捏脸/学习进度**
- 首页加「切换 OC」入口
- 新建 OC：命名（掌机输入麻烦——建议预设名字列表随机选）

### 2.3 豆豆小助手（上游 doudou.js）

**上游形态**：黑色团子形象，三种能力——
1. 聊天/问答（13 册词库+语法库**本地检索**，非 AI）
2. 画画（关键词简笔画，本地 SVG）
3. 描述生成自定义衣服（**上游是本地模板组合**，非 AI——
   从 wardrobe.js 的 registerCustomArt 注入档案）

**R36S 移植方案**：
- 能力 1（词库/语法检索）：直接移植——复用 data/*.json
- 能力 3（自定义衣服）：上游把生成的衣服 art 注入 registerCustomArt——
  R36S 版可以用**参数化模板**（颜色/图案组合生成 SVG）实现简化版
- 能力 2（简笔画）：上游简笔画库在本地 SVG，需提取；v2 可裁剪
- UI：左上角团子按钮 + 侧边面板

### 2.4 听力 TTS 离线化（可选）

当前听力题在线调用 MiMo TTS（需 WiFi）。离线方案：
- 预生成 3,493 个单词 mp3（MiMo TTS 批量，约 15-25KB/词 ≈ 60-90MB）
- 批量脚本：curl 循环调 /v1/chat/completions (model=mimo-v2.5-tts)
- 打包进 pck（+60-90MB，pck 从 12MB 变 ~80MB——R36S SD 卡无压力）
- 跟练/考试的听力卡优先读本地缓存，无缓存时在线请求（双保险）

### 2.5 掌机部署与实机验收（当前未完成）

部署包已备好：`.build/oc-buddy-pkg/`（sh + 12MB pck + gptk）+ `oc-buddy.zip`

**部署步骤**（需掌机开机连 WiFi，IP 查询后替换）：
```bash
export R36S_HOST="ark@<IP>"
scp .build/oc-buddy-pkg/oc-buddy.sh "$R36S_HOST:/roms/ports/oc-buddy.sh"
scp .build/oc-buddy-pkg/oc-buddy/oc-buddy.pck \
    .build/oc-buddy-pkg/oc-buddy/oc-buddy.gptk \
    "$R36S_HOST:/roms/ports/oc-buddy/"
ssh "$R36S_HOST" 'chmod +x /roms/ports/oc-buddy.sh && ls -lh /roms/ports/oc-buddy/'
```

**实机验收清单**：
- [ ] 启动无 SCRIPT ERROR（`ssh "$R36S_HOST" 'tail -50 /roms/ports/oc-buddy/log.txt'`）
- [ ] 学习中心 13 册全部可见、翻页正常
- [ ] 跟练：词义题选对 +2 积分、听力题 TTS 播放正常（**需 WiFi**）
- [ ] 单元考 15 题流程、通过后 +100
- [ ] 商店购买扣积分、衣橱换装 OC 形象实时变化
- [ ] 捏脸 7 项切换即时预览
- [ ] 重启应用存档保留（points/owned/learned/examBest）
- [ ] Start 退出正常

**已知风险**（实机首验时重点关注）：
- pngraw File 直读在 FRT 上未实测（PC 正常；FRT 的 File 系统层与
  桌面一致，理论可行，但需实机确认）
- 听力 TTS 需掌机 WiFi 稳定
- 704 张 pngraw 的 File 读性能（启动时 preload 全部纹理约 1-2 秒，
  如感觉慢可改按需加载）

---

## 三、关键实现细节（v2 开发时必须遵守）

### 3.1 OC 分层渲染（OcView.gd）

- **extends Control**（不要改回 Node2D——Sprite2D 在 --script 模式不可见）
- **27 个 TextureRect 槽位**，PIECE_ORDER 数组定义 z 序（上游 paint order）：
  back_art → hair_back → armL_base → armL_top → legL_base → legL_shoe →
  legL_bottom → armR_base → armR_top → held → legR_base → legR_shoe →
  legR_bottom → core_body → shoes_custom → bottom_hip → bottom_torso →
  bottom_custom → top_torso → top_custom → eyes → mouth → blush →
  hair_front → earring → glasses → hat
- 所有部件 PNG 共享 200x300 viewBox，栅格化为 400x600
- **纹理加载**：File 读 `.pngraw` 字节 → `Image.load_png_from_buffer` →
  `ImageTexture.create_from_image`，`_tex_cache` 字典缓存
- **不要改回 `load()`**——pngraw 不走导入管线，load() 会失败
- **不要加 Sprite2D**——--script 模式解析失败会连锁中断

### 3.2 数据管线（tools/）

- `extract_content.py`：上游 src-tauri/data → data/*.json（books/grammar/shop）
  注意 `parse_book` 的 units 循环缩进——曾因 python 替换破坏缩进导致
  每个单词被误当成一个单元（92 变 421）
- `gen_oc_parts.mjs`：Node 调用上游 character.js 的 buildCharacterLayers
  生成部件 SVG——**必须先 registerCustomArt(WARDROBE_ART)**
  （getArt 查的是自定义注册表）
- `rasterize_oc.py`：resvg 栅格化 + PIL alpha 差分
  （diff = 保留与 base 不同的像素 = 隔离 top 部件）
  diff 的 base 名必须与 piece 产出名一致（曾因命名错位全挂）
- `prepare_fonts.py`：DengXian 子集 + DejaVu 合并（IPA 音标），
  cmap 审计零缺字才可通过
- **quizzes_core.yaml 机制不存在**——oc-buddy 的题目全部从词表运行时
  生成（`_build_cards`），无需手写题库

### 3.3 上游源码缓存

- `.build/oc-src/repo`：上游 tarball 解包（含 src/js/character.js、
  src-tauri/data/*.json）
- 上游更新后：重新下载 tarball → 重跑 tools/ 全链 → smoke → 截图 → pck

---

## 四、验收标准（v2 完成时逐项检查）

- [ ] smoke 全绿（`--headless --script res://tools/smoke.gd`）
- [ ] tour 截图全屏无空白（`--path . --screenshot-tour`）
- [ ] pck 导出成功且 `--main-pack pck --quit` 退出码 0
- [ ] 房间：18 件家具可购买/摆放/收回，等距渲染正确
- [ ] 多 OC：切换后捏脸/衣橱/学习进度独立
- [ ] 豆豆：词库检索命中、语法卡弹出
- [ ] GitHub 推送成功（代理 git push 或 school-buddy/tools/api_push.py）
- [ ] 掌机部署后实机验收清单全过

---

## 五、文件清单（v2 涉及）

| 文件 | 操作 |
|---|---|
| scripts/RoomView.gd | 新增 |
| scripts/OcView.gd | 扩展（家具挂点） |
| scripts/App.gd | 加房间屏/多 OC/豆豆入口 |
| scripts/ProgressStore.gd | 加 furniture_layout/多 OC 字典 |
| scripts/MimoClient.gd | 不动（v1 已稳定） |
| tools/extract_content.py | 加 furniture.json 转换 |
| tools/smoke.gd | 加房间/多 OC 断言 |
| data/furniture.json | 上游原样（18 件） |

---

## 六、联系方式与上下文

- 上游仓库：https://github.com/yczz/oc-english（v1.8.3，MIT 缺失标注）
- 本仓库：https://github.com/liangdabiao/oc-buddy
- MiMo API：platform.xiaomimimo.com，Key 在 settings.local.json（gitignored）
- 家族其他项目：r36s-demo-main/ 下的 english-buddy / code-buddy /
  school-buddy / algo-buddy / kid-buddy（同架构可参考）
