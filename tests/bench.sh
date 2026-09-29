#!/usr/bin/env bash
# bench.sh —— zd 性能基准斜率法运行器
# 用法: ./bench.sh <exe> <case> <scale> [R]     # R 默认 200，低点取 R/2
# 输出: 单次测项成本（纳秒/op）——slope = (T(R) − T(R/2)) / (R/2)
#       固定启动成本在斜率中被抵消；R 越大抖动越小。
set -u
EXE="$1"; CASE="$2"; N="$3"; R="${4:-200}"
LO=$(( R / 2 ))

now_us() { date +%s%N | cut -c1-16; }   # 微秒精度时间戳

ta=$(now_us); "$EXE" "$CASE" "$N" "$LO" >/dev/null 2>&1 || { echo "CRASH $CASE n=$N rep=$LO"; exit 2; }; tb=$(now_us)
ta2=$(now_us); "$EXE" "$CASE" "$N" "$R" >/dev/null 2>&1 || { echo "CRASH $CASE n=$N rep=$R"; exit 3; }; tb2=$(now_us)

tlo=$(( tb - ta ))
thi=$(( tb2 - ta2 ))
unit_us=$(( (thi - tlo) / (R - LO) ))
per=$(( unit_us * 1000 / N ))
printf "%-9s n=%-8s R=%-4d Tlo=%8dus Thi=%8dus  unit=%7dus  %7dns/op\n" "$CASE" "$N" "$R" "$tlo" "$thi" "$unit_us" "$per"
