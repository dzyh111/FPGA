# 资源压缩与工程整理 2026年10月31日

本轮只交付源码、工程配置和局部验证，按用户要求没有运行综合、布局布线或生成位流。当前可下载的wave_layer位流仍是10月28日版本，不包含本轮改动。资源占用、MSlice与新时序必须由用户本轮综合实现后确认。

## 等价优化

1. `user_source/hdl_source/SD/bmp_read.v`：23处互斥数据扇区请求先选择簇号，共享一套32位“减2、可变移位、加数据区起点”表达式；下一扇区偏移也统一。保留完整32位回绕语义，没有缩窄磁盘地址、改变文件格式或增加请求状态/周期。37888组全宽随机及边界向量、18331个实际单周期请求，对照原版全部顶层输出、状态及续接状态一致。播放列表、WAV、五路音频选择/BMP边界/封面回退以及17场景SUB1/SUB2字幕包回归通过。
2. `rtl/video_zoom_rgb565.v`：余数更新改为并行减法和借位选择，避免比较后再串联选择减数与减法。128个全域算术组合、220000次原版/新版周期与内部状态对照通过。原有完整10帧扫描测试因用户中断只完成首帧614400像素，未宣称整套通过。五档缩放、画布语义和像素周期保持。
3. 保持OSD六级加字幕三级、现有按键/拨码、红幕8+48帧、AUTO淡变与字幕触发、波形位置/增益/图层、75%白条、ROM及TF素材。组合逻辑深度的目标是降低；像素/控制与SD请求时延不增加。本轮尚无新STA测量，不宣称已降低实际纳秒延迟或取得全局最小资源。

## GUI报错处理

10月31日11:18的GUI运行实际仍为map_mode=auto，出现5155个MSlices超4900。已同时修复正式AL和PRJ中syn_1的原生策略与UserParams，保留各自源条目、编译顺序、器件和VM的Z:工程路径：map_mode=area_prior，add_map_lut_struct=high，multi_thread_mapping=partition。用户已关闭旧工程且未保存旧配置，防止内存中的旧配置再次覆盖文件。

原生参数读取已在普通与single_run模式核对；官方export_flow_script也能从新Run元数据导出alRun和synWildParams，未执行该流程。正式工程另保存只读配置检查和原生导出证据。原5155失败运行整个_Runs目录移入backup_before_compact_20261031/gui_runs_before_reset，日志和数据库完整保留；GUI将重建运行目录，避免复用失败网表。没有用旧通过网表替换失败网表。

用户下一步：重新打开正式HX4S20_Multimedia_1024x600.al，从Syn Opt重新综合，再继续Phy Opt。不要只打开旧Run的数据库继续实现。新综合中应看到area_prior及high/partition；若配置又被旧GUI回写，关闭旧工程且不保存后运行tools/repair_gui_area_config.ps1再重开。该修复脚本只改工程元数据，不调用TD。

## 结构整理

当前44条综合源由sources.f定义；GUI保持对应的活动Verilog与IPC源条目。6个旧版参考模块归入rtl/legacy，原路径留两行include兼容入口，使历史测试和显式编译路径继续可用；6份预处理后的token与原实现一致。此归档不算作当前电路资源节省。font_cn.mem与spectrum_cos.mem未纳入当前运行链路，但暂保留，避免改变历史生成器。

build.tcl统一分发当前compact综合/实现流程；build_compact_synth.tcl调用tools/area_policy.tcl集中设置面积参数；build_compact_route.tcl复用原6时钟、原SDC和既有签核断言，以新文件名前缀保存未来结果。默认仅综合；BUILD_STAGE=route才进入实现。此前各版本入口和报告保留作历史，不再作为当前默认入口。tools/run_compact_tests.py可按测试名重跑相关用例。

所有旧位流、备份、约束和失败证据保留。未访问TF卡，未操作开发板。本轮仍需用户实际综合/实现；不能以局部仿真PASS代替资源或时序签核。
