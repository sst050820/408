# D:\study 考研资料工作区重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `D:\study` 重构为稳定的 408、数学一、英语一和大学英语六级资料架构，在不丢失独有内容、不破坏 Obsidian 链接的前提下删除已验证的重复 ZIP、缓存和空目录。

**Architecture:** 保持 `408-考研` 现有四科笔记路径不变，将外部资料就近归入 `90-复习资料`，将 OCR 工程归入 `98-OCR工程`，并在根目录建立独立的 `数学一`、`英语一`、`其他考试/大学英语六级`。每次移动前记录源文件大小和 SHA-256，移动后逐项复验；三个外层 ZIP 只有在其全部条目已于目标目录通过哈希检查后才删除。

**Tech Stack:** Windows PowerShell、Obsidian Flavored Markdown、YAML Frontmatter、Wikilink、SHA-256、`.NET System.IO.Compression`、JSON、Python 源码静态检查。

## Global Constraints

- 工作区绝对根路径固定为 `D:\study`；所有目标路径解析后必须仍位于该根路径。
- `408-考研` 既有 38 份 Markdown、26 章和四科目录路径不得改名或移动。
- 4 份带书签王道 PDF 和 4 份无书签 OCR 源 PDF 都保留。
- 数学二、CET-6、数据库、信息安全、4 个 `.one.zip`、OCR 文本、README、LICENSE 和 `.gitignore` 均保留。
- `.git`、`.agents`、`.obsidian`、`skills-lock.json` 保持原位。
- 目标存在且 SHA-256 不同时停止该文件操作，绝不覆盖。
- 删除只允许发生在设计文档明确列出的三个外层 ZIP、`__pycache__` 缓存和迁移后空目录。
- 当前目录不是有效 Git 仓库；每个任务以迁移表、哈希结果和验证报告作为检查点，不执行 Git 提交。
- 当前系统没有 `python`、`py` 或 `pdfinfo`；OCR 脚本只做静态验证，不宣称运行成功。

---

## 文件结构与职责

**创建：**

- `docs/workspace-reorganization/migration-map.md`：逐文件源路径、目标路径、字节数、SHA-256 和状态。
- `docs/workspace-reorganization/deletion-manifest.md`：删除候选、验证依据、删除前后状态和释放字节数。
- `docs/workspace-reorganization/validation-report.md`：基线、迁移前、删除前和删除后验证结果。
- `408-考研/90-复习资料/00-资料索引.md`：408 外部资料入口。
- `数学一/00-资料索引.md`：数学一资料入口。
- `英语一/00-资料索引.md`：英语一资料入口。
- `其他考试/大学英语六级/00-资料索引.md`：CET-6 资料入口。
- `408-考研/98-OCR工程/README.md`：OCR 工程使用与安全说明。

**修改：**

- `408-考研/00-总览/408考研复习总览.md`：增加复习资料入口。
- `408-考研/00-总览/资料来源与版本说明.md`：更新 OCR 路径和两套 PDF 的用途。
- `408-考研/**/*.md`：仅更新旧 `ocr_output/...` 文字路径，不改知识正文。
- `docs/408-rewrite/source-register.md`：登记新 OCR 路径和资料迁移位置。
- `docs/408-rewrite/validation-report.md`：追加工作区重构后的路径状态。
- `.obsidian/workspace.json`：将最近文件中的根目录王道 PDF 更新为新位置；保持合法 JSON。
- `408-考研/98-OCR工程/batch_ocr.py`：移除硬编码 API 凭据，改用环境变量，输出固定到工程 `output`。
- `task_plan.md`、`findings.md`、`progress.md`：执行期间持续记录，最后归档。

**移动但不改内容：**

- 根目录 4 份无书签王道 PDF。
- `408-考研/99-资料/王道2026-带书签PDF` 下 4 份带书签 PDF。
- `考研/408` 的真题、答案、分章讲义、旧版题库、知识图谱、OneNote 和其他资源。
- `考研/数一` 的 87 份 PDF。
- `考研/英一` 的英语一和 CET-6 资料。
- `ocr_output` 的全部 1,444 个文件与根目录 `batch_ocr.py`。

---

### Task 1: 建立不可变基线与迁移清单

**Files:**
- Create: `docs/workspace-reorganization/migration-map.md`
- Create: `docs/workspace-reorganization/deletion-manifest.md`
- Create: `docs/workspace-reorganization/validation-report.md`
- Modify: `task_plan.md`
- Modify: `progress.md`

**Interfaces:**
- Consumes: 已确认设计 `docs/superpowers/specs/2026-07-13-study-workspace-reorganization-design.md`。
- Produces: 后续所有任务使用的基线数量、字节数、哈希记录和删除门槛。

- [x] **Step 1: 验证固定根路径和关键源路径**

Run:

```powershell
$root = (Resolve-Path -LiteralPath 'D:\study').Path
if ($root -ne 'D:\study') { throw "Unexpected root: $root" }
@(
  'D:\study\408-考研',
  'D:\study\考研\408',
  'D:\study\考研\数一',
  'D:\study\考研\英一',
  'D:\study\ocr_output',
  'D:\study\batch_ocr.py'
) | ForEach-Object {
  if (-not (Test-Path -LiteralPath $_)) { throw "Missing source: $_" }
}
```

Expected: exit code 0，无输出。

