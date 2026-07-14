# 张宇《基础 30 讲·概率》Obsidian 笔记 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将扫描版概率讲义可靠地转化为带 PDF 页码映射、典型例题推导、权威最新补充和 Obsidian 导航的一组中文复习笔记。

**Architecture:** 使用独立 OCR 工作区完成“PDF 页面渲染 → Tesseract 初识别 → 页面抽查 → 章节映射”，再以章节映射为唯一边界编写 MOC、分章笔记和速查。联网资料单独登记来源，最后用一个只读 PowerShell 验证器检查 YAML、双链、页码、来源和 LaTeX 基本结构。

**Tech Stack:** Windows PowerShell 5.1、Windows Runtime PDF API（失败时改用经批准安装的 Poppler）、Tesseract OCR、Obsidian Flavored Markdown、LaTeX、Mermaid、官方网页与高校公开资料。

---

## 文件结构

**新建 OCR 工程文件：**

- `数学一/98-OCR工程/README.md`：运行方法、依赖、恢复方式和临时文件策略。
- `数学一/98-OCR工程/render-pdf.ps1`：按物理页码把 PDF 渲染为 PNG。
- `数学一/98-OCR工程/ocr-pages.ps1`：调用 Tesseract，生成逐页文本和 TSV。
- `数学一/98-OCR工程/verify-ocr.ps1`：检查页数连续性、空页和低文本量页面。
- `数学一/98-OCR工程/source-map.md`：物理页码、书内页码、章节和 OCR 置信问题的人工校正表。
- `数学一/98-OCR工程/.gitignore`：忽略页面 PNG、逐页 OCR 和本地语言模型。

**新建笔记文件：**

- `数学一/01-基础讲义/张宇基础30讲概率-讲解/00-概率论总览.md`
- `数学一/01-基础讲义/张宇基础30讲概率-讲解/01-随机事件与概率.md`
- `数学一/01-基础讲义/张宇基础30讲概率-讲解/02-一维随机变量及其分布.md`
- `数学一/01-基础讲义/张宇基础30讲概率-讲解/03-多维随机变量及其分布.md`
- `数学一/01-基础讲义/张宇基础30讲概率-讲解/04-随机变量的数字特征.md`
- `数学一/01-基础讲义/张宇基础30讲概率-讲解/05-大数定律与中心极限定理.md`
- `数学一/01-基础讲义/张宇基础30讲概率-讲解/06-数理统计的基本概念.md`
- `数学一/01-基础讲义/张宇基础30讲概率-讲解/07-参数估计.md`
- `数学一/01-基础讲义/张宇基础30讲概率-讲解/08-假设检验.md`
- `数学一/01-基础讲义/张宇基础30讲概率-讲解/99-公式与易错点速查.md`
- `数学一/01-基础讲义/张宇基础30讲概率-讲解/来源与版本说明.md`

若 PDF 实际目录合并或拆分上述主题，只允许在 `source-map.md` 记录依据后调整文件边界；MOC 必须列出完整映射，不能静默遗漏。

**修改现有文件：**

- `数学一/00-资料索引.md`：在“基础讲义”下增加讲解 MOC 链接。

**新建验证文件：**

- `数学一/01-基础讲义/张宇基础30讲概率-讲解/verify-notes.ps1`：只读检查全部交付文件。

---

### Task 1: 建立可恢复的 PDF 页面渲染器

**Files:**
- Create: `数学一/98-OCR工程/render-pdf.ps1`
- Create: `数学一/98-OCR工程/.gitignore`
- Create: `数学一/98-OCR工程/README.md`

- [ ] **Step 1: 写渲染器的失败冒烟测试**

先运行尚不存在的脚本，确认测试确实失败：

```powershell
& '数学一/98-OCR工程/render-pdf.ps1' `
  -PdfPath '数学一/01-基础讲义/27张宇基础30讲概率.pdf' `
  -OutputDir '数学一/98-OCR工程/work/pages' -FirstPage 1 -LastPage 2
```

