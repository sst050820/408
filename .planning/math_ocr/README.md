# 概率论讲义 OCR 页面渲染

本目录用于把 `数学一/01-基础讲义/27张宇基础30讲概率.pdf` 渲染成逐页 PNG，供后续 OCR 使用。脚本只读取源 PDF，不会修改、覆盖或重写源文件。

## 页码与断点续跑

- `FirstPage` 和 `LastPage` 都使用从 1 开始的物理页码；输出文件相应命名为 `page_0001.png`、`page_0002.png` 等。
- `LastPage` 默认为 `0`，表示渲染到 PDF 的总页数。
- 每页先完整写入同目录的 `.partial` 临时文件，刷新并校验 PNG 头尾后，再以同目录原子操作发布为最终文件；失败时会删除临时文件，不会留下新的半成品最终页。
- 输出目录中已有的完整 PNG 会显示 `SKIP` 并跳过；不完整的旧文件会被安全替换，因此命令中断后可用同一命令继续执行。
- `work/`、`output/` 和 `tessdata/` 是被 Git 忽略的 OCR 中间产物或本地资源目录。

## 两页冒烟测试

在仓库根目录运行：

```powershell
& '.planning/math_ocr/render-pdf.ps1' -PdfPath '数学一/01-基础讲义/27张宇基础30讲概率.pdf' -OutputDir '.planning/math_ocr/work/pages' -FirstPage 1 -LastPage 2
```

该文件当前报告 `PAGE_COUNT=173`，上述命令生成前两页。

## 完整渲染

省略 `LastPage` 即使用默认值 `0`，渲染至最后一页：

```powershell
& '.planning/math_ocr/render-pdf.ps1' -PdfPath '数学一/01-基础讲义/27张宇基础30讲概率.pdf' -OutputDir '.planning/math_ocr/work/pages' -FirstPage 1
```

如需更高分辨率，可添加 `-Scale 3.0`；默认缩放倍数为 `2.0`。

## 首页面目视检查

在默认 `Scale 2.0` 下，`page_0001.png` 为横向的双页/整幅封面展开图，方向正确，没有旋转；封面、书脊和左右边缘完整，未见内容裁切。标题和正文清晰，左侧较小的介绍文字在原始尺寸下仍可辨认，因此未提高到 `Scale 3.0`。

## 中文 OCR 环境

- OCR 程序：`C:/Program Files/Tesseract-OCR/tesseract.exe`。
- 语言模型：`chi_sim+eng`；`chi_sim.traineddata` 来自 Tesseract 官方 [`tessdata_fast`](https://github.com/tesseract-ocr/tessdata_fast) 仓库。
- 本地模型存放在 `.planning/math_ocr/tessdata/`，该目录已被 Git 忽略，不会提交二进制模型。
- OCR 输出存放在 `.planning/math_ocr/output/`，包括逐页 `.txt`、定位信息 `.tsv`、空白页清单及质量报告。

先识别前 20 个 PDF 物理页：

```powershell
& '.planning/math_ocr/ocr-pages.ps1' -ImageDir '.planning/math_ocr/work/pages' -OutputDir '.planning/math_ocr/output' -FirstPage 1 -LastPage 20
```

完成全部页面渲染后，省略 `LastPage` 即可识别到最后一页：

```powershell
& '.planning/math_ocr/ocr-pages.ps1' -ImageDir '.planning/math_ocr/work/pages' -OutputDir '.planning/math_ocr/output' -FirstPage 1
```

运行质量检查：

```powershell
& '.planning/math_ocr/verify-ocr.ps1' -ImageDir '.planning/math_ocr/work/pages' -OutputDir '.planning/math_ocr/output'
```

OCR 同样使用临时文件后发布；同时存在且非空的 TXT、TSV 会显示 `SKIP`。失败产生的临时文件会被清理，可用原命令继续。`quality-report.csv` 只把低文本量、汉字占比异常或长乱码串标为可疑页，不会擅自改写内容。

> [!warning] 数学公式必须回看原页
> Tesseract 能较好恢复多数中文正文和章节标题，但对分式、上下标、集合符号、无穷号、积分号与复杂公式识别不可靠。OCR 文本只用于定位和建立提纲，最终公式与例题必须结合页面图片人工校正，禁止自动猜测。

前 20 页样本中，第 8 页能辨认出全书六讲结构和考题分布，第 12、16、20 页能恢复大部分正文；封面和版权页的装饰字体、横排小字与公式噪声较多。这些限制会在后续章节映射中保留记录。