- [x] **Step 2: 记录四个资料区域的文件数与字节数**

Run:

```powershell
$areas = @(
  '408-考研', '考研\408', '考研\数一', '考研\英一', 'ocr_output'
)
foreach ($area in $areas) {
  $files = Get-ChildItem -LiteralPath $area -Recurse -File -Force
  [pscustomobject]@{
    Area = $area
    Files = $files.Count
    Bytes = ($files | Measure-Object Length -Sum).Sum
  }
}
```

Expected baseline: `408-考研=42`、`考研/408=186`、`考研/数一=87`、`考研/英一=88`、`ocr_output=1444`。若数量变化，先把实际差异写入验证报告再继续。

- [x] **Step 3: 对所有将移动或删除的文件计算 SHA-256**

Run:

```powershell
$sources = @(
  (Get-ChildItem -LiteralPath 'D:\study' -File -Filter '2026*.pdf'),
  (Get-ChildItem -LiteralPath 'D:\study\408-考研\99-资料' -Recurse -File -Force),
  (Get-ChildItem -LiteralPath 'D:\study\考研' -Recurse -File -Force),
  (Get-ChildItem -LiteralPath 'D:\study\ocr_output' -Recurse -File -Force),
  (Get-Item -LiteralPath 'D:\study\batch_ocr.py')
) | ForEach-Object { $_ }
$records = foreach ($file in $sources) {
  $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
  [pscustomobject]@{ Path=$file.FullName; Bytes=$file.Length; SHA256=$hash.Hash }
}
$records.Count
```

Expected: 哈希对象数等于所有纳入迁移的源文件数；无哈希失败。

- [x] **Step 4: 使用 apply_patch 写入三份基线文档**

`migration-map.md` 必须含：范围、源根路径、目标根路径、字段定义，以及每个移动单元的状态 `planned`。`deletion-manifest.md` 必须预登记三个 ZIP、缓存和空目录，状态为 `blocked-until-verified`。`validation-report.md` 必须写入 Step 2 的实际数量和 Step 3 的哈希对象数。

- [x] **Step 5: 检查基线文档完整性**

Run:

```powershell
rg -n "planned|blocked-until-verified|SHA-256|考研\\408|考研\\数一|考研\\英一" docs\workspace-reorganization
rg -n "T[B]D|T[O]DO|F[I]XME|待.{0}补充" docs\workspace-reorganization
```

Expected: 第一条命令命中三份文档的规定字段；第二条命令无输出。

---

### Task 2: 创建目标骨架并恢复缺失 XMind

**Files:**
- Create directories under: `408-考研/90-复习资料`
- Create directories under: `408-考研/98-OCR工程`
- Create directories under: `数学一`
- Create directories under: `英语一`
- Create directories under: `其他考试/大学英语六级`
- Extract: `考研/408/CS-Xmind-Note-master/计算机网络/第 4 章  网络层/第 4 章  网络层.xmind`
- Modify: `docs/workspace-reorganization/migration-map.md`

**Interfaces:**
- Consumes: Task 1 的基线和 `CS-Xmind-Note-master.zip`。
- Produces: 空目标骨架和完整的 91 文件 XMind 源目录。

- [x] **Step 1: 创建非冲突目标目录**

Run:

```powershell
$dirs = @(
  '408-考研\90-复习资料\01-核心教材\王道2026\带书签阅读版',
  '408-考研\90-复习资料\01-核心教材\王道2026\OCR源PDF',
  '408-考研\90-复习资料\02-历年真题\真题',
  '408-考研\90-复习资料\02-历年真题\答案',
  '408-考研\90-复习资料\03-分章讲义',
  '408-考研\90-复习资料\04-题库与旧版教材',
  '408-考研\90-复习资料\05-知识图谱',
  '408-考研\90-复习资料\06-OneNote原档',
  '408-考研\90-复习资料\07-其他资源',
  '408-考研\90-复习资料\99-来源说明\cs-408-master',
  '408-考研\90-复习资料\99-来源说明\CS-Xmind-Note-master',
  '408-考研\98-OCR工程',
  '数学一\01-基础讲义',
  '数学一\02-专题与强化',
  '数学一\03-公式手册',
  '数学一\04-历年真题',
  '数学一\05-真题解析',
  '数学一\06-答题卡与速查',
  '数学一\90-拓展资料\数学二',
  '英语一\01-历年真题',
  '英语一\02-真题解析',
  '英语一\90-拓展资料',
  '其他考试\大学英语六级\历年真题',
  'docs\workspace-reorganization'
)
foreach ($dir in $dirs) {
  $full = [IO.Path]::GetFullPath((Join-Path 'D:\study' $dir))
  if (-not $full.StartsWith('D:\study\')) { throw "Unsafe target: $full" }
  New-Item -ItemType Directory -Path $full -Force | Out-Null
}
```

Expected: 所有目录存在；无文件被移动。

- [x] **Step 2: 验证缺失 XMind 尚不存在**

Run:

```powershell
$missing = '考研\408\CS-Xmind-Note-master\计算机网络\第 4 章  网络层\第 4 章  网络层.xmind'
if (Test-Path -LiteralPath $missing) { throw 'XMind already exists; re-audit before extraction' }
```

Expected: exit code 0。

- [x] **Step 3: 安全提取唯一缺失 XMind**

