# FPGA 硬件加密通信系统

数字逻辑六人小组作业。电脑发一条加密命令，征途 Pro 解密后开关 D6，再把执行回执加密发回。三天交付两条命令、一盏灯和一个串口终端。

## 全组共同的设计约定

所有成员及各自的 AI 按下表实现同一条业务链。每人完成其中一个模块，模块间依靠现有顶层连接和 INTERFACE.md 对接。

```text
电脑生成加密命令 → UART 接收 → 协议组帧 → AES 解密 → 更新 D6
电脑解密验证回执 ← UART 发送 ← 协议拆帧 ← AES 加密 ← 生成回执
```

| 全组统一项 | 本项目约定 |
|---|---|
| 最终功能 | 电脑执行 on/off，板上 D6 开关，电脑收到并解开执行回执。 |
| 硬件及工程 | 一块征途 Pro，EP4CE10F17C8，50 MHz；正式工程 revision 为 secure_comm，顶层为 top。 |
| 串口 | 115200、8N1、无流控；一次请求或回执为 16 个原始字节，一问一答。 |
| 分组与位序 | 一个分组 128 位，首字节为 [127:120]；每个 UART 字节内 bit 0 先发送。 |
| 算法及密钥 | AES-128 单分组，电脑端 ECB、关闭填充；密钥固定为 000102030405060708090a0b0c0d0e0f。 |
| 命令与回执 | 开灯明文为 01 后接 15 字节零，关灯为 16 字节零；回执为 A0、灯状态、14 字节零。非法命令用 E0 并保留原灯状态。 |
| FPGA 握手 | UART 按 rx_valid 和 tx_valid/tx_ready；AES 按 start/busy/done。准确的采样沿与保持要求见 INTERFACE.md。 |
| 文件与模块 | 基于 rtl/ 现有模块实现，保留端口；加解密复用 aes_tables.vh，电脑端复用 reference.py。 |
| 共用答案 | 使用 INTERFACE.md 的同一组明密文向量，各角色独立核对。 |

开发前先同步原仓库最新 main，在群里确认共同起点的提交号。把本页、[设计目标](DESIGN.md)、[接口与时序](INTERFACE.md)、[编码约束](AGENTS.md)、自己的任务书和源码一起交给 AI。任务书决定分工，INTERFACE.md 决定数据与时序。遇到公共约定需要调整时，成员说明原因，由组长同步修改和通知受影响成员。

下面这段可供所有成员统一使用，填入各自角色编号即可。

> 我负责本项目【编号】号任务。先读取 README.md 的“全组共同的设计约定”、DESIGN.md、INTERFACE.md、AGENTS.md 和对应任务书，再检查现有顶层与本模块源码。实现前列出本模块的上下游、端口与位宽、字节顺序、握手和共用测试向量，核对与公共约定一致后继续实现任务书内的文件。测试按接口模拟上下游，交付实际运行命令和结果。公共接口问题列出依据及影响，交组长协调。

## 当前文件架构

下图列出当前 main 已纳入 Git 的文件。各模块的负责人及源码状态标在文件旁。

```text
fpga-secure-communication/
├── README.md                    # 全组入口、文件架构与任务分工
├── DESIGN.md                    # 三天交付目标与系统流程
├── INTERFACE.md                 # 端口、握手、字节顺序与共用向量
├── AGENTS.md                    # 所有成员与 AI 遵循的编码约束
├── Git协作说明.md               # Fork、分支、Pull Request 与同步步骤
├── 六人三天开发工作流.md         # 每日目标与集成安排
├── 并行开发与交付.md             # 独立测试方法、交付文件与结果填写
├── .gitignore                   # 编译及仿真生成文件的忽略规则
│
├── rtl/                         # FPGA 正式硬件源码
│   ├── top.v                    # 1 号维护，顶层连接已建立
│   ├── board_echo.v             # 1 号维护，线路自检逻辑已实现
│   ├── uart_rx.v                # 2 号，UART 接收已通过模块仿真和独立综合
│   ├── uart_tx.v                # 2 号，UART 发送已通过模块仿真和独立综合
│   ├── comm_ctrl.v              # 3 号实现，协议已合入并通过模块仿真
│   ├── aes_enc.v                # 4 号，AES-128 加密核已通过模块仿真
│   ├── aes_dec.v                # 5 号，AES-128 解密核已通过模块仿真
│   └── aes_tables.vh            # 已提供的 S 盒、逆 S 盒和固定轮密钥
│
├── quartus/                     # 1 号维护的 Quartus 工程
│   ├── secure_comm.qpf          # 工程入口，包含两个 revision
│   ├── board_echo.qsf           # 线路自检版本配置
│   ├── secure_comm.qsf          # 正式加密通信版本配置
│   ├── board.tcl                # 共用器件、引脚与 IO 配置
│   └── board.sdc                # 50 MHz 主时钟约束
│
├── sim/                         # 仿真测试源码
│   ├── tb_uart.sv               # 2 号，串口收发、位宽、握手和复位测试
│   ├── tb_aes.sv                # 共用 AES 加密/解密向量测试
│   ├── tb_aes_enc_extra.sv      # 4 号，加密核握手与复位测试
│   ├── tb_aes_dec_extra.sv      # 5 号，解密核握手与复位测试
│   └── tb_pc_vectors.sv         # 6 号，电脑请求与 FPGA 解密字节序测试
│
├── pc/                          # 电脑端，6 号负责
│   ├── reference.py             # 已提供的离线加解密与参考数据
│   ├── requirements.txt         # Python 依赖
│   ├── demo.py                  # 发送开关灯命令并校验回执
│   ├── test_demo.py             # 模拟串口与超时边界测试
│   └── README.md                # 电脑端运行与实板联调步骤
│
└── tasks/                       # 各角色可直接交给 AI 的任务书
    ├── 01-integration.md        # 1 号，组长与工程集成
    ├── 02-uart.md               # 2 号，串口收发
    ├── 03-protocol.md           # 3 号，协议与灯控制
    ├── 04-encrypt.md            # 4 号，AES 加密
    ├── 05-decrypt.md            # 5 号，AES 解密
    └── 06-pc-test.md            # 6 号，电脑端与联调记录
```

