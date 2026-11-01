# 当前下载：波形位于字幕上方（2026-10-28）

使用 [HX4S20_Multimedia_1024x600_wave_layer.bit](HX4S20_Multimedia_1024x600_wave_layer.bit)。白条保持75%白底，波形移到字幕图层之上，原波形位置和形态保持。新综合及实际seed13布线已签核：MSlices 4341/4900，Setup +0.195ns、Hold +0.035ns，TNS均0，原六时钟/双角/99.99%覆盖。详见 [WAVE_LAYER_RELEASE.md](WAVE_LAYER_RELEASE.md)。

TF内容未变，无需更新卡。未代用户烧录，实板连续运行观察待完成。旧wave_restore位流及以下历史记录保留。

---

# 当前源码：GUI 实际综合入口修正（2026-10-28，待用户重新综合）

最新 GUI 失败为 5155 MSlices；日志仍为 map_mode=auto，旧式 .prj / DefaultFlow 入口未加载先前 Run 配置。请双击正式工程根目录 [run_area_synth.bat](run_area_synth.bat)，在实际 optimize_gate 前强制使用已签核流程的 high / area_prior / partition 三项参数。详见 [GUI_ACTUAL_ENTRY_FIX.md](GUI_ACTUAL_ENTRY_FIX.md)。

本轮仅完成配置检查，综合、实现与时序验证由用户运行，实际资源结果待确认。RTL 未再修改：白条保持原75%，波形位于字幕上方。现有 .bit 保持上一签核版，尚不含本轮图层改动。

---

# 当前：波形恢复（2026-10-27）

当前下载`HX4S20_Multimedia_1024x600_wave_restore.bit`，实际seed13签核：Setup +0.170ns、Hold +0.022ns，两项TNS均0。仅恢复原波形位置、细线与50%光晕混色，当前清晰楷体字幕、菜单、边框和红幕保留。详情见[WAVE_RESTORE_RELEASE.md](WAVE_RESTORE_RELEASE.md)。

TF内容未变，继续使用已部署的SUB2，无需重写卡。未烧录，实板连续运行验收待完成。以下保留历次发布记录。

---

> 2026-10-27 TF部署更新：已确认FAT32卡序列号202614A3，14336字节SUB2原生24点楷体字模已更新并回读通过，须配套本轮ui_polish位流；旧ui_refine位流不能读取新包。TEXT.TXT及其余14个根目录媒体文件保持原hash。备份和记录见sim/ui_polish_tf_activation.json。未代用户烧录开发板，至少10分钟实板连续运行验收仍待完成。下文保留发布时记录。

# 当前：音波与字幕清晰度修订（2026-10-27）

当前下载`HX4S20_Multimedia_1024x600_ui_polish.bit`，实际seed13签核：Setup +0.040ns、Hold +0.022ns，两项TNS均0。音波上移/增强、菜单恢复疏朗旧风格、原生24点楷体保持32像素显示、字幕随画面揭开/淡入。详情见[UI_POLISH_RELEASE.md](UI_POLISH_RELEASE.md)。

本轮SUB2字模包须与本轮位流配套；实际TF卡部署尚待重新确认与回读。未烧录，实板连续运行验收待完成。以下保留历次发布记录。

---

> 2026-10-26 TF部署更新：已确认FAT32卡序列号202614A3，楷体SUBS.BIN已更新并回读通过；TEXT.TXT及其余14个根目录媒体文件保持原hash。备份和记录见sim/ui_refine_tf_activation.json。未烧录开发板，实板验收仍待完成。下文保留发布时记录。

## 当前发布：楷体字幕与UI整合

当前下载为 `HX4S20_Multimedia_1024x600_ui_refine.bit`（665708字节，SHA256 `507371FBF6B19A262A2253A34667F3B2862BD5BF0D849B8E679113BE43B688BF`）。实际seed13，setup/hold +0.162/+0.022ns，TNS均0，原6时钟、双角、99.99%覆盖；详见`UI_REFINE_RELEASE.md`及`sim/ui_refine_release.json`。
字幕尾端到x约576即可AUTO切图；楷体字模、4像素音乐边框、放大菜单及代码清理已整合。实际TF卡的`SUBS.BIN`尚待部署；未烧录、长期实板稳定性待验收。
根目录仅保留本轮下载位流，旧名称映射保存在`release_archive/ui_refine_20261025/manifest.json`；下方全部旧位流与旧入口说明均为历史。当前构建用`build_ui_refine_synth.tcl`及`build_ui_refine_route.tcl`；复现本次路由设置`UI_REFINE_PNR_SEED=13`。