Run:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = (Resolve-Path -LiteralPath '考研\408\CS-Xmind-Note-master.zip').Path
$target = [IO.Path]::GetFullPath('D:\study\考研\408\CS-Xmind-Note-master\计算机网络\第 4 章  网络层\第 4 章  网络层.xmind')
$allowed = [IO.Path]::GetFullPath('D:\study\考研\408\CS-Xmind-Note-master') + '\'
if (-not $target.StartsWith($allowed)) { throw "Unsafe extraction target: $target" }
$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
  $entry = $zip.Entries | Where-Object {
    $_.FullName -eq 'CS-Xmind-Note-master/计算机网络/第 4 章  网络层/第 4 章  网络层.xmind'
  }
  if ($null -eq $entry) { throw 'Required XMind entry not found' }
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
  $input = $entry.Open()
  $output = [IO.File]::Create($target)
  try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
} finally { $zip.Dispose() }
```

Expected: 目标 XMind 存在，大小为 ZIP 条目记录的大小。

- [x] **Step 4: 比较提取文件哈希**

Run:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = (Resolve-Path -LiteralPath '考研\408\CS-Xmind-Note-master.zip').Path
$target = (Resolve-Path -LiteralPath '考研\408\CS-Xmind-Note-master\计算机网络\第 4 章  网络层\第 4 章  网络层.xmind').Path
$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
$sha = [Security.Cryptography.SHA256]::Create()
try {
  $entry = $zip.Entries | Where-Object {
    $_.FullName -eq 'CS-Xmind-Note-master/计算机网络/第 4 章  网络层/第 4 章  网络层.xmind'
  }
  $entryStream = $entry.Open()
  try { $entryHash = [BitConverter]::ToString($sha.ComputeHash($entryStream)).Replace('-','') }
  finally { $entryStream.Dispose() }
  $fileStream = [IO.File]::OpenRead($target)
  try { $fileHash = [BitConverter]::ToString($sha.ComputeHash($fileStream)).Replace('-','') }
  finally { $fileStream.Dispose() }
  if ($entryHash -ne $fileHash) { throw 'Recovered XMind hash mismatch' }
  "sha256=$fileHash"
} finally {
  $sha.Dispose()
  $zip.Dispose()
}
```

Expected: 输出一个 64 位 SHA-256；将迁移表中该条目标记为 `recovered-verified`。

---

### Task 3: 迁移 408 外部资料

**Files:**
- Move: `408-考研/99-资料/王道2026-带书签PDF/*.pdf`
- Move: `D:/study/2026*.pdf`
- Move: `考研/408/真题/{真题,答案}` contents
- Move: `考研/408/cs-408-master` classified contents
- Move: `考研/408/CS-Xmind-Note-master` classified contents
- Modify: `docs/workspace-reorganization/migration-map.md`

**Interfaces:**
- Consumes: Task 2 的目标骨架和完整 XMind 源目录。
- Produces: 完整的 `408-考研/90-复习资料`；三个外层 ZIP 仍保留。

- [x] **Step 1: 定义并预检精确移动映射**

映射必须包含以下源到目标：

```text
408-考研/99-资料/王道2026-带书签PDF/*.pdf
  -> 408-考研/90-复习资料/01-核心教材/王道2026/带书签阅读版/
D:/study/2026操作系统.pdf、2026数据结构.pdf、2026计算机组成原理.pdf、2026计算机网络.pdf
  -> 408-考研/90-复习资料/01-核心教材/王道2026/OCR源PDF/
考研/408/真题/真题/* -> 408-考研/90-复习资料/02-历年真题/真题/
考研/408/真题/答案/* -> 408-考研/90-复习资料/02-历年真题/答案/
考研/408/cs-408-master/1数据结构 -> 408-考研/90-复习资料/03-分章讲义/数据结构
考研/408/cs-408-master/2计算机组成原理 -> 408-考研/90-复习资料/03-分章讲义/计算机组成原理
考研/408/cs-408-master/3操作系统 -> 408-考研/90-复习资料/03-分章讲义/操作系统
考研/408/cs-408-master/4计算机网络 -> 408-考研/90-复习资料/03-分章讲义/计算机网络
考研/408/cs-408-master/5王道书和刷题本/* -> 408-考研/90-复习资料/04-题库与旧版教材/
考研/408/CS-Xmind-Note-master/{信息安全,操作系统,数据库,数据结构,计算机组成原理,计算机网络}
  -> 408-考研/90-复习资料/05-知识图谱/
考研/408/cs-408-master/7onenote文件/* -> 408-考研/90-复习资料/06-OneNote原档/
考研/408/cs-408-master/6其他资源/* -> 408-考研/90-复习资料/07-其他资源/
```

对于每项映射，目标文件若存在：哈希相同则登记，不同则停止；所有目标不存在或同哈希后才执行 Step 2。

- [x] **Step 2: 按映射逐项使用 Move-Item 移动**

Run the following helper and exact mapping in one PowerShell session：

