# 器材柜加密布防与声光报警演示

本版把原有 AES-128 + UART 控灯链路作为布防控制通道，加入开发板本地交互。KEY1 模拟开门，不连接真实门磁或柜锁；声音来自板载蜂鸣器，未使用 WM8978 或外接喇叭。按键报警状态目前不上传电脑。

## 下载与运行

1. 使用 Quartus 18.0 打开 `quartus/secure_comm.qpf`，在 Project → Revisions 选择 **secure_alarm**，顶层应为 **alarm_top**。基础版 `secure_comm` 不含报警外设。
2. 完整编译后，在 Programmer 选择 `quartus/output_files/secure_alarm.sof` 下载。当前源路径含中文，如果 Quartus 无法打开工程，将源码复制到英文目录后编译，保持 `rtl` 与 `quartus` 相邻。也可使用本次验证生成的 SOF，实际构建信息见下文。
3. 板卡供电、USB-Blaster、板载 USB 串口与跳帽按原工程接法；电脑端为 115200、8N1、无流控。按下再松开独立 RESET，等待按键稳定。
4. 安装依赖：`python -m pip install -r pc/requirements.txt`。把下面的 COM3 改成实际串口号。

```powershell
# 开启监测
python pc/demo.py --port COM3 --command arm

# 解除监测和当前报警
python pc/demo.py --port COM3 --command disarm
```

on/off 仍可用，分别等价于 arm/disarm。请求和回执的共用密文全部沿用 INTERFACE.md。`PASS` 表示 FPGA 报告布防位与命令一致，仍需观察板上实际表现；电脑程序无法从现有回执识别下载的是基础版还是报警版。

## 板上操作

| 操作/显示 | 撤防状态 | 布防状态 |
|---|---|---|
| KEY1（模拟开门） | 无报警、不计数 | 每次有效按下触发报警、计数加一并取消旧消音 |
| KEY2（本地消音） | 无动作 | 有报警时消音，保留报警灯 |
| KEY3（自检） | D7–D9 点亮，蜂鸣、888888 持续 1 秒 | 忽略，防止覆盖报警 |
| KEY4（计数清零） | 清为 0000 | 忽略 |
| D6 | 灭 | 常亮，表示布防 |
| D7 | 灭；自检时亮 | 有报警时每 250 ms 亮/灭交替 |
| D8 | 灭；自检时亮 | 有报警且已消音时常亮 |
| D9 | 仅自检时亮 | 灭 |
| 数码管 | 右四位事件次数，左两位空白；自检显示 888888 | 同左，最大 9999 后保持 |

按键按下和释放各需约 20 ms 稳定时间。长按 KEY1 只记录一次；释放稳定后重新按下才计下一次。布防时已按住 KEY1，也会立即记录一次触发，避免“开门状态下布防却没有报警”的演示漏洞。

首次从撤防转为布防，蜂鸣器短响 100 ms；重复 arm 不重复短响，也不会清除已有报警/消音。报警使用约 2 kHz 音调，响 250 ms、停 250 ms。消音后 D7 继续闪烁，D8 亮；新的 KEY1 事件会重新鸣叫。撤防清除报警、消音并停止声音，计数保留；KEY4 或 RESET 清零。复位清除所有状态和计数，数据不保存在掉电存储中。

D6 在自检期间也始终表示布防位，自检只点亮 D7–D9。自检过程中电脑布防会中止自检。KEY1 与 KEY2 同拍有效时，新的触发优先；撤防优先于本地触发/消音。撤防转换同拍不启动自检。

## 建议现场演示顺序

1. RESET 后确认 D6–D9 灭，计数 0000；按 KEY1，不报警。
2. 按 KEY3，确认 1 秒自检并自动结束，计数不变。
3. 电脑运行 arm，核对加密回执、D6 亮及短提示音。
4. 按 KEY1，确认 D7 闪烁、间歇蜂鸣、计数 0001；持续按住不再递增。
5. 按 KEY2，确认安静但 D7 仍闪、D8 亮。重复 arm，仍保持消音。
6. 松开后再次按 KEY1，确认计数 0002、D8 灭、重新鸣叫。
7. 布防时按 KEY4，计数仍为 0002；按 KEY3，不启动自检。
8. 电脑运行 disarm，确认 D6–D9 灭、声音停止、计数仍 0002。
9. 按 KEY4，计数恢复 0000。然后按住 KEY1 再布防，确认同样会报警。
10. 最后验证报警中 RESET：灯灭、声音停止、计数清零，可以再次正常布防。

