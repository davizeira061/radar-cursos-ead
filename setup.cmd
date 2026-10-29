@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-github-repo.ps1" %*