```powershell
$root = 'D:\study\'
function Move-VerifiedFile([string]$source, [string]$destination) {
  $src = (Resolve-Path -LiteralPath $source).Path
  $dst = [IO.Path]::GetFullPath($destination)
  if (-not $src.StartsWith($root) -or -not $dst.StartsWith($root)) { throw "Unsafe path: $src -> $dst" }
  if (Test-Path -LiteralPath $dst) {
    $srcHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
    $dstHash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
    if ($srcHash -eq $dstHash) { throw "Same-hash target already exists; record duplicate before retry: $dst" }
    throw "Different-content target exists: $dst"
  }
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst)) | Out-Null
  $before = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
  Move-Item -LiteralPath $src -Destination $dst
  $after = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
  if ($before -ne $after) { throw "Post-move hash mismatch: $dst" }
}
function Move-VerifiedTree([string]$sourceRoot, [string]$destinationRoot) {
  $sourceFull = (Resolve-Path -LiteralPath $sourceRoot).Path
  foreach ($file in Get-ChildItem -LiteralPath $sourceFull -Recurse -File -Force) {
    $relative = $file.FullName.Substring($sourceFull.Length + 1)
    Move-VerifiedFile $file.FullName (Join-Path $destinationRoot $relative)
  }
}
$fileMoves = @(
  @('D:\study\2026操作系统.pdf','D:\study\408-考研\90-复习资料\01-核心教材\王道2026\OCR源PDF\2026操作系统.pdf'),
  @('D:\study\2026数据结构.pdf','D:\study\408-考研\90-复习资料\01-核心教材\王道2026\OCR源PDF\2026数据结构.pdf'),
  @('D:\study\2026计算机组成原理.pdf','D:\study\408-考研\90-复习资料\01-核心教材\王道2026\OCR源PDF\2026计算机组成原理.pdf'),
  @('D:\study\2026计算机网络.pdf','D:\study\408-考研\90-复习资料\01-核心教材\王道2026\OCR源PDF\2026计算机网络.pdf'),
  @('D:\study\考研\408\cs-408-master\README.md','D:\study\408-考研\90-复习资料\99-来源说明\cs-408-master\README.md'),
  @('D:\study\考研\408\cs-408-master\LICENSE','D:\study\408-考研\90-复习资料\99-来源说明\cs-408-master\LICENSE'),
  @('D:\study\考研\408\cs-408-master\.gitignore','D:\study\408-考研\90-复习资料\99-来源说明\cs-408-master\.gitignore'),
  @('D:\study\考研\408\CS-Xmind-Note-master\README.md','D:\study\408-考研\90-复习资料\99-来源说明\CS-Xmind-Note-master\README.md'),
  @('D:\study\考研\408\CS-Xmind-Note-master\LICENSE','D:\study\408-考研\90-复习资料\99-来源说明\CS-Xmind-Note-master\LICENSE')
)
$treeMoves = @(
  @('D:\study\408-考研\99-资料\王道2026-带书签PDF','D:\study\408-考研\90-复习资料\01-核心教材\王道2026\带书签阅读版'),
  @('D:\study\考研\408\真题\真题','D:\study\408-考研\90-复习资料\02-历年真题\真题'),
  @('D:\study\考研\408\真题\答案','D:\study\408-考研\90-复习资料\02-历年真题\答案'),
  @('D:\study\考研\408\cs-408-master\1数据结构','D:\study\408-考研\90-复习资料\03-分章讲义\数据结构'),
  @('D:\study\考研\408\cs-408-master\2计算机组成原理','D:\study\408-考研\90-复习资料\03-分章讲义\计算机组成原理'),
  @('D:\study\考研\408\cs-408-master\3操作系统','D:\study\408-考研\90-复习资料\03-分章讲义\操作系统'),
  @('D:\study\考研\408\cs-408-master\4计算机网络','D:\study\408-考研\90-复习资料\03-分章讲义\计算机网络'),
  @('D:\study\考研\408\cs-408-master\5王道书和刷题本','D:\study\408-考研\90-复习资料\04-题库与旧版教材'),
  @('D:\study\考研\408\CS-Xmind-Note-master\信息安全','D:\study\408-考研\90-复习资料\05-知识图谱\信息安全'),
  @('D:\study\考研\408\CS-Xmind-Note-master\操作系统','D:\study\408-考研\90-复习资料\05-知识图谱\操作系统'),
  @('D:\study\考研\408\CS-Xmind-Note-master\数据库','D:\study\408-考研\90-复习资料\05-知识图谱\数据库'),
  @('D:\study\考研\408\CS-Xmind-Note-master\数据结构','D:\study\408-考研\90-复习资料\05-知识图谱\数据结构'),
  @('D:\study\考研\408\CS-Xmind-Note-master\计算机组成原理','D:\study\408-考研\90-复习资料\05-知识图谱\计算机组成原理'),
  @('D:\study\考研\408\CS-Xmind-Note-master\计算机网络','D:\study\408-考研\90-复习资料\05-知识图谱\计算机网络'),
  @('D:\study\考研\408\cs-408-master\7onenote文件','D:\study\408-考研\90-复习资料\06-OneNote原档'),
  @('D:\study\考研\408\cs-408-master\6其他资源','D:\study\408-考研\90-复习资料\07-其他资源')
)
foreach ($pair in $fileMoves) { Move-VerifiedFile $pair[0] $pair[1] }
foreach ($pair in $treeMoves) { Move-VerifiedTree $pair[0] $pair[1] }
```

Expected: 所有目标存在且移动前后哈希相同；根目录 4 份 PDF 不再存在；三个外层 ZIP 仍在旧位置。

- [x] **Step 3: 迁移来源说明文件**

Move:

