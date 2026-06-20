@echo off
REM Обрабатывает ОДНО видео. Вызывается из AutoAllPE.bat параллельно
REM по нескольку штук — поэтому все временные файлы именуются по
REM имени видео, чтобы не пересекаться с другими запущенными копиями.
setlocal enabledelayedexpansion
chcp 65001 >nul

set "VIDEO=%~1"
set "FFMPEG_CMD=%~2"
set "FFPROBE_CMD=%~3"
set "NAME=%~n1"
set "TMPFILE=duration_%NAME%.tmp"

REM Resume: если видео уже полностью обработано в прошлом запуске — пропускаем.
REM Удали файл .done\<имя>.done, чтобы обработать видео заново.
if exist "%~dp0.done\%NAME%.done" (
    echo [%NAME%] Уже обработано ^(см. .done\%NAME%.done^), пропуск
    >>"%~dp0timings.log" echo %NAME%: пропущено - уже обработано
    exit /b 0
)

echo ═══ [%NAME%] Старт ═══
set "V_START=%TIME%"

"%FFMPEG_CMD%" -version >nul 2>&1
if errorlevel 1 (
    echo [%NAME%] ОШИБКА: FFmpeg не доступен в дочернем процессе
    exit /b 1
)

"%FFPROBE_CMD%" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "%VIDEO%" > "%TMPFILE%"
set /p DURATION_RAW=<"%TMPFILE%"
del "%TMPFILE%" 2>nul

for /f "tokens=1 delims=." %%A in ("%DURATION_RAW%") do set DURATION=%%A

if "%DURATION%"=="" (
    echo [%NAME%] ОШИБКА: не удалось получить длительность видео
    exit /b 1
)

echo [%NAME%] Длительность: %DURATION% сек

REM ======== СТОП-КАДРЫ — ОДИН ПРОХОД fps=1/3 ВМЕСТО СОТЕН ВЫЗОВОВ ========
set "TMP16=frames\16x9\%NAME%_tmp"
set "TMP9=frames\9x16\%NAME%_tmp"
mkdir "%TMP16%" 2>nul
mkdir "%TMP9%" 2>nul

"%FFMPEG_CMD%" -y -i "%VIDEO%" -vf "fps=1/3,scale=iw*2:ih*2:flags=lanczos" -pix_fmt yuvj420p -q:v 2 "%TMP16%\f_%%04d.jpg" -loglevel error

"%FFMPEG_CMD%" -y -i "%VIDEO%" -vf "fps=1/3,scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,scale=iw*2:ih*2:flags=lanczos" -pix_fmt yuvj420p -q:v 2 "%TMP9%\f_%%04d.jpg" -loglevel error

REM Переименование: f_0001 -> NAME_0s.jpg, f_0002 -> NAME_3s.jpg, ...
set IDX=0
for %%P in ("%TMP16%\*.jpg") do (
    set /a SEC=IDX*3
    move "%%P" "frames\16x9\%NAME%_!SEC!s.jpg" >nul
    set /a IDX+=1
)
rmdir "%TMP16%" 2>nul

set IDX=0
for %%P in ("%TMP9%\*.jpg") do (
    set /a SEC=IDX*3
    move "%%P" "frames\9x16\%NAME%_!SEC!s.jpg" >nul
    set /a IDX+=1
)
rmdir "%TMP9%" 2>nul

echo [%NAME%] Кадры готовы

REM ======== НАРЕЗКА 18 СЕК — COPY ГДЕ НЕ НУЖЕН RE-ENCODE ========
REM Внимание: -c copy режет по ближайшему keyframe ДО точки старта,
REM начало клипа может сместиться на доли секунды — это плата за скорость.
set /a PARTS_18=DURATION / 18 - 1
if !PARTS_18! LSS 0 set PARTS_18=0
echo [%NAME%] Частей по 18 сек: !PARTS_18!