## 本轮发布：音乐渐变边框与轻盈红幕布
当前使用 HX4S20_Multimedia_1024x600_red_curtain.bit（665708字节，SHA256 0445845FDB6ECA621E5592E8FFC4052B5CF6633E383B0EAB053CCF489DC8839D）。
实际seed7 setup/hold 0.131/0.024ns，TNS均0，6时钟/双角/100.00%覆盖；详见RED_CURTAIN_RELEASE.md与sim/red_curtain_release.json。
边框按四景2～3色随音乐渐变，内缩图片外沿2像素；手动红幕8+48帧，AUTO保持16+16。未烧录，长期实板稳定性待验收。
原curtain及更早说明均为历史，旧8个位流名保留浅金版本，本轮用明确命名red_curtain文件。

# HX4S20 1024×600 多媒体图片播放器

## 本轮更新：浅金揭幕、短介绍与白色堂鼓题字

2026-10-25：手动切图采用中央向两侧、下沿领先的浅金曲面揭幕，保留自动淡入淡出；四段介绍缩至40/41/40/41字（纯滚动约20秒），堂鼓白色逐笔题字移至原图(64,32)。即时缩放、图音缓存、音画同步、菜单、波形、动态边框及Logo保留。

本轮已完成回归、布局布线和独立签核，下载文件为 `HX4S20_Multimedia_1024x600_curtain.bit`（665708字节，SHA256 `AA754F9A474DE4FB69D553FE876405A5FEC3A3C0BF5B70BAEBDCAF26E4A178F2`）。最终seed5建立/保持余量+0.178ns/+0.003ns，两项TNS为0，STA覆盖99.99%；保留原6时钟，修正3组SDC首级同步器误匹配，8ns边界不变，电路和实际布线不变。物理资源LUT15936、FF8972、BRAM63、DSP10。TF根目录已成对启用40/41/40/41字短介绍及字模，其他14个媒体文件保持；旧位流和TF文件均已备份。

本轮未烧录开发板。当前发布依据为 `CURTAIN_RELEASE.md`、`sim/curtain_release.json`、`sim/curtain_route_verification.json`、`sim/curtain_tf_activation.json` 及 `sim/curtain_handoff_readback.json`。原7个常用下载别名已同步为curtain版；下方gallery及更早记录均为历史，不能据其旧hash判断本轮状态。

## 上一发布：国风长介绍与动态边框（历史记录）

2026-10-24 最新下载文件为 `HX4S20_Multimedia_1024x600_gallery.bit`。最终 seed4 建立/保持余量为 **+0.128 ns / +0.019 ns**，TNS均为0，STA覆盖99.99%，原时钟和SDC未改。物理资源 LUT15605/19600、FF8907/19600、LE16117/19600、BRAM63/64、DSP9/29。63块BRAM的字模/动画资源及独立重生成的配置载荷均已回读核对；这不代表实板验收已经通过。

TF根目录已成对启用长介绍 `TEXT.TXT` 和 `SUBS.BIN`，须搭配上述新位流，不能继续使用旧位流测试长介绍。旧TF备份目录已归档清理，图片、音频、播放列表、封面和Logo素材不动。旧字幕、旧位流均在D盘工程内备份。开发板尚未烧录。

以 `GALLERY_ROUTED_RELEASE.md`、`sim/gallery_release.json`、`sim/gallery_route_verification.json` 及 `sim/gallery_tf_activation.json` 为当前发布依据。最新83个输入冻结记录为 `sim/gallery_route_source_audit.json`；GUI工程已恢复D盘路径及缺失源文件，若TD仍打开旧Z盘工程请重新打开此D盘工程。命令行使用本轮 `build_gallery_area.tcl`、`build_gallery_route.tcl` 的面积/拥塞优化流程，不把下文历史 `build.tcl` 的默认策略当作本轮已验收配置。

## 本轮源码最初阶段（历史记录，已被上方发布取代）

