[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ImageDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [int]$FirstPage = 1,
    [int]$LastPage = 0,
    [string]$Tesseract = 'C:\Program Files\Tesseract-OCR\tesseract.exe',
    [string]$TessdataDir = (Join-Path $PSScriptRoot 'tessdata')
)

$ErrorActionPreference = 'Stop'

if ($FirstPage -lt 1) { throw 'FirstPage must be at least 1.' }
if ($LastPage -lt 0) { throw 'LastPage must be 0 or a positive page number.' }
if ($LastPage -ne 0 -and $LastPage -lt $FirstPage) {
    throw 'LastPage must be greater than or equal to FirstPage.'
}

$absoluteImageDir = [System.IO.Path]::GetFullPath($ImageDir)
if (-not [System.IO.Directory]::Exists($absoluteImageDir)) {
    throw "Image directory not found: $absoluteImageDir"
}
if (-not [System.IO.File]::Exists($Tesseract)) {
    throw "Tesseract executable not found: $Tesseract"
}
$absoluteTessdataDir = [System.IO.Path]::GetFullPath($TessdataDir)
if (-not [System.IO.Directory]::Exists($absoluteTessdataDir)) {
    throw "Tessdata directory not found: $absoluteTessdataDir"
}

$images = @(Get-ChildItem -LiteralPath $absoluteImageDir -File |
    Where-Object { $_.Name -match '^page_[0-9]{4}\.png$' } |
    Sort-Object Name)
if ($images.Count -eq 0) { throw "No page_*.png images found: $absoluteImageDir" }

if ($LastPage -eq 0) { $LastPage = $images.Count }
if ($FirstPage -gt $images.Count -or $LastPage -gt $images.Count) {
    throw "Requested range $FirstPage-$LastPage exceeds image count ($($images.Count))."
}

$absoluteOutputDir = [System.IO.Path]::GetFullPath($OutputDir)
[System.IO.Directory]::CreateDirectory($absoluteOutputDir) | Out-Null

for ($pageNumber = $FirstPage; $pageNumber -le $LastPage; $pageNumber++) {
    $image = $images[$pageNumber - 1]
    $stem = 'page_{0:D4}' -f $pageNumber
    $textPath = Join-Path $absoluteOutputDir "$stem.txt"
    $tsvPath = Join-Path $absoluteOutputDir "$stem.tsv"

    if ((Test-Path -LiteralPath $textPath -PathType Leaf) -and
        (Test-Path -LiteralPath $tsvPath -PathType Leaf) -and
        (Get-Item -LiteralPath $textPath).Length -gt 0 -and
        (Get-Item -LiteralPath $tsvPath).Length -gt 0) {
        Write-Output "SKIP $stem"
        continue
    }

    $temporaryStem = ".ocr-$stem-$([Guid]::NewGuid().ToString('N'))"
    $temporaryBase = Join-Path $absoluteOutputDir $temporaryStem
    $temporaryText = "$temporaryBase.txt"
    $temporaryTsv = "$temporaryBase.tsv"
    try {
        & $Tesseract $image.FullName $temporaryBase `
            -l 'chi_sim+eng' `
            --psm 6 `
            --tessdata-dir $absoluteTessdataDir `
            -c 'preserve_interword_spaces=1' `
            txt tsv
        if ($LASTEXITCODE -ne 0) {
            throw "Tesseract failed for $($image.Name) with exit code $LASTEXITCODE."
        }
        if (-not [System.IO.File]::Exists($temporaryText) -or
            -not [System.IO.File]::Exists($temporaryTsv) -or
            (Get-Item -LiteralPath $temporaryTsv).Length -eq 0) {
            throw "Tesseract did not produce complete TXT and TSV output for $($image.Name)."
        }

        if ([System.IO.File]::Exists($textPath)) { [System.IO.File]::Delete($textPath) }
        if ([System.IO.File]::Exists($tsvPath)) { [System.IO.File]::Delete($tsvPath) }
        [System.IO.File]::Move($temporaryText, $textPath)
        [System.IO.File]::Move($temporaryTsv, $tsvPath)
        Write-Output "OCR $($image.Name)"
    }
    finally {
        if ([System.IO.File]::Exists($temporaryText)) { [System.IO.File]::Delete($temporaryText) }
        if ([System.IO.File]::Exists($temporaryTsv)) { [System.IO.File]::Delete($temporaryTsv) }
    }
}

$emptyPages = @(Get-ChildItem -LiteralPath $absoluteOutputDir -File |
    Where-Object { $_.Name -match '^page_[0-9]{4}\.txt$' } |
    Sort-Object Name |
    Where-Object { ([System.IO.File]::ReadAllText($_.FullName) -replace '\s', '').Length -eq 0 } |
    ForEach-Object { $_.BaseName })
$emptyListPath = Join-Path $absoluteOutputDir 'empty-pages.txt'
$emptyListTemporary = "$emptyListPath.partial"
try {
    [System.IO.File]::WriteAllLines($emptyListTemporary, [string[]]$emptyPages, (New-Object System.Text.UTF8Encoding($false)))
    if ([System.IO.File]::Exists($emptyListPath)) { [System.IO.File]::Delete($emptyListPath) }
    [System.IO.File]::Move($emptyListTemporary, $emptyListPath)
}
finally {
    if ([System.IO.File]::Exists($emptyListTemporary)) { [System.IO.File]::Delete($emptyListTemporary) }
}
