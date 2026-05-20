#Requires -Version 5.1
<#
.SYNOPSIS
  Сканує обрані зовнішні диски та публікує data/drives.json у GitHub.

.PARAMETER All
  Сканувати всі підключені томи без інтерактивного запиту.
#>
[CmdletBinding()]
param(
  [Alias('a')]
  [switch]$All
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

$ApiUrl = 'https://api.github.com/repos/ViTwix/twix.production.drives/contents/data/drives.json'
$PagesUrl = 'https://twix-production-drives.pages.dev'

function Write-LogInfo {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  $ts = (Get-Date).ToString('HH:mm:ss')
  Write-Host "[$ts] $Message"
}

function Get-ErrorResponseBody {
  param(
    [Parameter(Mandatory = $true)]
    [System.Net.WebResponse]$Response
  )

  $reader = New-Object System.IO.StreamReader($Response.GetResponseStream())
  return $reader.ReadToEnd()
}

function Invoke-GitHubRequest {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('GET', 'PUT')]
    [string]$Method,
    [string]$Body = ''
  )

  $headers = @{
    Accept                 = 'application/vnd.github+json'
    Authorization          = "Bearer $($env:GITHUB_TOKEN)"
    'X-GitHub-Api-Version' = '2026-03-10'
    'User-Agent'           = 'twix-drives-scanner'
  }

  try {
    if ($Method -eq 'GET') {
      $response = Invoke-WebRequest -Method Get -Uri $ApiUrl -Headers $headers
    } else {
      $response = Invoke-WebRequest -Method Put -Uri $ApiUrl -Headers $headers -Body $Body -ContentType 'application/json'
    }

    return @{
      StatusCode = [int]$response.StatusCode
      Body       = $response.Content
    }
  } catch {
    if ($_.Exception.Response) {
      $statusCode = [int]$_.Exception.Response.StatusCode
      $responseBody = Get-ErrorResponseBody -Response $_.Exception.Response
      return @{
        StatusCode = $statusCode
        Body       = $responseBody
      }
    }

    throw
  }
}

function Get-RemoteState {
  $response = Invoke-GitHubRequest -Method GET

  switch ($response.StatusCode) {
    200 {
      $parsed = $response.Body | ConvertFrom-Json
      $sha = [string]$parsed.sha
      $contentRaw = [string]$parsed.content
      $contentBase64 = $contentRaw -replace '\s', ''

      if (-not $contentBase64) {
        throw "GitHub повернув порожній content для data/drives.json.`n$($response.Body)"
      }

      $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($contentBase64))
      return @{
        Sha  = $sha
        Json = $decoded
      }
    }
    404 {
      return @{
        Sha  = ''
        Json = '{"updatedAt": null, "drives": []}'
      }
    }
    default {
      throw "Помилка GET GitHub API (HTTP $($response.StatusCode)).`n$($response.Body)"
    }
  }
}

function Format-BytesShort {
  param(
    [Parameter(Mandatory = $true)]
    [int64]$Bytes
  )

  if ($Bytes -ge 1TB) {
    return '{0:N1} ТБ' -f ($Bytes / 1TB)
  }
  if ($Bytes -ge 1GB) {
    return '{0:N1} ГБ' -f ($Bytes / 1GB)
  }
  if ($Bytes -ge 1MB) {
    return '{0:N0} МБ' -f ($Bytes / 1MB)
  }

  return '{0:N0} КБ' -f ($Bytes / 1KB)
}

function Get-ExternalVolumes {
  return @(Get-Volume |
    Where-Object {
      $_.DriveLetter -and
      ($_.DriveType -eq 'Fixed' -or $_.DriveType -eq 'Removable') -and
      ("$($_.DriveLetter):" -ne $env:SystemDrive)
    })
}