最新源码说明见 `GALLERY_UPDATE.md`：蓝色堂鼓题字左移、持续游光边框、手动展卷、菜单美化及四段80字左右介绍，AUTO在介绍结束后换图。五档即时缩放及原有图音缓存路径保持。当前仅完成代码、仿真、资源综合与字模门级审计，尚未进行本轮布局布线、生成新位流或烧录。TF新字幕先在 `gallery_pending_20261024` 暂存，不替换旧程序正在使用的根目录短字幕。

下载目录现存的 `.bit` 仍为下述行起点修复版，不包含本轮新功能，不能将新TXT与旧位流混用。本轮源码与资源报告以 `GALLERY_UPDATE.md`、`sim/gallery_source_audit.json`、`sim/gallery_gate_audit.json` 为准；下述旧版本时序值不代表本轮新源码的布局布线结果。

## 上一下载版本：真实扫描修复

当前修复版：2026-10-24，即时缩放真实扫描行起点修复、字幕入场可见性修复。当前状态以 `ZOOM_REPAIR_RELEASE.md`、`sim/zoom_repair_build_result.json` 及新发布/最终回读账本为准。旧 `0AA11832…564E6FCF` 位流已被实际板测报告“封面即花屏”，撤回使用；`INSTANT_ZOOM_RELEASE.md` 留作问题版本的历史记录。

已查实旧顶层用 `11'd2048` 重建行起点，11位常量被截为0，使行起点失效；真实扫描回归复现第二行读取672字而非512字。修复由 `video_scan` 直接输出 `hc==0` 行脉冲并连接像素读端。字幕初始位置也改为进入场景即可见。最终seed1构建setup/hold +0.179ns/+0.024ns，LUT17370、FF8734、LE18281、BRAM62、DSP10，位流SHA256为 `C0A344A3…3EA34B5`（完整值见新发布说明）。正式发布须通过新账本回读；修复版仍待人类上板验收。

菜单仅为 ZOOM / BRIGHTNESS / CONTRAST / EXIT，取消 SCRIPT/ORIGINAL/FIT/FILL 菜单选择。ZOOM 五档50%、75%、100%、125%、150%，默认100%；直接采样现有SDRAM缓存，不重新读取图片、不重建缓存、不打断音频。笛子恢复六指孔光效，朱红音符从吹孔上浮；堂鼓去掉签条/边框，仅保留纯红竖排逐笔题字。古琴、二胡、堂鼓动作、第一版封面、轮播、淡入淡出、波形和Logo保留。TF已仅更新TEXT.TXT为四条中文介绍，保留其余14个根目录文件；字幕须按KEY2离开封面并将SW2拨到ON（低有效），封面抑制字幕仍为原设计。

五档缩放对象是已加载的1024×600画布，不是任意尺寸BMP的原始分辨率缓存。当前四图均1024×600，因此100%就是原像素；50/75%居中留边，125/150%中心裁剪，最近邻采样。书写/乐器特效随图片缩放，菜单/Logo/底部波形/字幕保持屏幕坐标。此前 `UI_VISIBILITY_RELEASE.md`、`FX_REFINEMENT_RELEASE.md`、`PENDING_UI_VISIBILITY.md`及下文均为历史记录。

正式工程目录：`D:\Anlogic\TD_Project\HX4S20_Multimedia_1024x600`

## 历史版本已实现功能（下文不作为当前使用说明）

- 从 FAT32 TF 卡读取 `PLAYLIST.TXT`，按脚本顺序预载并播放最多 4 张 24 位、无压缩 BMP。
- 支持 `ORIGINAL`、`FIT`、`FILL` 三种真实显示模式：原尺寸居中、等比例完整显示、等比例铺满并居中裁剪。
- 图片只使用淡出—不可见换帧—淡入切换；不会在半透明状态切换 SDRAM 帧地址。
- 中央常驻菜单只保留亮度、对比度、缩放覆盖模式和退出；不再显示会自动淡出的参数提示。
- TF 卡流式播放 `111.WAV`（48 kHz、16-bit、双声道 PCM），使用 512 深度异步 FIFO 跨越 SD/视频时钟域。
- 16 个频率测量通道显示为 32 个窄彩色柱，横向铺满屏幕底部，带快速上升、平滑衰减、高频补偿和高亮顶边；层级为图片之上、字幕之下。频谱余弦系数直接内置在 RTL，不依赖 TD 会忽略的 RAM 初始化文件。
- 正常播放画面右上角显示 96×64 安路 Logo；该图案由原 TF 卡 BMP 转换为片上调色板 ROM，错误页、重建页和菜单页不叠加 Logo。
- 优先读取 `TEXT.TXT`，没有时读取 `HELLO.TXT`；字幕在屏幕底部滚动，使用 50% 白色背景。
- 字幕每张最多 64 个字符。片上中文字模仅包含“你、好、呀、对、不、起、！”，ASCII 可直接显示，其他字符显示为 `?`。
- 图片像素以 RGB565 存入 SDRAM，每个 32 位字保存两个像素，四个 1024×600 帧约占 4.69 MiB；转换时使用 4×4 有序抖动减轻平滑渐变图的长条色带。
- 没有任何合法图片时，仅显示 `NO VALID IMAGE / CHECK TF CARD` 错误页。
- 不包含 MP3 硬件解码和语音合成；`111.mp3` 需先用并列工具目录中的脚本转换为 `111.WAV`。

