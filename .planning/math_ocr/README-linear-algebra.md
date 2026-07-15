# 线性代数讲义 OCR 记录

源文件：`数学一/01-基础讲义/27张宇基础30讲线代.pdf`。

本记录复用同目录的 `render-pdf.ps1`、`ocr-pages.ps1` 和 `verify-ocr.ps1`。中间图片、OCR 文本及语言模型分别位于被 Git 忽略的 `work/`、`output/`、`tessdata/`，不会修改源 PDF。

## 执行命令

```powershell
& '.planning/math_ocr/render-pdf.ps1' `
  -PdfPath '数学一/01-基础讲义/27张宇基础30讲线代.pdf' `
  -OutputDir '.planning/math_ocr/work/linear-pages' `
  -FirstPage 1
```

```powershell
& '.planning/math_ocr/ocr-pages.ps1' `
  -ImageDir '.planning/math_ocr/work/linear-pages' `
  -OutputDir '.planning/math_ocr/output/linear' `
  -FirstPage 1
```

```powershell
& '.planning/math_ocr/verify-ocr.ps1' `
  -ImageDir '.planning/math_ocr/work/linear-pages' `
  -OutputDir '.planning/math_ocr/output/linear'
```

## 本次结果

- PDF 物理页：213 页。
- 渲染页：213 页，连续。
- OCR TXT/TSV：213 组，连续。
- 质量规则标记：5 页。
  - 第 7 页为图形化目录，文字量低。
  - 第 14、64、88、169 页以矩阵和公式为主，汉字比例低。
- 章节首页已目视核对：第 8、18、52、89、121、146、185 页。
- 第 213 页为第 6 讲最后一页，不是空白页。

> [!warning] 矩阵公式必须回看原页
> OCR 对矩阵括号、行列式竖线、上下标、转置符号、特征值重数和二次型交叉项不可靠。OCR 文本只用于定位，最终公式必须根据页面图像或原 PDF 人工重排。

页码边界见 [[source-map-linear-algebra]]。