for /L %%I in (0,1,!PARTS_18!) do (
    set /a START=%%I * 18

    "%FFMPEG_CMD%" -y -ss !START! -t 18 -i "%VIDEO%" -c copy "clips\16x9_18sec\%NAME%_%%I.mp4" -loglevel error

    "%FFMPEG_CMD%" -y -ss !START! -t 18 -i "%VIDEO%" -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920" -c:v libx264 -preset veryfast -crf 18 -c:a copy "clips\9x16_18sec\%NAME%_%%I.mp4" -loglevel error

    "%FFMPEG_CMD%" -y -ss !START! -t 18 -i "%VIDEO%" -an -c:v copy "JAS_teaser\16x9_18sec\%NAME%_%%I.mp4" -loglevel error

    "%FFMPEG_CMD%" -y -ss !START! -t 18 -i "%VIDEO%" -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920" -an -c:v libx264 -preset veryfast -crf 18 "JAS_teaser\9x16_18sec\%NAME%_%%I.mp4" -loglevel error
)

REM ======== НАРЕЗКА 1:05 — COPY ГДЕ НЕ НУЖЕН RE-ENCODE ========
set /a PARTS_65=DURATION / 65 - 1
if !PARTS_65! LSS 0 set PARTS_65=0
echo [%NAME%] Частей по 1:05: !PARTS_65!

for /L %%I in (0,1,!PARTS_65!) do (
    set /a START=%%I * 65

    "%FFMPEG_CMD%" -y -ss !START! -t 65 -i "%VIDEO%" -c copy "clips\16x9_65sec\%NAME%_%%I.mp4" -loglevel error

    "%FFMPEG_CMD%" -y -ss !START! -t 65 -i "%VIDEO%" -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920" -c:v libx264 -preset veryfast -crf 18 -c:a copy "clips\9x16_65sec\%NAME%_%%I.mp4" -loglevel error
)

echo [%NAME%] Клипы готовы

REM ======== JAS — ДУБЛИКАТЫ С МУЗЫКОЙ ИЗ ПАПКИ MUSIC ========
set MUSIC_COUNT=0
for %%M in (music\*.mp3 music\*.wav music\*.m4a) do (
    set /a MUSIC_COUNT+=1
    set MUSIC_!MUSIC_COUNT!=%%M
    set MUSIC_NAME_!MUSIC_COUNT!=%%~nM
)

if !MUSIC_COUNT! GTR 0 (
    for /L %%I in (0,1,!PARTS_18!) do (
        set /a START=%%I * 18
        set /a MIDX=%%I %% !MUSIC_COUNT! + 1
        call set CM=%%MUSIC_!MIDX!%%
        call set CMN=%%MUSIC_NAME_!MIDX!%%

        "%FFMPEG_CMD%" -y -ss !START! -t 18 -i "%VIDEO%" -i "!CM!" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 192k -shortest "JAS\16x9_18sec\%NAME%_%%I_!CMN!.mp4" -loglevel error

        "%FFMPEG_CMD%" -y -ss !START! -t 18 -i "%VIDEO%" -i "!CM!" -map 0:v -map 1:a -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920" -c:v libx264 -preset veryfast -crf 18 -c:a aac -b:a 192k -shortest "JAS\9x16_18sec\%NAME%_%%I_!CMN!.mp4" -loglevel error
    )

    for /L %%I in (0,1,!PARTS_65!) do (
        set /a START=%%I * 65
        set /a MIDX=%%I %% !MUSIC_COUNT! + 1
        call set CM=%%MUSIC_!MIDX!%%
        call set CMN=%%MUSIC_NAME_!MIDX!%%

        "%FFMPEG_CMD%" -y -ss !START! -t 65 -i "%VIDEO%" -i "!CM!" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 192k -shortest "JAS\16x9_65sec\%NAME%_%%I_!CMN!.mp4" -loglevel error

        "%FFMPEG_CMD%" -y -ss !START! -t 65 -i "%VIDEO%" -i "!CM!" -map 0:v -map 1:a -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920" -c:v libx264 -preset veryfast -crf 18 -c:a aac -b:a 192k -shortest "JAS\9x16_65sec\%NAME%_%%I_!CMN!.mp4" -loglevel error
    )
) else (
    echo [%NAME%] Папка music пуста, пропускаем JAS
)

set "V_END=%TIME%"
call :elapsed "%V_START%" "%V_END%" V_ELAPSED
echo [%NAME%] Время обработки: %V_ELAPSED%
>>"%~dp0timings.log" echo %NAME%: %V_ELAPSED%

mkdir "%~dp0.done" 2>nul
>"%~dp0.done\%NAME%.done" echo done

echo ✅ [%NAME%] Готово
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
