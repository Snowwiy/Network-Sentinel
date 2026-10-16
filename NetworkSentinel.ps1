# ============================================================
#  NETWORK SENTINEL - Widget de escritorio para Windows 10/11
#  Deteccion AUTOMATICA de red:
#     VPN / Oficina (Ethernet) / Camaras CCTV / Puente de Red / Etiquetas / Generica / Sin red
# ------------------------------------------------------------
#  Uso normal:  doble clic en  NetworkSentinel.bat   (modo silencioso)
#  Prueba:      powershell -ExecutionPolicy Bypass -File NetworkSentinel.ps1 -Test
# ============================================================
[CmdletBinding()]
param(
    [switch]$Test
)

if ($Test) { $ErrorActionPreference = 'Stop' } else { $ErrorActionPreference = 'Continue' }

# ------------------------- CONFIGURACION / REGLAS -------------------------
$Cfg = @{
    PollSeconds        = 2                    # cada cuantos segundos se re-detecta
    PingTimeoutMs      = 1200                 # timeout de ping (ms)
    ExtPingTarget      = '1.1.1.1'            # destino ping externo
    PublicEverySeconds = 60                   # cada cuanto refrescar IP publica
    SparkSamples       = 28                   # muestras del grafico de ping
    LossWindow         = 24                   # muestras para calcular % de perdida
    MaxHistory         = 200                  # maximo de entradas guardadas

    # Subred(es) que identifican la red de CAMARAS / CCTV.
    CamerasSubnets     = @('192.168.100.0/24')

    # Etiquetas de subred personalizadas: 'subred = nombre'. Ejemplos:
    #   @('10.0.1.0/24 = VLAN1 Admin', '10.0.2.0/24 = VLAN2 Invitados')
    # Tambien editables desde el panel de ajustes del widget (engranaje).
    SubnetLabels       = @()

    # (Opcional) Subred(es) que identifican la red de OFICINA. Si esta vacio,
    # se toma como Oficina cualquier conexion Ethernet por cable activa.
    OfficeSubnets      = @()

    # Nombres de adaptadores que se consideran VPN.
    VpnRegex           = '(?i)\b(vpn|wireguard|wintun|openvpn|tap-?windows|tap0|tun\d|tailscale|zerotier|anyconnect|globalprotect|forticlient|fortinet|sstp|l2tp|ikev2|softether|protonvpn|nordlynx|mullvad|cloudflare\s*warp)\b'

    # Adaptadores que se ignoran (virtuales / no fisicos).
    VirtualRegex       = '(?i)(hyper-?v|vmware|virtualbox|vbox|vethernet|loopback|bluetooth|wi-?fi direct|docker|wsl|npcap|pseudo|wan miniport|teredo|isatap|6to4|ras async)'
}

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { try { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { $ScriptDir = $null } }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

# Carpeta de datos (historial / ajustes). Si la carpeta del script no es
# escribible (p.ej. Program Files), se usa %LOCALAPPDATA%\NetworkSentinel
$DataDir = $ScriptDir
try {
    $probe = Join-Path $ScriptDir ('.ns_write_test_' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($probe, 'x')
    Remove-Item $probe -Force -ErrorAction SilentlyContinue
} catch {
    $DataDir = Join-Path $env:LOCALAPPDATA 'NetworkSentinel'
    if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
}
$HistoryPath  = Join-Path $DataDir 'network_sentinel_history.json'
$SettingsPath = Join-Path $DataDir 'network_sentinel_settings.json'

# ------------------------- LIBRERIA DE DETECCION -------------------------
# Este bloque de funciones se comparte entre el modo -Test y el hilo de fondo.
$DetectLibSrc = @'
function Convert-IPv4ToUInt64([string]$ip) {
    try {
        $b = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
        if ($b.Length -ne 4) { return $null }
        return ([uint64]$b[0] -shl 24) -bor ([uint64]$b[1] -shl 16) -bor ([uint64]$b[2] -shl 8) -bor [uint64]$b[3]
    } catch { return $null }
}

function Format-IPv4([uint64]$v) {
    $o1 = [int](($v -shr 24) -band 255)
    $o2 = [int](($v -shr 16) -band 255)
    $o3 = [int](($v -shr 8) -band 255)
    $o4 = [int]($v -band 255)
    return "$o1.$o2.$o3.$o4"
}

function Get-SegmentInfo([string]$ip, [int]$prefix) {
    $v = Convert-IPv4ToUInt64 $ip
    if ($null -eq $v) { return $null }
    if ($prefix -lt 1)  { $prefix = 24 }
    if ($prefix -gt 32) { $prefix = 32 }
    $mask = [uint64]([long]4294967295 -bxor (([long]1 -shl (32 - $prefix)) - 1))
    $net  = $v -band $mask
    $bc   = $net -bor ([uint64]([long]4294967295 -bxor [long]$mask))
    return [pscustomobject]@{
        Segment   = (Format-IPv4 $net) + "/$prefix"
        Network   =  Format-IPv4 $net
        Broadcast =  Format-IPv4 $bc
        Prefix    =  $prefix
    }
}

function Test-IPInCidr([string]$ip, [string]$cidr) {
    if ([string]::IsNullOrWhiteSpace($ip) -or [string]::IsNullOrWhiteSpace($cidr)) { return $false }
    $parts = $cidr.Split('/')
    if ($parts.Count -ne 2) { return $false }
    $v = Convert-IPv4ToUInt64 $ip
    $n = Convert-IPv4ToUInt64 $parts[0].Trim()
    if ($null -eq $v -or $null -eq $n) { return $false }
    $len = 24
    if (-not [int]::TryParse($parts[1].Trim(), [ref]$len)) { return $false }
    if ($len -lt 1)  { $len = 1 }
    if ($len -gt 32) { $len = 32 }
    $mask = [uint64]([long]4294967295 -bxor (([long]1 -shl (32 - $len)) - 1))
    return (($v -band $mask) -eq ($n -band $mask))
}

function Get-AdapterKind($a) {
    $phys = "$($a.PhysicalMediaType)"
    $med  = "$($a.MediaType)"
    $txt  = "$($a.Name) $($a.InterfaceDescription)"
    if ($phys -eq 'Native 802.11' -or $med -eq 'Native 802.11' -or $txt -match '(?i)(wi-?fi|wireless|802\.11|wlan)') { return 'Wi-Fi' }
    if ($phys -eq '802.3' -or $med -eq '802.3' -or $txt -match '(?i)(ethernet|gigabit|\dgbe|realtek pcie|intel\(r\) ethernet)') { return 'Ethernet' }
    return 'Otro'
}

function Test-IsVirtualAdapter($a, $cfg) {
    $txt = "$($a.Name) $($a.InterfaceDescription)"
    return ($txt -match $cfg.VirtualRegex)
}

function Test-IsVpnAdapter($a, $cfg) {
    $txt = "$($a.Name) $($a.InterfaceDescription)"
    return ($txt -match $cfg.VpnRegex)
}

function Get-AdapterPriority($a) {
    $k = Get-AdapterKind $a
    if ($k -eq 'Ethernet') { return 0 }
    if ($k -eq 'Wi-Fi')    { return 1 }
    return 2
}

function Invoke-PingOnce([string]$target, [int]$timeoutMs) {
    if ([string]::IsNullOrWhiteSpace($target)) { return $null }
    $p = $null
    try {
        $p = New-Object System.Net.NetworkInformation.Ping
        $r = $p.Send($target, $timeoutMs)
        if ($r.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { return [int]$r.RoundtripTime }
        return $null
    } catch { return $null }
    finally { if ($p) { try { $p.Dispose() } catch {} } }
}

function Get-GwMac([int]$ifIndex, [string]$gw) {
    if ([string]::IsNullOrWhiteSpace($gw)) { return '' }
    try {
        $n = @(Get-NetNeighbor -InterfaceIndex $ifIndex -AddressFamily IPv4 -IPAddress $gw -ErrorAction SilentlyContinue |
               Where-Object { $_.LinkLayerAddress -and $_.LinkLayerAddress -notmatch '^(00-00-00|FF-FF)' })
        if ($n.Count -gt 0) {
            return (("$($n[0].LinkLayerAddress)" -replace '-', ':').ToLower())
        }
    } catch {}
    return ''
}

function Get-NetSnapshot([hashtable]$cfg) {
    $snap = [ordered]@{
        Ok=$true; AdapterFound=$false;
        Ip=''; Prefix=0; Gateway=''; GwMac=''; Segment=''; Broadcast='';
        IfaceName=''; IfaceDesc=''; IfaceKind=''; IfIndex=0;
        Ssid=''; ProfileName=''; Category=''; Speed=''; Dns=''; Mtu=''
    }
    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
        if ($adapters.Count -eq 0) { return $snap }

        # Metricas de interfaz
        $metrics = @{}
        foreach ($ipif in @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
            try { $metrics[[int]$ipif.ifIndex] = [int]$ipif.InterfaceMetric } catch {}
        }
        $routes = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                    Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' })
        $bestRoute = $null; $bestMetric = [int]::MaxValue
        foreach ($r in $routes) {
            $im = 0
            if ($metrics.ContainsKey([int]$r.ifIndex)) { $im = $metrics[[int]$r.ifIndex] }
            $m = [int]$r.RouteMetric + $im
            if ($m -lt $bestMetric) { $bestMetric = $m; $bestRoute = $r }
        }

        $active = $null
        if ($bestRoute) {
            $hit = @($adapters | Where-Object { [int]$_.ifIndex -eq [int]$bestRoute.ifIndex })
            if ($hit.Count -gt 0) { $active = $hit[0] }
        }
        if (-not $active) {
            # Sin ruta por defecto (p.ej. VLAN aislada): tomar adaptador fisico con IPv4 valida
            $cands = @()
            foreach ($a in $adapters) {
                if (Test-IsVirtualAdapter $a $cfg) { continue }
                $ip = @(Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                        Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' })
                if ($ip.Count -gt 0) { $cands += [pscustomobject]@{ A=$a; IP=$ip[0] } }
            }
            if ($cands.Count -gt 0) {
                $cands = @($cands | Sort-Object { Get-AdapterPriority $_.A })
                $active = $cands[0].A
            }
        }
        if (-not $active) { return $snap }

        $snap.AdapterFound = $true
        $snap.IfIndex      = [int]$active.ifIndex
        $snap.IfaceName    = "$($active.Name)"
        $snap.IfaceDesc    = "$($active.InterfaceDescription)"
        $snap.IfaceKind    = Get-AdapterKind $active
        if ($active.LinkSpeed) { $snap.Speed = "$($active.LinkSpeed)" }

        $ipInfo = @(Get-NetIPAddress -InterfaceIndex $active.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' })
        if ($ipInfo.Count -gt 0) {
            $snap.Ip     = "$($ipInfo[0].IPAddress)"
            $snap.Prefix = [int]$ipInfo[0].PrefixLength
            $seg = Get-SegmentInfo $snap.Ip $snap.Prefix
            if ($seg) { $snap.Segment = $seg.Segment; $snap.Broadcast = $seg.Broadcast }
        }

        $hit = @($routes | Where-Object { [int]$_.ifIndex -eq [int]$active.ifIndex })
        if ($hit.Count -gt 0) { $snap.Gateway = "$($hit[0].NextHop)" }
        if (-not $snap.Gateway) {
            try {
                $ipc = Get-NetIPConfiguration -InterfaceIndex $active.ifIndex -ErrorAction SilentlyContinue
                if ($ipc -and $ipc.IPv4DefaultGateway -and $ipc.IPv4DefaultGateway.NextHop) {
                    $snap.Gateway = "$($ipc.IPv4DefaultGateway.NextHop)"
                }
            } catch {}
        }

        try {
            $prof = @(Get-NetConnectionProfile -InterfaceIndex $active.ifIndex -ErrorAction SilentlyContinue)
            if ($prof.Count -gt 0) {
                $snap.ProfileName = "$($prof[0].Name)"
                switch ("$($prof[0].NetworkCategory)") {
                    'DomainAuthenticated' { $snap.Category = 'Dominio' }
                    'Private'             { $snap.Category = 'Privada' }
                    'Public'              { $snap.Category = 'Publica' }
                    default               { $snap.Category = "$($prof[0].NetworkCategory)" }
                }
            }
        } catch {}
        if ($snap.IfaceKind -eq 'Wi-Fi' -and $snap.ProfileName) { $snap.Ssid = $snap.ProfileName }

        try {
            $dns = @(Get-DnsClientServerAddress -InterfaceIndex $active.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
            if ($dns.Count -gt 0 -and $dns[0].ServerAddresses.Count -gt 0) {
                $snap.Dns = (@($dns[0].ServerAddresses | Select-Object -First 2) -join ', ')
            }
        } catch {}

        try {
            $ipif = @(Get-NetIPInterface -InterfaceIndex $active.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
            if ($ipif.Count -gt 0 -and $ipif[0].NlMtu) { $snap.Mtu = "$($ipif[0].NlMtu)" }
        } catch {}

        return $snap
    } catch {
        $snap.Ok = $false
        return $snap
    }
}

function Get-NetClassification($snap, $adaptersUp, $cfg) {
    $offline = @{ Key='offline'; Name='Desconectado de la Red'; Sub='Ninguna interfaz con enlace activo'; Tag='Offline' }
    if (-not $snap.AdapterFound) { return $offline }

    # --- 1) VPN ---
    $vpnConn = @()
    try { $vpnConn = @(Get-VpnConnection -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionStatus -eq 'Connected' }) } catch {}
    $activeTxt = "$($snap.IfaceName) $($snap.IfaceDesc)"
    $activeIsVpn = ($activeTxt -match $cfg.VpnRegex)
    if ($vpnConn.Count -gt 0 -or $activeIsVpn) {
        $name = 'VPN Activa'
        $sub  = "Tunel VPN · $($snap.IfaceDesc)"
        if ($vpnConn.Count -gt 0) {
            $name = "$($vpnConn[0].Name)"
            $sub  = "VPN de Windows · servidor $($vpnConn[0].ServerAddress)"
        } elseif ($snap.IfaceKind -eq 'Ethernet') {
            $sub = "Tunel VPN (adaptador $($snap.IfaceName))"
        }
        return @{ Key='vpn'; Name=$name; Sub=$sub; Tag='Segura' }
    }

    # --- 1b) Puente de Red (bridge de Windows) ---
    if ($activeTxt -match '(?i)(puente de red|network bridge|multiplexor)') {
        return @{ Key='bridge'; Name='Puente de Red (Bridge)'; Sub="Bridge de Windows · adaptador $($snap.IfaceName)"; Tag='Puente' }
    }

    # --- 1c) Etiquetas de subred (VLANs y redes personalizadas) ---
    # Id unico por subred: permite distinguir VLAN1 de VLAN2 en el historial.
    foreach ($lbl in @($cfg.SubnetLabels)) {
        $ls = "$lbl"
        $eq = $ls.IndexOf('=')
        if ($eq -lt 1) { continue }
        $lcidr = $ls.Substring(0, $eq).Trim()
        $lname = $ls.Substring($eq + 1).Trim()
        if (-not $lcidr -or -not $lname) { continue }
        if ((Test-IPInCidr $snap.Ip $lcidr) -or (Test-IPInCidr $snap.Gateway $lcidr)) {
            $segTxt = $snap.Segment; if (-not $segTxt) { $segTxt = $lcidr }
            return @{ Key='label'; Id="label:$lcidr"; Name=$lname; Sub="Etiqueta de subred · $segTxt"; Tag='Etiquetada' }
        }
    }

    # --- 2) Camaras / CCTV ---
    $camHit = $false
    foreach ($subnet in @($cfg.CamerasSubnets)) {
        if ((Test-IPInCidr $snap.Ip $subnet) -or (Test-IPInCidr $snap.Gateway $subnet)) { $camHit = $true; break }
    }
    if ($camHit) {
        return @{ Key='cctv'; Name='VLAN Camaras CCTV / IoT'; Sub="VLAN de camaras · subred restringida ($($snap.Segment))"; Tag='Aislada' }
    }

    # --- 3) Oficina (Ethernet) ---
    $officeSubnets = @($cfg.OfficeSubnets)
    if ($officeSubnets.Count -gt 0) {
        foreach ($subnet in $officeSubnets) {
            if ((Test-IPInCidr $snap.Ip $subnet) -or (Test-IPInCidr $snap.Gateway $subnet)) {
                return @{ Key='office'; Name='Red Oficina'; Sub="Ethernet · $($snap.IfaceDesc)"; Tag='Corporativa' }
            }
        }
    } elseif ($snap.IfaceKind -eq 'Ethernet') {
        return @{ Key='office'; Name='Red Oficina (Ethernet)'; Sub="Cable Ethernet · $($snap.IfaceDesc)"; Tag='Corporativa' }
    }

    # --- 4) Red generica (Wi-Fi u otra no catalogada) ---
    $subTxt = "Conexion $($snap.IfaceKind)"
    if ($snap.Ssid) { $subTxt = "SSID: $($snap.Ssid)" }
    elseif ($snap.ProfileName) { $subTxt = "Perfil: $($snap.ProfileName)" }
    return @{ Key='generic'; Name='Red Detectada (Generica)'; Sub=$subTxt; Tag='No catalogada' }
}

function Get-PublicInfo([int]$timeoutSec) {
    $out = @{ Ip=''; Isp='' }
    try {
        $r = Invoke-RestMethod -Uri 'http://ip-api.com/json/?fields=status,query,isp,org,countryCode,city' -TimeoutSec $timeoutSec -UseBasicParsing
        if ($r -and $r.status -eq 'success') {
            $out.Ip = "$($r.query)"
            $isp = "$($r.isp)"; if (-not $isp) { $isp = "$($r.org)" }
            if ($r.countryCode) { $out.Isp = "$isp ($($r.countryCode))" } else { $out.Isp = $isp }
            return $out
        }
    } catch {}
    try {
        $ip = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec $timeoutSec -UseBasicParsing).ip
        if ($ip) { $out.Ip = "$ip"; $out.Isp = 'ISP no disponible'; return $out }
    } catch {}
    try {
        $ip = (Invoke-WebRequest -Uri 'https://ifconfig.me/ip' -TimeoutSec $timeoutSec -UseBasicParsing).Content.Trim()
        if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') { $out.Ip = "$ip"; $out.Isp = 'ISP no disponible' }
    } catch {}
    return $out
}
'@


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


# ------------------------- XAML DEL WIDGET -------------------------
# Los colores usan DynamicResource: Apply-AppTheme (en _p3b) los cambia en vivo.
# Los valores XAML de fabrica corresponden al tema OSCURO.
$xamlDoc = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Network Sentinel" Width="430" SizeToContent="Height" MaxHeight="900"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" Topmost="False"
        WindowStartupLocation="Manual" FontFamily="Segoe UI" TextOptions.TextFormattingMode="Display"
        UseLayoutRounding="True" SnapsToDevicePixels="True" FontSize="11">
  <Window.Resources>

    <SolidColorBrush x:Key="WinBorder" Color="#28FFFFFF"/>
    <Color x:Key="WinBg1C">#F2151D2B</Color>
    <Color x:Key="WinBg2C">#F20C1119</Color>
    <Color x:Key="WinBg3C">#F2070A10</Color>
    <SolidColorBrush x:Key="HoverOverlay" Color="#1EFFFFFF"/>
    <SolidColorBrush x:Key="CtrlFg" Color="#9AA7B8"/>
    <SolidColorBrush x:Key="CtrlHoverFg" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="CtrlHoverIcon" Color="#67E8F9"/>
    <SolidColorBrush x:Key="PillBg" Color="#CC1B2434"/>
    <SolidColorBrush x:Key="PillBd" Color="#1FFFFFFF"/>
    <SolidColorBrush x:Key="PillHover" Color="#E62A3852"/>
    <SolidColorBrush x:Key="PillFg" Color="#D5DEE9"/>
    <SolidColorBrush x:Key="LinkFg" Color="#7C8AA0"/>
    <SolidColorBrush x:Key="LinkHoverBg" Color="#16FFFFFF"/>
    <SolidColorBrush x:Key="LinkHoverFg" Color="#E2E8F0"/>
    <SolidColorBrush x:Key="CardBg" Color="#C0141B28"/>
    <SolidColorBrush x:Key="CardBd" Color="#16FFFFFF"/>
    <SolidColorBrush x:Key="TextPri" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="TextSoft" Color="#E2E8F0"/>
    <SolidColorBrush x:Key="TextSec" Color="#8FA3B8"/>
    <SolidColorBrush x:Key="TextMut" Color="#7C8AA0"/>
    <SolidColorBrush x:Key="TextFaint" Color="#5F7186"/>
    <SolidColorBrush x:Key="IconCyan" Color="#67E8F9"/>
    <SolidColorBrush x:Key="IconAmber" Color="#FBBF24"/>
    <SolidColorBrush x:Key="IconViolet" Color="#A78BFA"/>
    <SolidColorBrush x:Key="IconGreen" Color="#6EE7B7"/>
    <SolidColorBrush x:Key="IcoBoxBg" Color="#1FA5F3FC"/>
    <SolidColorBrush x:Key="IcoBoxBd" Color="#40A5F3FC"/>
    <SolidColorBrush x:Key="IcoGlyph" Color="#67E8F9"/>
    <SolidColorBrush x:Key="ChipBg" Color="#2681E6FF"/>
    <SolidColorBrush x:Key="ChipBd" Color="#4081E6FF"/>
    <SolidColorBrush x:Key="ChipFg" Color="#9BE7FF"/>
    <SolidColorBrush x:Key="BannerTitle" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="BannerSub" Color="#A9B7C6"/>
    <SolidColorBrush x:Key="PingGwFg" Color="#67E8F9"/>
    <SolidColorBrush x:Key="PingExtFg" Color="#6EE7B7"/>
    <SolidColorBrush x:Key="Divider" Color="#22FFFFFF"/>
    <SolidColorBrush x:Key="HistRowBg" Color="#A6121A26"/>
    <SolidColorBrush x:Key="HistRowBd" Color="#10FFFFFF"/>
    <SolidColorBrush x:Key="HistSwitchFg" Color="#38BDF8"/>
    <SolidColorBrush x:Key="HistAlertFg" Color="#FB7185"/>
    <SolidColorBrush x:Key="LossNoneBg" Color="#14FFFFFF"/>
    <SolidColorBrush x:Key="LossNoneBd" Color="#22FFFFFF"/>
    <SolidColorBrush x:Key="LossNoneFg" Color="#8FA3B8"/>
    <SolidColorBrush x:Key="LossBadBg" Color="#26FB7185"/>
    <SolidColorBrush x:Key="LossBadBd" Color="#55FB7185"/>
    <SolidColorBrush x:Key="LossBadFg" Color="#FDA4AF"/>
    <SolidColorBrush x:Key="LossGoodBg" Color="#2610B981"/>
    <SolidColorBrush x:Key="LossGoodBd" Color="#4010B981"/>
    <SolidColorBrush x:Key="LossGoodFg" Color="#9FF0CE"/>
    <SolidColorBrush x:Key="SparkBase" Color="#2E3B4E"/>
    <SolidColorBrush x:Key="SparkLine" Color="#38BDF8"/>
    <SolidColorBrush x:Key="SparkG1" Color="#4638BDF8"/>
    <SolidColorBrush x:Key="SparkG2" Color="#0538BDF8"/>
    <SolidColorBrush x:Key="ToastBg" Color="#F01A2232"/>
    <SolidColorBrush x:Key="ToastMsg" Color="#C3CFDD"/>
    <SolidColorBrush x:Key="ToastTime" Color="#7C8AA0"/>
    <SolidColorBrush x:Key="PanelBg" Color="#FA0D1119"/>
    <SolidColorBrush x:Key="InputBg" Color="#E6111827"/>
    <SolidColorBrush x:Key="InputBd" Color="#26FFFFFF"/>
    <SolidColorBrush x:Key="OptSelBg" Color="#2638BDF8"/>
    <SolidColorBrush x:Key="OptSelBd" Color="#6638BDF8"/>
    <SolidColorBrush x:Key="OptSelFg" Color="#7DD3FC"/>
    <SolidColorBrush x:Key="PinOnBg" Color="#2638BDF8"/>
    <SolidColorBrush x:Key="PinOnFg" Color="#7DD3FC"/>

    <Style x:Key="TBtn" TargetType="Button">
      <Setter Property="Width" Value="30"/><Setter Property="Height" Value="30"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/><Setter Property="FontSize" Value="11"/>
      <Setter Property="Foreground" Value="{DynamicResource CtrlFg}"/><Setter Property="Background" Value="Transparent"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="8" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="{DynamicResource HoverOverlay}"/>
                <Setter Property="Foreground" Value="{DynamicResource CtrlHoverFg}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="CloseBtnS" TargetType="Button" BasedOn="{StaticResource TBtn}">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="8" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#E81123"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="MiniBtn" TargetType="Button">
      <Setter Property="Width" Value="20"/><Setter Property="Height" Value="18"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/><Setter Property="FontSize" Value="9"/>
      <Setter Property="Foreground" Value="{DynamicResource CtrlFg}"/><Setter Property="Background" Value="Transparent"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="6" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="{DynamicResource HoverOverlay}"/>
                <Setter Property="Foreground" Value="{DynamicResource CtrlHoverIcon}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="PillBtn" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource PillFg}"/><Setter Property="Background" Value="{DynamicResource PillBg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource PillBd}"/>
      <Setter Property="Cursor" Value="Hand"/><Setter Property="FontSize" Value="10.5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="10" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" Padding="10,5">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="{DynamicResource PillHover}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="LinkBtn" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource LinkFg}"/><Setter Property="Background" Value="Transparent"/>
      <Setter Property="Cursor" Value="Hand"/><Setter Property="FontSize" Value="9.5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="6" Background="{TemplateBinding Background}" Padding="7,3">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="{DynamicResource LinkHoverBg}"/>
                <Setter Property="Foreground" Value="{DynamicResource LinkHoverFg}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Card" TargetType="Border">
      <Setter Property="CornerRadius" Value="14"/>
      <Setter Property="Background" Value="{DynamicResource CardBg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource CardBd}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,8"/>
    </Style>

  </Window.Resources>

  <Border x:Name="Root" CornerRadius="22" BorderBrush="{DynamicResource WinBorder}" BorderThickness="1">
    <Border.Background>
      <RadialGradientBrush Center="0.15,0.0" GradientOrigin="0.25,0.08" RadiusX="1.5" RadiusY="1.7">
        <GradientStop Color="{DynamicResource WinBg1C}" Offset="0"/>
        <GradientStop Color="{DynamicResource WinBg2C}" Offset="0.55"/>
        <GradientStop Color="{DynamicResource WinBg3C}" Offset="1"/>
      </RadialGradientBrush>
    </Border.Background>

    <Grid x:Name="RootGrid">
      <Grid Margin="14,10,14,12">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- ===== BARRA DE TITULO ===== -->
        <Grid x:Name="TitleBar" Height="34" Background="Transparent" Grid.Row="0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <Border x:Name="IcoBox" Width="26" Height="26" CornerRadius="8" Background="{DynamicResource IcoBoxBg}" BorderBrush="{DynamicResource IcoBoxBd}" BorderThickness="1">
              <Grid>
                <TextBlock x:Name="IcoGlyph" Text="&#xE704;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource IcoGlyph}"
                           HorizontalAlignment="Center" VerticalAlignment="Center"/>
                <Image x:Name="IcoImg" Width="24" Height="24" Stretch="Uniform" Visibility="Collapsed"/>
              </Grid>
            </Border>
            <TextBlock Text="Network Sentinel" Foreground="{DynamicResource TextPri}" FontWeight="Bold" FontSize="13.5"
                       Margin="8,0,0,0" VerticalAlignment="Center"/>
            <Border Background="{DynamicResource ChipBg}" BorderBrush="{DynamicResource ChipBd}" BorderThickness="1" CornerRadius="6"
                    Padding="5,1" Margin="7,0,0,0" VerticalAlignment="Center">
              <TextBlock x:Name="VersionText" Text="AUTO" Foreground="{DynamicResource ChipFg}" FontSize="9"/>
            </Border>
          </StackPanel>
          <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
            <Button x:Name="SettingsBtn" Style="{StaticResource TBtn}" Content="&#xE713;" ToolTip="Ajustes"/>
            <Button x:Name="PinBtn" Style="{StaticResource TBtn}" Content="&#xE718;" ToolTip="Fijar siempre visible"/>
            <Button x:Name="RefreshBtn" Style="{StaticResource TBtn}" Content="&#xE72C;" ToolTip="Refrescar deteccion ahora"/>
            <Button x:Name="CollapseBtn" Style="{StaticResource TBtn}" Content="&#xE921;" ToolTip="Compactar / Expandir"/>
            <Button x:Name="CloseBtn" Style="{StaticResource CloseBtnS}" Content="&#xE8BB;" ToolTip="Cerrar"/>
          </StackPanel>
        </Grid>

        <!-- ===== BANNER: RED DETECTADA ===== -->
        <Border x:Name="Banner" Grid.Row="1" Margin="0,8,0,0" CornerRadius="16" BorderThickness="1"
                Background="#1F34D399" BorderBrush="#5534D399" Padding="10">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Grid Width="42" Height="42">
              <Border x:Name="BannerIconBox" CornerRadius="12" Background="#2634D399" BorderBrush="#6634D399" BorderThickness="1">
                <TextBlock x:Name="BannerIconGlyph" Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="17"
                           Foreground="#6EE7B7" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <Border x:Name="BannerPulseDot" Width="9" Height="9" CornerRadius="5" Background="#6EE7B7"
                      HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-2,-2,0"/>
            </Grid>
            <StackPanel Grid.Column="1" Margin="10,0,8,0" VerticalAlignment="Center">
              <TextBlock Text="RED DETECTADA" FontSize="8.5" Foreground="{DynamicResource TextSec}" FontWeight="SemiBold"/>
              <TextBlock x:Name="BannerTitle" Text="Detectando..." FontSize="14.5" FontWeight="Bold"
                         Foreground="{DynamicResource BannerTitle}" TextTrimming="CharacterEllipsis"/>
              <TextBlock x:Name="BannerSub" Text="Iniciando monitor de red..." FontSize="10"
                         FontFamily="Cascadia Mono, Consolas" Foreground="{DynamicResource BannerSub}" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
            <StackPanel Grid.Column="2" VerticalAlignment="Center">
              <Border x:Name="TagChip" CornerRadius="9" Padding="8,2" Background="#3D10B981"
                      BorderBrush="#6610B981" BorderThickness="1" HorizontalAlignment="Right">
                <TextBlock x:Name="TagText" Text="---" FontSize="8.5" FontWeight="Bold" Foreground="#C7F9E5"/>
              </Border>
              <TextBlock x:Name="UptimeText" Text="Up: --" FontSize="9.5" FontFamily="Cascadia Mono, Consolas"
                         Foreground="{DynamicResource TextSec}" HorizontalAlignment="Right" Margin="0,4,0,0"/>
              <TextBlock x:Name="UpdatedText" Text="act. --:--:--" FontSize="8.5" FontFamily="Cascadia Mono, Consolas"
                         Foreground="{DynamicResource TextFaint}" HorizontalAlignment="Right" Margin="0,2,0,0"/>
            </StackPanel>
          </Grid>
        </Border>

        <!-- ===== DETALLES (se ocultan al compactar) ===== -->
        <StackPanel x:Name="DetailsHolder" Grid.Row="2">

          <!-- Tarjetas 2x2 -->
          <Grid Margin="0,10,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
            <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>

            <Border Style="{StaticResource Card}" Margin="0,0,5,5">
              <StackPanel>
                <DockPanel LastChildFill="False">
                  <TextBlock Text="&#xE7F4;" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="{DynamicResource IconCyan}" VerticalAlignment="Center"/>
                  <TextBlock Text="TU IP LOCAL" FontSize="9" Foreground="{DynamicResource TextMut}" FontWeight="SemiBold" Margin="5,0,0,0" VerticalAlignment="Center"/>
                  <Button x:Name="CopyIpBtn" DockPanel.Dock="Right" Style="{StaticResource MiniBtn}" Content="&#xE8C8;" ToolTip="Copiar IP local"/>
                </DockPanel>
                <TextBlock x:Name="IpValue" Text="--" FontSize="13" FontWeight="Bold" Foreground="{DynamicResource TextPri}"
                           FontFamily="Cascadia Mono, Consolas" Margin="0,3,0,0" TextTrimming="CharacterEllipsis"/>
                <TextBlock x:Name="IpSub" Text="Iface: --" FontSize="9" FontFamily="Cascadia Mono, Consolas"
                           Foreground="{DynamicResource TextSec}" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" Margin="5,0,0,5" Grid.Column="1">
              <StackPanel>
                <DockPanel LastChildFill="False">
                  <TextBlock Text="&#xE704;" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="{DynamicResource IconAmber}" VerticalAlignment="Center"/>
                  <TextBlock Text="GATEWAY" FontSize="9" Foreground="{DynamicResource TextMut}" FontWeight="SemiBold" Margin="5,0,0,0" VerticalAlignment="Center"/>
                  <Button x:Name="CopyGwBtn" DockPanel.Dock="Right" Style="{StaticResource MiniBtn}" Content="&#xE8C8;" ToolTip="Copiar gateway"/>
                </DockPanel>
                <TextBlock x:Name="GwValue" Text="--" FontSize="13" FontWeight="Bold" Foreground="{DynamicResource TextPri}"
                           FontFamily="Cascadia Mono, Consolas" Margin="0,3,0,0" TextTrimming="CharacterEllipsis"/>
                <TextBlock x:Name="GwSub" Text="MAC: --" FontSize="9" FontFamily="Cascadia Mono, Consolas"
                           Foreground="{DynamicResource TextSec}" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" Margin="0,5,5,0" Grid.Row="1">
              <StackPanel>
                <DockPanel LastChildFill="False">
                  <TextBlock Text="&#xE71B;" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="{DynamicResource IconViolet}" VerticalAlignment="Center"/>
                  <TextBlock Text="SEGMENTO DE RED" FontSize="9" Foreground="{DynamicResource TextMut}" FontWeight="SemiBold" Margin="5,0,0,0" VerticalAlignment="Center"/>
                  <Button x:Name="CopySegBtn" DockPanel.Dock="Right" Style="{StaticResource MiniBtn}" Content="&#xE8C8;" ToolTip="Copiar segmento"/>
                </DockPanel>
                <TextBlock x:Name="SegValue" Text="--" FontSize="12" FontWeight="Bold" Foreground="{DynamicResource TextSoft}"
                           FontFamily="Cascadia Mono, Consolas" Margin="0,3,0,0" TextTrimming="CharacterEllipsis"/>
                <TextBlock x:Name="SegSub" Text="BCast: --" FontSize="9" FontFamily="Cascadia Mono, Consolas"
                           Foreground="{DynamicResource TextSec}" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" Margin="5,5,0,0" Grid.Row="1" Grid.Column="1">
              <StackPanel>
                <DockPanel LastChildFill="False">
                  <TextBlock Text="&#xE774;" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="{DynamicResource IconGreen}" VerticalAlignment="Center"/>
                  <TextBlock Text="IP PUBLICA" FontSize="9" Foreground="{DynamicResource TextMut}" FontWeight="SemiBold" Margin="5,0,0,0" VerticalAlignment="Center"/>
                  <Button x:Name="CopyPubBtn" DockPanel.Dock="Right" Style="{StaticResource MiniBtn}" Content="&#xE8C8;" ToolTip="Copiar IP publica"/>
                </DockPanel>
                <TextBlock x:Name="PubValue" Text="--" FontSize="12" FontWeight="Bold" Foreground="{DynamicResource TextPri}"
                           FontFamily="Cascadia Mono, Consolas" Margin="0,3,0,0" TextTrimming="CharacterEllipsis"/>
                <TextBlock x:Name="PubSub" Text="ISP: --" FontSize="9" Foreground="{DynamicResource TextSec}" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
            </Border>
          </Grid>

          <!-- Tarjeta de ping -->
          <Border Style="{StaticResource Card}" Margin="0,10,0,0">
            <StackPanel>
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal">
                  <StackPanel>
                    <TextBlock Text="PING GW" FontSize="8.5" Foreground="{DynamicResource TextMut}" FontWeight="SemiBold"/>
                    <TextBlock x:Name="GwPingText" Text="-- ms" FontSize="12" FontWeight="Bold"
                               Foreground="{DynamicResource PingGwFg}" FontFamily="Cascadia Mono, Consolas"/>
                  </StackPanel>
                  <Rectangle Width="1" Fill="{DynamicResource Divider}" Margin="14,2,14,2"/>
                  <StackPanel>
                    <TextBlock Text="PING EXT (1.1.1.1)" FontSize="8.5" Foreground="{DynamicResource TextMut}" FontWeight="SemiBold"/>
                    <TextBlock x:Name="ExtPingText" Text="-- ms" FontSize="12" FontWeight="Bold"
                               Foreground="{DynamicResource PingExtFg}" FontFamily="Cascadia Mono, Consolas"/>
                  </StackPanel>
                </StackPanel>
                <Border x:Name="LossChip" Grid.Column="1" CornerRadius="9" Padding="8,2" VerticalAlignment="Center"
                        Background="#2610B981" BorderBrush="#4010B981" BorderThickness="1">
                  <TextBlock x:Name="LossText" Text="0% LOSS" FontSize="9" FontFamily="Cascadia Mono, Consolas" Foreground="#9FF0CE"/>
                </Border>
              </Grid>
              <Canvas x:Name="SparkCanvas" Height="40" Margin="0,8,0,0" ClipToBounds="True"/>
            </StackPanel>
          </Border>

          <!-- Tarjeta de detalles de conexion -->
          <Border Style="{StaticResource Card}" Margin="0,10,0,0">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
              <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
              <StackPanel Margin="0,0,8,6">
                <TextBlock Text="DNS PRIMARIO" FontSize="8.5" Foreground="{DynamicResource TextMut}" FontWeight="SemiBold"/>
                <TextBlock x:Name="DnsText" Text="--" FontSize="10" FontFamily="Cascadia Mono, Consolas"
                           Foreground="{DynamicResource TextSoft}" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
              <StackPanel Grid.Column="1" Margin="0,0,0,6">
                <TextBlock Text="VELOCIDAD DE ENLACE" FontSize="8.5" Foreground="{DynamicResource TextMut}" FontWeight="SemiBold"/>
                <TextBlock x:Name="SpeedText" Text="--" FontSize="10" FontFamily="Cascadia Mono, Consolas"
                           Foreground="{DynamicResource TextSoft}" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
              <StackPanel Grid.Row="1" Margin="0,0,8,0">
                <TextBlock Text="PERFIL DE RED" FontSize="8.5" Foreground="{DynamicResource TextMut}" FontWeight="SemiBold"/>
                <TextBlock x:Name="ProfileText" Text="--" FontSize="10" FontFamily="Cascadia Mono, Consolas"
                           Foreground="{DynamicResource TextSoft}" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
              <StackPanel Grid.Row="1" Grid.Column="1">
                <TextBlock Text="MTU" FontSize="8.5" Foreground="{DynamicResource TextMut}" FontWeight="SemiBold"/>
                <TextBlock x:Name="MtuText" Text="--" FontSize="10" FontFamily="Cascadia Mono, Consolas"
                           Foreground="{DynamicResource TextSoft}" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
            </Grid>
          </Border>

          <!-- Historial -->
          <Grid Margin="0,10,0,0">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/><RowDefinition Height="150"/>
            </Grid.RowDefinitions>
            <DockPanel LastChildFill="False" Margin="2,0,0,4">
              <TextBlock Text="&#xE81C;" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="{DynamicResource TextMut}" VerticalAlignment="Center"/>
              <TextBlock Text="HISTORIAL DE CAMBIOS" FontSize="9.5" FontWeight="SemiBold" Foreground="{DynamicResource TextSec}"
                         Margin="6,0,0,0" VerticalAlignment="Center"/>
              <Button x:Name="ClearBtn" DockPanel.Dock="Right" Style="{StaticResource LinkBtn}" Content="Limpiar"/>
            </DockPanel>
            <ScrollViewer x:Name="HistoryScroll" Grid.Row="1" VerticalScrollBarVisibility="Auto"
                          HorizontalScrollBarVisibility="Disabled" Padding="0,0,4,0">
              <StackPanel x:Name="HistoryPanel"/>
            </ScrollViewer>
          </Grid>

          <!-- Pie -->
          <Grid Margin="0,10,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <Button x:Name="CopyAllBtn" Style="{StaticResource PillBtn}">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE8C8;" FontFamily="Segoe MDL2 Assets" FontSize="10" VerticalAlignment="Center"/>
                <TextBlock Text="Copiar Resumen" Margin="6,0,0,0" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
              <Ellipse x:Name="FooterDot" Width="7" Height="7" Fill="#34D399" VerticalAlignment="Center"/>
              <TextBlock x:Name="FooterText" Text="Escuchando NIC Windows..." FontSize="9" Foreground="{DynamicResource TextMut}"
                         Margin="6,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
          </Grid>

        </StackPanel>
      </Grid>

      <!-- ===== PANEL DE AJUSTES ===== -->
      <Border x:Name="SettingsPanel" Visibility="Collapsed" Margin="14,10,14,12" VerticalAlignment="Top"
              CornerRadius="16" Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource WinBorder}" BorderThickness="1">
        <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="0" Opacity="0.45" Color="#000000"/></Border.Effect>
        <StackPanel Margin="14,10,14,14">
          <DockPanel LastChildFill="False">
            <TextBlock Text="AJUSTES" FontSize="12" FontWeight="Bold" Foreground="{DynamicResource TextPri}" VerticalAlignment="Center"/>
            <TextBlock Text="&#xE713;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource TextMut}"
                       Margin="6,0,0,0" VerticalAlignment="Center"/>
            <Button x:Name="SettingsCloseBtn" DockPanel.Dock="Right" Style="{StaticResource TBtn}" Content="&#xE8BB;" ToolTip="Cerrar ajustes"/>
          </DockPanel>
          <TextBlock Text="Personaliza el widget. Los cambios de tema se guardan solos." FontSize="9"
                     Foreground="{DynamicResource TextMut}" Margin="0,2,0,12" TextWrapping="Wrap"/>

          <TextBlock Text="TEMA" FontSize="8.5" FontWeight="SemiBold" Foreground="{DynamicResource TextMut}"/>
          <WrapPanel Margin="0,5,0,0">
            <Button x:Name="ThemeOptSystem" Style="{StaticResource PillBtn}" Content="Sistema" Tag="system" Margin="0,0,6,6"/>
            <Button x:Name="ThemeOptDark" Style="{StaticResource PillBtn}" Content="Oscuro" Tag="dark" Margin="0,0,6,6"/>
            <Button x:Name="ThemeOptLight" Style="{StaticResource PillBtn}" Content="Claro" Tag="light" Margin="0,0,6,6"/>
            <Button x:Name="ThemeOptDracula" Style="{StaticResource PillBtn}" Content="Dracula" Tag="dracula" Margin="0,0,0,6"/>
          </WrapPanel>

          <TextBlock Text="SUBREDES DE CAMARAS (CCTV)" FontSize="8.5" FontWeight="SemiBold"
                     Foreground="{DynamicResource TextMut}" Margin="0,8,0,0"/>
          <TextBox x:Name="CamSubnetBox" Margin="0,5,0,0" FontFamily="Cascadia Mono, Consolas" FontSize="11"
                   Background="{DynamicResource InputBg}" Foreground="{DynamicResource TextPri}"
                   CaretBrush="{DynamicResource TextPri}" BorderBrush="{DynamicResource InputBd}"
                   BorderThickness="1" Padding="8,6" SelectionBrush="{DynamicResource OptSelBd}"/>
          <TextBlock Text="Formato CIDR, separa varias con comas. Ej: 192.168.100.0/24, 10.10.0.0/16. Vacio = sin deteccion de camaras."
                     FontSize="8.5" Foreground="{DynamicResource TextFaint}" Margin="0,4,0,0" TextWrapping="Wrap"/>

          <TextBlock Text="ETIQUETAS DE SUBRED (VLANs u otras)"
                     FontSize="8.5" FontWeight="SemiBold" Foreground="{DynamicResource TextMut}" Margin="0,10,0,0"/>
          <TextBox x:Name="LabelsBox" Margin="0,5,0,0" Height="56" AcceptsReturn="True" TextWrapping="Wrap"
                   VerticalScrollBarVisibility="Auto" FontFamily="Cascadia Mono, Consolas" FontSize="10"
                   Background="{DynamicResource InputBg}" Foreground="{DynamicResource TextPri}"
                   CaretBrush="{DynamicResource TextPri}" BorderBrush="{DynamicResource InputBd}"
                   BorderThickness="1" Padding="8,6" SelectionBrush="{DynamicResource OptSelBd}"/>
          <TextBlock Text="Una por linea: subred = nombre. Ej: 10.0.1.0/24 = VLAN1 Admin"
                     FontSize="8.5" Foreground="{DynamicResource TextFaint}" Margin="0,4,0,0" TextWrapping="Wrap"/>

          <TextBlock x:Name="SettingsMsg" Text="" FontSize="9" Foreground="#FB7185" Margin="0,8,0,0" TextWrapping="Wrap"/>

          <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
            <Button x:Name="SettingsSaveBtn" Style="{StaticResource PillBtn}" Content="Guardar"/>
            <Button x:Name="SettingsDoneBtn" Style="{StaticResource PillBtn}" Content="Cerrar" Margin="8,0,0,0"/>
          </StackPanel>
        </StackPanel>
      </Border>

      <!-- ===== TOAST ===== -->
      <Border x:Name="Toast" VerticalAlignment="Bottom" HorizontalAlignment="Center" Width="374"
              Margin="0,0,0,12" CornerRadius="14" Background="{DynamicResource ToastBg}" BorderBrush="#5538BDF8"
              BorderThickness="1" Padding="10" Opacity="0" IsHitTestVisible="False">
        <Border.RenderTransform><TranslateTransform x:Name="ToastTT" Y="14"/></Border.RenderTransform>
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Border x:Name="ToastIconBox" Width="34" Height="34" CornerRadius="10" Background="#2638BDF8"
                  BorderBrush="#5538BDF8" BorderThickness="1">
            <TextBlock x:Name="ToastIcon" Text="&#xE774;" FontFamily="Segoe MDL2 Assets" FontSize="13"
                       Foreground="#7DD3FC" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel Grid.Column="1" Margin="9,0,0,0">
            <TextBlock x:Name="ToastTitle" Text="Cambio de Red" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource TextPri}"/>
            <TextBlock x:Name="ToastMsg" Text="--" FontSize="10" Foreground="{DynamicResource ToastMsg}" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="ToastTime" Text="Ahora" FontSize="8.5" Foreground="{DynamicResource ToastTime}" FontFamily="Cascadia Mono, Consolas"/>
          </StackPanel>
        </Grid>
      </Border>

    </Grid>
  </Border>
</Window>
'@

$XamlSrc = $xamlDoc


# ------------------------- ARRANQUE DE LA UI -------------------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

# Estilo extendido WS_EX_TOOLWINDOW (oculta de Alt+Tab y barra de tareas)
try {
    Add-Type -Namespace NSNative -Name W32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int nValue);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
} catch {}

# Instancia unica
$script:AppMutex = New-Object System.Threading.Mutex($false, 'Local\NetworkSentinel_Widget_v3')
$hasMutex = $false
try { $hasMutex = $script:AppMutex.WaitOne(0) } catch { $hasMutex = $true }
if (-not $hasMutex) { exit 0 }

$Window = [System.Windows.Markup.XamlReader]::Parse($XamlSrc)

# Mapa de elementos de la interfaz (permite asignar propiedades y eventos)
$script:BC = New-Object System.Windows.Media.BrushConverter
function Br([string]$h) { return [System.Windows.Media.Brush]$script:BC.ConvertFromString($h) }

$UI = @{}
$uiNames = @(
    'TitleBar','IcoBox','IcoGlyph','IcoImg','Banner','PinBtn','RefreshBtn','CollapseBtn','CloseBtn',
    'SettingsBtn','SettingsPanel','SettingsCloseBtn','SettingsDoneBtn','SettingsSaveBtn','SettingsMsg','CamSubnetBox','LabelsBox',
    'ThemeOptSystem','ThemeOptDark','ThemeOptLight','ThemeOptDracula',
    'BannerTitle','BannerSub','TagChip','TagText','BannerIconBox','BannerIconGlyph','BannerPulseDot',
    'UptimeText','UpdatedText','DetailsHolder',
    'IpValue','IpSub','GwValue','GwSub','SegValue','SegSub','PubValue','PubSub',
    'GwPingText','ExtPingText','LossChip','LossText','SparkCanvas',
    'DnsText','SpeedText','ProfileText','MtuText',
    'HistoryPanel','HistoryScroll','ClearBtn','CopyAllBtn',
    'CopyIpBtn','CopyGwBtn','CopySegBtn','CopyPubBtn',
    'FooterDot','FooterText',
    'Toast','ToastTT','ToastIconBox','ToastIcon','ToastTitle','ToastMsg','ToastTime'
)
foreach ($nm in $uiNames) {
    try { $UI[$nm] = $Window.FindName($nm) } catch { $UI[$nm] = $null }
}

# ------------------------- ICONO DE LA APP -------------------------
# Si hay NetworkSentinel.ico junto al script: icono de ventana + barra de titulo.
# Si falta o falla la carga, se mantiene el glifo por defecto.
try {
    $icoPath = Join-Path $ScriptDir 'NetworkSentinel.ico'
    if (Test-Path $icoPath) {
        $bmpIco = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmpIco.BeginInit()
        $bmpIco.UriSource = New-Object System.Uri($icoPath)
        $bmpIco.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmpIco.EndInit()
        $bmpIco.Freeze()
        $Window.Icon = $bmpIco
        if ($UI['IcoImg']) { $UI['IcoImg'].Source = $bmpIco; $UI['IcoImg'].Visibility = 'Visible' }
        if ($UI['IcoGlyph']) { $UI['IcoGlyph'].Visibility = 'Collapsed' }
        if ($UI['IcoBox']) {
            $UI['IcoBox'].Background = [System.Windows.Media.Brushes]::Transparent
            $UI['IcoBox'].BorderBrush = [System.Windows.Media.Brushes]::Transparent
        }
    }
} catch {}

# ------------------------- TEMAS POR TIPO DE RED -------------------------
# iconFgL / tagFgL: variantes (mas oscuras) para el tema CLARO.
$ThemeMap = @{
    vpn = @{ ch=[char]0xE72E; accent='#34D399'; bannerBg='#1F34D399'; bannerBd='#5534D399';
             iconBg='#2634D399'; iconBd='#6634D399'; iconFg='#6EE7B7'; iconFgL='#059669'; pulse='#6EE7B7';
             tagBg='#3D10B981'; tagBd='#6610B981'; tagFg='#C7F9E5'; tagFgL='#065F46' }
    office = @{ ch=[char]0xE839; accent='#38BDF8'; bannerBg='#1F38BDF8'; bannerBd='#5538BDF8';
             iconBg='#2638BDF8'; iconBd='#6638BDF8'; iconFg='#7DD3FC'; iconFgL='#0284C7'; pulse='#7DD3FC';
             tagBg='#3D0EA5E9'; tagBd='#660EA5E9'; tagFg='#C9EFFF'; tagFgL='#075985' }
    cctv = @{ ch=[char]0xE714; accent='#A78BFA'; bannerBg='#1FA78BFA'; bannerBd='#55A78BFA';
             iconBg='#26A78BFA'; iconBd='#66A78BFA'; iconFg='#C4B5FD'; iconFgL='#7C3AED'; pulse='#C4B5FD';
             tagBg='#3D8B5CF6'; tagBd='#668B5CF6'; tagFg='#E4D9FF'; tagFgL='#5B21B6' }
    generic = @{ ch=[char]0xE774; accent='#60A5FA'; bannerBg='#1F60A5FA'; bannerBd='#5560A5FA';
             iconBg='#2660A5FA'; iconBd='#6660A5FA'; iconFg='#93C5FD'; iconFgL='#2563EB'; pulse='#93C5FD';
             tagBg='#3D3B82F6'; tagBd='#663B82F6'; tagFg='#D7E6FF'; tagFgL='#1E40AF' }
    offline = @{ ch=[char]0xE733; accent='#FB7185'; bannerBg='#1FFB7185'; bannerBd='#55FB7185';
             iconBg='#26FB7185'; iconBd='#66FB7185'; iconFg='#FDA4AF'; iconFgL='#E11D48'; pulse='#FDA4AF';
             tagBg='#3DF43F5E'; tagBd='#66F43F5E'; tagFg='#FFD9DF'; tagFgL='#9F1239' }
    label = @{ ch=[char]0xE8EC; accent='#FBBF24'; bannerBg='#1FFBBF24'; bannerBd='#55FBBF24';
             iconBg='#26FBBF24'; iconBd='#66FBBF24'; iconFg='#FCD34D'; iconFgL='#B45309'; pulse='#FCD34D';
             tagBg='#3DF59E0B'; tagBd='#66F59E0B'; tagFg='#FDE9B8'; tagFgL='#92400E' }
    bridge = @{ ch=[char]0xE71B; accent='#2DD4BF'; bannerBg='#1F2DD4BF'; bannerBd='#552DD4BF';
             iconBg='#262DD4BF'; iconBd='#662DD4BF'; iconFg='#5EEAD4'; iconFgL='#0F766E'; pulse='#5EEAD4';
             tagBg='#3D14B8A6'; tagBd='#6614B8A6'; tagFg='#C7F5EE'; tagFgL='#115E59' }
}

# ------------------------- TEMAS DE APLICACION (oscuro / claro / dracula / sistema) -------------------------
# Paletas de la interfaz. Claves terminadas en C = Color (para el degradado); el resto, brushes.
$AppThemes = @{
    dark = @{
        WinBorder='#28FFFFFF'; WinBg1C='#F2151D2B'; WinBg2C='#F20C1119'; WinBg3C='#F2070A10'
        HoverOverlay='#1EFFFFFF'; CtrlFg='#9AA7B8'; CtrlHoverFg='#FFFFFF'; CtrlHoverIcon='#67E8F9'
        PillBg='#CC1B2434'; PillBd='#1FFFFFFF'; PillHover='#E62A3852'; PillFg='#D5DEE9'
        LinkFg='#7C8AA0'; LinkHoverBg='#16FFFFFF'; LinkHoverFg='#E2E8F0'
        CardBg='#C0141B28'; CardBd='#16FFFFFF'
        TextPri='#FFFFFF'; TextSoft='#E2E8F0'; TextSec='#8FA3B8'; TextMut='#7C8AA0'; TextFaint='#5F7186'
        IconCyan='#67E8F9'; IconAmber='#FBBF24'; IconViolet='#A78BFA'; IconGreen='#6EE7B7'
        IcoBoxBg='#1FA5F3FC'; IcoBoxBd='#40A5F3FC'; IcoGlyph='#67E8F9'
        ChipBg='#2681E6FF'; ChipBd='#4081E6FF'; ChipFg='#9BE7FF'
        BannerTitle='#FFFFFF'; BannerSub='#A9B7C6'
        PingGwFg='#67E8F9'; PingExtFg='#6EE7B7'; Divider='#22FFFFFF'
        HistRowBg='#A6121A26'; HistRowBd='#10FFFFFF'; HistSwitchFg='#38BDF8'; HistAlertFg='#FB7185'
        LossNoneBg='#14FFFFFF'; LossNoneBd='#22FFFFFF'; LossNoneFg='#8FA3B8'
        LossBadBg='#26FB7185'; LossBadBd='#55FB7185'; LossBadFg='#FDA4AF'
        LossGoodBg='#2610B981'; LossGoodBd='#4010B981'; LossGoodFg='#9FF0CE'
        SparkBase='#2E3B4E'; SparkLine='#38BDF8'; SparkG1='#4638BDF8'; SparkG2='#0538BDF8'
        ToastBg='#F01A2232'; ToastMsg='#C3CFDD'; ToastTime='#7C8AA0'
        PanelBg='#FA0D1119'; InputBg='#E6111827'; InputBd='#26FFFFFF'
        OptSelBg='#2638BDF8'; OptSelBd='#6638BDF8'; OptSelFg='#7DD3FC'
        PinOnBg='#2638BDF8'; PinOnFg='#7DD3FC'
    }
    light = @{
        WinBorder='#D7DEE8'; WinBg1C='#F6FAFCFF'; WinBg2C='#F6F1F5FA'; WinBg3C='#F6E9EEF5'
        HoverOverlay='#140F172A'; CtrlFg='#475569'; CtrlHoverFg='#0F172A'; CtrlHoverIcon='#0284C7'
        PillBg='#F1F5F9'; PillBd='#CBD5E1'; PillHover='#E2E8F0'; PillFg='#334155'
        LinkFg='#64748B'; LinkHoverBg='#E2E8F0'; LinkHoverFg='#0F172A'
        CardBg='#F2FFFFFF'; CardBd='#E2E8F0'
        TextPri='#0F172A'; TextSoft='#1E293B'; TextSec='#475569'; TextMut='#64748B'; TextFaint='#94A3B8'
        IconCyan='#0284C7'; IconAmber='#D97706'; IconViolet='#7C3AED'; IconGreen='#059669'
        IcoBoxBg='#DBEAFE'; IcoBoxBd='#93C5FD'; IcoGlyph='#0284C7'
        ChipBg='#DBEAFE'; ChipBd='#93C5FD'; ChipFg='#1D4ED8'
        BannerTitle='#0F172A'; BannerSub='#475569'
        PingGwFg='#0284C7'; PingExtFg='#059669'; Divider='#E2E8F0'
        HistRowBg='#F5FFFFFF'; HistRowBd='#E2E8F0'; HistSwitchFg='#0284C7'; HistAlertFg='#BE123C'
        LossNoneBg='#F1F5F9'; LossNoneBd='#E2E8F0'; LossNoneFg='#64748B'
        LossBadBg='#FFE4E6'; LossBadBd='#FDA4AF'; LossBadFg='#BE123C'
        LossGoodBg='#D1FAE5'; LossGoodBd='#6EE7B7'; LossGoodFg='#047857'
        SparkBase='#CBD5E1'; SparkLine='#0284C7'; SparkG1='#460284C7'; SparkG2='#050284C7'
        ToastBg='#F7FFFFFF'; ToastMsg='#475569'; ToastTime='#64748B'
        PanelBg='#FEF8FAFC'; InputBg='#FFFFFFFF'; InputBd='#CBD5E1'
        OptSelBg='#DBEAFE'; OptSelBd='#60A5FA'; OptSelFg='#1D4ED8'
        PinOnBg='#DBEAFE'; PinOnFg='#1D4ED8'
    }
    dracula = @{
        WinBorder='#2E3142'; WinBg1C='#F22B2D3C'; WinBg2C='#F2212230'; WinBg3C='#F21A1B24'
        HoverOverlay='#1FFFFFFF'; CtrlFg='#A2A2BE'; CtrlHoverFg='#F8F8F2'; CtrlHoverIcon='#8BE9FD'
        PillBg='#CC2A2C3A'; PillBd='#2A2E3F'; PillHover='#E6404358'; PillFg='#D8D8E8'
        LinkFg='#8B8BA6'; LinkHoverBg='#1FFFFFFF'; LinkHoverFg='#F8F8F2'
        CardBg='#C02A2C3A'; CardBd='#16FFFFFF'
        TextPri='#F8F8F2'; TextSoft='#E6E6F0'; TextSec='#B4B4CC'; TextMut='#9A9AB5'; TextFaint='#6C6C85'
        IconCyan='#8BE9FD'; IconAmber='#FFB86C'; IconViolet='#BD93F9'; IconGreen='#50FA7B'
        IcoBoxBg='#2ABD93F9'; IcoBoxBd='#55BD93F9'; IcoGlyph='#D7BFFF'
        ChipBg='#2ABD93F9'; ChipBd='#55BD93F9'; ChipFg='#D7BFFF'
        BannerTitle='#F8F8F2'; BannerSub='#B8B8CC'
        PingGwFg='#8BE9FD'; PingExtFg='#50FA7B'; Divider='#2A2E3F'
        HistRowBg='#CC232532'; HistRowBd='#14FFFFFF'; HistSwitchFg='#8BE9FD'; HistAlertFg='#FF5555'
        LossNoneBg='#14FFFFFF'; LossNoneBd='#22FFFFFF'; LossNoneFg='#9A9AB5'
        LossBadBg='#26FF5555'; LossBadBd='#55FF5555'; LossBadFg='#FFB3B3'
        LossGoodBg='#2650FA7B'; LossGoodBd='#5550FA7B'; LossGoodFg='#B8FFCB'
        SparkBase='#3A3F55'; SparkLine='#8BE9FD'; SparkG1='#468BE9FD'; SparkG2='#058BE9FD'
        ToastBg='#F0232530'; ToastMsg='#C8C8DC'; ToastTime='#9A9AB5'
        PanelBg='#FA21222C'; InputBg='#E62A2C3A'; InputBd='#2A2E3F'
        OptSelBg='#2ABD93F9'; OptSelBd='#66BD93F9'; OptSelFg='#D7BFFF'
        PinOnBg='#2ABD93F9'; PinOnFg='#D7BFFF'
    }
}

$script:AppThemeKey    = 'dark'   # seleccion logica: system | dark | light | dracula
$script:EffectiveTheme = 'dark'   # tema realmente pintado (resuelve 'system')
$script:Pal            = $AppThemes['dark']

function Col([string]$h) { return [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($h) }
function PAL([string]$k) { try { return (Br "$($script:Pal[$k])") } catch { return (Br '#888888') } }
function PalC([string]$k) { try { return (Col "$($script:Pal[$k])") } catch { return (Col '#888888') } }

function Resolve-SystemTheme {
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme
        if ([int]$v -eq 1) { return 'light' }
    } catch {}
    return 'dark'
}

# Tema visual para una clave de red. Soporta ids compuestos ('label:10.0.1.0/24').
function Get-NetTheme([string]$key) {
    $th = $ThemeMap["$key"]
    if (-not $th -and $key -and $key.Contains(':')) { $th = $ThemeMap[$key.Split(':')[0]] }
    if (-not $th) { $th = $ThemeMap['generic'] }
    return $th
}

# ------------------------- ESTADO DE LA UI -------------------------
$script:ActiveKey   = ''
$script:ActiveName  = ''
$script:ActiveGw    = ''
$script:PendingKey  = ''
$script:PendingCount = 0
$script:StateSince  = $null
$script:LastVersion = -1
$script:History     = @()
$script:Collapsed   = $false
$script:WorkerRestarts = @()
$script:SysThemeTick = 0
$script:ToastTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ToastTimer.Interval = [TimeSpan]::FromMilliseconds(4200)

# ------------------------- TOAST -------------------------
function Hide-Toast {
    try {
        $t = $UI['Toast']; $tt = $UI['ToastTT']
        $t.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
        $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
        $t.Opacity = 0; $tt.Y = 14
    } catch {}
}

function Show-Toast([string]$title, [string]$msg, [string]$glyph, [string]$key) {
    try {
        $th = Get-NetTheme $key
        $t = $UI['Toast']; $tt = $UI['ToastTT']
        $UI['ToastTitle'].Text = $title
        $UI['ToastMsg'].Text = $msg
        $UI['ToastTime'].Text = 'Ahora - ' + (Get-Date).ToString('HH:mm:ss')
        $UI['ToastIcon'].Text = $glyph
        $icoFg = $th.iconFg; if ($script:EffectiveTheme -eq 'light' -and $th.iconFgL) { $icoFg = $th.iconFgL }
        $UI['ToastIcon'].Foreground = Br $icoFg
        $UI['ToastIconBox'].Background = Br $th.iconBg
        $UI['ToastIconBox'].BorderBrush = Br $th.iconBd
        $t.BorderBrush = Br $th.bannerBd
        $t.Opacity = 0; $tt.Y = 14
        $a1 = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, 1.0, [TimeSpan]::FromMilliseconds(200))
        $t.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a1)
        $a2 = New-Object System.Windows.Media.Animation.DoubleAnimation(14.0, 0.0, [TimeSpan]::FromMilliseconds(220))
        $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $a2)
        $script:ToastTimer.Stop(); $script:ToastTimer.Start()
    } catch {}
}