Expected: PowerShell 报告 `render-pdf.ps1` 不存在。

- [ ] **Step 2: 实现最小渲染器**

创建 `render-pdf.ps1`，完整内容如下：

```powershell
param(
  [Parameter(Mandatory)][string]$PdfPath,
  [Parameter(Mandatory)][string]$OutputDir,
  [int]$FirstPage = 1,
  [int]$LastPage = 0,
  [double]$Scale = 2.0
)
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Pdf.PdfPageRenderOptions, Windows.Data.Pdf, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime] | Out-Null

function Wait-WinRtResult {
  param([object]$Operation, [type]$ResultType)
  $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 } |
    Select-Object -First 1
  $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
  return $task.GetAwaiter().GetResult()
}

function Wait-WinRtAction {
  param([object]$Operation)
  $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
      $_.Name -eq 'AsTask' -and -not $_.IsGenericMethod -and
      $_.GetParameters().Count -eq 1 -and
      $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'
    } | Select-Object -First 1
  $task = $method.Invoke($null, @($Operation))
  $task.GetAwaiter().GetResult()
}

$resolvedPdf = (Resolve-Path -LiteralPath $PdfPath).Path
$resolvedOutput = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputDir))
[IO.Directory]::CreateDirectory($resolvedOutput) | Out-Null

$storageFile = Wait-WinRtResult `
  ([Windows.Storage.StorageFile]::GetFileFromPathAsync($resolvedPdf)) `
  ([Windows.Storage.StorageFile])
$document = Wait-WinRtResult `
  ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($storageFile)) `
  ([Windows.Data.Pdf.PdfDocument])
$pageCount = [int]$document.PageCount
Write-Output "PAGE_COUNT=$pageCount"

if ($LastPage -eq 0) { $LastPage = $pageCount }
if ($FirstPage -lt 1 -or $LastPage -lt $FirstPage -or $LastPage -gt $pageCount) {
  throw "页码范围无效：FirstPage=$FirstPage LastPage=$LastPage PageCount=$pageCount"
}

for ($number = $FirstPage; $number -le $LastPage; $number++) {
  $outputPath = Join-Path $resolvedOutput ('page_{0:D4}.png' -f $number)
  if ((Test-Path -LiteralPath $outputPath) -and (Get-Item -LiteralPath $outputPath).Length -gt 0) {
    Write-Output "SKIP=$number"
    continue
  }

  $page = $document.GetPage([uint32]($number - 1))
  $stream = [Windows.Storage.Streams.InMemoryRandomAccessStream]::new()
  $options = [Windows.Data.Pdf.PdfPageRenderOptions]::new()
  $options.DestinationWidth = [uint32][Math]::Ceiling($page.Size.Width * $Scale)
  $options.DestinationHeight = [uint32][Math]::Ceiling($page.Size.Height * $Scale)
  try {
    Wait-WinRtAction ($page.RenderToStreamAsync($stream, $options))
    $stream.Seek(0)
    $input = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
    $output = [IO.File]::Create($outputPath)
    try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
    Write-Output "RENDERED=$number"
  } finally {
    $stream.Dispose()
    $page.Dispose()
  }
}
```

- [ ] **Step 3: 验证两页 PNG**

```powershell
& '数学一/98-OCR工程/render-pdf.ps1' `
  -PdfPath '数学一/01-基础讲义/27张宇基础30讲概率.pdf' `
  -OutputDir '数学一/98-OCR工程/work/pages' -FirstPage 1 -LastPage 2
$files = Get-ChildItem '数学一/98-OCR工程/work/pages/page_000*.png'
if ($files.Count -ne 2 -or ($files | Where-Object Length -lt 10000)) { throw 'PNG smoke test failed' }
```

Expected: 输出 `PAGE_COUNT=<正整数>`，两张 PNG 均大于 10 KB。

- [ ] **Step 4: 视觉抽查第一页**

