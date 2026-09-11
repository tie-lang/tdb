# tdb

**tie 数据库** / *Database for the tie ecosystem*

tdb 是 tie 生态的数据库组件（原 tieDB/tiedb）：列式持久化 + 向量检索
（vecsearch），以 zd v2 格式为底座，提供 tie 侧数据库 API 与存储层。

*EN: tdb is the database component of the tie ecosystem (formerly tieDB/tiedb):
columnar persistence + vector search (vecsearch) over the zd v2 format, with a
tie-side database API and storage layer.*

## 内容 / Contents

- `api.tie` 数据库 API（tie 侧入口）
- `persist/` 持久化层（zd v2 线代存储：`persist/zd.tie` 读写/头兼容）
- `tests/` 探针测试（`tests/zd_test.tie`）

## License

本仓库按 **Tie Public License v2.0（TPL 2.0）** 授权发布（全文见 [LICENSE](LICENSE)）：
你可自由使用、修改并分发本软件源码，包括用于商业产品，仅需保留版权声明并附本许可证。

EN: This repository is released under the **Tie Public License v2.0 (TPL 2.0)**
(full text in [LICENSE](LICENSE)): you may freely use, modify, and redistribute
the source code, including in commercial products, provided you retain the
copyright notice and a copy of the license.
