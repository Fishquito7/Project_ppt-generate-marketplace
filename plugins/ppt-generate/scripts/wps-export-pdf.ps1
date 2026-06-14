param(
  [ValidateSet("Detect", "Export")]
  [string]$Mode = "Detect",
  [string]$InputPath,
  [string]$OutputPath,
  [string]$DiscoveryFixturePath
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$knownClsid = "{91493441-5A91-11CF-8700-00AA0060263B}"
$fixture = $null
if ($DiscoveryFixturePath) {
  $fixture = Get-Content -LiteralPath $DiscoveryFixturePath -Raw | ConvertFrom-Json
}

$candidates = New-Object System.Collections.ArrayList
$candidateKeys = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)
$diagnostics = New-Object System.Collections.ArrayList
$diagnosticKeys = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)

function Add-Diagnostic([string]$Message) {
  if ($Message -and $diagnosticKeys.Add($Message)) {
    [void]$diagnostics.Add($Message)
  }
}

function Get-FixtureValue([string]$PropertyName) {
  if (-not $fixture) { return $null }
  return $fixture.PSObject.Properties[$PropertyName].Value
}

function Test-DiscoveryPath([string]$Path) {
  if (-not $Path) { return $false }
  $existingPaths = @(Get-FixtureValue "existingPaths")
  if ($existingPaths.Count -gt 0) {
    foreach ($existing in $existingPaths) {
      if (-not $existing) { continue }
      if ([string]::Equals([string]$existing, $Path, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
      }
    }
  }
  return Test-Path -LiteralPath $Path
}

function Resolve-DiscoveryPath([string]$Path) {
  if (-not $Path) { return $null }
  $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
  if (-not (Test-DiscoveryPath $expanded)) { return $null }
  try {
    return (Get-Item -LiteralPath $expanded).FullName
  } catch {
    return [IO.Path]::GetFullPath($expanded)
  }
}

function Get-DiscoveryVersion([string]$Path) {
  foreach ($entry in @(Get-FixtureValue "fileVersions")) {
    if (-not $entry) { continue }
    if ([string]::Equals([string]$entry.path, $Path, [StringComparison]::OrdinalIgnoreCase)) {
      return [string]$entry.version
    }
  }
  try {
    return (Get-Item -LiteralPath $Path).VersionInfo.FileVersion
  } catch {
    return $null
  }
}

function Get-VersionValue([string]$Value) {
  if (-not $Value) { return [version]"0.0.0.0" }
  try {
    return [version]($Value -replace ",", "." -replace "[^0-9.].*$", "")
  } catch {
    return [version]"0.0.0.0"
  }
}

function Get-SourcePriority([string]$Source) {
  switch ($Source) {
    "com-clsid" { return 0 }
    "kingsoft-registry" { return 1 }
    "app-paths" { return 2 }
    "shell-shortcut" { return 3 }
    "running-process" { return 4 }
    "bounded-filesystem" { return 5 }
    default { return 99 }
  }
}

function Add-Candidate(
  [string]$ExecutablePath,
  [string]$Source,
  [string]$Architecture,
  [bool]$ComReady,
  [string]$Reason,
  [string]$RegistryPath,
  [string]$LocalServerCommand,
  [string]$ShortcutPath,
  [string]$ShortcutTarget
) {
  $resolved = Resolve-DiscoveryPath $ExecutablePath
  if (-not $resolved) { return $null }
  if ([IO.Path]::GetFileName($resolved) -ine "wpp.exe") { return $null }
  $key = "$Source|$resolved"
  if (-not $candidateKeys.Add($key)) { return $null }
  $candidate = [pscustomobject]@{
    executablePath = $resolved
    source = $Source
    architecture = if ($Architecture -in @("x86", "x64")) { $Architecture } else { $null }
    comReady = $ComReady
    reason = $Reason
    version = Get-DiscoveryVersion $resolved
    registryPath = $RegistryPath
    localServerCommand = $LocalServerCommand
  }
  if ($ShortcutPath) { Add-Member -InputObject $candidate -NotePropertyName shortcutPath -NotePropertyValue $ShortcutPath }
  if ($ShortcutTarget) { Add-Member -InputObject $candidate -NotePropertyName shortcutTarget -NotePropertyValue $ShortcutTarget }
  [void]$candidates.Add($candidate)
  return $candidate
}

function Get-RegistryValue(
  [string]$HiveName,
  [string]$ViewName,
  [string]$SubKey,
  [string]$ValueName = ""
) {
  foreach ($entry in @(Get-FixtureValue "registry")) {
    if (-not $entry) { continue }
    if (
      [string]::Equals([string]$entry.hive, $HiveName, [StringComparison]::OrdinalIgnoreCase) -and
      [string]::Equals([string]$entry.view, $ViewName, [StringComparison]::OrdinalIgnoreCase) -and
      [string]::Equals([string]$entry.subKey, $SubKey, [StringComparison]::OrdinalIgnoreCase) -and
      [string]::Equals([string]$entry.valueName, $ValueName, [StringComparison]::OrdinalIgnoreCase)
    ) {
      return [pscustomobject]@{ found = $true; value = $entry.value }
    }
  }
  if ($fixture) { return [pscustomobject]@{ found = $false; value = $null } }
  $hive = [Enum]::Parse([Microsoft.Win32.RegistryHive], $HiveName)
  $view = [Enum]::Parse([Microsoft.Win32.RegistryView], $ViewName)
  $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
  try {
    $key = $base.OpenSubKey($SubKey)
    if (-not $key) { return [pscustomobject]@{ found = $false; value = $null } }
    try {
      $value = $key.GetValue($(if ($ValueName) { $ValueName } else { $null }), $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
      return [pscustomobject]@{ found = $null -ne $value; value = $value }
    } finally {
      $key.Dispose()
    }
  } finally {
    $base.Dispose()
  }
}

function Get-ExecutableFromCommand([string]$Command) {
  if (-not $Command) { return $null }
  $match = [regex]::Match($Command, '^\s*(?:"([^"]+\.exe)"|(.+?\.exe))(?:\s|$)', "IgnoreCase")
  if (-not $match.Success) { return $null }
  if ($match.Groups[1].Success) { return $match.Groups[1].Value }
  return $match.Groups[2].Value
}

function Get-WindowsDirectory {
  $fixtureWindows = Get-FixtureValue "windowsDirectory"
  $values = @(
    $fixtureWindows
    [Environment]::GetFolderPath("Windows")
    $env:SystemRoot
    $env:WINDIR
    "C:\Windows"
  )
  foreach ($value in $values) {
    if ($value -and (Test-DiscoveryPath $value)) {
      return [IO.Path]::GetFullPath([string]$value)
    }
  }
  return $null
}

function Get-PowerShellForArchitecture([string]$Architecture) {
  $windows = Get-WindowsDirectory
  if (-not $windows) { return $null }
  $relative = if ($Architecture -eq "x86") {
    "SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
  } else {
    "System32\WindowsPowerShell\v1.0\powershell.exe"
  }
  return Resolve-DiscoveryPath (Join-Path $windows $relative)
}

function Get-SpecialFolder([string]$Name) {
  foreach ($entry in @(Get-FixtureValue "specialFolders")) {
    if (-not $entry) { continue }
    if ([string]::Equals([string]$entry.name, $Name, [StringComparison]::OrdinalIgnoreCase)) {
      return [string]$entry.path
    }
  }
  if ($fixture) { return $null }
  return [Environment]::GetFolderPath($Name)
}

function Test-IsLocalPath([string]$Path) {
  if (-not $Path) { return $false }
  $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
  if ($expanded -match '^[\\/]{2}') { return $false }
  try {
    if (-not [IO.Path]::IsPathRooted($expanded)) { return $false }
    if (-not $fixture) {
      $root = [IO.Path]::GetPathRoot($expanded)
      if ($root -and ([IO.DriveInfo]::new($root)).DriveType -eq [IO.DriveType]::Network) {
        return $false
      }
    }
    return $true
  } catch {
    return $false
  }
}

function Get-MatchingDiscoveryPaths([string]$Pattern) {
  if ($fixture) {
    foreach ($existing in @(Get-FixtureValue "existingPaths")) {
      if (-not $existing) { continue }
      if ([string]$existing -like $Pattern) {
        try { [IO.Path]::GetFullPath([string]$existing) } catch {}
      }
    }
    return
  }
  foreach ($file in @(Get-Item -Path $Pattern -ErrorAction SilentlyContinue)) {
    if ($file -and -not $file.PSIsContainer) { $file.FullName }
  }
}

function Test-ShortcutInsideRoot([string]$ShortcutPath, [string]$RootPath, [bool]$Recursive) {
  if (-not $ShortcutPath -or -not $RootPath) { return $false }
  try {
    $shortcut = [IO.Path]::GetFullPath($ShortcutPath)
    $root = [IO.Path]::GetFullPath($RootPath).TrimEnd("\")
    if ($Recursive) {
      return $shortcut.StartsWith("$root\", [StringComparison]::OrdinalIgnoreCase)
    }
    return [string]::Equals((Split-Path $shortcut -Parent), $root, [StringComparison]::OrdinalIgnoreCase)
  } catch {
    return $false
  }
}

function Get-ShortcutRoots {
  $roots = New-Object System.Collections.ArrayList
  foreach ($entry in @(
    [pscustomobject]@{ name = "Programs"; label = "user-start-menu"; recursive = $true }
    [pscustomobject]@{ name = "CommonPrograms"; label = "common-start-menu"; recursive = $true }
    [pscustomobject]@{ name = "Desktop"; label = "user-desktop"; recursive = $false }
    [pscustomobject]@{ name = "CommonDesktopDirectory"; label = "common-desktop"; recursive = $false }
  )) {
    $folder = Get-SpecialFolder $entry.name
    if ($folder -and (Test-IsLocalPath $folder) -and (Test-DiscoveryPath $folder)) {
      [void]$roots.Add([pscustomobject]@{ path = [IO.Path]::GetFullPath($folder); label = $entry.label; recursive = $entry.recursive })
    }
  }
  $appData = Get-SpecialFolder "ApplicationData"
  if ($appData -and (Test-IsLocalPath $appData)) {
    $taskbar = Join-Path $appData "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    if (Test-DiscoveryPath $taskbar) {
      [void]$roots.Add([pscustomobject]@{ path = [IO.Path]::GetFullPath($taskbar); label = "taskbar"; recursive = $false })
    }
  }
  return @($roots)
}

function Get-ShellShortcutEntries($Roots) {
  if ($fixture) {
    if (Get-FixtureValue "shortcutShellUnavailable") {
      Add-Diagnostic "WScript.Shell is unavailable; shell shortcut discovery was skipped."
      return @()
    }
    $result = New-Object System.Collections.ArrayList
    foreach ($entry in @(Get-FixtureValue "shortcuts")) {
      if (-not $entry -or -not $entry.path) { continue }
      foreach ($root in $Roots) {
        if (Test-ShortcutInsideRoot ([string]$entry.path) ([string]$root.path) ([bool]$root.recursive)) {
          [void]$result.Add($entry)
          break
        }
      }
    }
    return @($result)
  }

  $shell = $null
  $result = New-Object System.Collections.ArrayList
  try {
    try {
      $shell = New-Object -ComObject WScript.Shell
    } catch {
      Add-Diagnostic "WScript.Shell is unavailable; shell shortcut discovery was skipped: $($_.Exception.Message)"
      return @()
    }
    foreach ($root in $Roots) {
      $links = if ($root.recursive) {
        @(Get-ChildItem -LiteralPath $root.path -Filter *.lnk -File -Recurse -ErrorAction SilentlyContinue)
      } else {
        @(Get-ChildItem -LiteralPath $root.path -Filter *.lnk -File -ErrorAction SilentlyContinue)
      }
      foreach ($link in $links) {
        $shortcut = $null
        try {
          $shortcut = $shell.CreateShortcut($link.FullName)
          [void]$result.Add([pscustomobject]@{
            path = $link.FullName
            target = [string]$shortcut.TargetPath
          })
        } catch {
          Add-Diagnostic "Shell shortcut could not be parsed: $($link.FullName)"
        } finally {
          if ($shortcut -and [Runtime.InteropServices.Marshal]::IsComObject($shortcut)) {
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
          }
        }
      }
    }
  } finally {
    if ($shell -and [Runtime.InteropServices.Marshal]::IsComObject($shell)) {
      [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
    }
  }
  return @($result)
}

function Get-ArchitectureForView([string]$ViewName) {
  if ($ViewName -eq "Registry32") { return "x86" }
  return "x64"
}

function Get-RegistryLocation([string]$Hive, [string]$View, [string]$SubKey) {
  return "$Hive/$View/$SubKey"
}

function Find-ComProgIdCandidates($Views) {
  $progIdKey = "Software\Classes\PowerPoint.Application\CLSID"
  foreach ($entry in $Views) {
    $clsid = Get-RegistryValue $entry.hive $entry.view $progIdKey
    if (-not $clsid.found) {
      Add-Diagnostic "PowerPoint.Application ProgID is absent in $($entry.hive)/$($entry.view)."
      continue
    }
    $localServerKey = "Software\Classes\CLSID\$($clsid.value)\LocalServer32"
    $server = Get-RegistryValue $entry.hive $entry.view $localServerKey
    if (-not $server.found) {
      Add-Diagnostic "PowerPoint.Application exists in $($entry.hive)/$($entry.view), but LocalServer32 is absent."
      continue
    }
    $rawPath = Get-ExecutableFromCommand ([string]$server.value)
    if (-not $rawPath) {
      Add-Diagnostic "PowerPoint.Application LocalServer32 in $($entry.hive)/$($entry.view) is not a valid executable command."
      continue
    }
    if ([IO.Path]::GetFileName($rawPath) -ine "wpp.exe") {
      Add-Diagnostic "PowerPoint.Application in $($entry.hive)/$($entry.view) points to $([IO.Path]::GetFileName($rawPath)), not WPS wpp.exe."
      continue
    }
    $resolved = Resolve-DiscoveryPath $rawPath
    if (-not $resolved) {
      Add-Diagnostic "PowerPoint.Application in $($entry.hive)/$($entry.view) points to a missing wpp.exe: $rawPath"
      continue
    }
    $architecture = Get-ArchitectureForView $entry.view
    $powershell = Get-PowerShellForArchitecture $architecture
    $ready = $null -ne $powershell
    $reason = if ($ready) { $null } else { "Matching $architecture Windows PowerShell is unavailable." }
    if ($reason) { Add-Diagnostic $reason }
    [void](Add-Candidate $resolved "com-progid" $architecture $ready $reason (Get-RegistryLocation $entry.hive $entry.view $localServerKey) ([string]$server.value))
  }
}

function Find-KnownClsidCandidates($Views) {
  foreach ($entry in $Views) {
    $localServerKey = "Software\Classes\CLSID\$knownClsid\LocalServer32"
    $server = Get-RegistryValue $entry.hive $entry.view $localServerKey
    if (-not $server.found) { continue }
    $rawPath = Get-ExecutableFromCommand ([string]$server.value)
    if ($rawPath -and [IO.Path]::GetFileName($rawPath) -ieq "wpp.exe") {
      [void](Add-Candidate $rawPath "com-clsid" (Get-ArchitectureForView $entry.view) $false "Known CLSID exists, but the PowerPoint.Application ProgID chain is incomplete." (Get-RegistryLocation $entry.hive $entry.view $localServerKey) ([string]$server.value))
    }
  }
}

function Find-KingsoftRegistryCandidates($Views, [System.Collections.ArrayList]$SearchRoots) {
  $commonKey = "Software\Kingsoft\Office\6.0\Common"
  foreach ($entry in $Views) {
    $installRoot = Get-RegistryValue $entry.hive $entry.view $commonKey "InstallRoot"
    if (-not $installRoot.found) { continue }
    $architectureValue = Get-RegistryValue $entry.hive $entry.view $commonKey "Architecture"
    $architecture = if ($architectureValue.found) { [string]$architectureValue.value } else { Get-ArchitectureForView $entry.view }
    $root = [string]$installRoot.value
    if ($root) { [void]$SearchRoots.Add($root) }
    [void](Add-Candidate (Join-Path $root "office6\wpp.exe") "kingsoft-registry" $architecture $false "WPS installation was found, but COM automation is unavailable." (Get-RegistryLocation $entry.hive $entry.view $commonKey) $null)
  }
}

function Find-AppPathCandidates($Views, [System.Collections.ArrayList]$SearchRoots) {
  $appPathKey = "Software\Microsoft\Windows\CurrentVersion\App Paths\wpp.exe"
  foreach ($entry in $Views) {
    $appPath = Get-RegistryValue $entry.hive $entry.view $appPathKey
    if (-not $appPath.found) { continue }
    $rawPath = Get-ExecutableFromCommand ([string]$appPath.value)
    if (-not $rawPath) { $rawPath = [string]$appPath.value }
    $resolved = Resolve-DiscoveryPath $rawPath
    if ($resolved) { [void]$SearchRoots.Add((Split-Path $resolved -Parent)) }
    [void](Add-Candidate $rawPath "app-paths" (Get-ArchitectureForView $entry.view) $false "WPS App Paths entry was found, but COM automation is unavailable." (Get-RegistryLocation $entry.hive $entry.view $appPathKey) $null)
  }
}

function Find-ShellShortcutCandidates([System.Collections.ArrayList]$SearchRoots) {
  $roots = @(Get-ShortcutRoots)
  if ($roots.Count -eq 0) { return }
  foreach ($entry in @(Get-ShellShortcutEntries $roots)) {
    $shortcutPath = [string]$entry.path
    if ($entry.error) {
      Add-Diagnostic "Shell shortcut could not be parsed: $shortcutPath"
      continue
    }
    $target = [Environment]::ExpandEnvironmentVariables(([string]$entry.target).Trim())
    if (-not $target) { continue }
    if (-not (Test-IsLocalPath $target)) {
      if ($shortcutPath -match '(?i)(kingsoft|wps|演示|金山)' -or $target -match '(?i)(kingsoft|wps|wpp\.exe)') {
        Add-Diagnostic "Shell shortcut target is not a local path and was skipped: $shortcutPath"
      }
      continue
    }
    $targetName = [IO.Path]::GetFileName($target)
    if (
      $targetName -notin @("wpp.exe", "wps.exe", "et.exe", "kso.exe", "ksolaunch.exe") -and
      $target -notmatch '(?i)(kingsoft|wps)' -and
      $shortcutPath -notmatch '(?i)(kingsoft|wps|演示|金山)'
    ) {
      continue
    }
    if (-not (Test-DiscoveryPath $target)) {
      Add-Diagnostic "Shell shortcut target is missing: $shortcutPath -> $target"
      continue
    }
    $targetDirectory = Split-Path $target -Parent
    [void]$SearchRoots.Add($targetDirectory)
    $parentDirectory = Split-Path $targetDirectory -Parent
    if ($parentDirectory) { [void]$SearchRoots.Add($parentDirectory) }
    $patterns = @(
      $target
      (Join-Path $targetDirectory "wpp.exe")
      (Join-Path $targetDirectory "office6\wpp.exe")
      (Join-Path $targetDirectory "*\office6\wpp.exe")
    )
    if ($parentDirectory) {
      $patterns += (Join-Path $parentDirectory "office6\wpp.exe")
      $patterns += (Join-Path $parentDirectory "*\office6\wpp.exe")
    }
    foreach ($pattern in $patterns) {
      foreach ($wppPath in @(Get-MatchingDiscoveryPaths $pattern)) {
        $resolved = Resolve-DiscoveryPath $wppPath
        if (-not $resolved -or [IO.Path]::GetFileName($resolved) -ine "wpp.exe") { continue }
        [void]$SearchRoots.Add((Split-Path $resolved -Parent))
        [void](Add-Candidate $resolved "shell-shortcut" $null $false "A Windows shell shortcut located WPS, but it does not prove COM automation is registered." $null $null $shortcutPath $target)
      }
    }
  }
}

function Find-RunningProcessCandidates([System.Collections.ArrayList]$SearchRoots) {
  $paths = @(Get-FixtureValue "runningProcesses")
  if (-not $fixture) {
    $paths = @(Get-Process wpp -ErrorAction SilentlyContinue | ForEach-Object {
      try { $_.Path } catch { $null }
    })
  }
  foreach ($processPath in $paths) {
    if ($processPath) { [void]$SearchRoots.Add((Split-Path ([string]$processPath) -Parent)) }
    [void](Add-Candidate ([string]$processPath) "running-process" $null $false "A running WPS process was found, but it does not prove COM automation is registered." $null $null)
  }
}

function Find-BoundedFilesystemCandidates([System.Collections.ArrayList]$SearchRoots) {
  foreach ($folderName in @("ProgramFiles", "ProgramFilesX86", "LocalApplicationData")) {
    $folder = Get-SpecialFolder $folderName
    if ($folder) { [void]$SearchRoots.Add($folder) }
  }
  $uniqueRoots = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)
  foreach ($rootValue in $SearchRoots) {
    if (-not $rootValue) { continue }
    $root = [IO.Path]::GetFullPath([string]$rootValue)
    if (-not $uniqueRoots.Add($root)) { continue }
    foreach ($fixtureFile in @(Get-FixtureValue "boundedFiles")) {
      if (-not $fixtureFile) { continue }
      $filePath = [IO.Path]::GetFullPath([string]$fixtureFile)
      if ($filePath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        [void](Add-Candidate $filePath "bounded-filesystem" $null $false "A bounded filesystem search found WPS, but COM automation is unavailable." $null $null)
      }
    }
    if ($fixture) { continue }
    $patterns = @(
      (Join-Path $root "office6\wpp.exe")
      (Join-Path $root "*\office6\wpp.exe")
      (Join-Path $root "Kingsoft\WPS Office\*\office6\wpp.exe")
      (Join-Path $root "WPS Office\*\office6\wpp.exe")
      (Join-Path $root "Kingsoft\Office*\office6\wpp.exe")
      (Join-Path $root "Kingsoft\Office*\*\office6\wpp.exe")
    )
    foreach ($pattern in $patterns) {
      foreach ($file in @(Get-Item -Path $pattern -ErrorAction SilentlyContinue)) {
        [void](Add-Candidate $file.FullName "bounded-filesystem" $null $false "A bounded filesystem search found WPS, but COM automation is unavailable." $null $null)
      }
    }
  }
}

function Get-WpsDiscovery {
  $views = @(
    [pscustomobject]@{ hive = "CurrentUser"; view = "Registry64" }
    [pscustomobject]@{ hive = "CurrentUser"; view = "Registry32" }
    [pscustomobject]@{ hive = "LocalMachine"; view = "Registry64" }
    [pscustomobject]@{ hive = "LocalMachine"; view = "Registry32" }
  )
  $searchRoots = New-Object System.Collections.ArrayList
  Find-ComProgIdCandidates $views
  Find-KnownClsidCandidates $views
  Find-KingsoftRegistryCandidates $views $searchRoots
  Find-AppPathCandidates $views $searchRoots
  Find-ShellShortcutCandidates $searchRoots
  Find-RunningProcessCandidates $searchRoots
  Find-BoundedFilesystemCandidates $searchRoots

  $primary = @($candidates | Where-Object { $_.source -eq "com-progid" -and $_.comReady }) | Select-Object -First 1
  if ($primary) {
    return [pscustomobject]@{
      ok = $true
      installed = $true
      automationReady = $true
      discoverySource = "com-progid"
      executablePath = $primary.executablePath
      architecture = $primary.architecture
      version = $primary.version
      powershellPath = Get-PowerShellForArchitecture $primary.architecture
      progId = "PowerPoint.Application"
      registryPath = $primary.registryPath
      localServerCommand = $primary.localServerCommand
      candidates = @($candidates)
      diagnostics = @($diagnostics)
    }
  }

  $best = @($candidates | Sort-Object -Property @(
    @{ Expression = { Get-VersionValue $_.version }; Descending = $true }
    @{ Expression = { Get-SourcePriority $_.source }; Ascending = $true }
  )) | Select-Object -First 1
  if ($best) {
    $error = "WPS Presentation is installed, but PowerPoint.Application COM automation is unavailable."
    Add-Diagnostic $error
    return [pscustomobject]@{
      ok = $false
      installed = $true
      automationReady = $false
      discoverySource = $best.source
      executablePath = $best.executablePath
      architecture = $best.architecture
      version = $best.version
      powershellPath = $null
      progId = "PowerPoint.Application"
      registryPath = $best.registryPath
      localServerCommand = $best.localServerCommand
      candidates = @($candidates)
      diagnostics = @($diagnostics)
      error = $error
    }
  }

  $error = "WPS Presentation was not found in COM registration, installation metadata, shell shortcuts, running processes, or bounded search locations."
  Add-Diagnostic $error
  return [pscustomobject]@{
    ok = $false
    installed = $false
    automationReady = $false
    discoverySource = "none"
    candidates = @()
    diagnostics = @($diagnostics)
    error = $error
  }
}

function Write-Json($Value) {
  $Value | ConvertTo-Json -Depth 12 -Compress
}

$discovery = Get-WpsDiscovery
if ($Mode -eq "Detect") {
  Write-Json $discovery
  exit 0
}

if (-not $discovery.automationReady -or $discovery.discoverySource -ne "com-progid") {
  throw $discovery.error
}
if (-not $InputPath -or -not $OutputPath) {
  throw "Export mode requires InputPath and OutputPath."
}
$is64BitProcess = [Environment]::Is64BitProcess
if (($discovery.architecture -eq "x86" -and $is64BitProcess) -or ($discovery.architecture -eq "x64" -and -not $is64BitProcess)) {
  throw "PowerShell architecture does not match the WPS COM registration."
}

$input = [IO.Path]::GetFullPath($InputPath)
$output = [IO.Path]::GetFullPath($OutputPath)
$beforePids = @(Get-Process wpp -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$hadExistingInstance = $beforePids.Count -gt 0
$startedAt = Get-Date
$app = $null
$presentation = $null

try {
  $app = New-Object -ComObject PowerPoint.Application
  if (-not $hadExistingInstance) {
    try { $app.Visible = 0 } catch {}
    try { $app.DisplayAlerts = 0 } catch {}
  }
  $presentation = $app.Presentations.Open($input, -1, 0, 0)
  $presentation.SaveAs($output, 32)

  $deadline = (Get-Date).AddSeconds(30)
  while (-not (Test-Path -LiteralPath $output) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 250
  }
  if (-not (Test-Path -LiteralPath $output)) {
    throw "WPS returned from SaveAs but no PDF was created."
  }
  $pdf = Get-Item -LiteralPath $output
  Write-Json ([pscustomobject]@{
    ok = $true
    inputPath = $input
    outputPath = $pdf.FullName
    bytes = $pdf.Length
    durationMs = [int]((Get-Date) - $startedAt).TotalMilliseconds
    hadExistingInstance = $hadExistingInstance
    beforePids = $beforePids
    discovery = $discovery
  })
} finally {
  if ($presentation) {
    try { $presentation.Close() } catch {}
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($presentation)
  }
  if ($app) {
    if (-not $hadExistingInstance) {
      try { $app.Quit() } catch {}
    }
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($app)
  }
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}