function Show-VolumeMenu {
  param(
    [Parameter(Mandatory = $true)]
    [array]$Volumes
  )

  Write-Host ''
  Write-Host 'Підключені томи:'
  for ($i = 0; $i -lt $Volumes.Count; $i += 1) {
    $vol = $Volumes[$i]
    $name = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "$($vol.DriveLetter):" }
    $fs = if ([string]::IsNullOrWhiteSpace([string]$vol.FileSystemType)) { 'Unknown' } else { [string]$vol.FileSystemType }
    $total = [int64]$vol.Size
    $free = [int64]$vol.SizeRemaining
    $used = $total - $free
    Write-Host ('  [{0}] {1} — {2}, {3} / {4}' -f ($i + 1), $name, $fs, (Format-BytesShort $used), (Format-BytesShort $total))
  }

  Write-Host ''
  Write-Host 'Оберіть томи для сканування:'
  Write-Host '  • номери через кому: 1,3'
  Write-Host '  • діапазон: 1-3'
  Write-Host '  • Enter — усі томи'
  Write-Host '  • q — скасувати'
  Write-Host ''
}

function Parse-VolumeSelection {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InputText,
    [Parameter(Mandatory = $true)]
    [array]$Volumes
  )

  $normalized = ($InputText.Trim().ToLowerInvariant() -replace '\s', '')

  if (-not $normalized) {
    return ,$Volumes
  }

  $indices = New-Object 'System.Collections.Generic.List[int]'
  $parts = $normalized -split ','

  foreach ($part in $parts) {
    if (-not $part) { continue }

    if ($part -match '^(\d+)-(\d+)$') {
      $start = [int]$Matches[1]
      $end = [int]$Matches[2]
      if ($start -gt $end) {
        throw "Невірний діапазон: $part"
      }
      for ($n = $start; $n -le $end; $n += 1) {
        if (-not $indices.Contains($n)) { [void]$indices.Add($n) }
      }
      continue
    }

    if ($part -match '^\d+$') {
      $n = [int]$part
      if (-not $indices.Contains($n)) { [void]$indices.Add($n) }
      continue
    }

    throw "Невірний формат вибору: $part"
  }

  if ($indices.Count -eq 0) {
    throw 'Не вказано жодного тому.'
  }

  $selected = @()
  foreach ($idx in ($indices | Sort-Object)) {
    if ($idx -lt 1 -or $idx -gt $Volumes.Count) {
      throw "Номер поза діапазоном: $idx (доступно 1–$($Volumes.Count))"
    }
    $selected += $Volumes[$idx - 1]
  }

  return ,$selected
}

function Select-VolumesInteractive {
  param(
    [Parameter(Mandatory = $true)]
    [array]$Volumes
  )

  Show-VolumeMenu -Volumes $Volumes
  $choice = Read-Host 'Ваш вибір'

  if ($choice.Trim().ToLowerInvariant() -eq 'q') {
    Write-Host 'Скасовано.'
    exit 0
  }

  try {
    return @(Parse-VolumeSelection -InputText $choice -Volumes $Volumes)
  } catch {
    Write-Error $_.Exception.Message
    exit 1
  }
}

function Test-IsSkippedItem {
  param(
    [Parameter(Mandatory = $true)]
    [System.IO.FileSystemInfo]$Item
  )

  $skipNames = @(
    'System Volume Information',
    '$RECYCLE.BIN',
    '$Recycle.Bin',
    'RECYCLER'
  )

  if ($skipNames -contains $Item.Name) {
    return $true
  }

  if ($Item.Attributes -band [IO.FileAttributes]::Hidden) {
    return $true
  }

  if ($Item.Attributes -band [IO.FileAttributes]::System) {
    return $true
  }

  return $false
}

function Import-GitHubTokenFromEnvFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$EnvFilePath
  )

  if (-not (Test-Path -LiteralPath $EnvFilePath)) {
    return $false
  }

  foreach ($line in Get-Content -LiteralPath $EnvFilePath -Encoding UTF8) {
    if ($line -match '^\s*#') { continue }
    if ($line -match '^\s*GITHUB_TOKEN\s*=\s*(.+?)\s*$') {
      $value = $Matches[1].Trim().Trim('"').Trim("'")
      if ($value) {
        $env:GITHUB_TOKEN = $value
        return $true
      }
    }
  }

  return $false
}

if (-not $env:GITHUB_TOKEN) {
  $repoRoot = Split-Path $PSScriptRoot -Parent
  $envFile = Join-Path $repoRoot '.env'
  if (-not (Import-GitHubTokenFromEnvFile -EnvFilePath $envFile)) {
    Write-Error @"
Не задано GITHUB_TOKEN.
Створіть $envFile з рядком: GITHUB_TOKEN=github_pat_…
Або задайте змінну середовища (див. scripts/README.md)
"@
    exit 1
  }
}

