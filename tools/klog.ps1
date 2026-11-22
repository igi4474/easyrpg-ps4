# Captures the PS4's GoldHEN klog (port 3232) into klog.txt next to this script.
# Usage: right-click > Run with PowerShell, type the PS4's IP, THEN start the app on the PS4.
# Stop with Ctrl+C or by closing the window.
$ip = Read-Host "PS4 IP address"
$out = Join-Path $PSScriptRoot "klog.txt"
Write-Host "Connecting to ${ip}:3232 ... (saving to $out)"
$client = New-Object System.Net.Sockets.TcpClient($ip, 3232)
$reader = New-Object System.IO.StreamReader($client.GetStream())
Write-Host "Connected. Now launch the app on the PS4."
while ($true) {
    $line = $reader.ReadLine()
    if ($line -eq $null) { break }
    Write-Host $line
    Add-Content -Path $out -Value $line
}
