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