```text
考研/408/cs-408-master/README.md、LICENSE、.gitignore
  -> 408-考研/90-复习资料/99-来源说明/cs-408-master/
考研/408/CS-Xmind-Note-master/README.md、LICENSE
  -> 408-考研/90-复习资料/99-来源说明/CS-Xmind-Note-master/
```

Expected: 两个来源目录的说明和许可证齐全。

- [x] **Step 4: 用 Task 1 哈希复验全部 408 目标文件**

Expected: 每个移动文件的目标 SHA-256 等于源记录；迁移表状态改为 `moved-verified`。三个外层 ZIP 仍存在，旧来源目录只剩空目录结构。

---

### Task 4: 迁移数学一

**Files:**
- Move: `考研/数一/**/*`
- Modify: `docs/workspace-reorganization/migration-map.md`

**Interfaces:**
- Consumes: Task 1 数学一哈希基线和 Task 2 目标目录。
- Produces: 根目录 `数学一` 的完整分类结构；旧 `考研/数一` 只剩空目录。

- [x] **Step 1: 移动四个既有分类目录的内容**

```text
考研/数一/数一真题标准版（直接打印）/* -> 数学一/04-历年真题/
考研/数一/数一真题详解（步骤解析）/* -> 数学一/05-真题解析/
考研/数一/数一答案速查（核对结果）/* -> 数学一/06-答题卡与速查/答案速查/
考研/数一/答题卡与公式/* -> 数学一/06-答题卡与速查/答题卡与公式/
```

每个目标路径必须不存在或与源文件哈希相同。

- [x] **Step 2: 移动基础讲义**

Move these exact files to `数学一/01-基础讲义/`：

```text
27张宇《核心计算通关讲义》.pdf
27张宇基础30讲概率.pdf
27张宇基础30讲线代.pdf
27张宇基础30讲（高数）.pdf
27张宇零基础通关讲义.pdf
```

- [x] **Step 3: 移动公式与数学二资料**

```text
27张宇数学公式手册.pdf -> 数学一/03-公式手册/
考研数学公式手册随身看(打印版).pdf -> 数学一/03-公式手册/
考研高数【数学二】（完整版）.pdf -> 数学一/90-拓展资料/数学二/
考研高数【数学二】（默写版）(1).pdf -> 数学一/90-拓展资料/数学二/考研高数【数学二】（默写版）.pdf
```

最后一项仅清理下载文件名中的 `(1)`；重命名前记录原始哈希。

- [x] **Step 4: 复验数学一数量与哈希**

Run:

```powershell
$files = Get-ChildItem -LiteralPath '数学一' -Recurse -File -Force
$files.Count
($files | Measure-Object Length -Sum).Sum
```

Expected: PDF 为 87 份；总字节数等于 Task 1 数学一基线。每个目标哈希相同，迁移表状态为 `moved-verified`。

---

### Task 5: 迁移英语一与大学英语六级

**Files:**
- Move: `考研/英一/英一历年真题/**/*`
- Move: `考研/英一/历年六级真题/**/*`
- Modify: `docs/workspace-reorganization/migration-map.md`

**Interfaces:**
- Consumes: Task 1 英语一哈希基线和 Task 2 目标目录。
- Produces: 根目录 `英语一` 与 `其他考试/大学英语六级`；旧 `考研/英一` 只剩空目录。

- [x] **Step 1: 移动英语一真题**

Move `考研/英一/英一历年真题/*` to `英语一/01-历年真题/`，保持 21 份年份 PDF 文件名不变。

- [x] **Step 2: 移动 CET-6 年月与套题目录**

Move `考研/英一/历年六级真题/*` to `其他考试/大学英语六级/历年真题/`，保持 2016–2021 的年月和套题层级不变。

- [x] **Step 3: 复验英语资料数量与字节数**

Run:

```powershell
$english = Get-ChildItem -LiteralPath '英语一' -Recurse -File -Force
$cet6 = Get-ChildItem -LiteralPath '其他考试\大学英语六级' -Recurse -File -Force
"english=$($english.Count) cet6=$($cet6.Count) total=$($english.Count + $cet6.Count)"
(($english + $cet6) | Measure-Object Length -Sum).Sum
```

Expected before indexes: `english=21 cet6=67 total=88`；总字节数等于 Task 1 英一基线；所有目标 SHA-256 相同。

---

### Task 6: 迁移并安全化 OCR 工程

**Files:**
- Move: `batch_ocr.py` -> `408-考研/98-OCR工程/batch_ocr.py`
- Move: `ocr_output/**/*` -> `408-考研/98-OCR工程/output/**/*`
- Create: `408-考研/98-OCR工程/README.md`
- Modify: `408-考研/98-OCR工程/batch_ocr.py`
- Modify: `docs/workspace-reorganization/migration-map.md`

**Interfaces:**
- Consumes: Task 1 OCR 哈希基线。
- Produces: 无明文凭据的 OCR 工程和保持原内容的 1,444 个输出文件。

- [x] **Step 1: 移动脚本和 OCR 输出**

Run:

