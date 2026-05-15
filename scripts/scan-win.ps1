#Requires -Version 5.1
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

if (-not $env:GITHUB_TOKEN) {
  Write-Error 'Set GITHUB_TOKEN env var (see scripts/README.md)'
  exit 1
}

$volumes = Get-Volume |
  Where-Object {
    $_.DriveLetter -and
    ($_.DriveType -eq 'Fixed' -or $_.DriveType -eq 'Removable') -and
    ("$($_.DriveLetter):" -ne $env:SystemDrive)
  }

if (-not $volumes -or $volumes.Count -eq 0) {
  Write-Error 'Не знайдено зовнішніх томів для сканування.'
  exit 1
}

$nowIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

Write-LogInfo ("Знайдено {0} том(ів). Запускаю повне сканування..." -f $volumes.Count)
$driveRecords = @()

for ($v = 0; $v -lt $volumes.Count; $v += 1) {
  $selectedVolume = $volumes[$v]
  $rootPath = '{0}:\' -f $selectedVolume.DriveLetter
  $driveName = if ($selectedVolume.FileSystemLabel) { $selectedVolume.FileSystemLabel } else { "$($selectedVolume.DriveLetter):" }

  Write-Host ''
  Write-LogInfo ("=== [{0}/{1}] Сканую том: {2} ===" -f ($v + 1), $volumes.Count, $driveName)

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

$commitMessage = "scan: full sweep at $nowIso ($($driveRecords.Count) drives)"
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
