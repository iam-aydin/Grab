# =====================================================================
# install.ps1
# Generates, builds, publishes and launches GRAB (WinUI 3, unpackaged).
# Usage:  powershell -ExecutionPolicy Bypass -File .\install.ps1
# NOTE: this file is intentionally pure ASCII (Windows PowerShell 5.1 safe).
# =====================================================================
$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'

$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$src  = Join-Path $root 'Grab-Src'
$out  = Join-Path $root 'Grab-Output'
$iconSrc = Join-Path $root 'docs\icon.ico'

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Refresh-Path {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$m;$u"
}

function Get-InstalledSdks {
    $list = @()
    try {
        $lines = & dotnet --list-sdks 2>$null
        foreach ($l in $lines) {
            if ($l -match '^(\d+\.\d+\.\d+)\s' ) { $list += $Matches[1] }
        }
    } catch { }
    return $list
}

Write-Host '== GRAB build ==' -ForegroundColor Cyan

# ---------------------------------------------------------------------
# 0. Make sure a .NET 8 (preferred) or 9 SDK exists
# ---------------------------------------------------------------------
$sdks = @(Get-InstalledSdks)
$pick = $sdks | Where-Object { $_ -like '8.*' } | Sort-Object { [version]$_ } | Select-Object -Last 1
if (-not $pick) { $pick = $sdks | Where-Object { $_ -like '9.*' } | Sort-Object { [version]$_ } | Select-Object -Last 1 }
if (-not $pick) {
    Write-Host 'No .NET 8/9 SDK found. Trying to install .NET 8 SDK via winget...' -ForegroundColor Yellow
    try {
        & winget install --id Microsoft.DotNet.SDK.8 -e --accept-package-agreements --accept-source-agreements
        Refresh-Path
    } catch { }
    $sdks = @(Get-InstalledSdks)
    $pick = $sdks | Where-Object { $_ -like '8.*' } | Sort-Object { [version]$_ } | Select-Object -Last 1
    if (-not $pick) {
        if ($sdks.Count -gt 0) {
            Write-Host 'Warning: only a newer SDK is available. Continuing, but .NET 8 SDK is strongly recommended.' -ForegroundColor Yellow
        } else {
            throw 'The .NET SDK is not installed. Install the .NET 8 SDK from https://dotnet.microsoft.com/download/dotnet/8.0 and run this script again.'
        }
    }
}

# ---------------------------------------------------------------------
# 1. Generate sources
# ---------------------------------------------------------------------
Write-Host 'Generating source files...' -ForegroundColor Cyan
if (Test-Path -LiteralPath $src) { Remove-Item -LiteralPath $src -Recurse -Force }
New-Item -ItemType Directory -Path $src -Force | Out-Null

# --- Optional app icon: docs\icon.ico -> Grab-Src\icon.ico -------------
$hasIcon = Test-Path -LiteralPath $iconSrc
if ($hasIcon) {
    Copy-Item -LiteralPath $iconSrc -Destination (Join-Path $src 'icon.ico') -Force
    Write-Host 'App icon found: docs\icon.ico' -ForegroundColor Green
} else {
    Write-Host 'No docs\icon.ico found - building without a custom icon.' -ForegroundColor Yellow
}
# ---------------------------------------------------------------------

if ($pick) {
    # Pin the SDK so a newer preview/10.x SDK on the machine cannot break the XAML compiler.
    Write-Utf8NoBom (Join-Path $src 'global.json') ('{ "sdk": { "version": "' + $pick + '", "rollForward": "latestPatch", "allowPrerelease": false } }')
}

Write-Utf8NoBom (Join-Path $src 'nuget.config') @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
'@

# ----------------------------- Grab.csproj ---------------------------
# The placeholders <!--ICON_PROP--> and <!--ICON_CONTENT--> are replaced
# below with real icon markup when docs\icon.ico exists.
Write-Utf8NoBom (Join-Path $src 'Grab.csproj') @'
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows10.0.19041.0</TargetFramework>
    <TargetPlatformMinVersion>10.0.17763.0</TargetPlatformMinVersion>
    <SupportedOSPlatformVersion>10.0.17763.0</SupportedOSPlatformVersion>
    <RootNamespace>Grab</RootNamespace>
    <AssemblyName>Grab</AssemblyName>
    <ApplicationManifest>app.manifest</ApplicationManifest>
    <Platforms>x64</Platforms>
    <Platform>x64</Platform>
    <PlatformTarget>x64</PlatformTarget>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <UseWinUI>true</UseWinUI>
    <EnableMsixTooling>true</EnableMsixTooling>
    <WindowsPackageType>None</WindowsPackageType>
    <WindowsAppSDKSelfContained>true</WindowsAppSDKSelfContained>
    <SelfContained>true</SelfContained>
    <PublishSingleFile>true</PublishSingleFile>
    <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
    <PublishTrimmed>false</PublishTrimmed>
    <PublishReadyToRun>false</PublishReadyToRun>
    <SatelliteResourceLanguages>en</SatelliteResourceLanguages>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
    <AssemblyTitle>GRAB</AssemblyTitle>
    <Product>GRAB</Product>
    <Version>1.0.0</Version>
    <!--ICON_PROP-->
    <NoWarn>$(NoWarn);CS8618;CS8625;CS8600;CS8601;CS8602;CS8603;CS8604;NETSDK1206</NoWarn>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.WindowsAppSDK" Version="1.6.250228001" />
    <PackageReference Include="Microsoft.Windows.SDK.BuildTools" Version="10.0.26100.1742" />
  </ItemGroup>
  <!--ICON_CONTENT-->

