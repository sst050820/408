[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PdfPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [int]$FirstPage = 1,
    [int]$LastPage = 0,
    [double]$Scale = 2.0
)

$ErrorActionPreference = 'Stop'

function Wait-WinRtResult {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Operation,

        [Parameter(Mandatory = $true)]
        [type]$ResultType
    )

    $asTaskMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.IsGenericMethodDefinition -and
            $_.GetParameters().Count -eq 1
        } |
        Select-Object -First 1

    $task = $asTaskMethod.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $task.GetAwaiter().GetResult()
}

function Wait-WinRtAction {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Operation
    )

    $asTaskMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            -not $_.IsGenericMethod -and
            $_.GetParameters().Count -eq 1
        } |
        Select-Object -First 1

    $task = $asTaskMethod.Invoke($null, @($Operation))
    $null = $task.GetAwaiter().GetResult()
}

if ($FirstPage -lt 1) {
    throw 'FirstPage must be at least 1.'
}
if ($LastPage -lt 0) {
    throw 'LastPage must be 0 or a positive page number.'
}
if ($LastPage -ne 0 -and $LastPage -lt $FirstPage) {
    throw 'LastPage must be greater than or equal to FirstPage.'
}
if ($Scale -le 0) {
    throw 'Scale must be greater than 0.'
}

Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Pdf.PdfPageRenderOptions, Windows.Data.Pdf, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime] | Out-Null

$absolutePdfPath = [System.IO.Path]::GetFullPath($PdfPath)
if (-not [System.IO.File]::Exists($absolutePdfPath)) {
    throw "PDF file not found: $absolutePdfPath"
}

$absoluteOutputDir = [System.IO.Path]::GetFullPath($OutputDir)
[System.IO.Directory]::CreateDirectory($absoluteOutputDir) | Out-Null

$storageFile = Wait-WinRtResult `
    -Operation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($absolutePdfPath)) `
    -ResultType ([Windows.Storage.StorageFile])
$pdfDocument = Wait-WinRtResult `
    -Operation ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($storageFile)) `
    -ResultType ([Windows.Data.Pdf.PdfDocument])

$pageCount = [int]$pdfDocument.PageCount
Write-Output "PAGE_COUNT=$pageCount"

if ($LastPage -eq 0) {
    $LastPage = $pageCount
}
if ($FirstPage -gt $pageCount) {
    throw "FirstPage must not exceed the PDF page count ($pageCount)."
}
if ($LastPage -lt $FirstPage -or $LastPage -gt $pageCount) {
    throw "LastPage must be between FirstPage and the PDF page count ($pageCount)."
}

for ($pageNumber = $FirstPage; $pageNumber -le $LastPage; $pageNumber++) {
    $fileName = 'page_{0:D4}.png' -f $pageNumber
    $outputPath = [System.IO.Path]::Combine($absoluteOutputDir, $fileName)

    if ([System.IO.File]::Exists($outputPath) -and (Get-Item -LiteralPath $outputPath).Length -gt 0) {
        Write-Output "SKIP $fileName"
        continue
    }

    $page = $null
    $memoryStream = $null
    $readStream = $null
    $fileStream = $null
    try {
        $page = $pdfDocument.GetPage([uint32]($pageNumber - 1))
        $renderOptions = New-Object Windows.Data.Pdf.PdfPageRenderOptions
        $renderOptions.DestinationWidth = [uint32][Math]::Max(1, [Math]::Round($page.Size.Width * $Scale))
        $renderOptions.DestinationHeight = [uint32][Math]::Max(1, [Math]::Round($page.Size.Height * $Scale))

        $memoryStream = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
        Wait-WinRtAction -Operation ($page.RenderToStreamAsync($memoryStream, $renderOptions))
        $memoryStream.Seek(0)

        $readStream = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($memoryStream)
        $fileStream = [System.IO.File]::Open(
            $outputPath,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $readStream.CopyTo($fileStream)
        Write-Output "RENDER $fileName"
    }
    finally {
        if ($null -ne $fileStream) { $fileStream.Dispose() }
        if ($null -ne $readStream) { $readStream.Dispose() }
        if ($null -ne $memoryStream) { $memoryStream.Dispose() }
        if ($null -ne $page) { $page.Dispose() }
    }
}
