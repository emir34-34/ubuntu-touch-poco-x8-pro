#!/bin/bash
# Build the APK without Gradle: aapt2 + javac + d8 + zipalign + apksigner.
set -euo pipefail
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
BT=$SDK/build-tools/35.0.0
JAR=$SDK/platforms/android-34/android.jar
OUT=build
rm -rf "$OUT"; mkdir -p "$OUT/res" "$OUT/classes" "$OUT/dex"

"$BT/aapt2" compile --dir res -o "$OUT/res/res.zip"
"$BT/aapt2" link -o "$OUT/unsigned.apk" -I "$JAR" --manifest AndroidManifest.xml \
	--java "$OUT/gen" "$OUT/res/res.zip"
javac --release 11 -nowarn -classpath "$JAR" -d "$OUT/classes" \
	$(find src "$OUT/gen" -name '*.java')
"$BT/d8" --release --min-api 30 --lib "$JAR" --output "$OUT/dex" $(find "$OUT/classes" -name '*.class')
python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1], 'a', zipfile.ZIP_DEFLATED).write(sys.argv[2], 'classes.dex')" "$OUT/unsigned.apk" "$OUT/dex/classes.dex"
"$BT/zipalign" -f -p 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"

KS=${KLEE_KEYSTORE:-$HOME/klee-ut/apps/klee-debug.keystore}
[ -f "$KS" ] || keytool -genkeypair -keystore "$KS" -storepass kleekey -keypass kleekey \
	-alias klee -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=klee dual boot" >/dev/null 2>&1
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:kleekey --key-pass pass:kleekey \
	--out "$OUT/ubuntuya-gec.apk" "$OUT/aligned.apk"
"$BT/apksigner" verify "$OUT/ubuntuya-gec.apk"
echo "built: $(pwd)/$OUT/ubuntuya-gec.apk"
