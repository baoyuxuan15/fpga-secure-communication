# 6 号：电脑端使用与联调

## 报警版布防与撤防

先下载新增 `secure_alarm` revision 的 `secure_alarm.sof`，再运行：

```powershell
python pc/demo.py --port COM3 --command arm
python pc/demo.py --port COM3 --command disarm
```

arm/disarm 分别复用 on/off 的明文、密文和回执格式，老命令仍可用。回执只确认 FPGA 布防位，不包含本地报警、消音或计数状态，也不识别下载的 revision，所以必须先核对 SOF。按 KEY1 触发、KEY2 消音、KEY3 自检、KEY4 清零的完整步骤见 [报警演示说明](../docs/alarm-demo.md)。

2026-11-17 已在真实 COM8 完成报警版联调，10 轮连续测试共 20 条加密请求/回执全部通过，并完成使用者现场灯光、声音、数码管和按键核对。对应实现提交 `624afd3`，本轮证据、逐灯诊断及最终恢复状态见 [实板验收记录](../docs/acceptance-2026-11-17.md)。

## 功能与接口

`demo.py` 每次运行只发送一条控制请求（on/off，或报警版语义的 arm/disarm），然后接收、解密并校验一条回执，最后关闭串口。它复用 `reference.py`，不另行实现 AES。

- 串口：115200、8N1，无软硬件流控，读写超时 2 秒。
- 密钥：`000102030405060708090a0b0c0d0e0f`；AES-128 ECB，无填充。
- 请求与回执均固定为 16 个原始字节，不使用 ASCII 十六进制或额外换行。
- 开灯明文：`01` 后接 15 个 `00`；关灯明文：16 个 `00`。
- 正常回执：`A0`、灯状态 `00/01`、14 个 `00`。
- 非法命令回执：`E0`、保持的灯状态 `00/01`、14 个 `00`；本次命令判定失败。

程序启动后清空旧输入缓存，分段累计到 16 字节。所有读操作共用一个 2 秒绝对截止时刻，而非每次读取都重新等待 2 秒；每轮把单次读超时限制在剩余预算内，收满 16 字节后再按同一截止时刻复核一次，超过截止时刻才收满的回执判为超时（退出码 `2`）。回执检查同时覆盖首字节、状态、末 14 字节及命令一致性。正常回执只证明 FPGA 报告的状态，仍需人工观察 D6。

## 安装与运行（Windows PowerShell）

从**仓库根目录**执行。推荐每个组员建立自己的虚拟环境：

```powershell
py -m venv .venv
Set-ExecutionPolicy -Scope Process Bypass
.\.venv\Scripts\Activate.ps1
python -m pip install -r pc/requirements.txt
```

如 PowerShell 脚本执行策略不允许激活环境，无需修改系统策略，直接使用虚拟环境中的解释器：

```powershell
.\.venv\Scripts\python.exe -m pip install -r pc/requirements.txt
```

在 Windows 设备管理器的“端口（COM 和 LPT）”确认板载 USB 串口的 COM 号，关闭占用该端口的串口工具。以下示例把 `COM3` 替换为实际端口号，每次运行只发送一次：

```powershell
python pc/demo.py --port COM3 --command on
python pc/demo.py --port COM3 --command off
```

开灯成功时应显示如下关键值，末行还会提示人工核对 D6：

```text
发送密文（16 字节）：e37cd363dd7c87a09aff0e3e60e09c82
接收密文（16 字节）：b026dbf27fcdfabeeab01ed0cb78ac66
回执明文：a0010000000000000000000000000000
判定：PASS，on 命令回执有效，FPGA 报告灯已打开。请同时人工核对板上 D6 的实际状态。
```

关灯的预期密文及回执分别为：

| 项目 | 固定值 |
|---|---|
| 发送密文 | `c6a13b37878f5b826f4f8162a1c8d879` |
| 正常回执密文 | `966aab7bda958e77dd00c494cfc001d6` |
| 正常回执明文 | `a0000000000000000000000000000000` |

退出码：`0` 为回执检查通过；`1` 为收满 16 字节但回执非法、状态不符或 FPGA 返回 `E0`；`2` 为串口、短写、短读或超时错误。命令行参数错误由 argparse 返回 `2`。

## 无 FPGA 的独立测试

```powershell
python pc/reference.py
python -m unittest -v pc/test_demo.py
```

