
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