成员开发时按任务书新建以下文件，提交后由组长同步上面的文件树。

| 负责人 | 后续新建文件 | 用途 |
|---|---|---|
| 1 号 | sim/tb_system.sv | 整机连接及流程仿真 |
| 3 号 | sim/tb_comm_ctrl.sv | 模拟上下游的协议独立验证 |

Quartus 生成的程序保存在 quartus/output_files/，该目录由 Git 忽略。组长本机已有 board_echo.sof 自检程序，组员可从工程重新编译生成。

## 小组成员开始开发

六个编号代表小组职责，成员姓名由小组填写。每位成员先阅读本页、DESIGN.md、INTERFACE.md、AGENTS.md，再打开自己对应的任务书。任务书包含修改范围、实现步骤、上下游、最小验证和可直接发给 AI 的提示词。

网页 AI 使用者将这四份公共文档、对应任务书和该模块源码一起上传或粘贴。能够读取仓库的 AI 从当前分支直接读取。统一时序以 INTERFACE.md 为准。

六个人如何当天同时开工、上游未完成时用什么测试、每人需要提交哪些文件，都列在 [并行开发与交付](并行开发与交付.md)。每人先用自己的 Testbench 跑 ModelSim，再做 Quartus Analysis & Synthesis，把两份结果和复现步骤写进 PR。组长评审合并后，负责整机仿真、完整编译、引脚与时序核对，并与 6 号一起上板验收。[方案一：分布式测试](并行开发与交付.md#distributed-testing)

| 人员 | Git 分支 | 负责文件 | 交付条件 |
|---|---|---|---|
| [1 · 组长与集成](tasks/01-integration.md) | feature/integration | rtl/top.v、quartus/、共享文档及查表 | 第一天检查线路，第二天集成正式模块，第三天验收并保存提交号。 |
| [2 · 串口收发](tasks/02-uart.md) | feature/uart | rtl/uart_rx.v、rtl/uart_tx.v、sim/tb_uart.sv | 完成 115200、8N1 的收发，验证独立位序、连续字节和发送握手。 |
| [3 · 协议与灯控制](tasks/03-protocol.md) | feature/protocol | rtl/comm_ctrl.v、sim/tb_comm_ctrl.sv | 用模拟 AES 验证完整请求、单次启动、灯状态和 16 字节回执。 |
| [4 · AES 加密](tasks/04-encrypt.md) | feature/aes-encrypt | rtl/aes_enc.v、独立扩展测试 | 复用已有 S 盒和轮密钥，通过标准分组、开灯分组及握手验证。 |
| [5 · AES 解密](tasks/05-decrypt.md) | feature/aes-decrypt | rtl/aes_dec.v、独立扩展测试 | 复用逆 S 盒和轮密钥，通过标准密文、开灯密文及握手验证。 |
| [6 · 电脑端与记录](tasks/06-pc-test.md) | feature/pc-test | pc/demo.py、pc/reference.py、电脑端测试 | 复用参考代码实现串口 on/off，核对回执，协助整机验证。 |

## 共同编码约束

- RTL 使用可综合 Verilog-2001，统一 50 MHz 上升沿时钟和低有效复位，时序块使用非阻塞赋值。
- 保持现有模块端口和字节排列。数据只在公共握手约定的时钟沿接受，每个信号有唯一驱动者。
- 每人维护自己的文件和测试，公共接口由组长协调更新。仿真替身放入 sim/，正式工程使用真实 RTL。
- 每次交付附实际命令和结果。详细规则见 [AGENTS.md](AGENTS.md)，握手、复位、位序和向量见 [INTERFACE.md](INTERFACE.md)。

## 第一次开工

组员登录 GitHub，在原仓库右上角 Fork → Create fork 创建自己的副本，再用 GitHub Desktop 克隆自己账号下的仓库到英文路径，如 D:\fpga-secure。从 main 用 Current Branch → New Branch 创建所负责的任务分支。代码上传到自己的 Fork，再向原仓库 main 提交 Pull Request。完整步骤见 [Git 操作](Git协作说明.md)。

组长在原仓库负责集成。现有 Quartus 18.0 编译检查在中文工程路径下遇到打开工程错误，英文路径已编译通过。

每人推自己的分支，向 main 发起合并请求。第一天并行开发、晚间首次合并。第二天按串口、协议、解密、加密回执的顺序接入，下午首次整机上板。第三天留给复测、复位恢复和换人复现。[Git 操作](Git协作说明.md) · [三天工作流](六人三天开发工作流.md)

## 第一次上板

用 Quartus 18.0 打开 `quartus/secure_comm.qpf`，在 **Project → Revisions** 选 **board_echo** 后编译。用 USB-Blaster 下载 `quartus/output_files/board_echo.sof`。按野火说明连接板载 USB 串口和跳帽，在串口工具选择对应 COM、115200、8N1、无流控，关闭本地回显，按 HEX 发送 `00 55 AA FF`。应收到相同的四字节，按住复位可点亮 D6。该版本验证物理串口线路。正式工程选 **secure_comm**，其顶层已连接 UART、协议和两个 AES 核；2026-11-16 实板联调记录见 [pc/README.md](pc/README.md)。[串口接线图](https://doc.embedfire.com/fpga/altera/ep4ce10_pro/zh/latest/code/rs232.html) · [D6 说明](https://doc.embedfire.com/fpga/altera/ep4ce10_pro/zh/latest/code/led.html)

## 模块测试

在仓库根目录执行以下命令。电脑参考程序打印开灯、关灯的发送密文与预期回执，并核对标准向量。

```powershell
python -m pip install -r pc/requirements.txt
python pc/reference.py
```

加密、解密负责人可以在已设置 ModelSim 命令路径的 PowerShell 中，从仓库根目录运行下列测试。

```powershell
vlib work
vlog +incdir+rtl rtl/aes_enc.v rtl/aes_dec.v
vlog -sv sim/tb_aes.sv
vsim -c tb_aes -do "run -all; quit -f"
vlog -sv +define+TEST_DEC sim/tb_aes.sv
vsim -c tb_aes -do "run -all; quit -f"
vlog -sv sim/tb_aes_enc_extra.sv sim/tb_aes_dec_extra.sv
vsim -c tb_aes_enc_extra -do "run -all; quit -f"
vsim -c tb_aes_dec_extra -do "run -all; quit -f"
```

共用测试的加密和解密模式各自检查标准分组和开灯分组，均输出 `PASS: both AES blocks`。扩展测试检查连续任务、忙时启动、结果保持和复位恢复。

## 框架验证状态

已核对电脑端离线参考向量、正式顶层端口展开及 board_echo 的 Quartus 完整编译。两个 AES 核已在 ModelSim SE-64 2020.4 通过共用向量和各自的扩展测试。UART 收发已通过七阶段 ModelSim 测试。接收采样间隔和发送停止位至就绪的间隔均为 434 拍，`uart_rx` 与 `uart_tx` 单独综合均为 0 错误、0 告警。协议控制器已合入；2026-11-16 实板 on/off、10 轮、E0、半帧复位已通过，记录见 [pc/README.md](pc/README.md)。[2 号 UART 验收](https://github.com/baoyuxuan15/fpga-secure-communication/pull/6) · [4 号加密核验收](https://github.com/baoyuxuan15/fpga-secure-communication/pull/1) · [5 号解密核验收](https://github.com/baoyuxuan15/fpga-secure-communication/pull/2)

6 号电脑端已通过 17 项 Python 测试。ModelSim 用真实 `aes_dec` 逐字节核对了电脑端发送的开灯、关灯请求，32 字节全部一致。实板串口与 D6 已于 2026-11-16 通过整机验收，记录见 [pc/README.md](pc/README.md)。[6 号电脑端复审记录](https://github.com/baoyuxuan15/fpga-secure-communication/pull/5#pullrequestreview-5911401332)