</Project>
'@

# --- Inject icon markup into the csproj if docs\icon.ico exists ------
$csprojPath = Join-Path $src 'Grab.csproj'
$csprojText = [System.IO.File]::ReadAllText($csprojPath, (New-Object System.Text.UTF8Encoding($false)))
if ($hasIcon) {
    $iconProp = "    <ApplicationIcon>icon.ico</ApplicationIcon>"
    $iconContent = @'

  <ItemGroup>
    <Content Include="icon.ico">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
      <CopyToPublishDirectory>PreserveNewest</CopyToPublishDirectory>
    </Content>
  </ItemGroup>
'@
} else {
    $iconProp = ''
    $iconContent = ''
}
$csprojText = $csprojText.Replace('<!--ICON_PROP-->', $iconProp).Replace('<!--ICON_CONTENT-->', $iconContent)
[System.IO.File]::WriteAllText($csprojPath, $csprojText, (New-Object System.Text.UTF8Encoding($false)))
# ---------------------------------------------------------------------

# ----------------------------- app.manifest --------------------------
Write-Utf8NoBom (Join-Path $src 'app.manifest') @'
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="Grab.app" />
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" />
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
    </windowsSettings>
  </application>
</assembly>
'@

# ----------------------------- App.xaml ------------------------------
Write-Utf8NoBom (Join-Path $src 'App.xaml') @'
<?xml version="1.0" encoding="utf-8"?>
<Application
    x:Class="Grab.App"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    RequestedTheme="Dark">
    <Application.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <XamlControlsResources xmlns="using:Microsoft.UI.Xaml.Controls" />
            </ResourceDictionary.MergedDictionaries>
        </ResourceDictionary>
    </Application.Resources>
</Application>
'@

# ----------------------------- App.xaml.cs ---------------------------
Write-Utf8NoBom (Join-Path $src 'App.xaml.cs') @'
using Microsoft.UI.Xaml;

namespace Grab;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();

        UnhandledException += (s, e) =>
        {
            Logger.Log(e.Exception, "App.UnhandledException");
            e.Handled = true;
        };
        AppDomain.CurrentDomain.UnhandledException += (s, e) =>
        {
            Logger.Log(e.ExceptionObject as Exception, "AppDomain.UnhandledException");
        };
        TaskScheduler.UnobservedTaskException += (s, e) =>
        {
            Logger.Log(e.Exception, "TaskScheduler.UnobservedTaskException");
            e.SetObserved();
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            _window = new MainWindow();
            _window.Activate();
        }
        catch (Exception ex)
        {
            Logger.Log(ex, "OnLaunched");
            throw;
        }
    }
}
'@

# ----------------------------- Logger.cs -----------------------------
Write-Utf8NoBom (Join-Path $src 'Logger.cs') @'
using System.Text;

namespace Grab;

public static class Logger
{
    private static readonly object Gate = new();

    public static string LogDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Grab", "Logs");

    public static void Log(Exception? ex, string? context = null)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(LogDir);
                string file = Path.Combine(LogDir, "grab-" + DateTime.Now.ToString("yyyyMMdd") + ".log");
                var sb = new StringBuilder();
                sb.Append('[').Append(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff")).Append("] ");
                if (!string.IsNullOrEmpty(context)) sb.Append(context).Append(" - ");
                sb.AppendLine(ex?.ToString() ?? "(null exception)");
                sb.AppendLine();
                File.AppendAllText(file, sb.ToString(), new UTF8Encoding(false));
            }
        }
        catch
        {
            // Logging must never throw.
        }
    }
}
'@

# ----------------------------- AppSettings.cs ------------------------
Write-Utf8NoBom (Join-Path $src 'AppSettings.cs') @'
using System.Text;
using System.Text.Json;

namespace Grab;

public sealed class AppSettings
{
    public string? LastFolder { get; set; }

    private static string Dir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Grab");

    private static string FilePath => Path.Combine(Dir, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                string json = File.ReadAllText(FilePath, new UTF8Encoding(false));
                return JsonSerializer.Deserialize<AppSettings>(json) ?? new AppSettings();
            }
        }
        catch (Exception ex)
        {
            Logger.Log(ex, "AppSettings.Load");
        }
        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            string json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(FilePath, json, new UTF8Encoding(false));
        }
        catch (Exception ex)
        {
            Logger.Log(ex, "AppSettings.Save");
        }
    }
}
'@

# ----------------------------- FileIndex.cs --------------------------
Write-Utf8NoBom (Join-Path $src 'FileIndex.cs') @'
namespace Grab;

public sealed record ResolveResult(bool Found, string Rel, string Full, int Extra)
{
    public static readonly ResolveResult None = new(false, "", "", 0);
}

public sealed class FileIndex
{
    private static readonly HashSet<string> IgnoredDirs = new(StringComparer.OrdinalIgnoreCase)
    {
        "node_modules", ".git", "dist", "build", "bin", "obj"
    };