用本地图片查看工具打开 `page_0001.png`，记录方向、裁切、清晰度与是否有双页拼接。若文字高度不足，改为 `Scale 3.0` 后重测；不要在没有视觉证据时开始全量 OCR。

- [ ] **Step 5: 写 README 与忽略规则并提交**

`.gitignore` 内容：

```gitignore
work/
output/
tessdata/
```

README 必须写明输入 PDF、页码从 1 开始、断点续跑、OCR 产物不提交、原 PDF 不修改。

```powershell
git add -- '数学一/98-OCR工程/render-pdf.ps1' '数学一/98-OCR工程/.gitignore' '数学一/98-OCR工程/README.md'
git commit -m 'feat: add probability PDF page renderer'
```

---

### Task 2: 建立中文 OCR 与质量门禁

**Files:**
- Create: `数学一/98-OCR工程/ocr-pages.ps1`
- Create: `数学一/98-OCR工程/verify-ocr.ps1`
- Modify: `数学一/98-OCR工程/README.md`

- [ ] **Step 1: 写缺失中文模型的失败测试**

```powershell
$env:TESSDATA_PREFIX = (Resolve-Path '数学一/98-OCR工程/tessdata').Path
& 'C:/Program Files/Tesseract-OCR/tesseract.exe' --list-langs
```

Expected: 初始状态不包含 `chi_sim`，测试失败条件成立。

- [ ] **Step 2: 获取官方简体中文模型**

经用户批准后，从 Tesseract 官方 `tessdata_fast` 仓库下载 `chi_sim.traineddata` 到 `数学一/98-OCR工程/tessdata/`，并把本机 `eng.traineddata`、`osd.traineddata` 复制到同目录。校验三者非空，`--list-langs` 必须同时显示 `chi_sim`、`eng`、`osd`。

- [ ] **Step 3: 实现逐页 OCR**

创建 `ocr-pages.ps1`，完整内容如下：

```powershell
param(
  [Parameter(Mandatory)][string]$ImageDir,
  [Parameter(Mandatory)][string]$OutputDir,
  [int]$FirstPage = 1,
  [int]$LastPage = 0,
  [string]$Tesseract = 'C:/Program Files/Tesseract-OCR/tesseract.exe',
  [string]$TessdataDir = '数学一/98-OCR工程/tessdata'
)
$ErrorActionPreference = 'Stop'
$images = Get-ChildItem -LiteralPath $ImageDir -File -Filter 'page_*.png' | Sort-Object Name
if ($images.Count -eq 0) { throw '没有找到页面 PNG' }
if ($LastPage -eq 0) { $LastPage = $images.Count }
if ($FirstPage -lt 1 -or $LastPage -lt $FirstPage -or $LastPage -gt $images.Count) {
  throw "页码范围无效：FirstPage=$FirstPage LastPage=$LastPage ImageCount=$($images.Count)"
}
$resolvedTessdata = (Resolve-Path -LiteralPath $TessdataDir).Path
[IO.Directory]::CreateDirectory([IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputDir))) | Out-Null
$empty = [Collections.Generic.List[int]]::new()

for ($number = $FirstPage; $number -le $LastPage; $number++) {
  $image = Join-Path $ImageDir ('page_{0:D4}.png' -f $number)
  $text = Join-Path $OutputDir ('page_{0:D4}.txt' -f $number)
  $tsv = Join-Path $OutputDir ('page_{0:D4}.tsv' -f $number)
  if ((Test-Path $text) -and (Test-Path $tsv) -and (Get-Item $tsv).Length -gt 0) {
    Write-Output "SKIP=$number"
    continue
  }
  $base = Join-Path $OutputDir ('page_{0:D4}' -f $number)
  & $Tesseract $image $base -l 'chi_sim+eng' --psm 6 `
    --tessdata-dir $resolvedTessdata -c preserve_interword_spaces=1 txt tsv
  if ($LASTEXITCODE -ne 0) { throw "OCR failed: page_$('{0:D4}' -f $number).png" }
  if (-not (Test-Path $text)) { [IO.File]::WriteAllText($text, '', [Text.UTF8Encoding]::new($false)) }
  if ((Get-Content -Raw -LiteralPath $text).Trim().Length -eq 0) { $empty.Add($number) }
  Write-Output "OCR=$number"
}
$emptyPath = Join-Path $OutputDir 'empty-pages.txt'
[IO.File]::WriteAllLines($emptyPath, [string[]]@($empty | ForEach-Object { $_.ToString() }), [Text.UTF8Encoding]::new($false))
```

输出必须是 `output/page_0001.txt` 和 `output/page_0001.tsv`；已有非空文件跳过。空白页允许零文本，但必须写入 `output/empty-pages.txt`。

- [ ] **Step 4: 实现质量检查器**

创建 `verify-ocr.ps1`，完整内容如下：

```powershell
param(
  [Parameter(Mandatory)][string]$ImageDir,
  [Parameter(Mandatory)][string]$OutputDir
)
$ErrorActionPreference = 'Stop'
$images = Get-ChildItem -LiteralPath $ImageDir -File -Filter 'page_*.png' | Sort-Object Name
$texts = Get-ChildItem -LiteralPath $OutputDir -File -Filter 'page_*.txt' | Sort-Object Name
if ($images.Count -eq 0) { throw '没有页面图片' }
if ($images.Count -ne $texts.Count) { throw "页数不一致：images=$($images.Count) texts=$($texts.Count)" }

