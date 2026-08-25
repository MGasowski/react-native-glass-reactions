#!/bin/bash
#
# capture-gif.sh <in.mov> <out.gif> [width] [fps]
#
# Turns a screen recording into a README-sized GIF. Two passes so the palette
# is generated from the clip's own colours: the demo screen's artwork is
# heavily saturated and a generic 256-colour table bands it badly.
#
# Recording the input:
#   iOS      xcrun simctl io <UDID> recordVideo --codec h264 --force out.mov
#   Android  adb shell screenrecord --bit-rate 12000000 /sdcard/out.mp4
#
# Driving the gesture is platform-specific, because press-hold-drag cannot be
# synthesised by the usual tools:
#   iOS      the testCaptureDemoGesture XCUITest in example/ios
#   Android  adb shell input draganddrop <x1> <y1> <x2> <y2> <ms>
# `simctl`, Maestro, and `adb shell input swipe` all press and release as one
# event, or move before the long-press threshold, so none of them can open the
# picker and then traverse it.
IN="$1"; OUT="$2"; W="${3:-900}"; FPS="${4:-24}"
ffmpeg -v error -i "$IN" -vf "fps=$FPS,scale=$W:-1:flags=lanczos,palettegen=stats_mode=diff" -y /tmp/pal.png
ffmpeg -v error -i "$IN" -i /tmp/pal.png -lavfi "fps=$FPS,scale=$W:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=sierra2_4a:diff_mode=rectangle" -y "$OUT"
ls -lh "$OUT" | awk '{print $9, $5}'
