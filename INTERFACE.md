# 公共接口与时序

本文件用于所有模块及其测试。模块声明见 rtl/ 对应源码，连接见 rtl/top.v。涉及公共接口的变化由组长同步到本文件及相关任务书。

## 时钟与复位

clk 为 50 MHz，周期 20 ns，所有接口在上升沿采样。rst_n 为异步低有效复位，复位优先于启动和传输。复位后 UART 发送引脚为 1，rx_valid、tx_valid、start、busy、done 为 0，tx_ready 为 1，字节/分组输出及计数清零，协议回到接收态，led_on 为 0。

led_on 由 comm_ctrl 唯一维护，1 表示亮。top.v 已用 led_n = ~led_on 转换板上低有效 LED 极性。

## 串口线上字节

串口采用 115200、8N1、无流控。50 MHz 下每位取 434 个 clk 周期，实际约 115207 baud。每字节空闲高、起始位低、8 个数据位、停止位高，数据位按 bit 0 至 bit 7 发送。

每条请求及回执各为 16 个原始字节。终端可显示十六进制，串口写入的是 bytes。帧边界由固定长度确定，首字节对应分组 [127:120]，末字节对应 [7:0]。

电脑每次发一整帧，收到并校验完整回执后才发下一帧。协议控制器只在接收态接收请求，在其余状态丢弃 rx_valid。一条不完整请求的恢复步骤为复位 FPGA、清空电脑端缓存、重新发送整帧。

## 模块端口

以下表格方向均相对于所属模块。clk、rst_n 的方向为输入。

| 模块 | 输入 | 输出 |
|---|---|---|
| uart_rx | uart_rxd（1 位） | rx_data[7:0]、rx_valid（1 位） |
| uart_tx | tx_data[7:0]、tx_valid（1 位） | tx_ready（1 位）、uart_txd（1 位） |
| aes_enc / aes_dec | block_in[127:0]、start（1 位） | block_out[127:0]、busy（1 位）、done（1 位） |
| comm_ctrl | rx_data[7:0]、rx_valid、tx_ready；dec_busy、dec_done、dec_output[127:0]；enc_busy、enc_done、enc_output[127:0] | tx_data[7:0]、tx_valid、led_on；dec_input[127:0]、dec_start；enc_input[127:0]、enc_start |

comm_ctrl 的 dec_input 连接 aes_dec 的 block_in，dec_output 来自其 block_out；enc 侧同理。除表中标明的总线，其余信号均为 1 位。

## UART 字节握手

uart_rx 同步外部输入，确认起始位，在数据位中心采样并检查停止位。完整合法字节到达后，rx_valid 拉高一拍，rx_data 同时有效。接收端在 rx_valid 为高的上升沿保存数据。检测到错误停止位时丢弃该字节，等待线路恢复高电平后重新检测起始位。

uart_tx 空闲时 tx_ready=1。仅在 tx_valid && tx_ready 为高的上升沿锁存一个 tx_data，随后 tx_ready=0，直到该字节停止位发送完毕才重新拉高。控制器在未握手时保持 tx_valid 和 tx_data，每成功握手一次才前进到下一个字节。

tx_ready 表示可以接受新字节。最后一个字节握手后 UART 会自行发送完毕，协议可以回到接收态。电脑收到完整回执后才发送下条请求，因此两端能连续进行多轮交互。

## AES 分组握手

空闲核 busy=0、done=0。start && !busy 为高的上升沿接受任务并锁存 block_in，该沿之后 busy=1。核在 busy 期间忽略 start，输入总线变化不影响当前任务。

计算完成的时钟沿之后，block_out 更新为结果、busy=0、done=1。结果持续保持到下一次完成或复位。done 下一拍清零。每个核应在接受后 5000 个时钟周期内完成，与现有 tb_aes 的等待上限相容。

| 时点 | 控制器动作或核状态 |
|---|---|
| 接受任务前 | 控制器确认 busy=0，准备 block_in 和 start=1，并保持到下个上升沿。 |
| 接受沿之后 | 核锁存输入，busy=1，done=0。控制器清除 start。 |
| 计算期间 | 控制器依据 done 等待，完成延迟可变化。 |
| 完成沿之后 | 核给出有效 block_out 和 done=1。 |
| 下一上升沿 | 控制器采到 done 并保存结果，核清除 done。 |

复位中止当前任务，恢复空闲。控制器等待本次任务完成后再发下次启动。

## AES 数据与查表

密钥固定为 128'h000102030405060708090a0b0c0d0e0f。电脑端用 AES-128 ECB 对单个 16 字节分组操作，padding 关闭。

分组第 i 字节为 block[127-8*i -: 8]，对应状态矩阵 state[row][column]，其中 row=i%4、column=i/4。例如首四个字节依次填入第 0 列四行。输入、输出、轮密钥都采用相同顺序。