# ------------------------- HISTORIAL -------------------------
function New-HistoryRow($e) {
    $row = New-Object System.Windows.Controls.Border
    $row.CornerRadius = New-Object System.Windows.CornerRadius(10)
    $row.Background = PAL 'histRowBg'
    $row.BorderBrush = PAL 'histRowBd'
    $row.BorderThickness = New-Object System.Windows.Thickness(1)
    $row.Padding = New-Object System.Windows.Thickness(8,5,8,5)
    $row.Margin = New-Object System.Windows.Thickness(0,0,0,4)

    $g = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = 'Auto'
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = '*'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'
    [void]$g.ColumnDefinitions.Add($c0); [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)

    $st = "$($e.status)"
    $icon = New-Object System.Windows.Controls.TextBlock
    $icon.FontFamily = 'Segoe MDL2 Assets'; $icon.FontSize = 9
    $icon.VerticalAlignment = 'Center'; $icon.Margin = New-Object System.Windows.Thickness(0,0,6,0)
    if ($st -eq 'alert') { $icon.Text = [string][char]0xE7BA; $icon.Foreground = PAL 'histAlertFg' }
    elseif ($st -eq 'info') { $icon.Text = [string][char]0xE946; $icon.Foreground = PAL 'textSec' }
    else { $icon.Text = [string][char]0xE72A; $icon.Foreground = PAL 'histSwitchFg' }
    [System.Windows.Controls.Grid]::SetColumn($icon, 0)
    [void]$g.Children.Add($icon)

    $msg = New-Object System.Windows.Controls.TextBlock
    $msg.FontSize = 9.5; $msg.TextTrimming = 'CharacterEllipsis'; $msg.VerticalAlignment = 'Center'
    $r1 = New-Object System.Windows.Documents.Run("$($e.from)")
    $r1.Foreground = PAL 'textSec'
    $r2 = New-Object System.Windows.Documents.Run(' ' + [string][char]0xE72A + ' ')
    $r2.FontFamily = 'Segoe MDL2 Assets'; $r2.FontSize = 8; $r2.Foreground = PAL 'textFaint'
    $r3 = New-Object System.Windows.Documents.Run("$($e.to)")
    $r3.Foreground = PAL 'textPri'; $r3.FontWeight = 'Bold'
    [void]$msg.Inlines.Add($r1); [void]$msg.Inlines.Add($r2); [void]$msg.Inlines.Add($r3)
    [System.Windows.Controls.Grid]::SetColumn($msg, 1)
    [void]$g.Children.Add($msg)

    $tm = New-Object System.Windows.Controls.TextBlock
    $timeTxt = "$($e.time)"
    $today = (Get-Date).ToString('yyyy-MM-dd')
    if ("$($e.date)" -and "$($e.date)" -ne $today) { $timeTxt = ("$($e.date)").Substring(5) + " $timeTxt" }
    $tm.Text = $timeTxt
    $tm.FontFamily = 'Cascadia Mono, Consolas'; $tm.FontSize = 8.5
    $tm.Foreground = PAL 'textFaint'; $tm.VerticalAlignment = 'Center'
    $tm.Margin = New-Object System.Windows.Thickness(8,0,0,0)
    [System.Windows.Controls.Grid]::SetColumn($tm, 2)
    [void]$g.Children.Add($tm)

    $row.Child = $g
    return $row
}

