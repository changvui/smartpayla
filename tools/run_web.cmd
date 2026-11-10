@echo off
REM Wrapper so the script can run even when PowerShell blocks .ps1 files.
REM Double-click this file, or run:  tools\run_web.cmd
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_web.ps1" %*
