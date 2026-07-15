[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ImageDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

$absoluteImageDir = [System.IO.Path]::GetFullPath($ImageDir)
$absoluteOutputDir = [System.IO.Path]::GetFullPath($OutputDir)
if (-not [System.IO.Directory]::Exists($absoluteImageDir)) {
    throw "Image directory not found: $absoluteImageDir"
}
if (-not [System.IO.Directory]::Exists($absoluteOutputDir)) {
    throw "OCR output directory not found: $absoluteOutputDir"
}

$images = @(Get-ChildItem -LiteralPath $absoluteImageDir -File |
    Where-Object { $_.Name -match '^page_[0-9]{4}\.png$' } |
    Sort-Object Name)
if ($images.Count -eq 0) { throw "No page_*.png images found: $absoluteImageDir" }

$texts = @(Get-ChildItem -LiteralPath $absoluteOutputDir -File |
    Where-Object { $_.Name -match '^page_[0-9]{4}\.txt$' } |
    Sort-Object Name)

for ($index = 0; $index -lt $images.Count; $index++) {
    $expected = 'page_{0:D4}.png' -f ($index + 1)
    if ($images[$index].Name -ne $expected) {
        throw "Image sequence error: expected $expected but found $($images[$index].Name)."
    }
}
if ($images.Count -ne $texts.Count) {
    throw "Count mismatch: images=$($images.Count), text=$($texts.Count)."
}
for ($index = 0; $index -lt $texts.Count; $index++) {
    $expected = 'page_{0:D4}.txt' -f ($index + 1)
    if ($texts[$index].Name -ne $expected) {
        throw "Text sequence error: expected $expected but found $($texts[$index].Name)."
    }
}

$rows = @()
$suspectCount = 0
for ($index = 0; $index -lt $images.Count; $index++) {
    $content = [System.IO.File]::ReadAllText($texts[$index].FullName)
    $nonWhitespace = [regex]::Replace($content, '\s', '')
    $textChars = $nonWhitespace.Length
    $hanChars = ([regex]::Matches($content, '[\u3400-\u4DBF\u4E00-\u9FFF]')).Count
    $reasons = New-Object System.Collections.Generic.List[string]
    if ($textChars -lt 20) { $reasons.Add('low_text') }
    if ($textChars -gt 50 -and ($hanChars / [double]$textChars) -lt 0.05) {
        $reasons.Add('low_han_ratio')
    }
    if ($content -match '[\uFFFD\u25A1\u25A0\u25AF\?]{12,}') {
        $reasons.Add('garbled_run')
    }
    $reason = $reasons -join ';'
    if ($reason.Length -gt 0) { $suspectCount++ }

    $rows += [pscustomobject][ordered]@{
        page = $index + 1
        image_bytes = $images[$index].Length
        text_chars = $textChars
        han_chars = $hanChars
        suspect_reason = $reason
    }
}

$reportPath = Join-Path $absoluteOutputDir 'quality-report.csv'
$rows | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
Write-Output "PAGES=$($images.Count) SUSPECTS=$suspectCount REPORT=$reportPath"
