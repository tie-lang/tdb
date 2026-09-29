# zd 性能审计与基准 / zd Performance Audit & Benchmarks

* 日期 / Date: 2026-09-29
* 探针 / Probes: `tests/probe_zd_perf.tie`（吞吐）、`tests/bench.sh`（斜率法差值计时）
* 结论摘要 / TL;DR: zd 侧已落地 5 项优化（编码路径 >100×、f64 2.7×、池查询 23.7×）；
  剩余瓶颈在 **trm-lite 表容器**（每次元素访问 32–39ns，见 §3）与 **字节表的 8× 内存膨胀**（§4）。

---

## 1. 测量方法 / Measurement Method

tie 只有秒级 `time_now`，且最小 tie 程序的运行时启动成本实测 **≈680ms**（`main(){println("hi")}`）。
故采用**斜率法**：

```
unit = ( T(R) − T(R/2) ) / (R/2)
```

`R` 取 100–200，把测项成本放大两个数量级、压过固定启动成本的抖动（±90ms）。
测项在进程内重复 `R` 次，数据构造只在 `main` 内做一次。
**外部计时**：`date +%s%N` 前 16 位（微秒精度）。

Run: `tests/probe_zd_perf.exe <case> <scale> <repeat>`；`tests/bench.sh <exe> <case> <scale> [R]`

### 基线对照值 / Reference points (n = 200000, R = 200)

| 操作 / op | ns/op | 说明 / note |
| --- | ---: | --- |
| `noop` | ≈ 0 | 固定成本抵消后的本底噪声（±1.4ms 级） |
| **表读 `t[i]`** | **32** | `tl_tbl$tbl_at`——每次访问进出 CRITICAL_SECTION |
| **`table_push`** | **39** | `tl_tbl$tbl_push`——同上，加 ensure/memcpy/set_len |
| `memcpy`（`byte_concat`） | ≈ 0.1 | 原生 memcpy，参照上限 |

> **表元素访问 ≈ 32–39ns 是 tie 数据面的性能天花板**：任何「逐元素」写法（读或写）
> 都以此为下界；只有 memcpy 级批量原语（`byte_concat` / `str_sub_bytes` / `sb_append`）
> 才能突破。

---

## 2. 已落地优化 / Landed Optimizations

| # | 位置 / site | 优化 / change | 前 / before | 后 / after | 增益 / gain |
| --- | --- | --- | ---: | ---: | ---: |
| 1 | `zd.encode_bytes` | 逐元素 `table_push` → `byte_concat(头, 载荷)` | 33.4 ms / 200KB | **< 0.3 ms** | **> 100×** |
| 2 | `zd.read_f64_be` | 数学逆分解（`pow` + `parse_float`）→ `bitcast_i64_f64` | 1672 ns | 616 ns | 2.7× |
| 3 | `zd.encode_f64` / `write_f64_be` | 数学分解（`log`/`pow` + 52 轮尾数循环）→ `bitcast_f64_i64` | 1543 ns | 940 ns | 1.6× |
| 4 | `zd.write_u16/u32/u64_be`、`encode_i64` 定宽分支、`encode_bool/char/trit/u64` | `table_new` + N×`table_push` → 单次分配字面量 | 8 次 push ≈ 312ns | 1 次分配 ≈ 50ns | ≈ 6× |
| 5 | `zd_extra.pool_index` | 线性扫池 + 逐条解码（O(n×len)）→ **哈希索引**（FNV-1a 32 + 线性探测，O(1) 均摊） | 99 904 ns | **4 222 ns** | **23.7×** |

* 优化 1 的语义说明：旧实现逐元素 `& 0xFF`（对合法字节表是恒等操作）；新实现直接
  `byte_concat`，字节结果不变（`probe_zd_bytes` 全绿）。
* 优化 2/3 的**语义反而更强**：数学分解把次正规数简化为 ±0（丢信息），bitcast 逐位精确
  （含次正规 / NaN / ±inf / ±0）；常规数的字节输出不变（`probe_zd_bitcast` 全绿）。