function Add-UIHistoryRow($entry, [bool]$top) {
    try {
        $panel = $UI['HistoryPanel']
        $rowEl = New-HistoryRow $entry
        if ($top) { $panel.Children.Insert(0, $rowEl) } else { [void]$panel.Children.Add($rowEl) }
        while ($panel.Children.Count -gt 60) { $panel.Children.RemoveAt($panel.Children.Count - 1) }
    } catch {}
}

function Add-HistoryEntry($entry) {
    $merged = @($entry) + @($script:History)
    $script:History = @(Expand-HistoryEntries $merged | Where-Object { Test-HistoryEntry $_ })
    if ($script:History.Count -gt $Cfg.MaxHistory) { $script:History = @($script:History[0..($Cfg.MaxHistory - 1)]) }
    Save-History $script:History
    Add-UIHistoryRow $entry $true
}

function New-LogEntry([string]$from, [string]$to, [string]$status) {
    $now = Get-Date
    return [pscustomobject]@{
        time   = $now.ToString('HH:mm:ss')
        date   = $now.ToString('yyyy-MM-dd')
        from   = $from
        to     = $to
        status = $status
    }
}

# ------------------------- TEMAS: APLICACION Y REPINTADO -------------------------
function Update-ThemeOptUI {
    try {
        $names = @{ system = 'Sistema'; dark = 'Oscuro'; light = 'Claro'; dracula = 'Dracula' }
        $btns  = @{ system = 'ThemeOptSystem'; dark = 'ThemeOptDark'; light = 'ThemeOptLight'; dracula = 'ThemeOptDracula' }
        foreach ($k in @('system','dark','light','dracula')) {
            $btn = $UI[$btns[$k]]; if (-not $btn) { continue }
            if ($script:AppThemeKey -eq $k) {
                $btn.Background = PAL 'optSelBg'; $btn.BorderBrush = PAL 'optSelBd'; $btn.Foreground = PAL 'optSelFg'
                $btn.Content = ([string][char]0x25CF) + ' ' + $names[$k]
            } else {
                $btn.Background = Br 'Transparent'; $btn.BorderBrush = PAL 'pillBd'; $btn.Foreground = PAL 'textSec'
                $btn.Content = $names[$k]
            }
        }
    } catch {}
}

