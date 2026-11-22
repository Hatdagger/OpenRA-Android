#!/usr/bin/env bash
# Installs and launches the APK on a running emulator, capturing screenshots and logcat into ./smoke.
set -u
mkdir -p smoke
adb install -r out/OpenRA-Android.apk > smoke/install.txt 2>&1
cat smoke/install.txt
adb logcat -c
adb shell am start -n net.openra.android/net.openra.android.OpenRAActivity
for t in 30 60 120 180 240; do
	sleep $(( t - ${last:-0} ))
	last=$t
	adb exec-out screencap -p > "smoke/screen-${t}s.png"
	echo "screenshot at ${t}s"
done
adb logcat -d > smoke/logcat-full.txt
grep -E "OpenRA|DOTNET|mono|monodroid|SDL|AndroidRuntime|FATAL|libc|DEBUG" smoke/logcat-full.txt > smoke/logcat-openra.txt || true
adb shell run-as net.openra.android ls -R files/support 2>/dev/null | head -50 > smoke/support-files.txt || true
for f in debug exception graphics perf; do
	adb shell run-as net.openra.android cat "files/support/Logs/$f.log" > "smoke/$f.log" 2>/dev/null || true
done
tail -n 80 smoke/logcat-openra.txt
exit 0
