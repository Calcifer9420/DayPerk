#!/bin/bash
# 仅修改本地版本号，不创建提交、标签或执行推送。
set -euo pipefail
python3 - "$@" <<'PYTHON'
import re, sys
from pathlib import Path
if len(sys.argv) != 2 or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", sys.argv[1]):
    raise SystemExit("用法: scripts/update-version.sh 1.0.0")
p = Path("DayPerk/DayPerk.xcodeproj/project.pbxproj")
s = p.read_text()
updated, count = re.subn(r"MARKETING_VERSION = [^;]+;", "MARKETING_VERSION = " + sys.argv[1] + ";", s)
if not count: raise SystemExit("未找到版本字段")
p.write_text(updated)
print("本地版本号已更新；未创建提交或推送。")
PYTHON
