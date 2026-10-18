@echo off
"%SystemRoot%\System32\chcp.com" 65001 >nul
for %%I in ("%~dp0..\models") do set "JANAS_MODELS=%%~fI"
set "JANAS_GPU=0"
for %%I in ("%~dp0..\bin\janas\janas-chat.exe") do set "JANAS_CHAT=%%~fI"
"%JANAS_CHAT%" qwen3.6-35b-a3b --reserve 8 --no-tune