function Rebuild-HistoryRows {
    try {
        $panel = $UI['HistoryPanel']; if (-not $panel) { return }
        $panel.Children.Clear()
        $n = [Math]::Min(60, @($script:History).Count)
        for ($i = 0; $i -lt $n; $i++) { Add-UIHistoryRow $script:History[$i] $false }
    } catch {}
}

function Apply-AppTheme([string]$key) {
    try {
        if (-not $key) { $key = 'dark' }
        $eff = $key
        if ($key -eq 'system') { $eff = Resolve-SystemTheme }
        if (-not $AppThemes.ContainsKey($eff)) { $eff = 'dark' }
        $script:AppThemeKey = $key
        $script:EffectiveTheme = $eff
        $pal = $AppThemes[$eff]
        $script:Pal = $pal
        foreach ($k in $pal.Keys) {
            try {
                if ("$k".EndsWith('C')) { $Window.Resources[$k] = Col "$($pal[$k])" }
                else { $Window.Resources[$k] = Br "$($pal[$k])" }
            } catch {}
        }
        Update-ThemeOptUI
        Rebuild-HistoryRows
        if ($script:ActiveKey) { Apply-Theme $script:ActiveKey }
        Update-FromState
        Update-Spark
        Set-PinState ([bool]$Window.Topmost)
    } catch {}
}