    private static readonly HashSet<string> BinaryExts = new(StringComparer.OrdinalIgnoreCase)
    {
        // images
        ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".webp", ".tif", ".tiff", ".psd", ".ai", ".heic", ".icns", ".cur",
        // archives
        ".zip", ".7z", ".rar", ".gz", ".tar", ".tgz", ".bz2", ".xz", ".cab", ".iso", ".nupkg", ".vsix",
        // executables / compiled
        ".exe", ".dll", ".pdb", ".so", ".dylib", ".bin", ".obj", ".o", ".a", ".lib", ".msi", ".class", ".jar", ".pyc", ".pyd", ".sys", ".pri",
        // media
        ".mp3", ".mp4", ".wav", ".avi", ".mov", ".mkv", ".flac", ".ogg", ".webm", ".m4a", ".wmv",
        // office / pdf
        ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
        // fonts
        ".ttf", ".otf", ".woff", ".woff2", ".eot",
        // databases
        ".db", ".sqlite", ".sqlite3", ".mdb", ".mdf", ".ldf"
    };

    private readonly Dictionary<string, List<string>> _byName = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _set = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<string> _all = new();

    public string Root { get; }
    public int Count => _all.Count;

    private FileIndex(string root) { Root = root; }

    public static FileIndex Build(string root, CancellationToken ct)
    {
        string full = Path.GetFullPath(root);
        var idx = new FileIndex(full);
        var stack = new Stack<string>();
        stack.Push(full);

        while (stack.Count > 0)
        {
            ct.ThrowIfCancellationRequested();
            string dir = stack.Pop();

            try
            {
                foreach (string f in Directory.EnumerateFiles(dir))
                {
                    string ext = Path.GetExtension(f);
                    if (BinaryExts.Contains(ext)) continue;
                    string rel = Path.GetRelativePath(full, f);
                    idx.Add(Path.GetFileName(f), rel);
                }
            }
            catch (UnauthorizedAccessException) { }
            catch (DirectoryNotFoundException) { }
            catch (IOException) { }

            try
            {
                foreach (string d in Directory.EnumerateDirectories(dir))
                {
                    string name = Path.GetFileName(d);
                    if (IgnoredDirs.Contains(name)) continue;
                    try
                    {
                        if ((File.GetAttributes(d) & FileAttributes.ReparsePoint) != 0) continue;
                    }
                    catch { continue; }
                    stack.Push(d);
                }
            }
            catch (UnauthorizedAccessException) { }
            catch (DirectoryNotFoundException) { }
            catch (IOException) { }
        }

        return idx;
    }

    private void Add(string name, string rel)
    {
        _all.Add(rel);
        _set.Add(rel);
        if (!_byName.TryGetValue(name, out var list))
        {
            list = new List<string>(1);
            _byName[name] = list;
        }
        list.Add(rel);
    }

    public ResolveResult Resolve(string input)
    {
        string s = input.Trim().Trim('"', '\'').Replace('/', '\\');
        if (s.Length == 0) return ResolveResult.None;

        bool absolute = (s.Length >= 2 && s[1] == ':') || s.StartsWith("\\\\");
        if (absolute)
        {
            string prefix = Root.TrimEnd('\\') + "\\";
            if (s.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) s = s.Substring(prefix.Length);
            else return ResolveResult.None;
        }

        while (s.StartsWith(".\\")) s = s.Substring(2);
        s = s.TrimStart('\\');
        if (s.Length == 0) return ResolveResult.None;

        if (s.Contains('\\'))
        {
            if (_set.TryGetValue(s, out var exact)) return Make(exact, 0);

            string suffix = "\\" + s;
            var matches = _all.Where(r => r.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)).ToList();
            if (matches.Count == 0) return ResolveResult.None;
            string best = matches.OrderBy(m => m.Length).ThenBy(m => m, StringComparer.OrdinalIgnoreCase).First();
            return Make(best, matches.Count - 1);
        }

        if (_byName.TryGetValue(s, out var list) && list.Count > 0)
        {
            string best = list.OrderBy(m => m.Length).ThenBy(m => m, StringComparer.OrdinalIgnoreCase).First();
            return Make(best, list.Count - 1);
        }

        return ResolveResult.None;
    }

    private ResolveResult Make(string rel, int extra) => new(true, rel, Path.Combine(Root, rel), extra);
}
'@

# ----------------------------- FileRow.cs ----------------------------
Write-Utf8NoBom (Join-Path $src 'FileRow.cs') @'
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Grab;

public enum RowState { Idle, Found, NotFound }

public sealed class FileRow : INotifyPropertyChanged, IDisposable
{
    private static readonly SolidColorBrush GreyBrush  = new(Color.FromArgb(255, 150, 150, 156));
    private static readonly SolidColorBrush GreenBrush = new(Color.FromArgb(255, 76, 195, 138));
    private static readonly SolidColorBrush RedBrush   = new(Color.FromArgb(255, 242, 85, 90));

    public event PropertyChangedEventHandler? PropertyChanged;
    public event Action<FileRow>? CheckRequested;
    public event Action? Edited;

    private readonly DispatcherQueueTimer _timer;
    private string _text = "";
    private string _statusText = "Idle - type a filename";
    private SolidColorBrush _statusBrush = GreyBrush;

    public int Version { get; private set; }
    public RowState State { get; private set; } = RowState.Idle;
    public string? ResolvedRel { get; private set; }
    public string? ResolvedFull { get; private set; }

    public FileRow()
    {
        _timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _timer.Interval = TimeSpan.FromSeconds(2);   // exactly 2 seconds after the last keystroke
        _timer.IsRepeating = false;
        _timer.Tick += (s, e) =>
        {
            _timer.Stop();
            CheckRequested?.Invoke(this);
        };
    }

    public string Text
    {
        get => _text;
        set
        {
            if (_text == value) return;
            _text = value ?? "";
            Notify();
            OnTextEdited();
        }
    }