```powershell
$root = 'D:\study\'
function Move-VerifiedFile([string]$source, [string]$destination) {
  $src = (Resolve-Path -LiteralPath $source).Path
  $dst = [IO.Path]::GetFullPath($destination)
  if (-not $src.StartsWith($root) -or -not $dst.StartsWith($root)) { throw "Unsafe path: $src -> $dst" }
  if (Test-Path -LiteralPath $dst) {
    $srcHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
    $dstHash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
    if ($srcHash -eq $dstHash) { throw "Same-hash target already exists: $dst" }
    throw "Different-content target exists: $dst"
  }
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst)) | Out-Null
  $before = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
  Move-Item -LiteralPath $src -Destination $dst
  $after = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
  if ($before -ne $after) { throw "Post-move hash mismatch: $dst" }
}
$sourceRoot = (Resolve-Path -LiteralPath 'D:\study\ocr_output').Path
foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force) {
  $relative = $file.FullName.Substring($sourceRoot.Length + 1)
  Move-VerifiedFile $file.FullName (Join-Path 'D:\study\408-考研\98-OCR工程\output' $relative)
}
Move-VerifiedFile 'D:\study\batch_ocr.py' 'D:\study\408-考研\98-OCR工程\batch_ocr.py'
```

Expected: `408-考研/98-OCR工程/output` 含 1,444 个原输出文件，根目录 `batch_ocr.py` 不存在，源 `ocr_output` 仅剩空目录结构。

- [x] **Step 2: 使用 apply_patch 安全化脚本**

先用 apply_patch 删除现有以 `API_KEY =` 开头的整行，不复制或记录其右侧值。然后应用以下精确逻辑改动：

```diff
 API_BASE = "https://api.siliconflow.cn/v1"
 MODEL = "PaddlePaddle/PaddleOCR-VL-1.5"
 SCALE = 3

+def get_api_key():
+    """Read the SiliconFlow API key without storing it in source code."""
+    api_key = os.environ.get("SILICONFLOW_API_KEY")
+    if not api_key:
+        raise RuntimeError(
+            "Missing SILICONFLOW_API_KEY. Configure the environment variable before running OCR."
+        )
+    return api_key

 def ocr_page(image_path):
     """OCR a single page image, return clean text."""
     with open(image_path, 'rb') as f:
         b64 = base64.b64encode(f.read()).decode()

-    client = OpenAI(api_key=API_KEY, base_url=API_BASE)
+    client = OpenAI(api_key=get_api_key(), base_url=API_BASE)
```

Also change the main output path exactly:

```diff
-    output_dir = Path(pdf_file).parent / 'ocr_output'
+    output_dir = Path(__file__).resolve().parent / 'output'
```

Do not print the removed credential in commentary, reports or the README.

- [x] **Step 3: 创建 OCR README**

Create with this content:

```markdown
# 408 王道 PDF OCR 工程

本目录保存 OCR 脚本和已生成文本。`output` 包含四科分页文本与合并全文，是 408 笔记的本地底稿。

## 环境要求

- Python 3
- `openai`
- `pypdfium2`
- 环境变量 `SILICONFLOW_API_KEY`

## 使用

```powershell
if (-not $env:SILICONFLOW_API_KEY) { throw "请先在当前终端安全设置 SILICONFLOW_API_KEY" }
python batch_ocr.py "..\90-复习资料\01-核心教材\王道2026\OCR源PDF\2026数据结构.pdf"
python batch_ocr.py "..\90-复习资料\01-核心教材\王道2026\OCR源PDF\2026数据结构.pdf" 120
```

第二条命令从以 0 为起点的页索引 120 继续。脚本输出固定写入本目录的 `output`。

## 安全说明

凭据不得写入脚本、笔记或日志。旧凭据需要在服务控制台撤销并轮换。
```

- [x] **Step 4: 静态安全与完整性检查**

Run:

```powershell
rg -n 'sk-[A-Za-z0-9_-]{16,}' '408-考研\98-OCR工程'
rg -n 'SILICONFLOW_API_KEY|get_api_key|Path\(__file__\)' '408-考研\98-OCR工程\batch_ocr.py'
$ocr = Get-ChildItem -LiteralPath '408-考研\98-OCR工程\output' -Recurse -File -Force
"files=$($ocr.Count) bytes=$(($ocr | Measure-Object Length -Sum).Sum)"
```

Expected: 第一条无输出；第二条命中环境变量、读取函数和新输出路径；第三条为 `files=1444 bytes=8581920`。若实际基线已变化，以 Task 1 记录为准但必须解释差异。

---

### Task 7: 创建 Obsidian 资料索引并更新路径

**Files:**
- Create: `408-考研/90-复习资料/00-资料索引.md`
- Create: `数学一/00-资料索引.md`
- Create: `英语一/00-资料索引.md`
- Create: `其他考试/大学英语六级/00-资料索引.md`
- Modify: `408-考研/00-总览/408考研复习总览.md`
- Modify: `408-考研/00-总览/资料来源与版本说明.md`
- Modify: `408-考研/**/*.md` containing `ocr_output/`
- Modify: `docs/408-rewrite/source-register.md`
- Modify: `docs/408-rewrite/validation-report.md`
- Modify: `.obsidian/workspace.json`

**Interfaces:**
- Consumes: Tasks 3–6 的最终目标路径。
- Produces: 可导航资料入口和不含失效旧路径的 Obsidian Vault。

- [x] **Step 1: 创建四份索引**

每份索引必须有 YAML Frontmatter（`title`、`tags`、`status: active`、`updated: 2026-07-13`）、资料分类表、推荐使用顺序、版本说明和返回入口。