# ------------------------- CAMBIO DE RED (con confirmacion x2) -------------------------
function Apply-Theme([string]$key) {
    try {
        $th = Get-NetTheme $key
        $UI['Banner'].Background = Br $th.bannerBg
        $UI['Banner'].BorderBrush = Br $th.bannerBd
        $UI['BannerIconBox'].Background = Br $th.iconBg
        $UI['BannerIconBox'].BorderBrush = Br $th.iconBd
        $UI['BannerIconGlyph'].Text = [string]$th.ch
        $icoFg = $th.iconFg; if ($script:EffectiveTheme -eq 'light' -and $th.iconFgL) { $icoFg = $th.iconFgL }
        $UI['BannerIconGlyph'].Foreground = Br $icoFg
        $UI['BannerPulseDot'].Background = Br $th.pulse
        $UI['FooterDot'].Fill = Br $th.accent
        $UI['TagChip'].Background = Br $th.tagBg
        $UI['TagChip'].BorderBrush = Br $th.tagBd
        $tagFg = $th.tagFg; if ($script:EffectiveTheme -eq 'light' -and $th.tagFgL) { $tagFg = $th.tagFgL }
        $UI['TagText'].Foreground = Br $tagFg
    } catch {}
}

function Flash-Banner {
    try {
        $box = $UI['BannerIconBox']
        $sc = New-Object System.Windows.Media.ScaleTransform(1.0, 1.0)
        $box.RenderTransform = $sc
        $box.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
        $an1 = New-Object System.Windows.Media.Animation.DoubleAnimation(0.82, 1.0, [TimeSpan]::FromMilliseconds(280))
        $an2 = New-Object System.Windows.Media.Animation.DoubleAnimation(0.82, 1.0, [TimeSpan]::FromMilliseconds(280))
        $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $an1)
        $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $an2)
    } catch {}
}

