
# ------------------------- MODO PRUEBA (-Test) -------------------------
if ($Test) {
    . ([scriptblock]::Create($DetectLibSrc))
    # Aplicar subredes de camaras personalizadas (ajustes guardados del widget)
    try {
        if (Test-Path $SettingsPath) {
            $rawS = [IO.File]::ReadAllText($SettingsPath, [Text.Encoding]::UTF8)
            if ($rawS.Trim().Length -gt 0) {
                $objS = $rawS | ConvertFrom-Json
                if ($null -ne $objS.CamerasSubnets) {
                    $Cfg.CamerasSubnets = @(@($objS.CamerasSubnets) | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' })
                }
                if ($null -ne $objS.SubnetLabels) {
                    $Cfg.SubnetLabels = @(@($objS.SubnetLabels) | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '=' })
                }
            }
        }
    } catch {}
    $snap = Get-NetSnapshot $Cfg
    $cls  = Get-NetClassification $snap @() $Cfg
    $pub  = Get-PublicInfo 8
    $result = [pscustomobject]@{
        Clasificacion = $cls
        Deteccion     = $snap
        IPPublica     = $pub
        AdaptadoresUp = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } |
                          Select-Object Name, InterfaceDescription, MediaType, PhysicalMediaType, LinkSpeed)
    }
    $result | ConvertTo-Json -Depth 6
    exit 0
}

# ------------------------- ESTADO COMPARTIDO (UI <-> hilo de deteccion) -------------------------
$State = [hashtable]::Synchronized(@{
    Run=$true; ForceNow=$false; RefreshPublic=$true; Version=0; LastError=''
    RawKey=''; Name=''; Sub=''; Tag=''
    Ok=$true; AdapterFound=$false
    Ip=''; Prefix=0; Segment=''; Broadcast=''; Gateway=''; GwMac=''; IfIndex=0
    IfaceName=''; IfaceDesc=''; IfaceKind=''; Ssid=''; ProfileName=''; Category=''
    Speed=''; Dns=''; Mtu=''
    GwPing=$null; ExtPing=$null; LossPct=0; Spark=@()
    PubIp=''; Isp=''; PubOk=$false; PubWhen=''
    LastUpdate='--:--:--'
})

# ------------------------- HILO DE DETECCION (worker) -------------------------
$WorkerBody = @'


