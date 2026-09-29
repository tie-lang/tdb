#!/usr/bin/env bash
# ab2.sh —— 稳健 A/B：每版多轮跑固定 R，取**最小总时间**（干扰只增不减，最小值最接近真值），
#           再减去同形 noop 的最小总时间（扣固定启动成本）。
# 用法: ./ab2.sh <exeA> <exeB> <case> <scale> <R> [rounds]
set -u
A="$1"; B="$2"; CASE="$3"; N="$4"; R="${5:-100}"; ROUNDS="${6:-8}"
now_us() { date +%s%N | cut -c1-16; }

best_of() { # $1=exe  $2=case → 最小总时间(us)
  local exe="$1" c="$2" lo=0 t
  lo=999999999
  local i
  for i in $(seq 1 "$ROUNDS"); do
    local ta tb
    ta=$(now_us); "$exe" "$c" "$N" "$R" >/dev/null 2>&1; tb=$(now_us)
    t=$(( tb - ta ))
    if [ "$t" -lt "$lo" ]; then lo=$t; fi
  done
  echo "$lo"
}

# 同形 noop 基线与各版对照
for k in A B; do
  if [ "$k" = "A" ]; then EXE="$A"; else EXE="$B"; fi
  noop=$(best_of "$EXE" noop)
  ctot=$(best_of "$EXE" "$CASE")
  d=$(( ctot - noop ))
  per=$(( d * 1000 / (R * N) ))
  printf "%s: case=%8dus noop=%8dus delta=%8dus  %6dns/op\n" "$k" "$ctot" "$noop" "$d" "$per"
done
