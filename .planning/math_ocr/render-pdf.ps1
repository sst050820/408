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
            $parameterType = $_.GetParameters()[0].ParameterType
            $_.Name -eq 'AsTask' -and
            $_.IsGenericMethodDefinition -and
            $_.GetGenericArguments().Count -eq 1 -and
            $_.GetParameters().Count -eq 1 -and
            $parameterType.IsGenericType -and
            $parameterType.GetGenericTypeDefinition().FullName -eq 'Windows.Foundation.IAsyncOperation`1'
        } |
        Select-Object -First 1

    if ($null -eq $asTaskMethod) {
        throw 'Cannot find the WinRT IAsyncOperation<T> AsTask overload.'
    }

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

function Test-CompletePngFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not [System.IO.File]::Exists($Path)) {
        return $false
    }

    $pngSignature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
    $iendTrailer = [byte[]](0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130)
    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        if ($stream.Length -lt ($pngSignature.Length + $iendTrailer.Length)) {
            return $false
        }

        $header = New-Object byte[] $pngSignature.Length
        if ($stream.Read($header, 0, $header.Length) -ne $header.Length) {
            return $false
        }
        for ($index = 0; $index -lt $pngSignature.Length; $index++) {
            if ($header[$index] -ne $pngSignature[$index]) {
                return $false
            }
        }

        $stream.Seek(-$iendTrailer.Length, [System.IO.SeekOrigin]::End) | Out-Null
        $trailer = New-Object byte[] $iendTrailer.Length
        if ($stream.Read($trailer, 0, $trailer.Length) -ne $trailer.Length) {
            return $false
        }
        for ($index = 0; $index -lt $iendTrailer.Length; $index++) {
            if ($trailer[$index] -ne $iendTrailer[$index]) {
                return $false
            }
        }

        return $true
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
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
if ([double]::IsNaN($Scale) -or [double]::IsInfinity($Scale)) {
    throw 'Scale must be finite.'
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
    $temporaryPath = "$outputPath.partial"
    $backupPath = "$outputPath.backup"

    if (Test-CompletePngFile -Path $outputPath) {
        Write-Output "SKIP $fileName"
        continue
    }

    if ([System.IO.File]::Exists($temporaryPath)) {
        [System.IO.File]::Delete($temporaryPath)
    }
    if ([System.IO.File]::Exists($backupPath)) {
        [System.IO.File]::Delete($backupPath)
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
            $temporaryPath,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $readStream.CopyTo($fileStream)
        $fileStream.Flush($true)
        $fileStream.Dispose()
        $fileStream = $null

        if (-not (Test-CompletePngFile -Path $temporaryPath)) {
            throw "Rendered page is not a complete PNG: $fileName"
        }

        if (Test-CompletePngFile -Path $outputPath) {
            [System.IO.File]::Delete($temporaryPath)
            Write-Output "SKIP $fileName"
            continue
        }

        if ([System.IO.File]::Exists($outputPath)) {
            [System.IO.File]::Replace($temporaryPath, $outputPath, $backupPath, $true)
            [System.IO.File]::Delete($backupPath)
        }
        else {
            [System.IO.File]::Move($temporaryPath, $outputPath)
        }
        Write-Output "RENDER $fileName"
    }
    finally {
        if ($null -ne $fileStream) { $fileStream.Dispose() }
        if ($null -ne $readStream) { $readStream.Dispose() }
        if ($null -ne $memoryStream) { $memoryStream.Dispose() }
        if ($null -ne $page) { $page.Dispose() }
        if ([System.IO.File]::Exists($temporaryPath)) {
            [System.IO.File]::Delete($temporaryPath)
        }
        if ([System.IO.File]::Exists($backupPath)) {
            [System.IO.File]::Delete($backupPath)
        }
    }
}