`test_demo.py` 的 `FakeSerial` **只替代 pyserial 串口层**；实际运行 `demo.py` 和 `reference.py`，用真实 AES 算法生成并解密数据，不使用 FPGA RTL，也不连接真实串口。用例覆盖：

1. 开关灯共用密文、正常回执及 115200/8N1/无流控设置；
2. 清空输入、只发一次、完整写出、分段累计、总超时；
3. 零字节和部分帧超时、非法标志/状态/填充、`E0`、状态与命令不符；
4. 打开端口失败、读时断开、短写、写超时，以及成功/失败后的端口关闭；
5. 末段分别在 1.990 s、2.000 s 和 2.025 s 到达：前两者 PASS，2.025 s 判超时、退出码 `2`，不打印 PASS（复现评审给出的临界场景）。

上述测试无需 FPGA，只能证明电脑端软件和模拟串口行为，不能替代 UART/AES RTL 仿真或实板联调；实板结果见下文。

## 整机联调步骤

前提：组长已把各成员的 UART、协议、AES 实现合入同一提交，用 Quartus 18.0 编译 `secure_comm` revision，并下载对应的 `secure_comm.sof`。占位 RTL 不能通过本测试。

1. **先查线路**：按组长说明运行 `board_echo`，确认 COM 口和 USB 串口接线；关闭本地回显。然后换回正式 `secure_comm` 程序。
2. **确认版本**：记录 `git rev-parse HEAD`、实际编译的提交、sof 文件和 COM 号；不要在测试中途换版本。
3. **基本命令**：分别运行一次 `on`、`off`。核对输出的三段数据，并分别人工确认 D6 亮/灭。
4. **连续十轮**：按“复位后开灯 → 关灯”的顺序交替执行 10 轮，每轮启动一次程序，只发送一个请求；记录每轮回执和实际 D6，不只看最后的 PASS。
5. **非法命令**：确认 FPGA 协议测试已覆盖任意非法明文（包括原命令之外的 padding）和 `E0 + 保持状态`。如需电脑端发自定义 16 字节请求，另写联调工具调用 `transform`；`demo.py` 支持 on/off 及 arm/disarm 别名，把 `E0` 判为失败。
6. **半帧/复位恢复**：由协议或整机测试模拟不足 16 字节后复位；实板若出现短读/超时，按提示复位 FPGA，重新运行程序清空电脑端缓存，再发一条完整命令。程序不会自动重发。
7. **保存记录**：按下表记录命令、预期/实际密文、回执明文、PC 判定、D6 观察及提交号。实板结果不得用模拟结果代填。

| 日期/轮次 | Git 提交号 / sof | COM | 命令或场景 | 实际 RX 密文及明文 | PC 判定 | D6 人工观察 |
|---|---|---|---|---|---|---|
| 2026-11-16 on | `4b49ae6` / `secure_comm.sof` | COM5 | on | `b026dbf27fcdfabeeab01ed0cb78ac66` / `a0010000000000000000000000000000` | PASS | 亮 |
| 2026-11-16 off | `4b49ae6` / `secure_comm.sof` | COM5 | off | `966aab7bda958e77dd00c494cfc001d6` / `a0000000000000000000000000000000` | PASS | 灭 |
| 2026-11-16 10 轮 | `4b49ae6` / `secure_comm.sof` | COM5 | on/off 交替 10 轮 | 每轮对应正常回执，逐轮核对 | 10/10 PASS | 跟随，最终灭 |
| 2026-11-16 E0 灯灭 | `4b49ae6` / `secure_comm.sof` | COM5 | 非法明文 `02`+15×`00`，TX=`fb8ae31ba5db9cad97364d8722d47326` | `2e9680d015f0262542f0796b435ebcb0` / `e0000000000000000000000000000000` | 预期失败（E0） | 保持灭 |
| 2026-11-16 E0 灯亮 | `4b49ae6` / `secure_comm.sof` | COM5 | 先 on，再发同一非法帧 | `a47db3cbac8e8bf5c007ff13f2df1a09` / `e0010000000000000000000000000000` | 预期失败（E0） | 保持亮 |
| 2026-11-16 半帧 | `4b49ae6` / `secure_comm.sof` | COM5 | 仅发 on 密文前 8 字节 `e37cd363dd7c87a0` | 0.6 s 内无完整回执 | 预期超时（退出码 2） | 保持灭 |
| 2026-11-16 复位恢复 | `4b49ae6` / `secure_comm.sof` | COM5 | RESET 后重发完整 on 帧 | `b026dbf27fcdfabeeab01ed0cb78ac66` / `a0010000000000000000000000000000` | PASS | 复位后亮一下，随后 off 灭 |
| 2026-11-16 结束 | `4b49ae6` / `secure_comm.sof` | COM5 | off | `966aab7bda958e77dd00c494cfc001d6` / `a0000000000000000000000000000000` | PASS | 灭 |

