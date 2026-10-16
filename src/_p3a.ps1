
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