function Apply-KeyChange([string]$newKey) {
    try {
        $isFirst = ($script:ActiveKey -eq '')
        $newName = "$($State.Name)"
        $newGw = "$($State.Gateway)"
        if (-not $newGw) { $newGw = "$($State.Ip)" }
        if (-not $newGw) { $newGw = 'sin datos' }

        if ($isFirst) {
            $e = New-LogEntry '(inicio)' "$newName ($newGw)" 'info'
            Add-HistoryEntry $e
        } else {
            $prevName = $script:ActiveName
            if (-not $prevName) { $prevName = $script:ActiveKey }
            $prevGw = $script:ActiveGw
            $fromTxt = "$prevName ($prevGw)"
            $toTxt = "$newName ($newGw)"
            if ($newKey -eq 'offline') {
                $e = New-LogEntry $fromTxt $toTxt 'alert'
                Add-HistoryEntry $e
                Show-Toast 'Red Desconectada' "Sin conexion activa | Ultima red: $prevName" ([string][char]0xE733) $newKey
            } else {
                $e = New-LogEntry $fromTxt $toTxt 'switch'
                Add-HistoryEntry $e
                $msg = "Ahora en: $newName | GW: $newGw"
                if ($State.Ip) { $msg += " | IP: $($State.Ip)" }
                Show-Toast 'Cambio de Red Detectado' $msg ([string](Get-NetTheme $newKey).ch) $newKey
            }
            Flash-Banner
        }

        $script:ActiveKey = $newKey
        $script:ActiveName = $newName
        $script:ActiveGw = $newGw
        $script:StateSince = Get-Date
        $script:PendingKey = ''; $script:PendingCount = 0
        Apply-Theme $newKey
    } catch {}
}