$allVolumes = @(Get-ExternalVolumes)

if ($allVolumes.Count -eq 0) {
  Write-Error 'Не знайдено зовнішніх томів для сканування.'
  exit 1
}

if ($All) {
  $selectedVolumes = $allVolumes
} elseif ([Console]::IsInputRedirected) {
  Write-Error 'Неінтерактивний режим: додайте -All для сканування всіх томів.'
  exit 1
} else {
  $selectedVolumes = @(Select-VolumesInteractive -Volumes $allVolumes)
}

$selectedNames = @(
  foreach ($vol in $selectedVolumes) {
    if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "$($vol.DriveLetter):" }
  }
)

Write-Host ''
if ($selectedVolumes.Count -eq $allVolumes.Count) {
  Write-LogInfo ("Сканую всі {0} том(ів)..." -f $selectedVolumes.Count)
} else {
  Write-LogInfo ("Сканую {0} з {1} том(ів): {2}" -f $selectedVolumes.Count, $allVolumes.Count, ($selectedNames -join ', '))
}

$nowIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$driveRecords = @()

for ($v = 0; $v -lt $selectedVolumes.Count; $v += 1) {
  $selectedVolume = $selectedVolumes[$v]
  $rootPath = '{0}:\' -f $selectedVolume.DriveLetter
  $driveName = if ($selectedVolume.FileSystemLabel) { $selectedVolume.FileSystemLabel } else { "$($selectedVolume.DriveLetter):" }

  Write-Host ''
  Write-LogInfo ("=== [{0}/{1}] Сканую том: {2} ===" -f ($v + 1), $selectedVolumes.Count, $driveName)

  $entries = @()
  $rootItems = Get-ChildItem -LiteralPath $rootPath -Force -ErrorAction SilentlyContinue |
    Where-Object { -not (Test-IsSkippedItem -Item $_) }

  $totalBytes = [int64]$selectedVolume.Size
  $freeBytes = [int64]$selectedVolume.SizeRemaining
  $usedBytes = $totalBytes - $freeBytes
  $filesystem = if ([string]::IsNullOrWhiteSpace([string]$selectedVolume.FileSystemType)) { 'Unknown' } else { [string]$selectedVolume.FileSystemType }
  Write-LogInfo ("Том '{0}': FS={1}, used={2}, free={3}" -f $driveName, $filesystem, $usedBytes, $freeBytes)

  if (($null -eq $rootItems -or $rootItems.Count -eq 0) -and $usedBytes -gt 10485760) {
    Write-Warning "Том '$driveName' має зайнятий обсяг, але корінь повернув 0 елементів. Пропускаю, щоб не записати порожні дані."
    continue
  }

  Write-LogInfo ("Том '{0}': знайдено {1} елемент(ів) у корені" -f $driveName, $rootItems.Count)
  $foldersProcessed = 0
  $filesProcessed = 0
  $skippedItems = 0
  $totalItems = $rootItems.Count
  for ($i = 0; $i -lt $totalItems; $i += 1) {
    $item = $rootItems[$i]
    Write-Host ("  [{0}/{1}] {2}..." -f ($i + 1), $totalItems, $item.Name)

    if ($item.PSIsContainer) {
      try {
        $folderSize = (Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if ($null -eq $folderSize) {
          $folderSize = 0
        }

        $entries += [ordered]@{
          type      = 'folder'
          name      = $item.Name
          sizeBytes = [int64]$folderSize
        }
        $foldersProcessed += 1
      } catch {
        Write-Warning "Пропускаю папку без доступу: $($item.Name)"
        $skippedItems += 1
      }

      continue
    }

    try {
      $fileSize = (Get-Item -LiteralPath $item.FullName -ErrorAction Stop).Length
      $ext = $item.Extension.TrimStart('.').ToLowerInvariant()

      if ($ext) {
        $entries += [ordered]@{
          type      = 'file'
          name      = $item.Name
          ext       = $ext
          sizeBytes = [int64]$fileSize
        }
      } else {
        $entries += [ordered]@{
          type      = 'file'
          name      = $item.Name
          sizeBytes = [int64]$fileSize
        }
      }
      $filesProcessed += 1
    } catch {
      Write-Warning "Пропускаю файл без доступу: $($item.Name)"
      $skippedItems += 1
    }
  }

  $entriesSorted = @(
    $entries | Sort-Object `
      @{ Expression = { if ($_.type -eq 'folder') { 0 } else { 1 } } }, `
      @{ Expression = { $_.name.ToLowerInvariant() } }
  )

  $driveRecords += [ordered]@{
    name        = $driveName
    scannedAt   = $nowIso
    filesystem  = $filesystem
    totalBytes  = $totalBytes
    freeBytes   = $freeBytes
    usedBytes   = $usedBytes
    entries     = $entriesSorted
  }

  Write-LogInfo ("Підсумок '{0}': папок={1}, файлів={2}, пропущено={3}, entries={4}" -f $driveName, $foldersProcessed, $filesProcessed, $skippedItems, $entriesSorted.Count)
}

if (-not $driveRecords -or $driveRecords.Count -eq 0) {
  Write-Error 'Не вдалося зібрати дані з жодного тому. Перевірте попередження вище.'
  exit 1
}

function Build-NextJson {
  param(
    [Parameter(Mandatory = $true)]
    [string]$CurrentJson,
    [Parameter(Mandatory = $true)]
    [array]$DriveRecords,
    [Parameter(Mandatory = $true)]
    [string]$NowIso
  )

  $currentObj = $CurrentJson | ConvertFrom-Json
  $merged = @($currentObj.drives)

  foreach ($driveRecord in $DriveRecords) {
    $filtered = @($merged | Where-Object { $_.name -ne $driveRecord.name })
    $merged = @($filtered + ([pscustomobject]$driveRecord))
  }

  $merged = @($merged | Sort-Object -Property name)

  $nextObj = [ordered]@{
    updatedAt = $NowIso
    drives    = $merged
  }

  return ($nextObj | ConvertTo-Json -Depth 10)
}

function Build-PutPayload {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message,
    [Parameter(Mandatory = $true)]
    [string]$ContentBase64,
    [string]$Sha = ''
  )

  $payload = [ordered]@{
    message = $Message
    content = $ContentBase64
    branch  = 'main'
  }

  if ($Sha) {
    $payload.sha = $Sha
  }

  return ($payload | ConvertTo-Json -Depth 5 -Compress)
}