* 优化 5 新增 `pool_index_build` / `pool_lookup`（旧 `pool_index` 保留，语义不变）；
  正确性由 `probe_zd_poolidx` 7 项校验（含前缀/超串不误判、重复串取首个、空池）。

### 未做（有测量依据的取舍）/ Deliberately not done

* **`crc32` 不改为查表版**：表读 32ns > 逐位 8 轮 ≈ 16ns——在表访问提速前，查表版更慢。
* **`decode_bytes` / `slice` 未提速**：范围拷贝无法用现有原语表达为 memcpy（见 §4）。

---

## 3. 剩余瓶颈：trm-lite 表容器 / Remaining bottleneck

`core/tbl/tl_tbl.tie` 的每次元素访问（读/写/追加）成本 ≈ 32–39ns，成因逐项可量化：

1. **每访问一次加锁**（`EnterCriticalSection` + `LeaveCriticalSection`，2 次 kernel32 调用）≈ 20ns；
2. **句柄字段逐字节读写**：`r_i64` / `w_i64` 是 8 次迭代的字节循环，`tbl_at` 一次调用有
   ~16 次 `movzbl`（LLVM 未合并为单条 8 字节 load——实测反汇编确认）；
3. **外部函数调用 + 232 字节栈帧 + xmm 溢出**（`llvm-objdump -d trm_lite.a`）；
4. **`ensure_locked` 重复读取** cap/len/data/esz（调用方刚读过）。

### 建议（按收益/风险排序）/ Recommendations

| 方案 / option | 预期收益 / expected | 风险 / risk |
| --- | --- | --- |
| trm-lite 加**同线程重入快路径**（句柄存 owner TID + 深度；已知持锁则免 OS 调用） | 32 → ≈15ns（≈2×） | 低（跨线程语义不变） |
| **表字面量批量 codegen**（`tbl_new` + 一次 `ensure(n)` + N 次直写，替代 N 次 `tbl_push`） | 定宽编码 ≈10× | 低（纯 codegen，语义不变） |
| 语言级**宽指针 deref**（`ptr<i64>`），或以 token 允许 `int_to_ptr` 转换到宽类型 | 字段访问 8 轮 → 1 条 load（≈4×） | 中（语言/编译器改动） |
| **批量追加原语** `tbl_append(h, src, n)`（一次锁 + 一次 memcpy） | 逐元素 → memcpy 级（>100×） | 中（新外部符号 + 编译器接线） |

---

## 4. 内存：字节表 8× 膨胀 / Memory: 8× bloat

`table<i64>` 每元素 8 字节，而字节仅需 1 字节——承载 n 字节净荷实际占 **8n 字节**
（另加 48 字节句柄 + 每表 CRITICAL_SECTION 缓冲 64 字节）。换言之 **1 MB 载荷 → 8 MB 常驻**，
与「低内存」目标直接冲突。

对照 / contrast：tie 的**字符串**是 `(ptr, len)`，字节密度 1×，且具备 memcpy 级能力
（`str_byte` O(1) 取字节、`str_sub_bytes` 单次 memcpy 切片、`sb_append` 摊销 O(1) 追加）。

### 建议 / Recommendation

zd v3 的内部字节缓冲改用**字符串承载 + StringBuilder 组装**，仅在 API 边界转 `table<i64>`；
或新增「原始缓冲 + 偏移/长度」视图类型。前者无需编译器改动即可落地，且同时解决 §3 的
逐元素成本（解码侧仍受 `table<i64>` 输入限制，故两者宜并行推进）。

---

## 5. 复现 / Reproduce

```bash
cd tdb
../tiec/compiler/tiec.exe tests/probe_zd_perf.tie --no-cache --no-warn -o /tmp/perf.exe
tests/bench.sh /tmp/perf.exe encbytes 200000 200
tests/bench.sh /tmp/perf.exe poolidx  20000  100
tests/bench.sh /tmp/perf.exe poolhash 20000  100
```

测项清单见 `probe_zd_perf.tie` 头部注释（`noop / readloop / pushloop / slice / encbytes /
decbytes / encstr / decstr / encarr / encrec / f64enc / f64dec / poolbuild / poolidx /
poolhash / poolhashbuild / col / crc / chunk / offtab`）。