$rows = for ($index = 0; $index -lt $images.Count; $index++) {
  $expected = 'page_{0:D4}' -f ($index + 1)
  if ($images[$index].BaseName -ne $expected -or $texts[$index].BaseName -ne $expected) {
    throw "页码不连续：expected=$expected image=$($images[$index].BaseName) text=$($texts[$index].BaseName)"
  }
  $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $texts[$index].FullName
  $textChars = ($content -replace '\s','').Length
  $hanChars = ([regex]::Matches($content, '[\p{IsCJKUnifiedIdeographs}]')).Count
  $reasons = [Collections.Generic.List[string]]::new()
  if ($textChars -lt 20) { $reasons.Add('low_text') }
  if ($textChars -gt 50 -and ($hanChars / [double]$textChars) -lt 0.05) { $reasons.Add('low_han_ratio') }
  if ($content -match '[�□?]{12,}') { $reasons.Add('garbled_run') }
  [pscustomobject]@{
    page = $index + 1
    image_bytes = $images[$index].Length
    text_chars = $textChars
    han_chars = $hanChars
    suspect_reason = ($reasons -join ';')
  }
}
$report = Join-Path $OutputDir 'quality-report.csv'
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $report
$suspects = @($rows | Where-Object suspect_reason)
Write-Output "PAGES=$($rows.Count) SUSPECTS=$($suspects.Count) REPORT=$report"
```

- [ ] **Step 5: 在目录页样本上验证并提交**

先 OCR 前 20 页；抽查至少 5 页，必须能识别章节标题和多数正文汉字。公式即使错误也不得在此阶段自动“修正”。

```powershell
git add -- '数学一/98-OCR工程/ocr-pages.ps1' '数学一/98-OCR工程/verify-ocr.ps1' '数学一/98-OCR工程/README.md'
git commit -m 'feat: add resumable Chinese OCR pipeline'
```

---

### Task 3: 完成全书 OCR 和章节页码映射

**Files:**
- Create: `数学一/98-OCR工程/source-map.md`
- Generated, ignored: `数学一/98-OCR工程/work/pages/page_NNNN.png`
- Generated, ignored: `数学一/98-OCR工程/output/page_NNNN.txt`
- Generated, ignored: `数学一/98-OCR工程/output/page_NNNN.tsv`
- Generated, ignored: `数学一/98-OCR工程/output/quality-report.csv`

- [ ] **Step 1: 全量渲染并记录总页数**

```powershell
& '数学一/98-OCR工程/render-pdf.ps1' `
  -PdfPath '数学一/01-基础讲义/27张宇基础30讲概率.pdf' `
  -OutputDir '数学一/98-OCR工程/work/pages' -FirstPage 1
