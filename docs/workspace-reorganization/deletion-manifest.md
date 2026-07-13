# D:\study 删除清单

日期：2026-07-13  
状态：已完成删除并复验目标不存在

| 目标 | 字节数 | 删除依据 | 当前状态 |
|---|---:|---|---|
| `D:\study\考研\408\cs-408-master.zip` | 1,104,160,241 | 61/61 个条目在分类目标逐项哈希通过 | deleted-verified（2026-07-13；exists=False） |
| `D:\study\考研\408\CS-Xmind-Note-master.zip` | 105,418,231 | 91/91 个条目在知识图谱与来源目标逐项哈希通过 | deleted-verified（2026-07-13；exists=False） |
| `D:\study\考研\408\真题.zip` | 56,897,921 | 32/32 个条目在真题目标逐项哈希通过 | deleted-verified（2026-07-13；exists=False） |
| `D:\study\__pycache__\batch_ocr.cpython-313.pyc` | 5,102 | Python 生成缓存；源码迁移后不再需要；基线哈希一致 | deleted-verified（2026-07-13；exists=False） |
| 7 个迁移后的旧空目录 | 0 | 删除瞬间递归文件数为 0、绝对路径严格匹配 | deleted-verified（2026-07-13；exists=False） |

计划释放：`1,266,481,495` 字节。

实际释放：`1,266,481,495` 字节。删除命令未使用通配符；四个文件和七个旧目录的删除后存在状态均为 `False`。

## 删除前门槛结果

- 408 主笔记：38 份 Markdown、26 章，UTF-8、Frontmatter、必需标题、围栏、LaTeX 与占位符检查问题均为 0。
- 活动笔记：79 份 Markdown、487 个真实 Wikilink，排除 3 个模板变量链接后未解析为 0。
- ZIP 条目：`61/61`、`91/91`、`32/32`，共 `184/184` 匹配，缺失、哈希不一致和未映射均为 0。
- 四个精确删除文件均与 `baseline-hashes.csv` 的字节数和 SHA-256 一致。
- 数学一 87 份 PDF、英语一 21 份、CET-6 67 份、OCR 输出 1,444 份和两组王道 2026 PDF 共 8 份均通过数量/字节复验。

## 不删除

- 两组共 8 份王道 2026 PDF；
- 数学二、CET-6、数据库、信息安全和 4 个 `.one.zip`；
- OCR 文本、README、LICENSE、`.gitignore`；
- `.git`、`.agents`、`.obsidian`、`skills-lock.json`。