    public string StatusText
    {
        get => _statusText;
        private set { _statusText = value; Notify(); }
    }

    public SolidColorBrush StatusBrush
    {
        get => _statusBrush;
        private set { _statusBrush = value; Notify(); }
    }

    private void OnTextEdited()
    {
        Version++;
        ResolvedRel = null;
        ResolvedFull = null;
        _timer.Stop();

        if (_text.Trim().Length == 0)
        {
            Set(RowState.Idle, "Idle - type a filename", GreyBrush);
        }
        else
        {
            Set(RowState.Idle, "Waiting for you to stop typing...", GreyBrush);
            _timer.Start();   // restarts the 2s countdown on every keystroke
        }
        Edited?.Invoke();
    }

    public void CancelTimer() => _timer.Stop();

    public void ApplyIdle(string message)
    {
        ResolvedRel = null;
        ResolvedFull = null;
        Set(RowState.Idle, message, GreyBrush);
    }

    public void ApplyFound(ResolveResult r)
    {
        ResolvedRel = r.Rel;
        ResolvedFull = r.Full;
        string msg = r.Extra > 0
            ? "Found - " + r.Rel + "  (+" + r.Extra + " other matches, shortest path used)"
            : "Found - " + r.Rel;
        Set(RowState.Found, msg, GreenBrush);
    }

    public void ApplyNotFound()
    {
        ResolvedRel = null;
        ResolvedFull = null;
        Set(RowState.NotFound, "Not found", RedBrush);
    }

    private void Set(RowState state, string text, SolidColorBrush brush)
    {
        State = state;
        StatusText = text;
        StatusBrush = brush;
    }

    public void Dispose() => _timer.Stop();

