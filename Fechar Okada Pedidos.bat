@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "8085..8090 | ForEach-Object { try { (New-Object System.Net.WebClient).DownloadString('http://127.0.0.1:' + $_ + '/sair') } catch {} }" > nul 2>&1
echo Aplicativo encerrado.
