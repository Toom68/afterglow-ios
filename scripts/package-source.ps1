# Creates dist\Afterglow-source-<version>-<date>.zip on Windows for transfer to a Mac.
# Entry names use forward slashes so macOS Archive Utility and `unzip` restore the folder tree,
# and text files are written with LF line endings so the shell scripts run on macOS.
# Usage (from anywhere):
#   powershell -ExecutionPolicy Bypass -File scripts/package-source.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root

$pbxproj = [System.IO.File]::ReadAllText((Join-Path $root 'ios/Afterglow.xcodeproj/project.pbxproj'))
$version = if ($pbxproj -match 'MARKETING_VERSION = ([^;]+);') { $Matches[1] } else { 'dev' }
$name = "Afterglow-source-$version-$((Get-Date).ToUniversalTime().ToString('yyyyMMdd'))"
New-Item -ItemType Directory -Force -Path (Join-Path $root 'dist') | Out-Null
$out = Join-Path $root "dist/$name.zip"
if (Test-Path $out) { Remove-Item $out }

$backslash = [char]92
$slash = [char]47
$include = @('ios', 'docs', 'scripts', '.github', 'README.md', 'LICENSE', '.gitignore', '.gitattributes')
$excludedNames = @('xcuserdata', 'DerivedData', 'build', 'dist', '.DS_Store')
$excludedPatterns = @('*.mobileprovision', '*.provisionprofile', '*.p12', '*.cer', '*.p8', '*.xcarchive', '*.ipa', '.env*', 'ExportOptions*.plist')
$lfExtensions = @('.sh', '.py', '.swift', '.yml', '.md', '.plist', '.pbxproj', '.xcscheme', '.xcprivacy', '.json', '.xcworkspacedata', '.ps1', '.gitattributes', '.gitignore')

function Test-Excluded([string]$relative) {
    foreach ($part in $relative.Split($slash)) {
        if ($excludedNames -contains $part) { return $true }
        foreach ($pattern in $excludedPatterns) { if ($part -like $pattern) { return $true } }
    }
    return $false
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$zip = [System.IO.Compression.ZipFile]::Open($out, [System.IO.Compression.ZipArchiveMode]::Create)
$count = 0
try {
    foreach ($item in $include) {
        $path = Join-Path $root $item
        if (-not (Test-Path $path)) { continue }
        $files = if ((Get-Item $path -Force).PSIsContainer) { Get-ChildItem $path -Recurse -File -Force } else { @(Get-Item $path -Force) }
        foreach ($file in $files) {
            $relative = $file.FullName.Substring($root.Length).TrimStart($backslash, $slash).Replace($backslash, $slash)
            if (Test-Excluded $relative) { continue }
            $entry = $zip.CreateEntry("$name/$relative", [System.IO.Compression.CompressionLevel]::Optimal)
            $extension = if ($file.Extension) { $file.Extension.ToLowerInvariant() } else { $file.Name.ToLowerInvariant() }
            $stream = $entry.Open()
            try {
                if ($lfExtensions -contains $extension -or $lfExtensions -contains $file.Name.ToLowerInvariant()) {
                    $text = [System.IO.File]::ReadAllText($file.FullName).Replace("`r`n", "`n")
                    $bytes = $utf8.GetBytes($text)
                    $stream.Write($bytes, 0, $bytes.Length)
                } else {
                    $source = [System.IO.File]::OpenRead($file.FullName)
                    try { $source.CopyTo($stream) } finally { $source.Dispose() }
                }
            } finally {
                $stream.Dispose()
            }
            $count++
        }
    }
} finally {
    $zip.Dispose()
}

$hash = (Get-FileHash $out -Algorithm SHA256).Hash.ToLower()
[System.IO.File]::WriteAllText("$out.sha256", "$hash  $name.zip`n", $utf8)
Write-Host "Wrote $out ($count files)"
Write-Host "SHA-256 $hash"
