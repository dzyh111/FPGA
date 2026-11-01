# 听见非遗 FPGA多媒体工程

## 当前源码 2026年10月31日

资源压缩与结构整理版，**待用户综合实现**。本轮未运行综合、布局布线或生成新位流。具体改动、验证范围和GUI错误说明见 [OPTIMIZATION_NOTES.md](OPTIMIZATION_NOTES.md)。

- TF读取器23处簇地址表达式共享；32位语义和请求周期保持。
- 缩放余数采用并行减法；原新模块输出和状态逐周期等价。
- GUI的AL与PRJ同步保存面积优先参数；旧5155失败Run完整备份后复位。
- 6个旧参考模块归入rtl/legacy，保留兼容入口；当前44条综合源不变。

## 用户综合步骤

1. 重新打开正式 `HX4S20_Multimedia_1024x600.al`。
2. 从 `Syn Opt` 完整重新综合，再运行 `Phy Opt`。旧Run已备份，不能沿用旧失败网表。
3. 核对新综合参数 `map_mode=area_prior`、`add_map_lut_struct=high`、`multi_thread_mapping=partition`，再检查实际MSlice、六时钟及最终时序。

命令行当前入口为 `build.tcl`，默认综合；设置 `BUILD_STAGE=route` 后在新TD进程中运行才进行实现。面积参数集中在 `tools/area_policy.tcl`。用户要求本轮不代为执行。

## 现有签核位流

`HX4S20_Multimedia_1024x600_wave_layer.bit` 为10月28日已签核版，**不含本轮源码优化**。SHA256为 `994DAF125AE1E8F8F894E9C19C3E04A153072A17B909F51BFF6C1700020B490E`。其实际MSlice 4341/4900、Setup +0.195ns、Hold +0.035ns是历史基线，不是本轮结果。详见 [WAVE_LAYER_RELEASE.md](WAVE_LAYER_RELEASE.md)。

## 代码与资源

- `rtl/`：当前视频、交互、字幕、动画及公共逻辑；`rtl/legacy/`：历史测试参考。
- `user_source/hdl_source/SD/`：TF/FAT、图像读取及帧读写；`IP/`：原有FIFO和PLL。
- `sources.f`：当前综合源清单；`tools/`：构建策略、素材工具与验证入口。
- `tf_media/`：当前配套媒体；本轮未更新TF卡。
- `sim/compact_*`：本轮源码、配置和局部测试证据。所有资源与时序的新结论待用户构建。

功能保持：四景图音、第一版封面、五档即时缩放、音频动画、逐笔题字、音乐边框、菜单、亮度/对比度、Logo、手动8+48帧红幕、自动淡入淡出及字幕轮播。波形在字幕上方，字幕白底75%，OSD/字幕仍为6+3级。

此前README全文保留在 [docs/history/README_before_compact_20261031.md](docs/history/README_before_compact_20261031.md)。历史报告、位流与备份不删除。未代用户烧录，实板至少10分钟连续运行和历史绿点问题仍待验收。