rtl/aes_tables.vh 在两个核的 module 内分别 include，提供本地函数 aes_sbox(byte)、aes_inv_sbox(byte)、aes_round_key(round)。round=0 为原密钥，round=10 为最后轮密钥。解密直接按 10 至 0 的顺序调用同一套轮密钥。

## 命令与回执明文

| 含义 | 第 0 字节 [127:120] | 第 1 字节 [119:112] | 第 2–15 字节 [111:0] |
|---|---|---|---|
| 开灯请求 | 01 | 00 | 全 0 |
| 关灯请求 | 00 | 00 | 全 0 |
| 成功回执 | A0 | 新灯状态 00 或 01 | 全 0 |
| 非法命令回执 | E0 | 原灯状态 00 或 01 | 全 0 |

只有两个完整明文分组合法。即使首字节为 00 或 01，只要其余字节非零也返回 E0。非法命令保持灯状态。组装成功回执时使用执行命令后的灯状态，注意时序块里非阻塞赋值读取的是旧值。

## 共用验收向量

| 场景 | 明文 | 密文 |
|---|---|---|
| AES 标准分组 | 00112233445566778899aabbccddeeff | 69c4e0d86a7b0430d8cdb78070b4c55a |
| 开灯请求 | 01000000000000000000000000000000 | e37cd363dd7c87a09aff0e3e60e09c82 |
| 关灯请求 | 00000000000000000000000000000000 | c6a13b37878f5b826f4f8162a1c8d879 |
| 亮灯成功回执 | a0010000000000000000000000000000 | b026dbf27fcdfabeeab01ed0cb78ac66 |
| 灭灯成功回执 | a0000000000000000000000000000000 | 966aab7bda958e77dd00c494cfc001d6 |

业务向量可用 pc/reference.py 重算。标准分组及 AES 轮运算来自 NIST FIPS 197。[AES 标准原版，附录 C.1](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.197.pdf)

## 报警应用层扩展

`secure_alarm` revision 顶层为 `alarm_top`，保留基础顶层的五个端口，新增 `key_n[3:0]` 输入和 `alarm_led_n`、`muted_led_n`、`test_led_n`、`beep`、`shcp`、`stcp`、`ds`、`oe` 输出。原 `top`、`comm_ctrl`、UART 与 AES 模块的名称、端口、握手及明密文向量全部沿用。

在报警版中，原 `led_on` 的应用含义为 `armed`。布防 `arm` 与 `on` 使用 `01 + 15*00`，撤防 `disarm` 与 `off` 使用全零。回执第二字节仍仅表示布防位；末 14 字节仍为零，不能据此推断报警、消音、实际柜门或计数状态。重复布防保持现有报警和消音状态，不重复短响。按键事件不生成串口回执或主动上报。

| 新模块 | 输入 | 输出 |
|---|---|---|
| key_debounce | clk、rst_n、低有效 key_n | pressed 单拍、held 稳定按下电平 |
| alarm_ctrl | clk、rst_n、armed、key_pressed[3:0]、trigger_held | alarm_active、muted、selftest_active、count_bcd[15:0]、alarm_light、muted_light、test_light、beep |
| alarm_display | clk、rst_n、count_bcd[15:0]、selftest_active | shcp、stcp、ds、oe |

所有时序仍以 50 MHz `clk` 上升沿驱动，复位最高优先级。按键两级同步后需连续稳定 1,000,000 拍（20 ms）才接受按下/释放，按下一次只产生一拍 `pressed`。KEY1/2/3/4 分别映射位 0/1/2/3。`held` 使布防时已经按住 KEY1 的情况也能触发一次。

报警处理优先级：撤防清除当前报警与消音 > KEY1 新事件触发（并取消旧消音）> KEY2 消音。KEY3 自检和 KEY4 清零只在撤防状态生效；从布防进入撤防的同拍忽略自检请求。事件计数在有效触发时递增、9999 饱和，撤防保留、KEY4/系统复位清零。系统复位不保存计数。

蜂鸣器输出为 2 kHz 方波，空闲高电平；报警响 250 ms、停 250 ms，D7 同步闪烁。首次布防短响 100 ms。自检持续 1 秒，D7–D9 点亮、数码管显示 888888，D6 始终表示真实布防逻辑位。自检期间布防会中止自检并转为布防提示/报警处理。

数码管使用高有效单个位选和低有效段码（bit7 为小数点）；右侧四位显示 BCD 计数、左侧两位空白。每个扫描字锁存为 14 位，按 `sel[0]` 到 `sel[5]`、`seg[7]` 到 `seg[0]` 顺序发送。转换期间 OE=1 消隐，14 个 SHCP 上升沿后产生 STCP 锁存，再启用 OE=0，每位保持约 1 ms。所有串行输出由 clk 计数使能产生，未引入内部派生时钟。

新增外设引脚见 `quartus/alarm_pins.tcl`；`quartus/alarm.sdc` 只对异步按键输入到第一级同步器作 false path，后级同步和应用逻辑仍检查时序。具体引脚来源及实板核对见 [报警演示说明](docs/alarm-demo.md)。
