#!/usr/bin/env bash
# bench_carrier.sh —— 字节载体对比基准（差值法 + 最小总时间 + 自动标定档位）
# 用法: ./bench_carrier.sh <exe> <case> <n> [path] [min_signal_us] [rounds]
# 单位说明：`date +%s%N | cut -c1-16` = 秒(10) + 纳秒前 6 位 = **微秒**。
#   故 t/d 均为 us；每单位(ns) = d * 1000 / R / n。
# 原理：进程创建地板 ~0.6–1.2s，单次信号易被抖动淹没。故自动升级 rep，直到
#   「T(2R) − T(R)」明显超噪声（默认 ≥250ms），再以该差值 / R 得每次开销；
#   每档取多轮**最小总时间**（干扰只增不减，最小值最接近真值）。
set -u
EXE="$1"; CASE="$2"; N="$3"; PATH_ARG="${4:-}"; MIN_SIG_US="${5:-250000}"; ROUNDS="${6:-3}"
now() { date +%s%N | cut -c1-16; }

best() { # $1=rep → 最小总时间(us)
  local rep="$1" lo=999999999 t i
  for i in $(seq 1 "$ROUNDS"); do
    local a b
    a=$(now)
    if [ -n "$PATH_ARG" ]; then "$EXE" "$CASE" "$N" "$rep" "$PATH_ARG" >/dev/null 2>&1
    else "$EXE" "$CASE" "$N" "$rep" >/dev/null 2>&1; fi
    b=$(now); t=$(( b - a ))
    [ "$t" -lt "$lo" ] && lo=$t
  done
  echo "$lo"
}

R=25
while [ "$R" -le 25600 ]; do
  t1=$(best "$R"); t2=$(best $(( R * 2 )))
  d=$(( t2 - t1 ))
  if [ "$d" -ge "$MIN_SIG_US" ]; then
    per_ns=$(( d * 1000 / R ))                 # 每次 rep 的纳秒数
    unit_ns=$(( d * 1000 / R / N ))            # 每单位（字节）纳秒数
    per_us=$(( d / R ))
    printf "%-16s n=%-8s R=%-6s T(R)=%-8sus T(2R)=%-8sus Δ=%-8sus → %7s us/次  %6s ns/字节\n" \
      "$CASE" "$N" "$R" "$t1" "$t2" "$d" "$per_us" "$unit_ns"
    exit 0
  fi
  R=$(( R * 2 ))
done
echo "未能在合理 rep 内取得足够信号（case=$CASE n=$N）"
exit 1
