---
title: 408 王道 PDF OCR 工程
tags:
  - 408
  - OCR
status: active
updated: 2026-07-13
---

# 408 王道 PDF OCR 工程

本目录保存 OCR 脚本和已生成文本。`output` 包含四科分页文本与合并全文，是 408 笔记的本地底稿。

## 环境要求

- Python 3
- `openai`
- `pypdfium2`
- 环境变量 `SILICONFLOW_API_KEY`

## 使用方法

```powershell
if (-not $env:SILICONFLOW_API_KEY) { throw "请先在当前终端安全设置 SILICONFLOW_API_KEY" }
python batch_ocr.py "..\90-复习资料\01-核心教材\王道2026\OCR源PDF\2026数据结构.pdf"
python batch_ocr.py "..\90-复习资料\01-核心教材\王道2026\OCR源PDF\2026数据结构.pdf" 120
```

第二条命令从 0-based 页码 120 继续处理。输出目录固定为当前工程下的 `output`。

> [!warning] 凭据安全
> 源代码不保存 API 凭据。请通过环境变量配置密钥；曾写入旧脚本的密钥仍需在服务端撤销并轮换。
