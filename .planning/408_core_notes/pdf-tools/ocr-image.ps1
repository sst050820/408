param(
    [Parameter(Mandatory = $true)]
    [string[]]$ImagePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$LanguageTag = 'zh-Hans-CN'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Foundation.AsyncStatus, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Storage.FileAccessMode, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]

$script:AsTaskGenericMethod = (
    [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.IsGenericMethodDefinition -and
            $_.GetParameters().Count -eq 1
        } |
        Select-Object -First 1
)

function Wait-WinRtOperation {
    param(
        [Parameter(Mandatory = $true)]
        $Operation,

        [Parameter(Mandatory = $true)]
        [type]$ResultType
    )

    $asTask = $script:AsTaskGenericMethod.
        MakeGenericMethod($ResultType).
        Invoke($null, @($Operation))
    return $asTask.GetAwaiter().GetResult()
}

$language = [Windows.Globalization.Language]::new($LanguageTag)
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
if ($null -eq $engine) {
    throw "OCR language is not installed: $LanguageTag"
}

$resolvedImages = [System.Collections.Generic.List[string]]::new()
foreach ($pattern in $ImagePath) {
    $matches = @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue)
    if ($matches.Count -eq 0 -and (Test-Path -LiteralPath $pattern -PathType Leaf)) {
        $matches = @(Get-Item -LiteralPath $pattern)
    }
    foreach ($match in $matches) {
        $resolvedImages.Add($match.FullName)
    }
}
if ($resolvedImages.Count -eq 0) {
    throw 'No input images were found.'
}

$results = [System.Collections.Generic.List[object]]::new()
$started = Get-Date

foreach ($image in $resolvedImages) {
    $imageStarted = Get-Date
    $storageFile = Wait-WinRtOperation -Operation (
        [Windows.Storage.StorageFile]::GetFileFromPathAsync($image)
    ) -ResultType ([Windows.Storage.StorageFile])
    $stream = Wait-WinRtOperation -Operation (
        $storageFile.OpenAsync([Windows.Storage.FileAccessMode]::Read)
    ) -ResultType ([Windows.Storage.Streams.IRandomAccessStream])
    try {
        $decoder = Wait-WinRtOperation -Operation (
            [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)
        ) -ResultType ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Wait-WinRtOperation -Operation (
            $decoder.GetSoftwareBitmapAsync()
        ) -ResultType ([Windows.Graphics.Imaging.SoftwareBitmap])
        try {
            if (
                $bitmap.PixelWidth -gt [Windows.Media.Ocr.OcrEngine]::MaxImageDimension -or
                $bitmap.PixelHeight -gt [Windows.Media.Ocr.OcrEngine]::MaxImageDimension
            ) {
                throw (
                    'Image exceeds OCR maximum dimension: {0}x{1}' -f
                    $bitmap.PixelWidth,
                    $bitmap.PixelHeight
                )
            }

            $ocrResult = Wait-WinRtOperation -Operation (
                $engine.RecognizeAsync($bitmap)
            ) -ResultType ([Windows.Media.Ocr.OcrResult])
            $lines = [System.Collections.Generic.List[object]]::new()
            foreach ($line in $ocrResult.Lines) {
                $words = [System.Collections.Generic.List[object]]::new()
                foreach ($word in $line.Words) {
                    $rect = $word.BoundingRect
                    $words.Add([pscustomobject]@{
                        text = $word.Text
                        x = [math]::Round($rect.X, 2)
                        y = [math]::Round($rect.Y, 2)
                        width = [math]::Round($rect.Width, 2)
                        height = [math]::Round($rect.Height, 2)
                    })
                }
                $lines.Add([pscustomobject]@{
                    text = $line.Text
                    words = $words
                })
            }

            $results.Add([pscustomobject]@{
                image = $image
                width = $bitmap.PixelWidth
                height = $bitmap.PixelHeight
                language = $LanguageTag
                text = $ocrResult.Text
                line_count = $lines.Count
                lines = $lines
                elapsed_ms = [math]::Round(
                    ((Get-Date) - $imageStarted).TotalMilliseconds
                )
            })
            [Console]::Error.WriteLine((
                'ocr {0}: {1} lines, {2} characters' -f
                [System.IO.Path]::GetFileName($image),
                $lines.Count,
                $ocrResult.Text.Length
            ))
        }
        finally {
            if ($null -ne $bitmap) {
                $bitmap.Dispose()
            }
        }
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

$report = [pscustomobject]@{
    engine = 'Windows.Media.Ocr'
    language = $LanguageTag
    image_count = $results.Count
    elapsed_ms = [math]::Round(((Get-Date) - $started).TotalMilliseconds)
    results = $results
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    ($report | ConvertTo-Json -Depth 8),
    [System.Text.UTF8Encoding]::new($false)
)

$report |
    Select-Object engine, language, image_count, elapsed_ms |
    ConvertTo-Json -Compress
