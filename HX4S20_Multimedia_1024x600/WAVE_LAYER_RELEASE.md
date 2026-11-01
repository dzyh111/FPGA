# 波形位于字幕上方：签核发布（2026-10-28）

下载文件：`HX4S20_Multimedia_1024x600_wave_layer.bit`，665708 字节。
SHA256：`994DAF125AE1E8F8F894E9C19C3E04A153072A17B909F51BFF6C1700020B490E`。

白条保持原75%白底；波形在字幕白条和文字之上显示，原位置、粗细、幅度和光晕保留。其他界面、红幕和操作保持，像素及控制信号仍为OSD六级加字幕三级。TF字模包未变，无需更新TF卡。

本轮使用现有已签核流程的 high / area_prior / partition 面积映射参数，新综合与实际seed13布局布线均已完成。实际MSlices 4341/4900，Setup WNS +0.195ns，Hold WNS +0.035ns，TNS均0。原六时钟、双角、STA覆盖99.99%，SDC及限制保持。

84份构建输入冻结核对；复用源码一致的两项相关局部回归；新gate/physical ROM和字幕缓存审核、路由DRC及独立导入数据库重生成位流载荷比对均通过。详情见 sim/wave_layer_release.json、sim/wave_layer_route_verification.json 和 sim/wave_layer_handoff_readback.json。

新构建入口为 build_wave_layer_synth.tcl 与 build_wave_layer_route.tcl。旧GUI的5155失败记录、旧签核报告及wave_restore位流保持，不能混作本轮结果。未代用户烧录，实板至少10分钟连续运行验收仍待完成。