```

Expected: 所有物理页均有连续编号 PNG；中断后同一命令可续跑。

- [ ] **Step 2: 全量 OCR 并运行质量检查**

```powershell
& '数学一/98-OCR工程/ocr-pages.ps1' `
  -ImageDir '数学一/98-OCR工程/work/pages' `
  -OutputDir '数学一/98-OCR工程/output' -FirstPage 1
& '数学一/98-OCR工程/verify-ocr.ps1' `
  -ImageDir '数学一/98-OCR工程/work/pages' `
  -OutputDir '数学一/98-OCR工程/output'
```

Expected: 页数连续，无缺失文本；suspect 页面全部进入 CSV。

- [ ] **Step 3: 人工校正目录与页码偏移**

查看目录页、每个章首页和 suspect 页面，建立 `source-map.md`：

```markdown
| 笔记主题 | PDF 物理页 | 书内页码 | PDF 标题原文 | 处理说明 |
|---|---:|---:|---|---|
```

每个知识章节必须有起止物理页；前言、目录、答案和附录也要列出，确保没有页段失踪。

- [ ] **Step 4: 提交页码映射**

```powershell
git add -- '数学一/98-OCR工程/source-map.md'
git commit -m 'docs: map probability textbook chapters to PDF pages'
```

---

### Task 4: 核验最新考试信息与学术补充

**Files:**
- Create: `数学一/01-基础讲义/张宇基础30讲概率-讲解/来源与版本说明.md`
- Modify: `findings.md`

- [ ] **Step 1: 建立来源登记表**

文件使用以下固定表头：

```markdown
| 主题 | 结论 | 来源机构 | 页面标题 | 直接链接 | 发布/更新日期 | 访问日期 | 用途 |
|---|---|---|---|---|---|---|---|
```

- [ ] **Step 2: 搜索并核验最新官方考试信息**

只接受教育部、中国研究生招生信息网或招生单位官方页面支持会变化的事实。明确写出“截至 2026-07-14，能检索到的最新官方文件是什么”；若 2027 数学一大纲尚未正式发布，必须写“尚未发现正式发布”，不得用培训机构预测代替。

- [ ] **Step 3: 核验核心概率知识**

对条件概率、独立性、常见分布、随机变量函数、协方差、中心极限定理、抽样分布、点估计、区间估计和假设检验，至少选用一套高校公开课程/教材资料交叉核对。技术来源优先官方课程页、开放教材或原始学术材料。

- [ ] **Step 4: 区分考试范围和拓展**

每条现代补充只能标为以下之一：

```text
考试信息 / 概念澄清 / 现代拓展 / 勘误依据
```

现代拓展不得进入“必须掌握”清单；所有外部事实同时写入 `findings.md`，不写入 `task_plan.md`。

- [ ] **Step 5: 检查直接链接并提交**

逐个打开链接，确认不是搜索结果页、聚合页或失效页。

```powershell
git add -- '数学一/01-基础讲义/张宇基础30讲概率-讲解/来源与版本说明.md'
git commit -m 'docs: register probability notes sources and version scope'
```

---

### Task 5: 编写 MOC 和分章笔记

**Files:**
- Create: `数学一/01-基础讲义/张宇基础30讲概率-讲解/00-概率论总览.md`
- Create: `数学一/01-基础讲义/张宇基础30讲概率-讲解/01-随机事件与概率.md`
- Create: `数学一/01-基础讲义/张宇基础30讲概率-讲解/02-一维随机变量及其分布.md`
- Create: `数学一/01-基础讲义/张宇基础30讲概率-讲解/03-多维随机变量及其分布.md`
- Create: `数学一/01-基础讲义/张宇基础30讲概率-讲解/04-随机变量的数字特征.md`
- Create: `数学一/01-基础讲义/张宇基础30讲概率-讲解/05-大数定律与中心极限定理.md`
- Create: `数学一/01-基础讲义/张宇基础30讲概率-讲解/06-数理统计的基本概念.md`
- Create: `数学一/01-基础讲义/张宇基础30讲概率-讲解/07-参数估计.md`
- Create: `数学一/01-基础讲义/张宇基础30讲概率-讲解/08-假设检验.md`

- [ ] **Step 1: 写笔记结构失败检查**

```powershell
$root='数学一/01-基础讲义/张宇基础30讲概率-讲解'
$expected='00-概率论总览.md','01-随机事件与概率.md','02-一维随机变量及其分布.md','03-多维随机变量及其分布.md','04-随机变量的数字特征.md','05-大数定律与中心极限定理.md','06-数理统计的基本概念.md','07-参数估计.md','08-假设检验.md'
$missing=$expected | Where-Object {-not (Test-Path (Join-Path $root $_))}
if($missing.Count -eq 0){throw 'Precondition invalid: notes already exist'}
```

Expected: 缺失列表非空。

- [ ] **Step 2: 创建统一 YAML 与导航骨架**

每篇分章必须使用：

```yaml
---
title: "章节标题"
created: 2026-07-14
updated: 2026-07-14
type: study-note
status: complete
exam: 数学一
source: "[[数学一/01-基础讲义/27张宇基础30讲概率.pdf]]"
pdf_pages: "起始-结束"
tags:
  - 考研
  - 数学一
  - 概率论与数理统计
