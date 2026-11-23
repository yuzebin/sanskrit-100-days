#!/usr/bin/env bash
# 生成第 N 天日课文件，并在打卡表登记日期。用法：./new-day.sh 1
set -euo pipefail

N="${1:-}"
if ! [[ "$N" =~ ^[0-9]+$ ]] || [ "$N" -lt 1 ] || [ "$N" -gt 100 ]; then
  echo "用法：./new-day.sh <1-100>" >&2
  exit 1
fi

DAY="$(printf '%03d' "$N")"
FILE="day-${DAY}.md"
TODAY="$(date +%F)"

if [ -f "$FILE" ]; then
  echo "已存在：$FILE"
  exit 0
fi

sed "s/Day ___｜___ 年 ___ 月 ___ 日/Day ${DAY}｜${TODAY}/" "模板/day-模板.md" > "$FILE"

python3 - "$DAY" "$TODAY" <<'PY'
import sys, pathlib
day, today = sys.argv[1], sys.argv[2]
p = pathlib.Path("打卡表.md")
s = p.read_text(encoding="utf-8")
old = f"- [ ] **Day {day}** · ____-__-__"
new = f"- [ ] **Day {day}** · {today}"
if old in s:
    s = s.replace(old, new, 1)
    p.write_text(s, encoding="utf-8")
PY

echo "已生成 ${FILE}（${TODAY}）"
echo "写完后：git add . && git commit -m 'day-${DAY} · 简短记录' && git push"
