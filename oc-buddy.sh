#!/bin/bash
# PORTMASTER: oc-buddy.zip, oc-buddy.sh

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source "$controlfolder/control.txt"
source "$controlfolder/device_info.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

get_controls

GAMEDIR="/roms/ports/oc-buddy"
CONFDIR="$GAMEDIR/conf"
mkdir -p "$CONFDIR"

export XDG_CONFIG_HOME="$CONFDIR"
export XDG_DATA_HOME="$CONFDIR"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

cd "$GAMEDIR" || exit 1
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

runtime="frt_3.5.2"
godot_file="$controlfolder/libs/${runtime}.squashfs"

if [ ! -f "$godot_file" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    echo "Godot runtime not found. Update PortMaster first." > /dev/tty0
    sleep 5
    exit 1
  fi
  $ESUDO "$controlfolder/harbourmaster" --quiet --no-check runtime_check "${runtime}.squashfs"
fi

godot_dir="$HOME/godot"
$ESUDO mkdir -p "$godot_dir"
$ESUDO umount "$godot_file" || true
$ESUDO mount "$godot_file" "$godot_dir" || exit 1
PATH="$godot_dir:$PATH"

export FRT_NO_EXIT_SHORTCUTS=1
export FRT_EXIT_SHORTCUT=esc
GODOT_OPTS="${GODOT_OPTS:-} --video-driver GLES2"

gptokeyb_pid=""
cleanup() {
  if [ -n "$gptokeyb_pid" ]; then
    $ESUDO kill "$gptokeyb_pid" >/dev/null 2>&1 || true
    wait "$gptokeyb_pid" 2>/dev/null || true
  fi
  $ESUDO umount "$godot_dir" >/dev/null 2>&1 || true
  $ESUDO systemctl restart oga_events >/dev/null 2>&1 &
  printf '\033c' > /dev/tty0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

$ESUDO chmod 666 /dev/uinput
$GPTOKEYB "$runtime" -c "./oc-buddy.gptk" &
gptokeyb_pid=$!

"$runtime" $GODOT_OPTS --main-pack "oc-buddy.pck"
exit $?