# ------------------------- ACTUALIZACION DE LA UI -------------------------
function Update-FromState {
    $key = "$($State.RawKey)"
    if (-not $key) { return }

    if ($key -ne $script:ActiveKey) {
        if ($key -eq $script:PendingKey) { $script:PendingCount++ } else { $script:PendingKey = $key; $script:PendingCount = 1 }
        if ($script:ActiveKey -eq '' -or $script:PendingCount -ge 2) { Apply-KeyChange $key }
    } else { $script:PendingCount = 0 }

    try {
        $UI['BannerTitle'].Text = "$($State.Name)"
        $UI['BannerSub'].Text = "$($State.Sub)"
        $UI['TagText'].Text = ("$($State.Tag)").ToUpper()

        $ipTxt = '--'
        if ($State.Ip) { $ipTxt = "$($State.Ip)/$($State.Prefix)" }
        $UI['IpValue'].Text = $ipTxt
        $ifSub = 'Iface: --'
        if ($State.IfaceName) {
            $ifSub = "Iface: $($State.IfaceName)"
            if ($State.Speed) { $ifSub += " · $($State.Speed)" }
        }
        $UI['IpSub'].Text = $ifSub

        if ($State.Gateway) { $UI['GwValue'].Text = "$($State.Gateway)" } else { $UI['GwValue'].Text = '--' }
        if ($State.GwMac) { $UI['GwSub'].Text = "MAC: $($State.GwMac)" } else { $UI['GwSub'].Text = 'MAC: --' }

        if ($State.Segment) { $UI['SegValue'].Text = "$($State.Segment)" } else { $UI['SegValue'].Text = '--' }
        if ($State.Broadcast) { $UI['SegSub'].Text = "BCast: $($State.Broadcast)" } else { $UI['SegSub'].Text = 'BCast: --' }

        if (-not $State.AdapterFound) {
            $UI['PubValue'].Text = 'Desconectado'; $UI['PubSub'].Text = 'Sin acceso a Internet'
        } elseif ($State.PubIp) {
            $UI['PubValue'].Text = "$($State.PubIp)"
            if ($State.Isp) { $UI['PubSub'].Text = "ISP: $($State.Isp)" } else { $UI['PubSub'].Text = 'ISP: --' }
        } else {
            $UI['PubValue'].Text = 'Sin salida'; $UI['PubSub'].Text = 'NAT no disponible'
        }

        if ($null -eq $State.GwPing -or -not $State.AdapterFound) { $UI['GwPingText'].Text = '--' } else { $UI['GwPingText'].Text = "$($State.GwPing) ms" }
        if ($null -eq $State.ExtPing -or -not $State.AdapterFound) { $UI['ExtPingText'].Text = 'Timeout' } else { $UI['ExtPingText'].Text = "$($State.ExtPing) ms" }

        if (-not $State.AdapterFound) {
            $UI['LossText'].Text = 'SIN ENLACE'
            $UI['LossChip'].Background = PAL 'lossNoneBg'; $UI['LossChip'].BorderBrush = PAL 'lossNoneBd'; $UI['LossText'].Foreground = PAL 'lossNoneFg'
        } elseif ([int]$State.LossPct -ge 1) {
            $UI['LossText'].Text = "$($State.LossPct)% LOSS"
            $UI['LossChip'].Background = PAL 'lossBadBg'; $UI['LossChip'].BorderBrush = PAL 'lossBadBd'; $UI['LossText'].Foreground = PAL 'lossBadFg'
        } else {
            $UI['LossText'].Text = '0% LOSS'
            $UI['LossChip'].Background = PAL 'lossGoodBg'; $UI['LossChip'].BorderBrush = PAL 'lossGoodBd'; $UI['LossText'].Foreground = PAL 'lossGoodFg'
        }

        if ($State.Dns) { $UI['DnsText'].Text = "$($State.Dns)" } else { $UI['DnsText'].Text = '--' }
        if ($State.Speed) { $UI['SpeedText'].Text = "$($State.Speed)" } else { $UI['SpeedText'].Text = '--' }
        $profTxt = '--'
        if ($State.Ssid) { $profTxt = "$($State.Ssid)" }
        elseif ($State.ProfileName) { $profTxt = "$($State.ProfileName)" }
        if ($State.Category) { $profTxt = "$profTxt · $($State.Category)" }
        $UI['ProfileText'].Text = $profTxt
        if ($State.Mtu) { $UI['MtuText'].Text = "$($State.Mtu)" } else { $UI['MtuText'].Text = '--' }

        $UI['UpdatedText'].Text = "act. $($State.LastUpdate)"
    } catch {}
}

function Update-Clocks {
    try {
        if ($script:StateSince) {
            $d = (Get-Date) - $script:StateSince
            $t = ''
            if ($d.TotalDays -ge 1) { $t = '{0}d {1:00}h' -f [int]$d.TotalDays, $d.Hours }
            elseif ($d.TotalHours -ge 1) { $t = '{0}h {1:00}m' -f [int]$d.TotalHours, $d.Minutes }
            elseif ($d.TotalMinutes -ge 1) { $t = '{0}m {1:00}s' -f [int]$d.TotalMinutes, $d.Seconds }
            else { $t = '{0}s' -f [int]$d.TotalSeconds }
            $UI['UptimeText'].Text = "Up: $t"
        }
    } catch {}
}

function Update-Spark {
    try {
        $c = $UI['SparkCanvas']; if (-not $c) { return }
        $c.Children.Clear()
        $w = $c.ActualWidth; if ($w -lt 40) { $w = 380 }
        $h = 40
        $samples = @($State.Spark)
        if ($samples.Count -lt 2) {
            $line = New-Object System.Windows.Shapes.Line
            $line.X1 = 2; $line.X2 = $w - 2; $line.Y1 = $h - 3; $line.Y2 = $h - 3
            $line.Stroke = PAL 'sparkBase'; $line.StrokeThickness = 1
            [void]$c.Children.Add($line)
            return
        }
        $good = @($samples | Where-Object { $null -ne $_ })
        $maxV = 60.0
        if ($good.Count -gt 0) { $maxV = [double][Math]::Max(60.0, [double](($good | Measure-Object -Maximum).Maximum) * 1.25) }
        $n = $samples.Count
        $step = $w / [Math]::Max(1, ($n - 1))
        $pts = New-Object System.Windows.Media.PointCollection
        $prevY = $h - 4.0
        for ($i = 0; $i -lt $n; $i++) {
            $v = $samples[$i]
            if ($null -eq $v) { $y = $prevY }
            else {
                $y = $h - 4.0 - ([double]$v / $maxV) * ($h - 10.0)
                if ($y -lt 2) { $y = 2 }
            }
            $prevY = $y
            [void]$pts.Add((New-Object System.Windows.Point(([double]$i * $step), $y)))
        }
        $fill = New-Object System.Windows.Media.PointCollection
        foreach ($p in $pts) { [void]$fill.Add($p) }
        [void]$fill.Add((New-Object System.Windows.Point($w, [double]$h)))
        [void]$fill.Add((New-Object System.Windows.Point(0.0, [double]$h)))
        $polyFill = New-Object System.Windows.Shapes.Polygon
        $polyFill.Points = $fill
        $grad = New-Object System.Windows.Media.LinearGradientBrush
        $grad.StartPoint = New-Object System.Windows.Point(0, 0)
        $grad.EndPoint = New-Object System.Windows.Point(0, 1)
        $gs1 = New-Object System.Windows.Media.GradientStop; $gs1.Color = PalC 'sparkG1'; $gs1.Offset = 0.0
        $gs2 = New-Object System.Windows.Media.GradientStop; $gs2.Color = PalC 'sparkG2'; $gs2.Offset = 1.0
        [void]$grad.GradientStops.Add($gs1); [void]$grad.GradientStops.Add($gs2)
        $polyFill.Fill = $grad
        [void]$c.Children.Add($polyFill)

        $poly = New-Object System.Windows.Shapes.Polyline
        $poly.Points = $pts
        $poly.Stroke = PAL 'sparkLine'
        $poly.StrokeThickness = 1.6
        $poly.StrokeLineJoin = 'Round'
        [void]$c.Children.Add($poly)

        for ($i = 0; $i -lt $n; $i++) {
            if ($null -eq $samples[$i]) {
                $tick = New-Object System.Windows.Shapes.Rectangle
                $tick.Width = 2.5; $tick.Height = 4
                $tick.Fill = PAL 'histAlertFg'
                [System.Windows.Controls.Canvas]::SetLeft($tick, [double]$i * $step - 1.2)
                [System.Windows.Controls.Canvas]::SetTop($tick, [double]$h - 5)
                [void]$c.Children.Add($tick)
            }
        }
    } catch {}
}

# ------------------------- ACCIONES DE USUARIO -------------------------
function Set-PinState([bool]$on) {
    try {
        $Window.Topmost = $on
        $script:Pinned = $on
        $btn = $UI['PinBtn']
        if ($on) {
            $btn.Background = PAL 'pinOnBg'; $btn.Foreground = PAL 'pinOnFg'
            $btn.Content = [string][char]0xE77A; $btn.ToolTip = 'Quitar fijado'
        } else {
            $btn.Background = Br 'Transparent'; $btn.Foreground = PAL 'ctrlFg'
            $btn.Content = [string][char]0xE718; $btn.ToolTip = 'Fijar siempre visible'
        }
    } catch {}
}

function Copy-Text([string]$text, [string]$msg) {
    try {
        [System.Windows.Clipboard]::SetText($text)
        Show-Toast 'Copiado' $msg ([string][char]0xE8C8) "$($script:ActiveKey)"
    } catch {
        try { Set-Clipboard -Value $text } catch {}
    }
}

function Get-Summary {
    $gwTxt = "$($State.Gateway)"; if (-not $gwTxt) { $gwTxt = '--' }
    $macTxt = "$($State.GwMac)"; if (-not $macTxt) { $macTxt = '--' }
    $ipTxt = '--'; if ($State.Ip) { $ipTxt = "$($State.Ip)/$($State.Prefix)" }
    $segTxt = "$($State.Segment)"; if (-not $segTxt) { $segTxt = '--' }
    $bcTxt = "$($State.Broadcast)"; if (-not $bcTxt) { $bcTxt = '--' }
    $pubTxt = "$($State.PubIp)"; if (-not $pubTxt) { $pubTxt = 'no disponible' }
    $ispTxt = "$($State.Isp)"; if (-not $ispTxt) { $ispTxt = '--' }
    $gwPingTxt = '--'; if ($null -ne $State.GwPing) { $gwPingTxt = "$($State.GwPing) ms" }
    $extPingTxt = 'Timeout'; if ($null -ne $State.ExtPing) { $extPingTxt = "$($State.ExtPing) ms" }
    $lines = @(
        '--- NETWORK SENTINEL ---',
        "Red: $($State.Name) [$($State.Tag)]",
        "IP local: $ipTxt",
        "Segmento: $segTxt    BCast: $bcTxt",
        "Gateway: $gwTxt   MAC: $macTxt",
        "Interfaz: $($State.IfaceName) - $($State.IfaceDesc) - $($State.IfaceKind) - $($State.Speed)",
        "Perfil/SSID: $($State.ProfileName) $($State.Ssid)",
        "DNS: $($State.Dns)   MTU: $($State.Mtu)",
        "IP publica: $pubTxt ($ispTxt)",
        "Ping GW: $gwPingTxt | Ping Ext: $extPingTxt | Perdida: $($State.LossPct)%",
        "Fecha: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))",
        '------------------------'
    )
    return ($lines -join "`r`n")
}

function Close-Widget {
    try { Save-Settings $Window.Left $Window.Top ([bool]$Window.Topmost); Save-History $script:History } catch {}
    $State.Run = $false
    try { $Window.Close() } catch {}
}

