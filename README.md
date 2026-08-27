# tiedb

Data service layer for the [tie](https://github.com/TIE-LANG) programming language.

tiedb provides parsing, serialization, API, and CLI tooling for tie:data and tie:zd formats.

## Modules

| Module | File | Namespace | Description |
|--------|------|-----------|-------------|
| **tdata** | `src/tdata.tie` | `td` | tie:data text format parser and writer |
| **zd** | `src/zd.tie` | `zd` | tie:zd MessagePack-style binary serialization |
| **vec** | `src/vec.tie` | `vecsearch` | Flat vector search (L2, cosine, top-k) |
| **codec** | `src/codec.tie` | `tdc` | Bridge between tdata and zd (encode/decode nodes) |
| **api** | `src/api.tie` | — | Data API layer |
| **json** | `src/cli/json.tie` | `json` | JSON parser and writer |
| **cli** | `src/cli/main.tie` | — | Nine-command CLI tool |

## CLI Commands

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

## Build

Requires the [tie compiler](https://github.com/TIE-LANG/tie) and LLVM/Clang.

```bash
# Compile a module as static library
tiec src/tdata.tie --emit-ir -o bin/tdata.exe
clang bin/tdata.ll -o bin/tdata.a -fuse-ld=link

# Set bridge library path
export TIE_INTERP_LIB=path/to/tie_interp.lib

# Link CLI (requires all .a libraries + bridge)
clang bin/main.ll -o bin/tiedb.exe \
  -Wl,/FORCE:MULTIPLE -Wl,/STACK:134217728 \
  -rtlib=compiler-rt "$TIE_INTERP_LIB" \
  -lws2_32 -luserenv -lntdll -lbcrypt -ladvapi32 -lole32 -lshell32
```

## Known Issues

- **CLI pre-main AV**: The current tiec compiler has a known issue where binaries containing `file_read()` + `td.parse()` + tree traversal (`td.write` / `tdc.encode_node`) trigger an access violation before `main()` starts. Core library modules (`.a` files) are not affected and can be used independently.

## License

TIE-LANG Open Source License v1.1. See [LICENSE](LICENSE).
