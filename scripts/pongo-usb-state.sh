#!/usr/bin/env bash
# Print the local Apple USB device state without opening a USB device.
set -euo pipefail

expected=''
if [[ "${1:-}" == --expect ]]; then
  expected=$2
fi

declare -a paths=()
declare -a products=()
declare -a serials=()
declare -a topologies=()

for devpath in /sys/bus/usb/devices/*; do
  [[ -f "$devpath/idVendor" && -f "$devpath/idProduct" ]] || continue
  vid=$(cat "$devpath/idVendor")
  pid=$(cat "$devpath/idProduct")
  case "$vid:$pid" in
    05ac:1227) product=DFU ;;
    05ac:1281) product=Recovery ;;
    05ac:4141) product=Pongo ;;
    05ac:12ab) product=iPadOS ;;
    1d6b:0104) product=Linux ;;
    *) continue ;;
  esac
  paths+=("$devpath")
  products+=("$product")
  serials+=("$(cat "$devpath/serial" 2>/dev/null || true)")
  topologies+=("$(basename "$devpath")")
done

count=${#paths[@]}
if [[ $count -eq 0 ]]; then
  state=none
elif [[ $count -gt 1 ]]; then
  state=multiple
else
  state=${products[0]}
fi

echo "STATE=$state"
if [[ $count -eq 0 ]]; then
  echo "COUNT=0"
else
  echo "COUNT=$count"
  for i in "${!paths[@]}"; do
    bus=$(cat "${paths[$i]}/busnum")
    dev=$(cat "${paths[$i]}/devnum")
    node=$(printf '/dev/bus/usb/%03d/%03d' "$bus" "$dev")
    echo "DEVICE[$i]=${paths[$i]}"
    echo "PRODUCT[$i]=${products[$i]}"
    echo "SERIAL[$i]=${serials[$i]}"
    echo "TOPOLOGY[$i]=${topologies[$i]}"
    echo "NODE[$i]=$node"
    if [[ -e "$node" ]]; then
      echo "NODE_MODE[$i]=$(stat -c %A "$node")"
      echo "NODE_OWNER[$i]=$(stat -c %U "$node")"
      echo "NODE_GROUP[$i]=$(stat -c %G "$node")"
    fi
  done
fi

if [[ -n "$expected" && "$state" != "$expected" ]]; then
  echo "EXPECTED=$expected" >&2
  exit 1
fi