实板使用的 `secure_comm.sof` 为基于 main `4b49ae6` 工程的 Quartus 18.0 全编译产物，358718 字节，SHA256 `3055b06b1c8e6333762c84a7bcdc54dbcf1a3f6d81e4a1519ae490f47e0a769d`。该哈希只标识本次实测产物，重新编译的 `.sof` 可能因构建时间不同而哈希不同。D6 是四颗蓝色用户灯中的第一颗（用户称 LED2），红色 LED1 是电源指示灯。

## 当前实际验证记录

验证日期：2026-11-15（离线、模拟串口、ModelSim、Quartus）；2026-11-16（实板联调）。工作起点为 `main` 的 `a4ff957051aee7c9557c87200c5d0a42fc696ec6`，本地分支为 `feature/pc-test`。超时修复、新增临界用例与 `sim/tb_pc_vectors.sv` 的提交为 `1a18b79`，本节的离线记录由紧随其后的文档提交补充。

环境：Windows，本机 Python 3.14.3，`cryptography 46.0.5`，`pyserial 3.5`。仓库中的 `.venv` 是 Linux/MSYS 风格环境，不能直接在 PowerShell 中使用；上面给出的 `.venv\Scripts` 步骤可在 Windows 创建正确环境。

### 离线 AES 参考：通过

实际命令：

```text
C:/Users/MR/AppData/Local/Python/bin/python.exe pc/reference.py
```

实际输出：

```text
ON  TX=e37cd363dd7c87a09aff0e3e60e09c82 RX=b026dbf27fcdfabeeab01ed0cb78ac66
OFF TX=c6a13b37878f5b826f4f8162a1c8d879 RX=966aab7bda958e77dd00c494cfc001d6
PASS: offline reference vectors
```

这里只验证软件 AES 参考数据，不代表 FPGA AES 核通过。

### 模拟串口：17 项通过

实际命令：

```text
C:/Users/MR/AppData/Local/Python/bin/python.exe -m unittest -v pc/test_demo.py
```

实际结果：`Ran 17 tests in 4.034s`，`OK`。其中原有 14 项仍通过，新增 3 项覆盖 1.990 s、2.000 s、2.025 s 三个临界时刻。替代范围见上文；未使用 UART、协议或 AES RTL，未观察真实 D6。

### 跨端向量 testbench（ModelSim）：通过

实际命令（从仓库根目录执行，先清掉旧库以确保重新编译）：

```text
rm -rf work
vlib work
vlog +incdir+rtl rtl/aes_dec.v
vlog -sv sim/tb_pc_vectors.sv
vsim -c tb_pc_vectors -do "run -all; quit -f"
```

环境：ModelSim SE-64 2020.4。实际输出（PASS 行原样摘录）：

```text
# [1] PC on request: first byte in [127:120]
#   PASS ct=e37cd363dd7c87a09aff0e3e60e09c82 -> pt=01000000000000000000000000000000 (16 bytes)
# [2] PC off request: first byte in [127:120]
#   PASS ct=c6a13b37878f5b826f4f8162a1c8d879 -> pt=00000000000000000000000000000000 (16 bytes)
# PASS: tb_pc_vectors on/off byte order (32 bytes, max 11 cycles)
```

该用例用 `pc/reference.py` 生成的请求密文驱动真实 `rtl/aes_dec.v`，按 PC 发送顺序把首字节放在 `block_in[127:120]`，等 `done` 后逐字节核对 32 字节明文。它验证 RTL 解密与字节序，不代表实板 UART、协议或 D6 已验证。

### Quartus Analysis & Synthesis：通过

