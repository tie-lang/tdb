# tdb

**tieDB — tie 生态数据库完整实现** / *Full database implementation for the tie ecosystem*

tdb 是 tie 生态的数据库组件（原 tieDB/tiedb），提供**列式持久化 + 向量检索
（vecsearch）**的能力。以 zd v2 二进制格式为底座，覆盖 tie:data（文本）、
tie:zd（二进制）两种线代格式，并提供 tie 侧数据 API、编解码桥与命令行工具。

*EN: tdb is the database component of the tie ecosystem (formerly tieDB),
delivering columnar persistence + vector search (vecsearch) over the zd v2
format, covering both tie:data (text) and tie:zd (binary) wire formats, with a
tie-side data API, codec bridge, and CLI tooling.*

> v2: this repository hosts the **complete** tieDB v2 implementation
> (p.9.6.1). The former split-component v1 API/persist layout is archived
> under `archive/v1/`.

## 模块 / Modules

| Module     | File                        | Namespace  | Description |
|------------|-----------------------------|------------|-------------|
| **tdata**  | `src/tdata.tie`            | `td`       | tie:data 文本格式解析与写出            |
| **zd**     | `src/zd.tie`               | `zd`       | tie:zd MessagePack 风格二进制序列化（v2 头） |
| **vec**    | `src/vec.tie`              | `vecsearch`| Flat 向量检索（L2、cosine、top-k）     |
| **codec**  | `src/codec.tie`            | `tdc`      | tdata↔zd 编解码桥（节点 encode/decode）|
| **zd_builder** | `src/zd_builder.tie`   | —          | zd 批量构建（i64/f64/string 批量编解码）|
| **zd_ext** | `src/zd_ext.tie`           | —          | zd 扩展（null/optional 0xc0、ext 0xd7、schema 与内容 hash 段）|
| **zd_extra** | `src/zd_extra.tie`       | —          | zd 增强（string dict、列式容器、零拷贝视图、offset 表）|
| **zd_stream** | `src/zd_stream.tie`     | —          | zd 流式（CRC32、分块帧、解压声明）    |
| **zd_v3** | `src/zd_v3.tie`             | `zd_v3`    | **zd v3 载体**（头 / 索引 footer / 段表 / 多段文档 / v2+v3 读义务；对齐 zd-java）|
| **api**    | `src/api.tie`              | —          | 数据 API 层（tdata 节点池设计）        |
| **json**   | `src/cli/json.tie`         | `json`     | JSON 解析与写出                        |
| **cli**    | `src/cli/main.tie`         | —          | 九命令 CLI 工具                        |

## CLI 命令 / CLI Commands

```
tiedb fmt <file> [-w] [--compact] [--indent N] [--insertion-order] [--no-trailing]
tiedb check <files...>
tiedb to-json <file> [-o out] [-i]
tiedb from-json <file> [-o out] [--header] [--compact]
tiedb get <file> <path>
tiedb set <file> <path> <literal> [-w]
tiedb merge <base> <overlay...> [-o out]
tiedb compact <in.data.tie> -o <out.zd.tie>
tiedb decompress <in.zd.tie> -o <out.data.tie>
```

## 测试 / Tests

`tests/` 下约 30 个探针（probe_*.tie），覆盖 tdata 解析/格式化、zd v2 头与
往返、批量构建（builder）、ext/extra/stream 扩展、向量检索等。用 tiec 编译运行：

```bash
tiec tests/probe_zd_v2.tie -o tests/probe_zd_v2.exe
tests/probe_zd_v2.exe
```

*EN: ~30 probes under `tests/` cover tdata parsing/formatting, the zd v2 header
and round-trips, batch building, the ext/extra/stream extensions, and vector
search. Compile and run with tiec as shown above.*

## 构建 / Build

需要 [tie 编译器](https://github.com/TIE-LANG/tie) 与 LLVM/Clang。
Requires the tie compiler and LLVM/Clang.

```bash
tiec src/tdata.tie --emit-ir -o bin/tdata.exe
clang bin/tdata.ll -o bin/tdata.a -fuse-ld=link
export TIE_INTERP_LIB=path/to/tie_interp.lib
clang bin/main.ll -o bin/tiedb.exe \
  -Wl,/FORCE:MULTIPLE -Wl,/STACK:134217728 \
  -rtlib=compiler-rt "$TIE_INTERP_LIB" \
  -lws2_32 -luserenv -lntdll -lbcrypt -ladvapi32 -lole32 -lshell32
```

## 已知问题 / Known Issues

- **CLI pre-main AV**：当前 tiec 编译器对包含 `file_read()` + `td.parse()` +
  树遍历（`td.write` / `tdc.encode_node`）的二进制存在已知问题，会在 `main()`
  前触发访问冲突。核心库模块（`.a`）不受影响，可独立使用。
  *The current tiec compiler has a known issue where binaries mixing `file_read()`
  + `td.parse()` + tree traversal trigger an access violation before `main()`.
  Core library modules are unaffected.*

## License

本仓库按 **Tie Public License v2.0（TPL 2.0）** 授权发布（全文见 [LICENSE](LICENSE)）：
你可自由使用、修改并分发本软件源码，包括用于商业产品，仅需保留版权声明并附本许可证。

EN: This repository is released under the **Tie Public License v2.0 (TPL 2.0)**
(full text in [LICENSE](LICENSE)): you may freely use, modify, and redistribute
the source code, including in commercial products, provided you retain the
copyright notice and a copy of the license.