# ------------------------- PANEL DE AJUSTES -------------------------
function Load-PanelData {
    try {
        $UI['CamSubnetBox'].Text = (@($Cfg.CamerasSubnets) -join ', ')
        $UI['LabelsBox'].Text = (@($Cfg.SubnetLabels) -join "`r`n")
        $UI['SettingsMsg'].Text = ''
        Update-ThemeOptUI
    } catch {}
}

function Toggle-SettingsPanel([bool]$open) {
    try {
        $p = $UI['SettingsPanel']
        if ($open) { $p.Visibility = 'Visible'; Load-PanelData } else { $p.Visibility = 'Collapsed' }
    } catch {}
}

function Test-CidrToken([string]$cidr) {
    $m = [regex]::Match($cidr, '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/(\d{1,2})$')
    if (-not $m.Success) { return $false }
    $oct = @([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value, [int]$m.Groups[4].Value)
    $pfx = [int]$m.Groups[5].Value
    if (@($oct | Where-Object { $_ -gt 255 }).Count -gt 0) { return $false }
    if ($pfx -lt 8 -or $pfx -gt 32) { return $false }
    return $true
}

function Save-PanelSettings {
    try {
        # --- Subredes de camaras ---
        $txt = "$($UI['CamSubnetBox'].Text)"
        $parts = @($txt -split '[,;\s]+' | Where-Object { $_ -ne '' })
        $okList = New-Object System.Collections.ArrayList
        $bad = @()
        foreach ($p in $parts) {
            $cidr = "$p".Trim()
            if ($cidr -notmatch '/') { $cidr = "$cidr/24" }
            if (Test-CidrToken $cidr) { [void]$okList.Add($cidr) } else { $bad += "$p" }
        }
        # --- Etiquetas de subred ('subred = nombre') ---
        $ltxt = "$($UI['LabelsBox'].Text)"
        $llines = @($ltxt -split '[\r\n]+' | Where-Object { "$_".Trim() -ne '' })
        $okLabels = New-Object System.Collections.ArrayList
        foreach ($ln in $llines) {
            $s = "$ln".Trim()
            $eq = $s.IndexOf('=')
            if ($eq -lt 1) { $bad += $s; continue }
            $cidr = $s.Substring(0, $eq).Trim()
            $lname = $s.Substring($eq + 1).Trim()
            if ($cidr -notmatch '/') { $cidr = "$cidr/24" }
            if (-not $lname -or -not (Test-CidrToken $cidr)) { $bad += $s; continue }
            [void]$okLabels.Add("$cidr = $lname")
        }
        if ($bad.Count -gt 0) {
            $UI['SettingsMsg'].Foreground = Br '#F43F5E'
            $UI['SettingsMsg'].Text = 'Valor invalido: ' + ($bad -join ' | ') + '  |  Formatos: 192.168.100.0/24   y   "subred = nombre"'
            return
        }
        $Cfg.CamerasSubnets = @($okList)
        $Cfg.SubnetLabels   = @($okLabels)
        $State.ForceNow = $true
        Save-Settings $Window.Left $Window.Top ([bool]$Window.Topmost)
        $UI['LabelsBox'].Text = (@($okLabels) -join "`r`n")
        $UI['SettingsMsg'].Foreground = Br '#10B981'
        $camTxt = 'desactivadas'
        if ($okList.Count -gt 0) { $camTxt = ($okList -join ', ') }
        $msg = "Guardado. Camaras: $camTxt"
        if ($okLabels.Count -gt 0) { $msg += " | Etiquetas: $($okLabels.Count)" }
        $UI['SettingsMsg'].Text = $msg
        Show-Toast 'Ajustes Guardados' $msg ([string][char]0xE713) "$($script:ActiveKey)"
    } catch {}
}

# ------------------------- EVENTOS -------------------------
$UI['TitleBar'].Add_MouseLeftButtonDown({ try { $Window.DragMove() } catch {} })
$UI['Banner'].Add_MouseLeftButtonDown({ try { $Window.DragMove() } catch {} })

$UI['CloseBtn'].Add_Click({ Close-Widget })
$UI['SettingsBtn'].Add_Click({
    try {
        $p = $UI['SettingsPanel']
        if ($p.Visibility -eq 'Visible') { Toggle-SettingsPanel $false } else { Toggle-SettingsPanel $true }
    } catch {}
})
$UI['SettingsCloseBtn'].Add_Click({ try { Toggle-SettingsPanel $false } catch {} })
$UI['SettingsDoneBtn'].Add_Click({ try { Toggle-SettingsPanel $false } catch {} })
$UI['SettingsSaveBtn'].Add_Click({ Save-PanelSettings })
foreach ($nm in @('ThemeOptSystem','ThemeOptDark','ThemeOptLight','ThemeOptDracula')) {
    $btn = $UI[$nm]
    if ($btn) {
        $btn.Add_Click({
            try {
                Apply-AppTheme "$($this.Tag)"
                try { Save-Settings $Window.Left $Window.Top ([bool]$Window.Topmost) } catch {}
            } catch {}
        })
    }
}
$UI['PinBtn'].Add_Click({ Set-PinState (-not [bool]$Window.Topmost) })
$UI['RefreshBtn'].Add_Click({
    try {
        $State.RefreshPublic = $true; $State.ForceNow = $true
        $btn = $UI['RefreshBtn']
        $rot = New-Object System.Windows.Media.RotateTransform(0)
        $btn.RenderTransform = $rot
        $btn.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
        $an = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, 360.0, [TimeSpan]::FromMilliseconds(620))
        $an.RepeatBehavior = New-Object System.Windows.Media.Animation.RepeatBehavior(2.0)
        $rot.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $an)
    } catch {}
})
$UI['CollapseBtn'].Add_Click({
    try {
        $script:Collapsed = -not $script:Collapsed
        $dh = $UI['DetailsHolder']; $btn = $UI['CollapseBtn']
        if ($script:Collapsed) {
            $dh.Visibility = 'Collapsed'; $btn.Content = [string][char]0xE922; $btn.ToolTip = 'Expandir'
        } else {
            $dh.Visibility = 'Visible'; $btn.Content = [string][char]0xE921; $btn.ToolTip = 'Compactar'
        }
    } catch {}
})
$UI['ClearBtn'].Add_Click({
    try {
        $script:History = @()
        Save-History @()
        $UI['HistoryPanel'].Children.Clear()
        Show-Toast 'Historial Limpiado' 'Se borraron los cambios registrados.' ([string][char]0xE74D) "$($script:ActiveKey)"
    } catch {}
})
$UI['CopyIpBtn'].Add_Click({ Copy-Text $UI['IpValue'].Text 'IP local copiada' })
$UI['CopyGwBtn'].Add_Click({ Copy-Text $UI['GwValue'].Text 'Gateway copiado' })
$UI['CopySegBtn'].Add_Click({ Copy-Text $UI['SegValue'].Text 'Segmento copiado' })
$UI['CopyPubBtn'].Add_Click({ Copy-Text $UI['PubValue'].Text 'IP publica copiada' })
$UI['CopyAllBtn'].Add_Click({ Copy-Text (Get-Summary) 'Resumen completo copiado al portapapeles' })

$script:ToastTimer.Add_Tick({ $script:ToastTimer.Stop(); Hide-Toast })

# ------------------------- POSICION / ESTADO INICIAL -------------------------
$Window.Add_SourceInitialized({
    try {
        $hwnd = ([System.Windows.Interop.WindowInteropHelper]$Window).Handle
        $ex = [NSNative.W32]::GetWindowLong($hwnd, -20)
        [void][NSNative.W32]::SetWindowLong($hwnd, -20, ($ex -bor 0x80))
        # Forzar que la ventana sea visible aunque el lanzador use -WindowStyle Hidden
        [void][NSNative.W32]::ShowWindow($hwnd, 5)
    } catch {}
})

$Window.Add_Loaded({
    try {
        $hwnd2 = ([System.Windows.Interop.WindowInteropHelper]$Window).Handle
        [void][NSNative.W32]::ShowWindow($hwnd2, 5)
        $s = Load-Settings
        $vsL = [System.Windows.SystemParameters]::VirtualScreenLeft
        $vsT = [System.Windows.SystemParameters]::VirtualScreenTop
        $vsW = [System.Windows.SystemParameters]::VirtualScreenWidth
        $vsH = [System.Windows.SystemParameters]::VirtualScreenHeight
        $wa = [System.Windows.SystemParameters]::WorkArea
        $x = $wa.Right - $Window.Width - 24
        $y = $wa.Top + 24
        if ($null -ne $s.Left -and $null -ne $s.Top) {
            if ([double]$s.Left -ge ($vsL - 60) -and [double]$s.Left -le ($vsL + $vsW - 120) -and
                [double]$s.Top -ge ($vsT - 60) -and [double]$s.Top -le ($vsT + $vsH - 120)) {
                $x = [double]$s.Left; $y = [double]$s.Top
            }
        }
        $Window.Left = $x; $Window.Top = $y
        Apply-AppTheme "$($s.Theme)"
        if ($null -ne $s.CamerasSubnets) { $Cfg.CamerasSubnets = @($s.CamerasSubnets); $State.ForceNow = $true }
        if ($null -ne $s.SubnetLabels) { $Cfg.SubnetLabels = @($s.SubnetLabels); $State.ForceNow = $true }
        if ($s.Pinned) { Set-PinState $true }

        $p1 = New-Object System.Windows.Media.Animation.DoubleAnimation(0.25, 1.0, [TimeSpan]::FromMilliseconds(1100))
        $p1.AutoReverse = $true
        $p1.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $UI['FooterDot'].BeginAnimation([System.Windows.UIElement]::OpacityProperty, $p1)
        $p2 = New-Object System.Windows.Media.Animation.DoubleAnimation(0.25, 1.0, [TimeSpan]::FromMilliseconds(1300))
        $p2.AutoReverse = $true
        $p2.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $UI['BannerPulseDot'].BeginAnimation([System.Windows.UIElement]::OpacityProperty, $p2)

        Update-Spark
        Update-Clocks
    } catch {}
})

$Window.Add_Closing({
    try { Save-Settings $Window.Left $Window.Top ([bool]$Window.Topmost); Save-History $script:History } catch {}
    $State.Run = $false
})

# ------------------------- TIMER PRINCIPAL -------------------------
$script:TickTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:TickTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$script:TickTimer.Add_Tick({
    try {
        if ($State.Run -and $script:WorkerHandle -and $script:WorkerHandle.IsCompleted) {
            $script:WorkerRestarts = @($script:WorkerRestarts | Where-Object { ((Get-Date) - $_).TotalSeconds -lt 60 })
            if ($script:WorkerRestarts.Count -lt 8) {
                $script:WorkerRestarts += (Get-Date)
                Start-NetWorker
            } else {
                $UI['FooterText'].Text = 'Monitor detenido - error interno'
            }
        }
        if ([int]$State.Version -ne $script:LastVersion) {
            $script:LastVersion = [int]$State.Version
            Update-FromState
            Update-Spark
        }
        Update-Clocks
        if ($script:AppThemeKey -eq 'system') {
            $script:SysThemeTick = [int]$script:SysThemeTick + 1
            if ($script:SysThemeTick -ge 8) {
                $script:SysThemeTick = 0
                if ((Resolve-SystemTheme) -ne $script:EffectiveTheme) { Apply-AppTheme 'system' }
            }
        }
    } catch {}
})

# ------------------------- HISTORIAL GUARDADO + ARRANQUE -------------------------
$script:History = @(Load-History)
Rebuild-HistoryRows

# Fuerza extra: si el proceso arranco con STARTUPINFO oculto (lanzador silencioso),
# asegura que la ventana quede visible unos instantes despues de abrirse.
$script:ShowPokeTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ShowPokeTimer.Interval = [TimeSpan]::FromMilliseconds(450)
$script:ShowPokeCount = 0
$script:ShowPokeTimer.Add_Tick({
    try {
        $script:ShowPokeCount++
        $h = ([System.Windows.Interop.WindowInteropHelper]$Window).Handle
        if ($h -ne [IntPtr]::Zero) {
            [void][NSNative.W32]::ShowWindow($h, 5)
            if ($script:ShowPokeCount -eq 1) { try { $Window.Activate() } catch {} }
        }
        if ($script:ShowPokeCount -ge 3) { $script:ShowPokeTimer.Stop() }
    } catch { $script:ShowPokeTimer.Stop() }
})
$script:ShowPokeTimer.Start()

Start-NetWorker
$script:TickTimer.Start()
[void]$Window.ShowDialog()
$script:TickTimer.Stop()
Stop-NetWorker
try { $script:AppMutex.ReleaseMutex() } catch {}
exit 0