aliases: []
---
```

正文首尾均链接 `[[00-概率论总览]]`，相关章节使用精确 wikilink。

- [ ] **Step 3: 按统一教学结构写完每章**

每章必须依次包含：本章定位、概念直觉、严格定义与公式、PDF 典型例题、易错点、真题思路、最新补充、闭卷自测、PDF 页码索引。典型例题使用折叠 callout：

```markdown
> [!example]- 典型例题：题型名称（PDF p.物理页码）
> **识别：** 看到什么条件，应想到什么工具。
>
> **推导：** 每一步写明使用的定义或定理。
>
> **检查：** 概率范围、归一化、边界值或量纲检查。
>
> **迁移：** 同类变式如何处理。
```

每章至少覆盖 PDF 中出现的全部代表性题型；相同模板的机械重复题在“题型归纳”列出页码，不复制题干。

- [ ] **Step 4: 校正公式**

逐个核对：条件、取值范围、分母非零、密度归一化、分布函数右连续、方差非负、协方差对称、估计量与参数区分、原假设与拒绝域方向。OCR 公式不得直接粘贴；无法确认时回看 PNG 并在笔记中标记“需人工核对”。

- [ ] **Step 5: 提交 MOC 与分章笔记**

```powershell
git add -- '数学一/01-基础讲义/张宇基础30讲概率-讲解/00-概率论总览.md' '数学一/01-基础讲义/张宇基础30讲概率-讲解/01-随机事件与概率.md' '数学一/01-基础讲义/张宇基础30讲概率-讲解/02-一维随机变量及其分布.md' '数学一/01-基础讲义/张宇基础30讲概率-讲解/03-多维随机变量及其分布.md' '数学一/01-基础讲义/张宇基础30讲概率-讲解/04-随机变量的数字特征.md' '数学一/01-基础讲义/张宇基础30讲概率-讲解/05-大数定律与中心极限定理.md' '数学一/01-基础讲义/张宇基础30讲概率-讲解/06-数理统计的基本概念.md' '数学一/01-基础讲义/张宇基础30讲概率-讲解/07-参数估计.md' '数学一/01-基础讲义/张宇基础30讲概率-讲解/08-假设检验.md'
git commit -m 'docs: add probability textbook chapter notes'
```

---

### Task 6: 编写公式与易错点速查

**Files:**
- Create: `数学一/01-基础讲义/张宇基础30讲概率-讲解/99-公式与易错点速查.md`

- [ ] **Step 1: 从分章笔记建立公式清单**

每条公式必须包含“公式、适用条件、常见误用、来源章节”四项；不能只有裸公式。

- [ ] **Step 2: 建立分布速查表**

离散分布和连续分布分别列参数、支持集、概率质量/密度、期望、方差、可加性或极限定理关系。表格中的竖线必须转义，复杂公式改用表格外块公式。

- [ ] **Step 3: 建立考前检查表**

至少覆盖事件关系、条件概率分母、分布函数分段点、二维积分区域、独立与不相关、方差展开、标准化方向、统计量自由度、估计量评价、单双侧检验。

- [ ] **Step 4: 提交速查**

```powershell
git add -- '数学一/01-基础讲义/张宇基础30讲概率-讲解/99-公式与易错点速查.md'
git commit -m 'docs: add probability formulas and pitfalls reference'
```

---

### Task 7: 自动验证 Obsidian 交付物

**Files:**
- Create: `数学一/01-基础讲义/张宇基础30讲概率-讲解/verify-notes.ps1`
- Modify: `数学一/00-资料索引.md`

- [ ] **Step 1: 写会失败的验证器调用**

```powershell
& '数学一/01-基础讲义/张宇基础30讲概率-讲解/verify-notes.ps1'
```

Expected: 脚本尚不存在，失败。

- [ ] **Step 2: 实现只读验证器**

创建 `verify-notes.ps1`，完整内容如下：

```powershell
param([string]$Root = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$requiredProperties = 'title','created','updated','type','status','exam','source','pdf_pages','tags'
$requiredSections = '本章定位','概念直觉','严格定义','易错点','闭卷自测','PDF 页码索引'
$chapterPattern = '^(0[1-8])-.*\.md$'
$errors = [Collections.Generic.List[string]]::new()
$notes = Get-ChildItem -LiteralPath $Root -File -Filter '*.md'
$chapters = @($notes | Where-Object Name -Match $chapterPattern)

foreach ($file in $chapters) {
  $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
  if ($content -notmatch '(?s)^---\s*\r?\n(.+?)\r?\n---') {
    $errors.Add("$($file.Name): 缺少有效 YAML frontmatter")
    continue
  }
  $yaml = $Matches[1]
  foreach ($property in $requiredProperties) {
    if ($yaml -notmatch "(?m)^$([regex]::Escape($property))\s*:") {
      $errors.Add("$($file.Name): 缺少属性 $property")
    }
  }
  foreach ($section in $requiredSections) {
    if ($content -notmatch "(?m)^##+\s+$([regex]::Escape($section))") {
      $errors.Add("$($file.Name): 缺少章节 $section")
    }
  }
  if ($content -notmatch '\[\[00-概率论总览(?:\||\]\])') { $errors.Add("$($file.Name): 缺少 MOC 回链") }
  if ($content -notmatch '27张宇基础30讲概率\.pdf#page=\d+') { $errors.Add("$($file.Name): 缺少 PDF 物理页链接") }
  if (([regex]::Matches($content, '(?m)^```')).Count % 2 -ne 0) { $errors.Add("$($file.Name): 代码围栏未闭合") }
  if (([regex]::Matches($content, '\$\$')).Count % 2 -ne 0) { $errors.Add("$($file.Name): 块公式未闭合") }
  if ($content -match '(?i)TBD|TODO|待补充|示例内容') { $errors.Add("$($file.Name): 存在占位符") }
}

$mocPath = Join-Path $Root '00-概率论总览.md'
if (-not (Test-Path $mocPath)) { $errors.Add('缺少 00-概率论总览.md') }
else {
  $moc = Get-Content -Raw -Encoding UTF8 -LiteralPath $mocPath
  foreach ($file in $chapters + @($notes | Where-Object Name -EQ '99-公式与易错点速查.md')) {
    if ($moc -notmatch "\[\[$([regex]::Escape($file.BaseName))(?:\||\]\])") {
      $errors.Add("MOC 未链接 $($file.Name)")
    }
  }
}

if ($chapters.Count -ne 8) { $errors.Add("分章文件数量应为 8，实际为 $($chapters.Count)") }
if ($errors.Count -gt 0) {
  $errors | ForEach-Object { Write-Error $_ }
  exit 1
}
Write-Output "PASS: $($notes.Count) notes validated"
```

若 `source-map.md` 证明实际目录需要合并或拆分主题，先同步修改 `$chapterPattern` 和数量断言，再运行验证；调整理由必须留在映射表中。

- [ ] **Step 3: 更新资料索引**

在 `数学一/00-资料索引.md` 的“基础讲义”列表中，紧邻原 PDF 链接新增：

```markdown
- [[数学一/01-基础讲义/张宇基础30讲概率-讲解/00-概率论总览|基础 30 讲：概率·讲解笔记]]
```

- [ ] **Step 4: 运行验证并修复全部失败**

```powershell
& '数学一/01-基础讲义/张宇基础30讲概率-讲解/verify-notes.ps1'
git diff --check -- '数学一/01-基础讲义/张宇基础30讲概率-讲解' '数学一/00-资料索引.md'
```

Expected: 验证器输出 PASS；`git diff --check` 无输出且退出码 0。

- [ ] **Step 5: 提交验证器和索引**

```powershell
git add -- '数学一/01-基础讲义/张宇基础30讲概率-讲解/verify-notes.ps1' '数学一/00-资料索引.md'
git commit -m 'test: validate and index probability Obsidian notes'
```

---

### Task 8: 最终人工验收与交付

**Files:**
- Modify if needed: `数学一/98-OCR工程/source-map.md`
- Modify if needed: `数学一/01-基础讲义/张宇基础30讲概率-讲解/*.md`

- [ ] **Step 1: 抽查 PDF 对应关系**

每个分章随机抽查至少 3 个物理页：章首页、一个定义/定理页、一个典型例题页。核对题型、符号、页码和结论；将结果追加到 `source-map.md` 的“最终抽查”节。

- [ ] **Step 2: 抽查公式数学一致性**

至少对每章 5 个核心公式做特殊值或边界检查；二项分布概率和为 1、密度积分为 1、方差非负、分布函数端点正确、置信区间随样本量变化方向正确。

- [ ] **Step 3: 核对来源时效**

重新打开所有会变化信息的直接链接，确认访问日期、官方身份和表述没有超出来源支持范围；明确 2027 大纲是否已经正式发布。

- [ ] **Step 4: 在 Obsidian 中验证渲染**

若 Obsidian 已运行，使用 CLI 读取 MOC 并检查 backlinks；若未运行，启动需要另行获得 GUI 权限。视觉抽查 Mermaid、Callout、表格和块公式，修复断链或渲染异常。

- [ ] **Step 5: 最终验证与提交**

```powershell
& '数学一/01-基础讲义/张宇基础30讲概率-讲解/verify-notes.ps1'
git status --short -- '数学一/98-OCR工程' '数学一/01-基础讲义/张宇基础30讲概率-讲解' '数学一/00-资料索引.md'
```

Expected: 验证 PASS；状态中没有临时 PNG、OCR 文本或语言模型；只显示计划内 Markdown/PowerShell 文件。

```powershell
git add -- '数学一/98-OCR工程/source-map.md' '数学一/01-基础讲义/张宇基础30讲概率-讲解'
git commit -m 'docs: finalize probability Obsidian study guide'
```

---

## 完成定义

- PDF 的全部知识章节均在 `source-map.md` 有明确页码边界并映射到笔记。
- MOC、8 个主题笔记（或经映射说明调整后的实际章节）、速查和来源说明齐全。
- 代表性例题有逐步推导，机械重复题仅归纳方法并列页码。
- 所有公式、最新信息和本地链接通过自动检查与人工抽查。
- OCR 临时文件、语言模型和页面图片不进入 Git；不修改或覆盖原 PDF。
- 不把用户工作区中与本任务无关的现有改动纳入任何提交。
