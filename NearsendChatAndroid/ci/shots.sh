#!/bin/bash
# Runs inside the emulator: installs the debug APK and screenshots each screen (day, then night).
set -x
APK=app/build/outputs/apk/debug/app-debug.apk
adb install -r "$APK"
mkdir -p shots
shot() { # name, extras...
  adb shell am force-stop app.nearsend.chat
  adb shell am start -n app.nearsend.chat/.MainActivity "${@:2}"
  sleep 6
  adb exec-out screencap -p > "shots/$1.png"
}
adb shell cmd uimode night no
# Warm-up launch: the first start after install is slow and can screenshot as a blank frame.
adb shell am start -n app.nearsend.chat/.MainActivity --ez onboarded true
sleep 15
shot 1-onboarding --ez onboarded false
shot 2-nearby --ez onboarded true --ei tab 0
shot 3-chats --ez onboarded true --ei tab 1
shot 4-thread --ez onboarded true --ei tab 1 --es thread a
shot 5-you --ez onboarded true --ei tab 2
shot 9-public-channel --ez onboarded true --ei tab 1 --es thread public
shot 17-contact-info --ez onboarded true --ei tab 1 --es thread a --ez info true
shot 10-nearby-sv --ez onboarded true --ei tab 0 --es lang sv
shot 11-you-sv --ez onboarded true --ei tab 2 --es lang sv
shot 12-you-ar --ez onboarded true --ei tab 2 --es lang ar
shot 13-nearby-ja --ez onboarded true --ei tab 0 --es lang ja
shot 14-thread-de --ez onboarded true --ei tab 1 --es thread a --es lang de
shot 15-onboarding-ru --ez onboarded false --es lang ru
adb shell cmd uimode night yes
sleep 2
# The language extra is saved like the in-app picker, so go back to the phone's language (English) for the rest.
shot 6-nearby-night --ez onboarded true --ei tab 0 --es lang system
shot 7-thread-night --ez onboarded true --ei tab 1 --es thread a
shot 8-onboarding-night --ez onboarded false
