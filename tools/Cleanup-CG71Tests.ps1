[CmdletBinding(SupportsShouldProcess = $true)]
param()
$ErrorActionPreference = 'Stop'
$cg71Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cg71RecordPath = Join-Path $cg71Root 'docs\cg71_pet_30000.json'
$cg71Record = Get-Content -LiteralPath $cg71RecordPath -Raw -Encoding UTF8 | ConvertFrom-Json
$cg71TestDir = [IO.Path]::GetFullPath((Join-Path $cg71Root 'gmsv\lua\tests\cg71_pet_poc'))
if (-not $cg71TestDir.StartsWith($cg71Root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected test directory.' }
$cg71Files = @()
foreach ($cg71File in $cg71Record.test_cleanup_files) {
    $cg71Path = [IO.Path]::GetFullPath((Join-Path $cg71Root $cg71File.relative_path))
    if ([IO.Path]::GetDirectoryName($cg71Path) -ne $cg71TestDir) { throw 'Unexpected cleanup file path.' }
    if ((Test-Path -LiteralPath $cg71Path) -and (Get-FileHash -LiteralPath $cg71Path -Algorithm SHA256).Hash -ne $cg71File.sha256) { throw 'Test file changed; inspect it before cleanup.' }
    $cg71Files += $cg71Path
}
foreach ($cg71Path in $cg71Files) {
    if ((Test-Path -LiteralPath $cg71Path) -and $PSCmdlet.ShouldProcess($cg71Path, 'Remove test file')) { Remove-Item -LiteralPath $cg71Path }
}
if ((Test-Path -LiteralPath $cg71TestDir) -and @(Get-ChildItem -LiteralPath $cg71TestDir -Force).Count -eq 0) {
    if ($PSCmdlet.ShouldProcess($cg71TestDir, 'Remove empty test directory')) { Remove-Item -LiteralPath $cg71TestDir }
}
Write-Output 'Test cleanup complete or previewed. Pet DATA, database, backups and documentation are retained.'
