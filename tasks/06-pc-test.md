# 6 号任务书 · 电脑端与联调记录

工作分支为 feature/pc-test。负责新建 pc/demo.py，可维护 pc/reference.py 和 pc/requirements.txt。串口接口、密钥和回执见 INTERFACE.md。

开工时按 [并行开发与交付](../并行开发与交付.md) 使用模拟输入独立验证；交付文件和结果填写方式也见该说明。Fork 提交与同步见 [Git 协作说明](../Git协作说明.md)。

## 已有材料

reference.py 提供 transform(block, decrypt=False)、request(led_on)、reply(led_on)。分别用于单分组变换、生成请求和生成正常预期回执。requirements.txt 已列 cryptography 和 pyserial。

## 实现内容

- 提供命令行入口，约定用 python pc/demo.py --port COM3 --command on 或 --command off 执行一次交互。
- 用 pyserial 打开指定端口，115200、8N1、无软硬件流控，读写超时可设 2 秒。启动时清空旧输入缓存。
- 调用 request 生成 16 字节请求并发送，确认完整写出。打印发送密文。
- 分次 read 并累计到 16 字节，整体等待上限 2 秒。超时显示已收到字节数及恢复步骤，退出本次请求。串口异常也给出明确提示。
- 调用 transform(..., decrypt=True) 解密回执，检查首字节 A0/E0、灯状态 00/01 和末 14 字节零。成功时核对灯状态与命令一致，打印收到的密文、明文和判定结果。
- 失败时由使用者按公共步骤复位并重发。一次调用仅发一个请求，完成后关闭串口。

## 独立验证与交付

第一天先运行 python pc/reference.py，与 3/4/5 号共享生成值。可用模拟 serial 对象验证脚本的分段读取、短读超时和异常回执。测试文件可命名 pc/test_demo.py。

编写自己的 `sim/tb_pc_vectors.sv`，核对电脑端与 FPGA 的字节顺序。把 `python pc/reference.py` 打印的两条请求密文按电脑发送顺序装入 `block_in`（首字节在 `[127:120]`），用 `start` 启动已有的 `aes_dec`。在 ModelSim 中等 `done` 后逐字节核对明文，开灯应为 `01` 后跟 15 字节零，关灯应为 16 字节零。再以 `aes_dec` 为 RTL 顶层独立跑 Quartus Analysis & Synthesis。电脑脚本用 Python 和模拟串口测试。PR 分别附上这三项的运行方法和实际结果。[方案一：分布式测试](../并行开发与交付.md#distributed-testing)

第二天配合组长实板跑 on/off。第三天协助执行连续 10 轮、非法命令和复位恢复，记录提交号、收发数据和人工观察的 LED 状态。PC 解出成功回执与实物亮灯各自核对。非法请求可用 transform 对自定义 16 字节明文生成。

## 对接对象

与 2 号核对串口设置，与 3 号核对全分组合法性及回执，与组长确认 COM 口和板上版本。交付可运行的 `pc/demo.py`、电脑端测试和 `sim/tb_pc_vectors.sv`，附运行方法及实际结果。

## 交给本角色 AI 的任务

> 先读 AGENTS.md、DESIGN.md、INTERFACE.md 和本任务书。复用 pc/reference.py，为固定 16 字节协议实现 pc/demo.py 的 on/off 命令。支持分段读取、整体超时和明确的回执判定。记录离线、模拟串口和实板各自实际验证的范围。
