# zbuf —— 原始字节缓冲抽象 / Raw Byte-Buffer Abstraction

* 模块 / Module: `src/zbuf.tie`（namespace `zbuf`）
* 引入 / Introduced: r.1.6.7（2026-09-30）
* 定位 / Role: 字节数据的**统一载体**与读写原语；同时提供与既有 `table<i64>` 的边界互换

---

## 一、为什么需要它 / Why

tie 里表示「一串字节」长期有两种做法，代价差异极大：

| 载体 / carrier | 密度 / density | 单字节访问 / per-byte access |
| --- | --- | --- |
| `table<i64>`（元素 0..255） | **8×**（每字节独占 8 字节槽） | 容器下标（走容器锁） |
| **字符串（本模块）** | **1×** | `str_byte` 单指令 |

内置 `byte_read` 还会把读入的 u8 缓冲**逐字节零扩展**成 8 字节槽（`tb[i*8] = u8[i]`），
即文件读取天然 8× 且双次分配。`bytes_to_str` 之类的转换助手此前在至少 3 处被各自复制
实现（`tie-compiler` 的 `keel_auditor` / `keel_registry_cli` / `zdpub`）。

**tie 字符串本身即可安全承载任意二进制**（含 `0x00` / `0xFF`）：
`len(s)` 是**字节数**（码点数是 `str_len`），`str_byte(s, i)` 按**字节**索引，
`sb_append` 按**字节** memcpy。本模块就是把这一事实固化为显式、可复用、可测量的接口。

> The byte carrier: tie strings are `(ptr, len)` with **byte** semantics, so they carry
> arbitrary binary at **1×** density with single-instruction byte access, versus
> `table<i64>` at **8×** with a container-lock per element.

---

## 二、接口 / API

### 写端（StringBuilder 组装）/ Writer

| 函数 | 说明 |
| --- | --- |
| `bw_new() -> i64` | 新建写端（StringBuilder 句柄） |
| `bw_reset(bw)` | 重置复用（保留容量） |
| `bw_put_u8(bw, b)` | 单字节（自动 `& 0xFF`） |
| `bw_put_bytes(bw, s)` | **整段原始字节（单次 memcpy）**——批量首选 |
| `bw_put_u16_be/le`、`u32`、`u64` | 定宽整数 |
| `bw_put_f64_be/le` | IEEE 754 位模式（bitcast 逐位精确） |
| `bw_put_varint(bw, n)` | LEB128（与 `zd.write_varint` 同形） |
| `bw_put_zigzag(bw, n)` | 有符号 zigzag + varint |
| `bw_put_len_bytes(bw, s)` | varint 字节数 + 原始字节（zd 的 string/bytes 框式） |
| `bw_build(bw) -> string` | 收束为字符串 |
| `bw_len(bw) -> i64` | 已写字节数（**O(n)**，仅诊断用；热循环请自持计数器） |

单值便捷形：`enc_u8/u16_be/u32_be/u64_be/f64_be/varint/len_bytes` → 直接产出小字符串。

### 读端（纯函数：(缓冲, 位置) → (值, 新位置)）/ Reader

`br_u8/u16_be/le/u32_be/le/u64_be/le/f64_be/le/varint/zigzag/len_bytes`，
以及 `br_len`（字节长度）、`br_remaining`、`br_has`、`br_at`、`br_slice`。
**越界/畸形一律 `next = -1`**（与 tdb/zd 既有约定一致），调用方必须检查。

### 边界互换 / Boundary interop

`to_table(s) -> table<i64>`、`from_table(t) -> string`。

> ⚠ **两者都是逐字节 O(n)（实测 `to_table` 35 ns/字节、`from_table` 49 ns/字节）**，
> 比它们要代替的工作本身还贵。**字节应在整条链路上保持字符串载体，只在真正存在
> `table<i64>` 签名 API 的边界处互换**；在热循环里反复互换会把收益吃光。
> Both converters are per-byte O(n) and cost more than the work they replace - convert
> only at true API boundaries.

### 文件 I/O / File I/O

`file_load(path) -> string`、`file_store(path, s) -> bool`、`file_append_bytes(path, s) -> bool`。
走内置 `file_read`/`file_write`（字符串载体，**1×**）；对照 `byte_read` 的 8× 零扩展。

---

## 三、实测 / Measurements

同一台机、同一载荷，外部计时（差值法 + 多轮最小总时间）。a 与 b 为同长度载荷。

| 操作 / operation | `table<i64>`（8×） | 字符串（1×） | 比值 / ratio |
| --- | ---: | ---: | ---: |
| 构造 n 字节（push vs `sb_append_byte`） | 33 ns/字节 | **4 ns/字节** | **8.25×** |
| 扫描 n 字节（`t[i]` vs `str_byte`） | 40 ns/字节 | **6 ns/字节** | 6.7× |
| CRC32（表版 vs `crc32_str`） | 52 ns/字节 | **7 ns/字节** | 7.4× |
| 读 1 MB 文件（`byte_read` vs `file_read`） | 4471 µs | **418 µs** | **10.7×** |
| `chunk_encode`（zd 帧，含 CRC） | 104 ns/字节 | **7 ns/字节** | **14.9×** |
| `chunk_next`（取 payload） | 74 ns/字节 | **6 ns/字节** | 12.3× |
| 峰值工作集（16 MB 载荷） | 184.6 MB | **25.7 MB** | 7.2× 更低 |

峰值内存用 `PeakWorkingSet64` 采样（进程存活期间轮询取累计峰值）。
`chunk_*` 两行是 `zd_stream` 载体迁移的**真实 A/B**（旧实现取自迁移前 git 版本，
作为独立模块同进程对照）；旧 `chunk_encode` 除了 8× 载体外还把 payload
**逐元素 push** 进输出表，新实现是 `u32` + **单次 memcpy** + CRC。

---

## 四、迁移纪律（改线上格式时）/ Migration discipline

`zd_stream` 的帧/流已由 `table<i64>` 迁到字符串载体，**线上字节格式一字未变**——
迁移前先把各帧/流 dump 成 hex 基线，迁移后重跑同一语义并 `diff`，要求**逐字节相同**，
然后才删掉基线。凡「换载体 / 换实现」的改动都应照此办理：**字节格式用逐字节比对证明，
不用"看起来一样"证明。**

> The zd_stream frame/stream carrier migration was proven byte-identical by diffing a
> pre-migration hex dump against a post-migration one. Always prove wire-format
> invariance by byte comparison.

---

## 五、与 `zd` / `zd_v3` 的关系 / Relation to zd

`zbuf` 只做**原始字节**搬运，**不做**码点 ↔ UTF-8 转换（那是 `zd.utf8_encode` 的文本语义）。
`zd.write_varint` / `write_u64_be` / `write_f64_be` 与本模块的写端**逐字节同值**
（`tests/probe_zbuf.tie` 有交叉断言），因此两种载体可安全互通。
`zd_v3`（v3 容器）目前仍以 `table<i64>` 承载字节；其内部层整体迁到字符串载体是
后续项（见 trm-lite `docs/2026-09-29-tie-perf-safety-and-startup.md` §2.3）。
