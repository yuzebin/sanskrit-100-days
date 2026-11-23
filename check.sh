#!/usr/bin/env bash
# 一键打卡：勾选 + 重算进度 + 连同当天日课一起 commit & push
set -euo pipefail

MODE="check"
PUSH=1
MSG=""
DAYS=()

usage() {
  cat <<'EOF'
用法：
  ./check.sh                  打卡：自动勾选「最新已写日课中未勾的那天」，并提交推送
  ./check.sh 7                勾选指定天（Day 007）
  ./check.sh 3 4 5            一次补勾多天
  ./check.sh -u 3             撤销 Day 003 的勾选
  ./check.sh --refresh        只重算状态计数与进度条，不改勾选（网页勾选后用它同步）
  ./check.sh -m "拆字与词尾"   自定义 commit 说明
  ./check.sh --no-push         只 commit，不 push
  ./check.sh --status          仅查看进度，不做任何改动
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -u|--undo)    MODE="undo"; shift ;;
    --refresh)    MODE="refresh"; shift ;;
    --status)     MODE="status"; shift ;;
    --no-push)    PUSH=0; shift ;;
    -m|--message) MSG="${2:-}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    [0-9]*)       DAYS+=("$1"); shift ;;
    *)            echo "未知参数：$1" >&2; usage >&2; exit 1 ;;
  esac
done

RESULT="$(python3 - "$MODE" ${DAYS[@]+"${DAYS[@]}"} <<'PY'
import sys, re, pathlib

mode = sys.argv[1]
args = [int(x) for x in sys.argv[2:]]
p = pathlib.Path("打卡表.md")
s = p.read_text(encoding="utf-8")
notes = []
changed = False

# 默认目标：编号最大的「已写日课且未勾选」的那天
if mode == "check" and not args:
    cands = []
    for f in pathlib.Path(".").glob("day-[0-9][0-9][0-9].md"):
        n = int(f.stem.split("-")[1])
        if re.search(rf"^- \[ \] \*\*Day {n:03d}\*\*", s, re.M):
            cands.append(n)
    if cands:
        args = [max(cands)]
    else:
        mode = "status"

for n in args:
    if not 1 <= n <= 100:
        print(f"ERR:Day {n} 超出 1-100"); sys.exit(1)
    day = f"{n:03d}"
    if mode in ("check", "undo"):
        if not pathlib.Path(f"day-{day}.md").exists():
            notes.append(f"跳过 Day {day}：日课文件不存在，先 ./new-day.sh {n}")
            continue
        pat = re.compile(rf"^(- \[)([ x])(\] \*\*Day {day}\*\*)", re.M)
        m = pat.search(s)
        if not m:
            notes.append(f"跳过 Day {day}：打卡表找不到该行"); continue
        target = "x" if mode == "check" else " "
        if m.group(2) == target:
            notes.append(f"Day {day} 已是目标状态，未改动"); continue
        s = pat.sub(lambda mm: mm.group(1) + target + mm.group(3), s, count=1)
        changed = True
        notes.append(f"{'已勾' if mode == 'check' else '已撤销'} Day {day}")

count = len(re.findall(r"^- \[x\] \*\*Day \d{3}\*\*", s, re.M))
latest = args[-1] if args else count
filled = round(count / 100 * 20)
bar = "█" * filled + "░" * (20 - filled)

s2 = re.sub(r"^状态：\d+ / 100$", f"状态：{count} / 100", s, flags=re.M)
if re.search(r"^进度：", s2, re.M):
    s2 = re.sub(r"^进度：.*$", f"进度：{bar} {count:3d}%", s2, flags=re.M)
else:
    s2 = s2.replace(f"状态：{count} / 100",
                    f"状态：{count} / 100\n进度：{bar} {count:3d}%", 1)
if s2 != s:
    changed = True
    s = s2

if mode != "status" and changed:
    p.write_text(s, encoding="utf-8")

print(f"CHANGED:{1 if changed else 0}")
print(f"DAY:{latest:03d}")
for note in notes:
    print(note)
print(f"进度：{bar} {count:3d}%  ({count}/100)")
PY
)"

CHANGED="$(printf '%s\n' "$RESULT" | head -n 1 | cut -d: -f2)"
printf '%s\n' "$RESULT" | tail -n +3

if [ "$CHANGED" != "1" ] || [ "$MODE" = "status" ]; then
  exit 0
fi

DAY_TAG="$(printf '%s\n' "$RESULT" | head -n 2 | tail -n 1 | cut -d: -f2)"
if [ "$MODE" = "refresh" ]; then
  MSG="${MSG:-同步打卡进度}"
elif [ "$MODE" = "undo" ]; then
  MSG="${MSG:-day-${DAY_TAG} · 撤销勾选}"
else
  MSG="${MSG:-day-${DAY_TAG} · 打卡}"
fi

git add -A
git commit -m "$MSG" -q
echo "已提交：$MSG"

if [ "$PUSH" = "1" ]; then
  git push -q && echo "已推送 origin/main"
else
  echo "未推送（--no-push）"
fi