图形界面：Quartus 18.0 → File → New Project Wizard，器件选 Cyclone IV E / `EP4CE10F17C8`，顶层实体 `aes_dec`，加入 `rtl/aes_dec.v` 并把 `rtl` 加入搜索路径（用于 `include "aes_tables.vh"`），然后 Processing → Start → Start Analysis & Synthesis。

命令行等价做法：在工程目录放入下列关键赋值后运行 `quartus_map aes_dec_synth.qpf`：

```text
set_global_assignment -name FAMILY "Cyclone IV E"
set_global_assignment -name DEVICE EP4CE10F17C8
set_global_assignment -name TOP_LEVEL_ENTITY aes_dec
set_global_assignment -name VERILOG_FILE rtl/aes_dec.v
set_global_assignment -name SEARCH_PATH rtl
```

实际结果：`Quartus Prime Analysis & Synthesis was successful. 0 errors, 0 warnings`，耗时约 37 s；资源为 4178 logic cells、8 RAM segments（查表 ROM 推断）、131 input pins、130 output pins。未做全编译、时序分析、引脚分配或 sof 生成。

### 命令行错误路径：已验证

实际运行 `python pc/demo.py --help`，参数及 on/off 选项显示正常。对不存在的 `COM_TEST_NOT_PRESENT` 运行一次 `on`，pyserial 报告无法打开端口，程序打印串口错误及复位/重发步骤并返回 `2`。

### 真实 FPGA：已联调（2026-11-16）

使用 main `4b49ae6` 全编译的 `secure_comm.sof`（358718 字节，SHA256 `3055b06b1c8e6333762c84a7bcdc54dbcf1a3f6d81e4a1519ae490f47e0a769d`），在野火征途 Pro（EP4CE10F17C8，50 MHz）上通过 USB-Blaster 下载：

```text
quartus_pgm -c USB-Blaster -m JTAG -o "P;D:\project_one\secure_comm.sof"
```

下载报告 EP4CE10F17 JTAG ID `0x020F10DD`，`Configuration succeeded -- 1 device(s) configured`，0 errors、0 warnings。串口为 COM5（USB-SERIAL CH340，115200 8N1，无流控）。

整机 `secure_comm` 完整编译：0 errors、7 warnings；8499/10320 LE（82%）、851 registers；slow 85C setup +6.057 ns、hold +0.452 ns；fast 0C setup +13.474 ns、hold +0.186 ns。`.sof` 未入库（`.gitignore` 忽略 `output_files/` 与 `*.sof`）；上面的 SHA256 只标识本次实测产物，重编后可能不同，组员应重编并在板上复测功能。

实板结果：

- on：RX=`b026dbf27fcdfabeeab01ed0cb78ac66`，PT=`a0010000000000000000000000000000`，PASS，D6 亮。
- off：RX=`966aab7bda958e77dd00c494cfc001d6`，PT=`a0000000000000000000000000000000`，PASS，D6 灭。
- 连续 10 轮 on/off 交替：10/10 PASS，灯态逐轮跟随，最终停在 off。
- E0（灯灭时）：非法明文 `02`+15×`00`，TX=`fb8ae31ba5db9cad97364d8722d47326`，RX=`2e9680d015f0262542f0796b435ebcb0`，PT=`e0000000000000000000000000000000`，灯保持灭。
- E0（灯亮时）：先 on 再发同一非法帧，RX=`a47db3cbac8e8bf5c007ff13f2df1a09`，PT=`e0010000000000000000000000000000`，灯保持亮；随后 off 恢复。
- 半帧：只发 on 密文前 8 字节 `e37cd363dd7c87a0`，0.6 s 内无完整回执，D6 保持灭；按 RESET 并清空电脑端缓存后重发完整 on 帧，RX=`b026dbf27fcdfabeeab01ed0cb78ac66`，PT=`a0010000000000000000000000000000`，PASS，D6 亮了一下；最后 off，D6 灭。
- D6 为四颗蓝色用户灯中的第一颗（用户称 LED2），红色 LED1 为电源指示灯；上述亮/灭均由人工观察确认。

结论：本块板、本 `secure_comm.sof`、COM5 的实板联调通过，状态由“待联调”更新为“已联调（2026-11-16）”。该 sof 下载到 SRAM，断电后需重新下载；换提交或换板必须重跑。1 号任务书要求的“另一成员从相同提交重新编译并演示”不在 6 号本机记录范围内，仍待 1 号补做。