408 索引至少直接链接 8 份王道 2026 PDF、2009 与 2024 真题/答案、四科分章讲义和知识图谱入口。数学一索引至少链接 5 份基础讲义、2 份公式手册、1987 与 2023 真题/解析以及 2 份数学二拓展。英语一索引至少链接最早、2009 和最新年份真题，并链接六级索引。六级索引至少链接每个年份目录中的第一套真题 PDF。

所有内部文件使用 Vault 根相对 Wikilink，例如：

```markdown
[[408-考研/90-复习资料/01-核心教材/王道2026/带书签阅读版/2026数据结构_带书签.pdf|数据结构·带书签版]]
[[数学一/01-基础讲义/27张宇基础30讲（高数）.pdf|高等数学基础 30 讲]]
[[英语一/01-历年真题/2002.pdf|2002 英语一真题]]
[[其他考试/大学英语六级/00-资料索引|大学英语六级资料]]
```

- [x] **Step 2: 在 408 总览增加资料入口**

在不改变现有四科导航的前提下增加：

```markdown
## 复习资料入口

- [[408-考研/90-复习资料/00-资料索引|408 教材、真题、题库与知识图谱]]
- [[数学一/00-资料索引|数学一资料]]
- [[英语一/00-资料索引|英语一资料]]
```

- [x] **Step 3: 更新 OCR 文字路径**

将当前有效文档中的 `ocr_output/...` 路径统一改为 `408-考研/98-OCR工程/output/...`。历史设计中用于描述旧基线的路径保留，但需在验证报告中说明其为历史路径。

Run after edits:

```powershell
rg -n 'ocr_output/' '408-考研' 'docs\408-rewrite'
rg -n '408-考研/98-OCR工程/output/' '408-考研' 'docs\408-rewrite'
```

Expected: 第一条无有效旧路径命中；第二条命中资料来源说明、分科目录/章节来源和来源登记。

- [x] **Step 4: 更新 Obsidian workspace 最近文件**

将 `.obsidian/workspace.json` 中四个根目录 PDF 名称替换为：

```text
408-考研/90-复习资料/01-核心教材/王道2026/OCR源PDF/2026操作系统.pdf
408-考研/90-复习资料/01-核心教材/王道2026/OCR源PDF/2026数据结构.pdf
408-考研/90-复习资料/01-核心教材/王道2026/OCR源PDF/2026计算机组成原理.pdf
408-考研/90-复习资料/01-核心教材/王道2026/OCR源PDF/2026计算机网络.pdf
```

Validate:

```powershell
Get-Content -LiteralPath '.obsidian\workspace.json' -Raw -Encoding utf8 | ConvertFrom-Json | Out-Null
```

Expected: exit code 0。

- [x] **Step 5: 验证所有索引链接**

解析四份索引中的 Wikilink，去除别名和标题锚点，将 Vault 根相对目标与实际文件名索引比较。

Expected: 索引未解析链接为 0。

---

### Task 8: 删除前完整验收

**Files:**
- Modify: `docs/workspace-reorganization/validation-report.md`
- Modify: `docs/workspace-reorganization/deletion-manifest.md`
- Modify: `task_plan.md`
- Modify: `progress.md`

**Interfaces:**
- Consumes: Tasks 3–7 的已迁移目标和索引。
- Produces: 允许或阻止 Task 9 删除的明确门槛结果。

- [x] **Step 1: 验证 408 既有笔记结构**

严格 UTF-8 解码 `408-考研` 下 Markdown；对 26 个 `第N章-*.md` 检查 10 个 Frontmatter 字段、`核心知识框架`、`前后章节导航`、围栏和 `$$` 成对、无占位符。

Expected: 原 38 份 Markdown 全部通过；新增索引另行通过 UTF-8 和 Frontmatter 检查。

- [x] **Step 2: 验证全库 Wikilink**

排除模板中的示例变量，解析全部真实 Wikilink。

Expected: 原有 323 个链接继续可解析；新增索引链接也全部可解析；`unresolved=0`。

- [x] **Step 3: 重新对三个 ZIP 逐条目做 SHA-256 对比**

比较：

```text
cs-408-master.zip 的 61 项 -> 03/04/06/07/99 分类目标
CS-Xmind-Note-master.zip 的 91 项 -> 05-知识图谱与 99-来源说明
真题.zip 的 32 项 -> 02-历年真题
```

Expected: `61/61`、`91/91`、`32/32` 均匹配，`hash_mismatch=0`、`missing=0`。

- [x] **Step 4: 验证分科数量与总字节数**

Expected:

- 数学一迁移资料为 87 份 PDF，字节数等于基线；另有 1 份新索引 Markdown。
- 英语一为 21 份 PDF，六级为 67 份 PDF，合计字节数等于原英一基线；各有 1 份新索引。
- OCR 为 1,444 个原输出文件，字节数等于基线；另有脚本和 README。
- 两组王道 2026 PDF 共 8 份。

- [x] **Step 5: 更新删除门槛**

只有 Steps 1–4 全部通过，才将三个 ZIP 和缓存从 `blocked-until-verified` 改为 `approved-for-deletion`。若任一失败，Task 9 不得执行。

---

### Task 9: 删除已验证冗余与空目录

**Files:**
- Delete: `考研/408/cs-408-master.zip`
- Delete: `考研/408/CS-Xmind-Note-master.zip`
- Delete: `考研/408/真题.zip`
- Delete: `__pycache__/batch_ocr.cpython-313.pyc`
- Delete empty directories under: `考研`
- Modify: `docs/workspace-reorganization/deletion-manifest.md`