[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072

$spark   = New-Object System.Collections.ArrayList
$lossArr = New-Object System.Collections.ArrayList
$lastPub = [datetime]::MinValue
$pubIp = ''; $pubIsp = ''

while ($state.Run) {
    try {
        $snap = Get-NetSnapshot $cfg
        $cls  = Get-NetClassification $snap @() $cfg

        $rawId = "$($cls.Id)"
        if (-not $rawId) { $rawId = "$($cls.Key)" }
        $state.RawKey  = $rawId
        $state.Name    = "$($cls.Name)"
        $state.Sub     = "$($cls.Sub)"
        $state.Tag     = "$($cls.Tag)"
        $state.Ok      = $snap.Ok
        $state.AdapterFound = $snap.AdapterFound
        $state.Ip        = $snap.Ip
        $state.Prefix    = $snap.Prefix
        $state.Segment   = $snap.Segment
        $state.Broadcast = $snap.Broadcast
        $state.Gateway   = $snap.Gateway
        $state.IfIndex   = $snap.IfIndex
        $state.IfaceName = $snap.IfaceName
        $state.IfaceDesc = $snap.IfaceDesc
        $state.IfaceKind = $snap.IfaceKind
        $state.Ssid      = $snap.Ssid
        $state.ProfileName = $snap.ProfileName
        $state.Category  = $snap.Category
        $state.Speed     = $snap.Speed
        $state.Dns       = $snap.Dns
        $state.Mtu       = $snap.Mtu

        # --- Pings reales (gateway + externo) ---
        $gwPing = $null; $extPing = $null
        if ($snap.AdapterFound -and $snap.Gateway) { $gwPing = Invoke-PingOnce $snap.Gateway $cfg.PingTimeoutMs }
        if ($snap.AdapterFound) { $extPing = Invoke-PingOnce $cfg.ExtPingTarget $cfg.PingTimeoutMs }
        $state.GwPing  = $gwPing
        $state.ExtPing = $extPing

        # --- MAC del gateway (despues del ping para que exista en ARP) ---
        if ($snap.AdapterFound -and $snap.Gateway) {
            $mac = Get-GwMac $snap.IfIndex $snap.Gateway
            if ($mac) { $state.GwMac = $mac }
        } elseif (-not $snap.AdapterFound) { $state.GwMac = '' }

        # --- Sparkline + perdida de paquetes ---
        [void]$spark.Add($extPing)
        while ($spark.Count -gt $cfg.SparkSamples) { $spark.RemoveAt(0) }
        [void]$lossArr.Add(($null -ne $extPing))
        while ($lossArr.Count -gt $cfg.LossWindow) { $lossArr.RemoveAt(0) }
        $state.Spark = @($spark)
        if ($state.AdapterFound) {
            $okCount = @($lossArr | Where-Object { $_ }).Count
            $state.LossPct = [int][Math]::Round((100.0 * ($lossArr.Count - $okCount)) / [Math]::Max(1, $lossArr.Count))
        } else { $state.LossPct = 0 }

        # --- IP publica / ISP ---
        $needPub = $state.RefreshPublic
        if (-not $needPub) {
            if (((Get-Date) - $lastPub).TotalSeconds -ge $cfg.PublicEverySeconds) { $needPub = $true }
        }
        if ($needPub) {
            $state.RefreshPublic = $false
            $lastPub = Get-Date
            if ($snap.AdapterFound) {
                $pi = Get-PublicInfo 6
                if ($pi.Ip) {
                    $pubIp = "$($pi.Ip)"; $pubIsp = "$($pi.Isp)"
                    $state.PubOk = $true
                    $state.PubWhen = (Get-Date).ToString('HH:mm:ss')
                } else { $state.PubOk = $false }
            } else { $state.PubOk = $false }
        }
        if ($snap.AdapterFound) { $state.PubIp = $pubIp; $state.Isp = $pubIsp }
        else { $state.PubIp = ''; $state.Isp = '' }

        $state.LastUpdate = (Get-Date).ToString('HH:mm:ss')
        $state.Version = [int]$state.Version + 1
    } catch {
        $state.LastError = "$_"
        $state.Version = [int]$state.Version + 1
    }

    # Dormir en trozos de 100 ms (salir antes si hay refresco manual o cierre)
    for ($i = 0; $i -lt ($cfg.PollSeconds * 10); $i++) {
        if (-not $state.Run) { break }
        if ($state.ForceNow) { $state.ForceNow = $false; break }
        Start-Sleep -Milliseconds 100
    }
}
'@

# Script completo del worker: param + libreria de deteccion + cuerpo
$WorkerScript = "param(`$state, `$cfg)`r`n" + $DetectLibSrc + "`r`n" + $WorkerBody

$script:WorkerPS = $null
$script:WorkerRS = $null
$script:WorkerHandle = $null

function Start-NetWorker {
    try {
        if ($script:WorkerPS) { try { $script:WorkerPS.Dispose() } catch {} }
        if ($script:WorkerRS) { try { $script:WorkerRS.Dispose() } catch {} }
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'MTA'
        $rs.ThreadOptions  = 'ReuseThread'
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($WorkerScript).AddArgument($State).AddArgument($Cfg)
        $script:WorkerHandle = $ps.BeginInvoke()
        $script:WorkerPS = $ps
        $script:WorkerRS = $rs
    } catch {
        $State.LastError = "worker: $_"
    }
}

function Stop-NetWorker {
    try {
        $State.Run = $false
        Start-Sleep -Milliseconds 350
        if ($script:WorkerPS) { try { $script:WorkerPS.Stop() } catch {}; try { $script:WorkerPS.Dispose() } catch {} }
        if ($script:WorkerRS) { try { $script:WorkerRS.Dispose() } catch {} }
        $script:WorkerPS = $null; $script:WorkerRS = $null; $script:WorkerHandle = $null
    } catch {}
}

# ------------------------- PERSISTENCIA (historial y ajustes) -------------------------
# Aplana listas anidadas y "desenvuelve" envoltorios {value:[...], Count:n} que dejan
# ConvertFrom-Json/ConvertTo-Json de PS 5.1 al deserializar arrays dentro de arrays.
function Expand-HistoryEntries($node) {
    $out = New-Object System.Collections.ArrayList
    if ($null -eq $node) { return @() }
    $stack = New-Object System.Collections.Stack
    $stack.Push($node)
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        if ($null -eq $cur) { continue }
        if ($cur -is [System.Array]) {
            for ($i = $cur.Length - 1; $i -ge 0; $i--) { $stack.Push($cur[$i]) }
            continue
        }
        if ($cur -is [string]) { [void]$out.Add($cur); continue }
        $hasV = $null -ne $cur.PSObject.Properties['value']
        $hasC = $null -ne $cur.PSObject.Properties['Count']
        if ($hasV -and $hasC) { $stack.Push($cur.value); continue }
        [void]$out.Add($cur)
    }
    return @($out)
}

