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
try {
    New-NetFirewallRule -DisplayName "AllowWebServer" -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
} catch {
    Write-Host "Failed to create firewall rule. Please run PowerShell as Administrator." -ForegroundColor Red
    exit
}

# Start the web server
$webServer = New-Object System.Net.HttpListener 
$webServer.Prefixes.Add("http://$localIP:$port/")  # Listen on local IP
$webServer.Prefixes.Add("http://localhost:$port/")  # Listen on localhost
try {
    $webServer.Start()
} catch {
    Write-Host "Failed to start the web server. Ensure that the firewall rule was created successfully." -ForegroundColor Red
    exit
}

Write-Host ("Network Devices Can Reach the server at : http://$localIP:$port") 
Write-Host "Press escape key for 5 seconds to exit" -ForegroundColor Cyan
Write-Host "Hiding this window.." -ForegroundColor Yellow
Start-Sleep -Seconds 4

# Code to hide the console on Windows 10 and 11
if ($hide -eq 1) {
    $Async = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
    $Type = Add-Type -MemberDefinition $Async - Name Win32ShowWindow -PassThru
    $Type::ShowWindowAsync((Get-Process -Id $pid).MainWindowHandle, 0) | Out-Null
}

# Main loop to handle requests
while ($true) {
    try {
        $context = $webServer.GetContext()
        $request = $context.Request
        $response = $context.Response

        # Check for valid hostname
        if ($request.Url.Host -ne $localIP -and $request.Url.Host -ne "localhost") {
            $response.StatusCode = 400
            $response.StatusDescription = "Bad Request - Invalid Hostname"
            $response.OutputStream.Write([System.Text.Encoding]::UTF8.GetBytes("Bad Request - Invalid Hostname"))
            $response.OutputStream.Close()
            continue
        }

        # Process the request and send a response
        $response.ContentType = "text/plain"
        $response.StatusCode = 200
        $response.OutputStream.Write([System.Text.Encoding]::UTF8.GetBytes("Hello from $localIP"))
        $response.OutputStream.Close()
    } catch {
        Write-Host "An error occurred: $_" -ForegroundColor Red
    }
}
