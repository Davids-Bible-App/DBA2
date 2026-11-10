# Run from the project root:  powershell -ExecutionPolicy Bypass -File tools\fetch_llama_android.ps1
# Downloads the official llama.cpp Android arm64 build and puts it in jniLibs.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster
$jni  = Join-Path $PSScriptRoot '..\android\app\src\main\jniLibs\arm64-v8a'
$work = Join-Path $env:TEMP 'llama_android'
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $work, $jni | Out-Null

$releases = Invoke-RestMethod 'https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=15' -Headers @{ 'User-Agent' = 'bible-ai' }
$asset = $releases | Where-Object { -not $_.draft } | ForEach-Object { $_.assets } |
    Where-Object { $_.name -like '*bin-android-arm64.tar.gz' } | Select-Object -First 1
if (-not $asset) { throw 'No android-arm64 asset in the latest release. See https://github.com/ggml-org/llama.cpp/releases' }
Write-Host "Downloading $($asset.name) ..."
$tar = Join-Path $work $asset.name
Invoke-WebRequest $asset.browser_download_url -OutFile $tar
tar -xzf $tar -C $work

Write-Host "`nArchive contents (executables and libraries):"
Get-ChildItem $work -Recurse -File | Where-Object { $_.Name -like 'llama-server*' -or $_.Name -like '*.so*' } |
    ForEach-Object { Write-Host "  $($_.FullName.Substring($work.Length))" }

$server = Get-ChildItem $work -Recurse -File -Filter 'llama-server' | Select-Object -First 1
if (-not $server) { throw 'llama-server not found in the archive.' }
Copy-Item $server.FullName (Join-Path $jni 'libllama_server.so') -Force
Get-ChildItem $work -Recurse -File -Filter '*.so' | ForEach-Object { Copy-Item $_.FullName (Join-Path $jni $_.Name) -Force }

if (Get-ChildItem $work -Recurse -File -Filter '*.so.*') {
    Write-Warning 'Versioned libraries (*.so.N) were found and NOT copied. Tell me the file names; they need renaming.'
}
Write-Host "`nInstalled into $jni :"
Get-ChildItem $jni | Select-Object Name, Length