function Test-HistoryEntry($e) {
    if ($null -eq $e) { return $false }
    return (($null -ne $e.PSObject.Properties['time']) -and ($null -ne $e.PSObject.Properties['to']))
}

function Load-History {
    $h = @()
    try {
        if (Test-Path $HistoryPath) {
            $raw = [IO.File]::ReadAllText($HistoryPath, [Text.Encoding]::UTF8)
            if ($raw.Trim().Length -gt 0) {
                $parsed = $raw | ConvertFrom-Json
                foreach ($it in (Expand-HistoryEntries $parsed)) {
                    if (Test-HistoryEntry $it) { $h += $it }
                }
            }
        }
    } catch { $h = @() }
    return @($h)
}

function Save-History($entries) {
    try {
        $flat = @(Expand-HistoryEntries $entries | Where-Object { Test-HistoryEntry $_ })
        $arr = @($flat | Select-Object -First $Cfg.MaxHistory)
        $json = ConvertTo-Json -InputObject $arr -Depth 4
        [IO.File]::WriteAllText($HistoryPath, $json, (New-Object Text.UTF8Encoding($false)))
    } catch {}
}

function Load-Settings {
    $s = @{ Left = $null; Top = $null; Pinned = $false; Theme = 'dark'; CamerasSubnets = $null; SubnetLabels = $null }
    try {
        if (Test-Path $SettingsPath) {
            $raw = [IO.File]::ReadAllText($SettingsPath, [Text.Encoding]::UTF8)
            if ($raw.Trim().Length -gt 0) {
                $obj = $raw | ConvertFrom-Json
                if ($null -ne $obj.Left) { $s.Left = [double]$obj.Left }
                if ($null -ne $obj.Top)  { $s.Top  = [double]$obj.Top }
                if ($null -ne $obj.Pinned) { $s.Pinned = [bool]$obj.Pinned }
                if ($null -ne $obj.Theme) {
                    $t = "$($obj.Theme)"
                    if ($t -in @('system','dark','light','dracula')) { $s.Theme = $t }
                }
                if ($null -ne $obj.CamerasSubnets) {
                    $cs = @(@($obj.CamerasSubnets) | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$' })
                    $s.CamerasSubnets = @($cs)
                }
                if ($null -ne $obj.SubnetLabels) {
                    $ls = @(@($obj.SubnetLabels) | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}\s*=\s*.+$' })
                    $s.SubnetLabels = @($ls)
                }
            }
        }
    } catch {}
    return $s
}

function Save-Settings($left, $top, $pinned) {
    try {
        $themeKey = 'dark'
        try { if ($script:AppThemeKey) { $themeKey = "$($script:AppThemeKey)" } } catch {}
        $obj = [pscustomobject]@{
            Left           = [double]$left
            Top            = [double]$top
            Pinned         = [bool]$pinned
            Theme          = $themeKey
            CamerasSubnets = @($Cfg.CamerasSubnets)
            SubnetLabels   = @($Cfg.SubnetLabels)
        }
        $json = ConvertTo-Json -InputObject $obj -Depth 4
        [IO.File]::WriteAllText($SettingsPath, $json, (New-Object Text.UTF8Encoding($false)))
    } catch {}
}