**Interfaces:**
- Consumes: Task 8 的 `approved-for-deletion` 状态。
- Produces: 无重复外层 ZIP、无 Python 缓存、无空旧目录的工作区。

- [x] **Step 1: 再次核对删除目标绝对路径**

Run:

```powershell
$expected = @(
  'D:\study\考研\408\cs-408-master.zip',
  'D:\study\考研\408\CS-Xmind-Note-master.zip',
  'D:\study\考研\408\真题.zip',
  'D:\study\__pycache__\batch_ocr.cpython-313.pyc'
)
foreach ($path in $expected) {
  $resolved = (Resolve-Path -LiteralPath $path).Path
  if ($resolved -ne $path) { throw "Unsafe deletion target: $resolved" }
}
```

Expected: exit code 0。

- [x] **Step 2: 删除四个已批准文件**

Run four independent commands，不使用通配符、不使用递归：

```powershell
Remove-Item -LiteralPath 'D:\study\考研\408\cs-408-master.zip'
Remove-Item -LiteralPath 'D:\study\考研\408\CS-Xmind-Note-master.zip'
Remove-Item -LiteralPath 'D:\study\考研\408\真题.zip'
Remove-Item -LiteralPath 'D:\study\__pycache__\batch_ocr.cpython-313.pyc'
```

Expected: 三个 ZIP 和一个 `.pyc` 不存在；按文件长度统计释放 `1,266,481,495` 字节（若 Task 1 实际值不同，使用基线实际和）。

- [x] **Step 3: 删除已验证为空的旧目录**

候选顺序从深到浅：`考研/408`、`考研/数一`、`考研/英一`、`考研`、`ocr_output`、`__pycache__`、旧 `408-考研/99-资料`。每个目录必须满足：存在、递归文件数为 0、解析路径与预期绝对路径相同；然后使用 `Remove-Item -LiteralPath -Recurse`。

若 `考研` 或任一候选仍含文件，保留该目录并在删除清单列出剩余项，不强制删除。

- [x] **Step 4: 更新删除清单**

记录每个目标的原始字节数、验证依据、删除时间、删除后存在状态和实际释放总字节数。

---

### Task 10: 删除后复验与交付归档

**Files:**
- Modify: `docs/workspace-reorganization/validation-report.md`
- Modify: `docs/workspace-reorganization/migration-map.md`
- Move at final step: `task_plan.md`, `findings.md`, `progress.md` -> `docs/workspace-reorganization/`

**Interfaces:**
- Consumes: Task 9 的最终文件系统状态。
- Produces: 可交付的重构目录和完整审计记录。

- [x] **Step 1: 重复 Task 8 的全部内容与链接验证**

Expected: Markdown/Frontmatter/围栏/LaTeX/链接问题均为 0；索引链接可解析；OCR 静态安全检查通过。

- [x] **Step 2: 验证最终根目录**

Run:

```powershell
Get-ChildItem -LiteralPath 'D:\study' -Force | Select-Object Name,PSIsContainer,Length
@(
  'D:\study\408-考研',
  'D:\study\数学一',
  'D:\study\英语一',
  'D:\study\其他考试\大学英语六级',
  'D:\study\docs',
  'D:\study\.obsidian',
  'D:\study\.git',
  'D:\study\.agents',
  'D:\study\skills-lock.json'
) | ForEach-Object { "$_=$(Test-Path -LiteralPath $_)" }
```

Expected: 所列路径全部为 `True`；根目录没有 `2026*.pdf`、`batch_ocr.py`、`ocr_output` 或 `__pycache__`。

- [x] **Step 3: 验证旧路径和删除目标不存在**

Run:

```powershell
@(
  'D:\study\考研\408',
  'D:\study\考研\数一',
  'D:\study\考研\英一',
  'D:\study\考研\408\cs-408-master.zip',
  'D:\study\考研\408\CS-Xmind-Note-master.zip',
  'D:\study\考研\408\真题.zip'
) | ForEach-Object { "$_=$(Test-Path -LiteralPath $_)" }
```

Expected: 全部为 `False`。若 `考研` 因剩余内容被保留，验证报告必须列出原因，但三个旧科目目录仍应不存在。

- [x] **Step 4: 将迁移表状态全部收束**

Expected: `migration-map.md` 中没有 `planned`、`moving` 或未解释的冲突；状态只能为 `moved-verified`、`recovered-verified`、`created`。`deletion-manifest.md` 没有 `approved-for-deletion` 残留，已删项为 `deleted-verified`。

- [x] **Step 5: 归档规划文件**

在所有验证与报告写入完成后，将根目录 `task_plan.md`、`findings.md`、`progress.md` 移入 `docs/workspace-reorganization/`。移动后确认三份文件均存在于归档目录，根目录不再出现这三份维护记录。

- [x] **Step 6: 最终只读验收**

重新输出：各顶层目录文件数/字节数、8 份王道 PDF、数学一 87 份 PDF、英语一 21 份 PDF、CET-6 67 份 PDF、OCR 1,444 份原输出、未解析 Wikilink 0、硬编码凭据命中 0、实际释放字节数。

Expected: 所有数字与最终验证报告一致，任务状态为 complete。