if ($driveRecords.Count -eq $allVolumes.Count) {
  $commitMessage = "scan: full sweep at $nowIso ($($driveRecords.Count) drives)"
} else {
  $commitMessage = "scan: $($selectedNames -join ', ') at $nowIso"
}
$remoteState = Get-RemoteState
$nextJson = Build-NextJson -CurrentJson $remoteState.Json -DriveRecords $driveRecords -NowIso $nowIso
$nextBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($nextJson))
$payload = Build-PutPayload -Message $commitMessage -ContentBase64 $nextBase64 -Sha $remoteState.Sha
Write-LogInfo ("Підготовлено {0} запис(ів) дисків. Записую в GitHub..." -f $driveRecords.Count)
$putResult = Invoke-GitHubRequest -Method PUT -Body $payload

if ($putResult.StatusCode -eq 409) {
  Write-Warning 'Отримано 409 Conflict. Повторюю один раз...'
  $remoteState = Get-RemoteState
  $nextJson = Build-NextJson -CurrentJson $remoteState.Json -DriveRecords $driveRecords -NowIso $nowIso
  $nextBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($nextJson))
  $payload = Build-PutPayload -Message $commitMessage -ContentBase64 $nextBase64 -Sha $remoteState.Sha
  $putResult = Invoke-GitHubRequest -Method PUT -Body $payload
}

if ($putResult.StatusCode -eq 200 -or $putResult.StatusCode -eq 201) {
  Write-LogInfo "Готово. Дані оновлено успішно (HTTP $($putResult.StatusCode))."
  Write-LogInfo "Веб: $PagesUrl"
  exit 0
}

Write-Error "Помилка PUT GitHub API (HTTP $($putResult.StatusCode)).`n$($putResult.Body)"
Write-Host 'Нижче надруковано JSON, який не вдалося записати:'
Write-Output $nextJson
exit 1
