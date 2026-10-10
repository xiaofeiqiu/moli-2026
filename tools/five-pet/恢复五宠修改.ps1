$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$backupRoot = Join-Path $taskRoot 'backups\five_pet_feature_20261004\original\gmsv'
$configPath = Join-Path $taskRoot 'gmsv\lua\ModuleConfig.lua'
$setupPath = Join-Path $taskRoot 'gmsv\setup.cf'
$encoding = [Text.Encoding]::GetEncoding(936)
$configText = [IO.File]::ReadAllText($configPath, $encoding)
$configText = [regex]::Replace($configText, '(?m)^\s*loadModule\([''"]fivePet[''"]\)\s*\r?\n?', '')
[IO.File]::WriteAllText($configPath, $configText, $encoding)
$backupText = [IO.File]::ReadAllText((Join-Path $backupRoot 'setup.cf'), $encoding)
$oldCapacity = [regex]::Match($backupText, '(?m)^dummynum=\d+').Value
if (-not $oldCapacity) { throw 'Cannot read original dummy capacity.' }
$setupText = [IO.File]::ReadAllText($setupPath, $encoding)
$setupText = [regex]::Replace($setupText, '(?m)^dummynum=\d+', $oldCapacity)
[IO.File]::WriteAllText($setupPath, $setupText, $encoding)
Write-Output 'Five-pet module disabled. Restart the launcher to apply. AI preferences remain saved.'