## TF 卡文件

文件名使用 FAT 8.3 短文件名。示例 `PLAYLIST.TXT`：

```text
IMG1.BMP,5,FIT
IMG0.BMP,4,FILL
IMG2.BMP,7,ORIGINAL
```

每行依次为文件名、显示秒数、显示模式。秒数省略或为 0 时按 5 秒；未知模式按 `FIT`。列表中缺失或格式非法的 BMP 会被跳过，字幕行仍跟随对应的原脚本行。`TEXT.TXT`/`HELLO.TXT` 的第 1～4 行分别对应脚本第 1～4 行；过长行截断到 64 个字符。

音频文件名固定为 FAT 8.3 短文件名 `111.WAV`，格式固定为 48 kHz、16-bit、双声道 PCM WAV。读取器识别 RIFF 块并查找 `data` 块，支持文件跨扇区、跨簇和循环播放。

## 按键

- KEY1：板级复位，换卡后按此键重新扫描。
- KEY2：菜单关闭时切换下一张；菜单打开时减小或切换到前一个值。
- KEY3：打开菜单；菜单中切换到下一项。
- KEY4：菜单关闭时开关自动播放；菜单打开时增大或切换到后一个值。

菜单的 `SCALE` 有 `SCRIPT / ORIGINAL / FIT / FILL`。`SCRIPT` 使用播放列表逐项模式；另外三项会覆盖脚本模式。缩放模式在退出菜单后生效，系统先淡出，再重新生成四个缓存，最后淡入当前图片。选择 `EXIT` 或等待 8 秒可关闭菜单。

重新生成缓存时，屏幕中央显示 `RENDERING`、当前模式和 `IMAGE x / n` 进度，不再表现为无提示黑屏。只有连续 2 秒没有任何读图、缩放或写帧进展才判定停滞，因此大型 ORIGINAL 图片不会再因总读取时间超过 15 秒而误报；缩放输入溢出仍会报错。

亮度和对比度均为 50%、75%、100%、125%、150%。拨码为低电平有效，拨到 `ON` 才启用对应功能：SW1 频谱显示，SW2 字幕显示，SW3 TF 音频播放，SW4 静音。SW3 拨离 `ON` 时暂停并保留 FIFO 和文件位置；SW4 静音时文件仍继续播放，频谱也继续响应音频。

## 构建与验证

TD GUI 打开 `HX4S20_Multimedia_1024x600.al`。命令行构建使用：

```text
td_commands_prompt.exe build.tcl
```

RTL 回归：

```text
python tools/run_tests.py --iverilog-bin <iverilog-portable/bin>
```

`tools/make_project.py` 根据 `sources.f` 更新 TD 原生工程文件。是否可交付必须以最新 `build_timing_status.txt` 中建立/保持时序均非负为准，不能只依据生成了 `.bit` 文件。顶层 RGB565 扫描链必须向 `video_pixels_rgb565` 传递完整 32 位 SDRAM 字；每字包含相邻两个 16 位像素。

## 设计取舍

三种模式采用流式最近邻缩放，逻辑简单、缓存小、运行时模式切换可靠；原工程的双线性模块仍保留并有独立回归测试，但不在主显示链路中使用。板上最终仍需检查 TF 卡兼容性、HDMI 锁定、画面裁剪位置及按键手感。
