"""Run alarm regressions with Icarus; stage in an ASCII directory on Windows.

python scripts/verify_alarm.py --iverilog C:/tools/iverilog/bin/iverilog.exe --build-dir C:/fpga-alarm-test
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--build-dir", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    build = args.build_dir.resolve()
    if not str(build).isascii():
        parser.error("--build-dir must be an ASCII path for the Windows Icarus tools")
    if build == root or root in build.parents:
        parser.error("--build-dir must be outside the source checkout")
    compiler = shutil.which(args.iverilog)
    if not compiler:
        parser.error("iverilog executable not found")
    runtime = Path(compiler).with_name("vvp.exe" if os.name == "nt" else "vvp")
    build.mkdir(parents=True, exist_ok=True)
    for folder in ("rtl", "sim"):
        (build / folder).mkdir(exist_ok=True)
        for source in (root / folder).glob("*"):
            if source.suffix in (".v", ".vh", ".sv"):
                shutil.copy2(source, build / folder / source.name)
    scratch = build / "tmp"
    scratch.mkdir(exist_ok=True)
    env = dict(os.environ, TMP=str(scratch), TEMP=str(scratch), TMPDIR=str(scratch))
    env["PATH"] = str(Path(compiler).parent) + os.pathsep + env.get("PATH", "")
    rtl = [str(p.relative_to(build)) for p in sorted((build / "rtl").glob("*.v"))]

    def run(command):
        print("RUN", subprocess.list2cmdline([str(x) for x in command]), flush=True)
        subprocess.run(command, cwd=build, env=env, check=True)

    # Independently enforce Verilog-2001-compatible RTL (benches use SV).
    run([compiler, "-g2001", "-I", "rtl", "-s", "alarm_top", "-o", "rtl_check.vvp", *rtl])
    tests = [("tb_alarm_ctrl", []), ("tb_alarm_display", []), ("tb_alarm_system", []),
             ("tb_comm_ctrl", []), ("tb_uart", []), ("tb_pc_vectors", []),
             ("tb_aes", []), ("tb_aes", ["-DTEST_DEC"]),
             ("tb_aes_enc_extra", []), ("tb_aes_dec_extra", [])]
    for index, (bench, defines) in enumerate(tests):
        output = f"test_{index}.vvp"
        run([compiler, "-g2012", "-I", "rtl", *defines, "-s", bench, "-o", output,
             *rtl, f"sim/{bench}.sv"])
        run([str(runtime), output])
    run([sys.executable, "-m", "unittest", "discover", "-s", str(root / "pc"), "-p", "test_demo.py", "-v"])
    print("PASS: alarm and existing communication regressions", flush=True)


if __name__ == "__main__":
    main()