## 硬件引脚依据

本工程沿用征途 Pro EP4CE10F17C8，50 MHz。新增约束只在 `secure_alarm` 生效，见 `quartus/alarm_pins.tcl`。

| 资源 | 顶层端口 | FPGA 引脚 | 电平/用途 |
|---|---|---|---|
| KEY1 | key_n[0] | M2 | 低有效，模拟开门 |
| KEY2 | key_n[1] | M1 | 低有效，消音 |
| KEY3 | key_n[2] | E15 | 低有效，自检 |
| KEY4 | key_n[3] | E16 | 低有效，清零 |
| D6 | led_n | L7 | 低有效，布防 |
| D7 | alarm_led_n | M6 | 低有效，报警 |
| D8 | muted_led_n | P3 | 低有效，已消音 |
| D9 | test_led_n | N3 | 低有效，自检 |
| 蜂鸣器 | beep | J11 | 2 kHz 方波，空闲高 |
| 数码管移位时钟 | shcp | B1 | 74HC595 SHCP |
| 数码管锁存时钟 | stcp | K9 | 74HC595 STCP |
| 数码管串行数据 | ds | R1 | 段选/位选串行数据 |
| 数码管输出使能 | oe | L11 | 低有效 |

原时钟 E1、复位 M15、UART RX N6/TX N5 保持。厂家来源：[按键引脚表](https://doc.embedfire.com/fpga/altera/ep4ce10_pro/zh/latest/code/i2c_ad.html)、[LED 引脚表](https://doc.embedfire.com/fpga/altera/ep4ce10_pro/zh/latest/code/flow_led.html)、[蜂鸣器实验](https://doc.embedfire.com/fpga/altera/ep4ce10_pro/zh/latest/code/beep.html)、[数码管接线和串行位序](https://doc.embedfire.com/fpga/altera/ep4ce10_pro/zh/latest/code/seg_static.html)、[数码管引脚表](https://doc.embedfire.com/fpga/altera/ep4ce10_pro/zh/latest/code/seg_danamic.html)。厂家概览把蜂鸣器称为有源，但专门实验、实物照片标为无源；本版按专门实验采用方波驱动，最终声音和空闲电平仍需在实际板卡上核对。

## 仿真和构建复现

准备同一套 Icarus 的 `iverilog`、`vvp`，在仓库根目录执行：

```powershell
python scripts/verify_alarm.py --iverilog C:/tools/iverilog/bin/iverilog.exe --build-dir C:/fpga-alarm-test
```

把工具路径替换为实际安装位置。build-dir 必须在源码仓库外且为英文路径。脚本复制 RTL/测试到构建目录，设置英文 TMP/TEMP 和工具 PATH，先用 `-g2001` 检查真实顶层，再运行 10 组仿真和电脑端单元测试。原协议独立 bench 的 AES 替身仍仅用于原协议握手回归；新增 `tb_alarm_system` 使用真实 UART、协议和 AES，未替换任何功能模块，只缩短应用层提示时长、按键消抖与显示扫描参数。UART 保留真实的每 bit 434 拍。

Quartus 从英文副本的 quartus 目录执行：

```powershell
& 'D:/intelFPGA/18.0/quartus/bin64/quartus_sh.exe' --flow compile secure_comm -c secure_alarm
```

生成程序为 `output_files/secure_alarm.sof`。保存资源、引脚及 TimeQuest 报告，核对 50 MHz 内部 setup/hold，以及外部异步引脚的约束范围。仿真与编译通过不代替实板验收。

## 本次实际验证记录

日期：2026-11-17。源代码基于团队 main `74f8dd147a4e1c2a3ab198aa98605ba4a710716b`，扩展在本地 `codex/alarm-extension` 工作区中，尚未提交。不能把基础提交号写成扩展版实板验收号。

- Icarus Verilog 13.0：严格 `-g2001` 顶层编译通过；10 组仿真全部通过，其中新增 3 组分别覆盖报警/消抖、数码管引脚位序、完整串口加密链路。控制测试覆盖计数到 9999 饱和及自检中布防。
- Python：`Ran 18 tests`、`OK`，覆盖原通信异常/超时与新 arm/disarm 密文一致性、错误状态拒绝。模拟只替代串口层，不连接真实板卡。
- 实际仿真入口：`python scripts/verify_alarm.py --iverilog <下列工具目录>/iverilog.exe --build-dir <下列仿真目录>`。
- 工具目录：`C:/Users/30464/.codex/visualizations/2026/11/15/01a1df00-38f7-7ca1-aaea-3272bd00873c/fpga_prs_236_clyv8q6f/role3_kf9j1j4g/icarus_tools/ucrt64/bin`。
- 仿真目录：`C:/Users/30464/.codex/visualizations/2026/11/17/01a1e894-9810-7962-9d9b-3ed50b9c398a/alarm_test`；实际命令与输出保存在 `regression.log`。
- Quartus 18.0 完整编译：`Quartus Prime Full Compilation was successful. 0 errors, 6 warnings`，生成 `quartus/output_files/secure_alarm.sof`。实际命令与上节相同，工作目录为 `C:/Users/30464/.codex/visualizations/2026/11/17/01a1e894-9810-7962-9d9b-3ed50b9c398a/alarm_build/quartus`。
- 布局布线后资源：9,166 / 10,320 逻辑单元（89%）、1,239 寄存器、2,048 bit 存储、17 个引脚、0 PLL。已逐项核对 `.pin` 中 17 个端口的位置和 3.3-V LVTTL 标准，包括全部新增外设，没有自动分配或忽略的引脚。
- 内部 50 MHz 时序：跨全部分析角最差 setup 为 **5.687 ns**（Slow 85°C），最差 hold 为 **0.153 ns**（Fast 0°C）；TNS 均为 0。Slow 85°C Fmax 69.87 MHz。快速模型 setup 的 13.430 ns 不是全角最差值。
- 约束范围：异步按键至首级同步器有专门 false path，后级继续计时；TimeQuest 识别 5 条同步链。报告仍列出 rst_n / uart_rxd 两个输入和全部 10 个输出没有外部 I/O delay，不能声称所有外部路径都已约束。LED/蜂鸣器为非同步指示输出，串口为异步收发，数码管仍需结合真实 74HC595 和板卡上板确认。
- 6 条告警：4 条为未指定并行处理器数；1 条为 10 个输出使用默认驱动强度；1 条为 3.3-V IO 的电气条件提醒（7 个输入）。这些没有作为错误忽略掉，实板需按厂家供电和电气条件验证。完整日志、引脚表、资源和时序报告已放入 `quartus/output_files/secure_alarm*`。
- RTL/Tcl/SDC 构建输入与工作区逐字节一致；Quartus 自动展开的已有 IO 标准、版本/保留引脚元数据和工程 revision 排序已单独核对，无功能配置差异。源码与构建输入的 SHA-256 都在 `quartus/output_files/secure_alarm-build.json`，其中明确标记尚未提交、未做实板测试。下载文件和报告属于生成产物，被 Git 忽略；其他成员从源码重新编译。
- 本次 SOF 为 358,725 字节，SHA-256：`dca7b0148e1b4dd4bb1b95322b13b5b27ff14323be4cb35e8def983236ba3d09`。
- 实板：未执行。需要人工核对板卡版本、所有灯/按键/数码管、蜂鸣器实际声音及完整演示流程。

| 实板项目 | 实际结果 | 备注 |
|---|---|---|
| 实际 Git 提交号、SOF SHA-256 | 待填写 | 提交扩展后重新确认 |
| 撤防 KEY1 无报警 | 待填写 | |
| 布防命令与回执、100 ms 短响 | 待填写 | |
| KEY1 报警、长按单次计数 | 待填写 | |
| KEY2 消音保留灯、新事件恢复声音 | 待填写 | |
| KEY3 自检和自动结束 | 待填写 | |
| KEY4 只在撤防清零 | 待填写 | |
| 计数显示、撤防保留、RESET 清零 | 待填写 | |
| 非法命令、半帧复位、连续交互 | 待填写 | |

固定实验密钥和单分组 ECB 演示没有消息认证及防重放；本次扩展用于课程应用展示，不代表成品门禁或安防系统。