    private void Notify([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
'@

# ----------------------------- MainWindow.xaml -----------------------
Write-Utf8NoBom (Join-Path $src 'MainWindow.xaml') @'
<?xml version="1.0" encoding="utf-8"?>
<Window
    x:Class="Grab.MainWindow"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:local="using:Grab">

    <Window.SystemBackdrop>
        <MicaBackdrop Kind="Base" />
    </Window.SystemBackdrop>

    <Grid x:Name="RootGrid" RequestedTheme="Dark">
        <Grid.RowDefinitions>
            <RowDefinition Height="40" />
            <RowDefinition Height="*" />
        </Grid.RowDefinitions>

        <!-- Title bar drag region (native caption buttons stay on the right) -->
        <Grid x:Name="AppTitleBar" Grid.Row="0">
            <TextBlock Text="GRAB"
                       FontSize="12"
                       FontWeight="SemiBold"
                       CharacterSpacing="200"
                       VerticalAlignment="Center"
                       Margin="16,0,0,0"
                       Opacity="0.85" />
        </Grid>

        <Grid x:Name="ContentHost" Grid.Row="1" Padding="28,8,28,24" RowSpacing="16">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="*" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
            </Grid.RowDefinitions>

            <!-- Root folder card -->
            <Border Grid.Row="0"
                    CornerRadius="8"
                    BorderThickness="1"
                    Padding="16"
                    Background="{ThemeResource CardBackgroundFillColorDefaultBrush}"
                    BorderBrush="{ThemeResource CardStrokeColorDefaultBrush}">
                <StackPanel Spacing="10">
                    <TextBlock Text="ROOT FOLDER"
                               FontSize="11"
                               CharacterSpacing="120"
                               Foreground="{ThemeResource TextFillColorSecondaryBrush}" />
                    <Grid ColumnSpacing="8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*" />
                            <ColumnDefinition Width="Auto" />
                            <ColumnDefinition Width="Auto" />
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="RootBox"
                                 Grid.Column="0"
                                 PlaceholderText="C:\path\to\your\project"
                                 CornerRadius="6"
                                 TextChanged="RootBox_TextChanged"
                                 KeyDown="RootBox_KeyDown"
                                 LostFocus="RootBox_LostFocus" />
                        <Button x:Name="BrowseBtn"
                                Grid.Column="1"
                                CornerRadius="6"
                                Click="Browse_Click">
                            <StackPanel Orientation="Horizontal" Spacing="8">
                                <FontIcon Glyph="&#xE8B7;" FontSize="14" />
                                <TextBlock Text="Browse" />
                            </StackPanel>
                        </Button>
                        <Button Grid.Column="2"
                                CornerRadius="6"
                                Click="Refresh_Click"
                                ToolTipService.ToolTip="Re-scan folder">
                            <FontIcon Glyph="&#xE72C;" FontSize="14" />
                        </Button>
                    </Grid>
                    <StackPanel Orientation="Horizontal" Spacing="8">
                        <ProgressRing x:Name="IndexRing" Width="14" Height="14" IsActive="False" Visibility="Collapsed" />
                        <TextBlock x:Name="IndexStatus"
                                   Text="No folder selected"
                                   FontSize="12"
                                   Foreground="{ThemeResource TextFillColorSecondaryBrush}" />
                    </StackPanel>
                </StackPanel>
            </Border>

            <!-- Files header -->
            <Grid Grid.Row="1">
                <TextBlock Text="FILES"
                           FontSize="11"
                           CharacterSpacing="120"
                           VerticalAlignment="Center"
                           Foreground="{ThemeResource TextFillColorSecondaryBrush}" />
                <Button x:Name="AddBtn"
                        HorizontalAlignment="Right"
                        CornerRadius="6"
                        Click="AddRow_Click"
                        PointerEntered="Pop_Enter"
                        PointerExited="Pop_Exit"
                        ToolTipService.ToolTip="Add file row">
                    <FontIcon Glyph="&#xE710;" FontSize="14" />
                </Button>
            </Grid>

            <!-- File rows -->
            <ScrollViewer x:Name="Scroller"
                          Grid.Row="2"
                          VerticalScrollBarVisibility="Auto"
                          Padding="0,0,12,0">
                <ItemsControl x:Name="FilesList">
                    <ItemsControl.ItemContainerTransitions>
                        <TransitionCollection>
                            <AddDeleteThemeTransition />
                            <ReorderThemeTransition />
                        </TransitionCollection>
                    </ItemsControl.ItemContainerTransitions>
                    <ItemsControl.ItemTemplate>
                        <DataTemplate x:DataType="local:FileRow">
                            <Grid Margin="0,0,0,12">
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto" />
                                    <RowDefinition Height="Auto" />
                                </Grid.RowDefinitions>

                                <StackPanel Grid.Row="0"
                                            Orientation="Horizontal"
                                            Spacing="8"
                                            Margin="2,0,0,6">
                                    <Ellipse Width="8"
                                             Height="8"
                                             VerticalAlignment="Center"
                                             Fill="{x:Bind StatusBrush, Mode=OneWay}" />
                                    <TextBlock Text="{x:Bind StatusText, Mode=OneWay}"
                                               FontSize="12"
                                               Foreground="{x:Bind StatusBrush, Mode=OneWay}" />
                                </StackPanel>

                                <Grid Grid.Row="1" ColumnSpacing="8">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*" />
                                        <ColumnDefinition Width="Auto" />
                                    </Grid.ColumnDefinitions>
                                    <TextBox Grid.Column="0"
                                             CornerRadius="6"
                                             PlaceholderText="app.tsx  or  src/app.tsx"
                                             Text="{x:Bind Text, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" />
                                    <Button Grid.Column="1"
                                            CornerRadius="6"
                                            Click="RemoveRow_Click"
                                            ToolTipService.ToolTip="Remove row">
                                        <FontIcon Glyph="&#xE711;" FontSize="12" />
                                    </Button>
                                </Grid>
                            </Grid>
                        </DataTemplate>
                    </ItemsControl.ItemTemplate>
                </ItemsControl>
            </ScrollViewer>

            <InfoBar x:Name="InfoBarMain"
                     Grid.Row="3"
                     IsOpen="False"
                     IsClosable="True"
                     CornerRadius="6" />

            <!-- Export buttons -->
            <Grid Grid.Row="4" ColumnSpacing="12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="*" />
                </Grid.ColumnDefinitions>
                <Button x:Name="TxtBtn"
                        Grid.Column="0"
                        Style="{StaticResource AccentButtonStyle}"
                        HorizontalAlignment="Stretch"
                        Height="44"
                        CornerRadius="8"
                        Click="ExportTxt_Click"
                        PointerEntered="Pop_Enter"
                        PointerExited="Pop_Exit">
                    <StackPanel Orientation="Horizontal" Spacing="10">
                        <FontIcon Glyph="&#xE8A5;" FontSize="16" />
                        <TextBlock Text="TXT TO DESKTOP" FontWeight="SemiBold" />
                    </StackPanel>
                </Button>
                <Button x:Name="ZipBtn"
                        Grid.Column="1"
                        Style="{StaticResource AccentButtonStyle}"
                        HorizontalAlignment="Stretch"
                        Height="44"
                        CornerRadius="8"
                        Click="ExportZip_Click"
                        PointerEntered="Pop_Enter"
                        PointerExited="Pop_Exit">
                    <StackPanel Orientation="Horizontal" Spacing="10">
                        <FontIcon Glyph="&#xE896;" FontSize="16" />
                        <TextBlock Text="ZIP TO DESKTOP" FontWeight="SemiBold" />
                    </StackPanel>
                </Button>
            </Grid>
        </Grid>
    </Grid>
</Window>
'@

# ----------------------------- MainWindow.xaml.cs --------------------
Write-Utf8NoBom (Join-Path $src 'MainWindow.xaml.cs') @'
using System.Collections.ObjectModel;
using System.IO.Compression;
using System.Numerics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.UI;
using Microsoft.UI.Composition;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Input;
using Windows.Storage.Pickers;

namespace Grab;

public sealed class ExportResult
{
    public int Written;
    public List<string> Failed = new();
}

public sealed partial class MainWindow : Window
{
    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    private readonly ObservableCollection<FileRow> Rows = new();
    private readonly AppSettings _settings;
    private readonly DispatcherQueueTimer _rootTimer;

    private FileIndex? _index;
    private Task _indexTask = Task.CompletedTask;
    private CancellationTokenSource? _cts;
    private int _indexGen;
    private string? _rootPath;
    private bool _suppressRoot;
    private bool _exporting;
    private bool _started;

    public MainWindow()
    {
        InitializeComponent();
        _settings = AppSettings.Load();

        _rootTimer = DispatcherQueue.CreateTimer();
        _rootTimer.Interval = TimeSpan.FromSeconds(2);
        _rootTimer.IsRepeating = false;
        _rootTimer.Tick += (s, e) =>
        {
            _rootTimer.Stop();
            SafeCommit(false);
        };

        ConfigureChrome();

        FilesList.ItemsSource = Rows;
        Rows.Add(NewRow());
        UpdateButtons();

        Closed += OnClosed;
        RootGrid.Loaded += OnRootLoaded;
    }

    // ------------------------------------------------------------ chrome
    private void ConfigureChrome()
    {
        try
        {
            Title = "GRAB";
            ExtendsContentIntoTitleBar = true;
            SetTitleBar(AppTitleBar);

            IntPtr hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            uint dpi = GetDpiForWindow(hwnd);
            double scale = dpi > 0 ? dpi / 96.0 : 1.0;
            AppWindow.Resize(new Windows.Graphics.SizeInt32((int)(940 * scale), (int)(780 * scale)));

            if (AppWindowTitleBar.IsCustomizationSupported())
            {
                var tb = AppWindow.TitleBar;
                tb.ButtonBackgroundColor = Colors.Transparent;
                tb.ButtonInactiveBackgroundColor = Colors.Transparent;
                tb.ButtonForegroundColor = Colors.White;
                tb.ButtonInactiveForegroundColor = Windows.UI.Color.FromArgb(255, 150, 150, 150);
                tb.ButtonHoverBackgroundColor = Windows.UI.Color.FromArgb(0x26, 255, 255, 255);
                tb.ButtonHoverForegroundColor = Colors.White;
                tb.ButtonPressedBackgroundColor = Windows.UI.Color.FromArgb(0x40, 255, 255, 255);
                tb.ButtonPressedForegroundColor = Colors.White;
            }

            // App window / taskbar / titlebar icon. No-ops quietly if icon.ico
            // is not sitting next to the exe at runtime.
            try
            {
                var ico = Path.Combine(AppContext.BaseDirectory, "icon.ico");
                if (File.Exists(ico)) AppWindow.SetIcon(ico);
            }
            catch (Exception ex) { Logger.Log(ex, "SetIcon"); }
        }
        catch (Exception ex)
        {
            Logger.Log(ex, "ConfigureChrome");
        }
    }

    private void OnRootLoaded(object sender, RoutedEventArgs e)
    {
        if (_started) return;
        _started = true;

        try { PlayIntro(); } catch (Exception ex) { Logger.Log(ex, "PlayIntro"); }

        if (!string.IsNullOrWhiteSpace(_settings.LastFolder))
        {
            _suppressRoot = true;
            RootBox.Text = _settings.LastFolder;
            _suppressRoot = false;
            SafeCommit(true);
        }
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        try
        {
            _cts?.Cancel();
            _rootTimer.Stop();
            foreach (var r in Rows) r.Dispose();
        }
        catch (Exception ex) { Logger.Log(ex, "OnClosed"); }
    }

    // --------------------------------------------------- composition anim
    private void PlayIntro()
    {
        var visual = ElementCompositionPreview.GetElementVisual(ContentHost);
        var c = visual.Compositor;
        ElementCompositionPreview.SetIsTranslationEnabled(ContentHost, true);

        var ease = c.CreateCubicBezierEasingFunction(new Vector2(0.1f, 0.9f), new Vector2(0.2f, 1.0f));

        var fade = c.CreateScalarKeyFrameAnimation();
        fade.InsertKeyFrame(0f, 0f);
        fade.InsertKeyFrame(1f, 1f, ease);
        fade.Duration = TimeSpan.FromMilliseconds(500);
        visual.StartAnimation("Opacity", fade);

        var slide = c.CreateVector3KeyFrameAnimation();
        slide.InsertKeyFrame(0f, new Vector3(0, 18, 0));
        slide.InsertKeyFrame(1f, Vector3.Zero, ease);
        slide.Duration = TimeSpan.FromMilliseconds(500);
        visual.StartAnimation("Translation", slide);
    }

    private static void Pop(UIElement element, float to)
    {
        var v = ElementCompositionPreview.GetElementVisual(element);
        if (element is FrameworkElement fe)
            v.CenterPoint = new Vector3((float)fe.ActualWidth / 2f, (float)fe.ActualHeight / 2f, 0f);

        var spring = v.Compositor.CreateSpringVector3Animation();
        spring.FinalValue = new Vector3(to, to, 1f);
        spring.DampingRatio = 0.6f;
        spring.Period = TimeSpan.FromMilliseconds(55);
        v.StartAnimation("Scale", spring);
    }

    private void Pop_Enter(object sender, PointerRoutedEventArgs e)
    {
        if (sender is UIElement el) Pop(el, 1.04f);
    }

    private void Pop_Exit(object sender, PointerRoutedEventArgs e)
    {
        if (sender is UIElement el) Pop(el, 1.0f);
    }

    // ------------------------------------------------------------- rows
    private FileRow NewRow()
    {
        var r = new FileRow();
        r.CheckRequested += row => { _ = CheckRowAsync(row); };
        r.Edited += UpdateButtons;
        return r;
    }

    private void AddRow_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Rows.Add(NewRow());
            UpdateButtons();
            DispatcherQueue.TryEnqueue(() =>
            {
                try { Scroller.ChangeView(null, Scroller.ScrollableHeight, null); } catch { }
            });
        }
        catch (Exception ex) { Logger.Log(ex, "AddRow"); }
    }

    private void RemoveRow_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if ((sender as FrameworkElement)?.DataContext is not FileRow row) return;

            if (Rows.Count <= 1)
            {
                row.Text = "";   // always keep at least one row
            }
            else
            {
                Rows.Remove(row);
                row.Dispose();
            }
            UpdateButtons();
        }
        catch (Exception ex) { Logger.Log(ex, "RemoveRow"); }
    }

    private void UpdateButtons()
    {
        bool any = Rows.Any(r => r.Text.Trim().Length > 0);
        bool enabled = any && !_exporting;
        TxtBtn.IsEnabled = enabled;
        ZipBtn.IsEnabled = enabled;
    }

    // ----------------------------------------------------- availability
    private async Task CheckRowAsync(FileRow row)
    {
        try
        {
            int ver = row.Version;
            string text = row.Text.Trim();
            if (text.Length == 0)
            {
                row.ApplyIdle("Idle - type a filename");
                return;
            }

            var wait = _indexTask;
            if (!wait.IsCompleted)
            {
                row.ApplyIdle("Waiting for index...");
                await wait;
                if (ver != row.Version) return;
            }

            var idx = _index;
            if (idx == null)
            {
                row.ApplyIdle("Select a valid root folder first");
                return;
            }

            var res = await Task.Run(() => idx.Resolve(text));
            if (ver != row.Version) return;

            if (res.Found) row.ApplyFound(res);
            else row.ApplyNotFound();
        }
        catch (Exception ex)
        {
            Logger.Log(ex, "CheckRowAsync");
        }
    }

    private async Task RecheckAllAsync()
    {
        foreach (var row in Rows.ToList())
        {
            row.CancelTimer();
            if (row.Text.Trim().Length > 0) await CheckRowAsync(row);
        }
    }

    // ------------------------------------------------------ root / index
    private void RootBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_suppressRoot) return;
        _rootTimer.Stop();
        _rootTimer.Start();   // 2s debounce for typed paths
    }

    private void RootBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter)
        {
            SafeCommit(false);
            e.Handled = true;
        }
    }

    private void RootBox_LostFocus(object sender, RoutedEventArgs e) => SafeCommit(false);

    private void Refresh_Click(object sender, RoutedEventArgs e) => SafeCommit(true);

    private async void Browse_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.DocumentsLibrary };
            picker.FileTypeFilter.Add("*");
            WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));

            var folder = await picker.PickSingleFolderAsync();
            if (folder != null)
            {
                _suppressRoot = true;
                RootBox.Text = folder.Path;
                _suppressRoot = false;
                SafeCommit(true);
            }
        }
        catch (Exception ex)
        {
            _suppressRoot = false;
            Logger.Log(ex, "Browse");
            ShowInfo(InfoBarSeverity.Error, "Could not open folder picker", ex.Message);
        }
    }

    private void SafeCommit(bool force)
    {
        try { CommitRoot(force); }
        catch (Exception ex) { Logger.Log(ex, "CommitRoot"); }
    }

    private void CommitRoot(bool force)
    {
        _rootTimer.Stop();
        string p = (RootBox.Text ?? "").Trim().Trim('"');

        if (!force && string.Equals(p, _rootPath, StringComparison.OrdinalIgnoreCase)) return;

        _rootPath = p;
        _cts?.Cancel();
        int gen = ++_indexGen;

        if (p.Length == 0)
        {
            _index = null;
            _indexTask = Task.CompletedTask;
            SetIndexStatus("No folder selected", false);
            _ = RecheckAllAsync();
            return;
        }

        if (!Directory.Exists(p))
        {
            _index = null;
            _indexTask = Task.CompletedTask;
            SetIndexStatus("Folder not found", false);
            _ = RecheckAllAsync();
            return;
        }

        _settings.LastFolder = p;
        _settings.Save();

        _cts = new CancellationTokenSource();
        var ct = _cts.Token;
        _index = null;
        SetIndexStatus("Indexing...", true);

        foreach (var r in Rows)
            if (r.Text.Trim().Length > 0) r.ApplyIdle("Indexing folder...");

        _ = IndexThenRecheckAsync(p, gen, ct);
    }

    private async Task IndexThenRecheckAsync(string root, int gen, CancellationToken ct)
    {
        try
        {
            var build = BuildIndexAsync(root, gen, ct);
            _indexTask = build;
            await build;
            if (gen == _indexGen) await RecheckAllAsync();
        }
        catch (Exception ex)
        {
            Logger.Log(ex, "IndexThenRecheck");
        }
    }

    private async Task BuildIndexAsync(string root, int gen, CancellationToken ct)
    {
        try
        {
            var idx = await Task.Run(() => FileIndex.Build(root, ct), ct);
            if (gen != _indexGen) return;
            _index = idx;
            SetIndexStatus("Indexed " + idx.Count.ToString("N0") + " files", false);
        }
        catch (OperationCanceledException)
        {
            // superseded by a newer scan
        }
        catch (Exception ex)
        {
            Logger.Log(ex, "BuildIndex");
            if (gen == _indexGen)
            {
                _index = null;
                SetIndexStatus("Could not read folder", false);
            }
        }
    }

    private void SetIndexStatus(string text, bool busy)
    {
        IndexStatus.Text = text;
        IndexRing.IsActive = busy;
        IndexRing.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
    }

    // ------------------------------------------------------------ export
    private void ExportTxt_Click(object sender, RoutedEventArgs e) => _ = ExportAsync(false);
    private void ExportZip_Click(object sender, RoutedEventArgs e) => _ = ExportAsync(true);

    private void ShowInfo(InfoBarSeverity severity, string title, string message)
    {
        InfoBarMain.Severity = severity;
        InfoBarMain.Title = title;
        InfoBarMain.Message = message;
        InfoBarMain.IsOpen = true;
    }

    private async Task ExportAsync(bool zip)
    {
        if (_exporting) return;
        _exporting = true;
        UpdateButtons();
        string? outPath = null;

        try
        {
            // Make sure the index is ready and every row has been checked, even if the user
            // clicked export before the 2s debounce elapsed.
            try { await _indexTask; } catch { }
            foreach (var row in Rows.ToList())
            {
                row.CancelTimer();
                if (row.Text.Trim().Length > 0) await CheckRowAsync(row);
            }

            var files = Rows
                .Where(r => r.State == RowState.Found && r.ResolvedFull != null)
                .GroupBy(r => r.ResolvedFull!, StringComparer.OrdinalIgnoreCase)
                .Select(g => (Rel: g.First().ResolvedRel!, Full: g.Key))
                .ToList();

            int notFound = Rows.Count(r => r.Text.Trim().Length > 0 && r.State != RowState.Found);

            if (files.Count == 0)
            {
                ShowInfo(InfoBarSeverity.Warning, "Nothing to export",
                    "None of the entered files were found. Check the root folder and file names.");
                return;
            }

            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            outPath = UniquePath(desktop, "Grab_" + DateTime.Now.ToString("yyyyMMdd_HHmmss"), zip ? ".zip" : ".txt");
            string target = outPath;

            ExportResult result = await Task.Run(() => zip ? WriteZip(target, files) : WriteTxt(target, files));

            if (result.Written == 0)
            {
                TryDelete(target);
                ShowInfo(InfoBarSeverity.Error, "Export failed",
                    "None of the files could be read (they may be locked, moved or deleted).");
                return;
            }

            int skipped = result.Failed.Count + notFound;
            string msg = "Saved " + result.Written + " file(s) to Desktop: " + Path.GetFileName(target);
            if (skipped > 0) msg += "  (" + skipped + " skipped)";
            ShowInfo(InfoBarSeverity.Success, "Export complete", msg);

            ClearRows();
        }
        catch (UnauthorizedAccessException ex)
        {
            Logger.Log(ex, "Export");
            if (outPath != null) TryDelete(outPath);
            ShowInfo(InfoBarSeverity.Error, "Access denied", "Could not write to the Desktop. " + ex.Message);
        }
        catch (Exception ex)
        {
            Logger.Log(ex, "Export");
            if (outPath != null) TryDelete(outPath);
            ShowInfo(InfoBarSeverity.Error, "Export failed", ex.Message);
        }
        finally
        {
            _exporting = false;
            UpdateButtons();
        }
    }

    private void ClearRows()
    {
        foreach (var r in Rows) r.Dispose();
        Rows.Clear();
        Rows.Add(NewRow());
        UpdateButtons();
    }

    private static string UniquePath(string dir, string baseName, string ext)
    {
        string p = Path.Combine(dir, baseName + ext);
        int i = 1;
        while (File.Exists(p))
        {
            p = Path.Combine(dir, baseName + "_" + i + ext);
            i++;
        }
        return p;
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

    private static ExportResult WriteTxt(string path, List<(string Rel, string Full)> files)
    {
        var res = new ExportResult();
        var utf8 = new UTF8Encoding(false);   // UTF-8 without BOM

        using var fs = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        using var sw = new StreamWriter(fs, utf8);

        foreach (var (rel, full) in files)
        {
            string content;
            try
            {
                using var rf = new FileStream(full, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                using var sr = new StreamReader(rf, utf8, true);
                content = sr.ReadToEnd();
            }
            catch (Exception ex)
            {
                Logger.Log(ex, "Read " + full);
                res.Failed.Add(rel);
                continue;
            }

            sw.Write(rel);
            sw.Write(":\n\n");
            sw.Write(content);
            sw.Write("\n\n\n");
            res.Written++;
        }

        sw.Flush();
        return res;
    }

    private static ExportResult WriteZip(string path, List<(string Rel, string Full)> files)
    {
        var res = new ExportResult();

        using var fs = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        using var zip = new ZipArchive(fs, ZipArchiveMode.Create, false, new UTF8Encoding(false));

        foreach (var (rel, full) in files)
        {
            try
            {
                using var rf = new FileStream(full, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                var entry = zip.CreateEntry(rel.Replace('\\', '/'), CompressionLevel.Optimal);
                using var es = entry.Open();
                rf.CopyTo(es);
                res.Written++;
            }
            catch (Exception ex)
            {
                Logger.Log(ex, "Zip " + full);
                res.Failed.Add(rel);
            }
        }

        return res;
    }
}
'@

# ---------------------------------------------------------------------
# 2. Build + publish
# ---------------------------------------------------------------------
Write-Host 'Restoring, building and publishing (first run downloads NuGet packages; this can take a few minutes)...' -ForegroundColor Cyan
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }

Push-Location $src
try {
    & dotnet publish .\Grab.csproj `
        -c Release `
        -r win-x64 `
        --self-contained true `
        -p:Platform=x64 `
        -p:PublishSingleFile=true `
        -p:DebugType=None `
        -p:DebugSymbols=false `
        -o $out `
        --nologo
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit code $LASTEXITCODE). Review the compiler output above." }
}
finally {
    Pop-Location
}

$exe = Join-Path $out 'Grab.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "Build finished but '$exe' was not produced." }

# ---------------------------------------------------------------------
# 3. Launch
# ---------------------------------------------------------------------
Write-Host "Published: $exe" -ForegroundColor Green
Write-Host 'Launching GRAB...' -ForegroundColor Green
Start-Process -FilePath $exe -WorkingDirectory $out