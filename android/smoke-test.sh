#!/usr/bin/env bash
# Installs the APK on a running emulator with the Red Alert game files pre-loaded,
# launches it, and captures screenshots, logcat and OpenRA's own logs into ./smoke.
set -u
PKG=net.openra.android
mkdir -p smoke

echo "=== Fetching the Red Alert quick-install package"
mkdir -p /tmp/racontent && cd /tmp/racontent
for url in $(curl -fsSL https://www.openra.net/packages/ra-quickinstall-mirrors.txt); do
	curl -fsSL -o ra.zip "$url" && break
done
echo "44241f68e69db9511db82cf83c174737ccda300b  ra.zip" | sha1sum -c - || echo "WARNING: checksum mismatch"
mkdir -p zip stage && unzip -qo ra.zip -d zip
# Lay files out the way the in-game installer does (see mods/ra-content/installer/downloads.yaml).
sed -n '/^quickinstall:/,/^[^\t ]/p' "$OLDPWD/mods/ra-content/installer/downloads.yaml" \
	| grep -o '\^SupportDir|Content/ra/v2/[^:]*: .*' \
	| while IFS= read -r line; do
		dest="${line#^SupportDir|}"; dest="${dest%%:*}"
		src="${line#*: }"
		mkdir -p "stage/$(dirname "$dest")"
		cp "zip/$src" "stage/$dest"
	done
cd "$OLDPWD"
find /tmp/racontent/stage -type f | wc -l

echo "=== Installing"
adb root > /dev/null 2>&1; sleep 3; adb wait-for-device
adb install -r out/OpenRA-Android.apk > smoke/install.txt 2>&1
cat smoke/install.txt
EXT=/sdcard/Android/data/$PKG/files
# Launch once so Android creates the app's external folder, then pre-load the game files
# as root with the app's ownership and SELinux labels.
adb shell am start -n $PKG/$PKG.OpenRAActivity > /dev/null
sleep 15
adb shell am force-stop $PKG
RAW=/data/media/0/Android/data/$PKG/files
OWNER=$(adb shell stat -c %u:%g "$RAW" | tr -d '\r')
echo "external files owner: $OWNER"
adb shell mkdir -p "$RAW/support"
adb push /tmp/racontent/stage/Content "$RAW/support/" > /dev/null
adb shell chown -R "$OWNER" "$RAW/support"
adb shell restorecon -R "$RAW/support"
adb shell ls -lZ "$RAW/support/Content/ra/v2" | head -5

echo "=== Launching"
adb logcat -c
adb shell am start -n $PKG/$PKG.OpenRAActivity
last=0
for t in 20 40 60 90 120 180 240; do
	sleep $(( t - last )); last=$t
	adb exec-out screencap -p > "smoke/screen-${t}s.png"
	echo "screenshot at ${t}s (pid: $(adb shell pidof $PKG))"
	# If the pre-loaded files weren't picked up, press "Quick Install" like a player would
	# (button position on the 2560x1800 pixel_c screen).
	if [ "$t" = 20 ] && grep -q "Loading mod: ra-content" <(adb logcat -d -s DOTNET); then
		echo "Content installer is showing; tapping Quick Install"
		adb shell input swipe 1263 1092 1263 1092 200
	fi
done

adb logcat -d > smoke/logcat-full.txt
PID_LINES=$(grep -E "OpenRA|DOTNET|mono|monodroid|SDL|AndroidRuntime|FATAL|F DEBUG|F libc|ndk_translation" smoke/logcat-full.txt)
echo "$PID_LINES" > smoke/logcat-openra.txt
adb pull "$EXT/support/Logs" smoke/Logs > /dev/null 2>&1 || true
adb shell ls -R "$EXT/support" > smoke/support-files.txt 2>&1 || true
tail -n 100 smoke/logcat-openra.txt
for f in smoke/Logs/*.log; do [ -f "$f" ] && { echo "=== $f"; tail -n 60 "$f"; }; done
exit 0
