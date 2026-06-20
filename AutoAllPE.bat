@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM Сколько видео обрабатывать одновременно. Авто-расчёт по числу ядер:
REM каждое видео само грузит несколько ядер (libx264 multi-thread), поэтому
REM параллельных видео берём заметно меньше, чем ядер, иначе диск/CPU забьются.
REM Хочешь зафиксировать вручную — закомментируй блок ниже и пропиши число сам.
set /a MAX_PARALLEL=%NUMBER_OF_PROCESSORS% / 2
if %MAX_PARALLEL% LSS 2 set MAX_PARALLEL=2
if %MAX_PARALLEL% GTR 6 set MAX_PARALLEL=6

REM ======== ПРОВЕРКА FFMPEG ========
set "FFMPEG_CMD=ffmpeg"
set "FFPROBE_CMD=ffprobe"

if exist "%~dp0ffmpeg\ffmpeg.exe" (
    set "FFMPEG_CMD=%~dp0ffmpeg\ffmpeg.exe"
    set "FFPROBE_CMD=%~dp0ffmpeg\ffprobe.exe"
    echo Используется портативный FFmpeg
) else (
    echo Используется системный FFmpeg
)

"%FFMPEG_CMD%" -version >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: FFmpeg не найден!
    echo Установите FFmpeg или поместите ffmpeg.exe и ffprobe.exe в папку ffmpeg\
    pause
    exit /b 1
)

if not exist "%~dp0process_one.bat" (
    echo ОШИБКА: process_one.bat не найден рядом с AutoAllPE.bat
    pause
    exit /b 1
)

if not exist "videos\" (
    echo ОШИБКА: папка videos\ не найдена. Создай её и положи видео туда.
    pause
    exit /b 1
)

mkdir clips\16x9_18sec 2>nul
mkdir clips\9x16_18sec 2>nul
mkdir clips\16x9_65sec 2>nul
mkdir clips\9x16_65sec 2>nul
mkdir JAS\16x9_18sec 2>nul
mkdir JAS\9x16_18sec 2>nul
mkdir JAS\16x9_65sec 2>nul
mkdir JAS\9x16_65sec 2>nul
mkdir JAS_teaser\16x9_18sec 2>nul
mkdir JAS_teaser\9x16_18sec 2>nul
mkdir frames\16x9 2>nul
mkdir frames\9x16 2>nul

if exist "%~dp0timings.log" del "%~dp0timings.log" 2>nul
set "TOTAL_START=%TIME%"

echo ════════════════════════════════════════════
echo   НАРЕЗКА: 18 СЕК + 1:05, ПАРАЛЛЕЛЬНО (до %MAX_PARALLEL% видео)
echo   Источник: videos\
echo ════════════════════════════════════════════
echo.

set FOUND=0
for %%F in (videos\*.mp4 videos\*.mov videos\*.mkv) do (
    set FOUND=1
    call :wait_slot

    echo Запуск: %%F
    start "AutoSlice_%%~nF" /min cmd /c call "%~dp0process_one.bat" "%%F" "!FFMPEG_CMD!" "!FFPROBE_CMD!"
    REM Маленькая пауза, чтобы заголовок успел зарегистрироваться перед следующей проверкой слотов
    timeout /t 1 /nobreak >nul
)

if !FOUND! EQU 0 (
    echo Видео не найдено в videos\. Положи .mp4/.mov/.mkv туда.
    pause
    exit /b 0
)

echo.
echo Ожидание завершения всех видео...
call :wait_all

set "TOTAL_END=%TIME%"
call :elapsed "%TOTAL_START%" "%TOTAL_END%" TOTAL_ELAPSED

echo.
echo ════════════════════════════════════════════
echo   ВРЕМЯ ОБРАБОТКИ ПО ВИДЕО:
echo ════════════════════════════════════════════
if exist "%~dp0timings.log" (
    type "%~dp0timings.log"
) else (
    echo   (лог времён не найден)
)
echo ════════════════════════════════════════════
echo   ОБЩЕЕ ВРЕМЯ: %TOTAL_ELAPSED%
echo ════════════════════════════════════════════

REM Чистим папки 65-сек, если все видео короче 65 сек (остались пустыми)
for %%D in (clips\16x9_65sec clips\9x16_65sec JAS\16x9_65sec JAS\9x16_65sec) do rmdir "%%D" 2>nul

echo.
echo ✅ ВСЁ ГОТОВО!
echo    frames\      - стоп-кадры каждые 3 сек (x2 upscale)
echo    clips\       - нарезки (без re-encode, где не нужно)
echo    JAS\         - дубликаты с музыкой из папки music
echo    JAS_teaser\  - клипы 18 сек без звука
pause
exit /b 0

:wait_slot
for /f %%C in ('tasklist /fi "windowtitle eq AutoSlice_*" 2^>nul ^| find /c /i "cmd.exe"') do set RUNNING=%%C
if !RUNNING! GEQ %MAX_PARALLEL% (
    timeout /t 2 /nobreak >nul
    goto :wait_slot
)
exit /b 0

:wait_all
for /f %%C in ('tasklist /fi "windowtitle eq AutoSlice_*" 2^>nul ^| find /c /i "cmd.exe"') do set RUNNING=%%C
if !RUNNING! GTR 0 (
    timeout /t 2 /nobreak >nul
    goto :wait_all
)
exit /b 0

:elapsed
setlocal
set "_s=%~1"
set "_e=%~2"
for /f "tokens=1-4 delims=:.," %%a in ("%_s%") do set /a _sh=100%%a%%100, _sm=100%%b%%100, _ss=100%%c%%100, _sc=100%%d%%100
for /f "tokens=1-4 delims=:.," %%a in ("%_e%") do set /a _eh=100%%a%%100, _em=100%%b%%100, _es=100%%c%%100, _ec=100%%d%%100
set /a _st=(_sh*360000)+(_sm*6000)+(_ss*100)+_sc
set /a _et=(_eh*360000)+(_em*6000)+(_es*100)+_ec
set /a _diff=_et-_st
if %_diff% lss 0 set /a _diff+=8640000
set /a _min=_diff/6000
set /a _sec=(_diff%%6000)/100
set /a _cs=_diff%%100
endlocal & set "%~3=%_min%m %_sec%.%_cs%s"
goto :eof
