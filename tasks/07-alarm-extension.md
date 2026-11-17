# 7 · 报警应用扩展（集成与电脑端）

用户授权范围：在现有加密通信项目上增加布防、撤防、按键模拟开门、本地消音、声光提示、自检和数码管事件计数。起点为 2026-11-17 同步的团队 main `74f8dd147a4e1c2a3ab198aa98605ba4a710716b`，开发分支 `codex/alarm-extension`。

## 文件与协作边界

- 新 RTL：`rtl/alarm_top.v`、`rtl/alarm_ctrl.v`、`rtl/key_debounce.v`、`rtl/alarm_display.v`。
- 新工程配置：`quartus/secure_alarm.qsf`、`quartus/alarm_pins.tcl`、`quartus/alarm.sdc`；在 `secure_comm.qpf` 注册新 revision。
- 新测试：`sim/tb_alarm_ctrl.sv`、`sim/tb_alarm_display.sv`、`sim/tb_alarm_system.sv` 和 `scripts/verify_alarm.py`。
- PC：`pc/demo.py` 与 `pc/test_demo.py` 增加 arm/disarm 别名和回归；复用 `reference.py`。
- 共同说明：README、DESIGN、INTERFACE、电脑端说明和 `docs/alarm-demo.md`。

集成包装层只读取基础 `top` 的公开输出，不改变原 top/comm_ctrl/UART/AES 端口及消息格式，不加入模拟模块到 Quartus。若后续增加查询或主动上报，必须另行定义协议并同步 PC，不能直接向当前一问一答链路插入事件帧。

## 最小交付验证

1. 按键短毛刺、按下/释放抖动、长按单次计数，复位后恢复。
2. 撤防触发不报警；布防短响；布防后触发、消音保留灯、新事件重新鸣叫。
3. 同拍撤防优先、触发优先于消音，布防时按住模拟门键也报警。
4. 自检只在撤防生效，1 秒后结束；布防中止自检；布防时禁止计数清零。
5. BCD 进位 9→10、99→100、999→1000，9999 饱和，撤防保留计数。
6. 从数码管串行引脚重建 14 位，检查位序、段码、6 位扫描、自检、复位和转换消隐。
7. 整机使用真实 UART/AES/协议 RTL，走串行引脚核对加密布防/撤防回执、重复布防、非法命令、半帧复位和报警中复位。
8. 回归原 UART、协议、AES、跨端向量及 PC 测试；检查 Verilog-2001 语法；完整编译并记录资源、引脚和时序。
9. 实板按演示说明逐项核对，记录实际提交号和 SOF 哈希。仿真和编译不能代填实板结果。

## 运行

从仓库根目录：`python scripts/verify_alarm.py --iverilog <iverilog.exe绝对路径> --build-dir <仓库外英文临时目录>`。测试脚本自动加入同目录 vvp，复制源码到临时目录，运行新增与原有回归。仿真只缩短提示音、消抖、显示等应用层计时参数，UART 仍为 434 拍/bit，AES 未替换。

Quartus 从英文副本的 `quartus` 目录执行 `quartus_sh --flow compile secure_comm -c secure_alarm`。操作手册与实际结果见 [报警演示说明](../docs/alarm-demo.md)。
