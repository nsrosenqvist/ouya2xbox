#!/bin/bash

: ${TMPDIR:=/tmp}
# Define event variables
event=""
eventJs=""
eventMouse=""
eventPermission=""
emulationID=""

declare -A controllerVirtMap
declare -A emulationMap
declare -A controllerRealMap
declare -A controllerTempMap
controllers=()
eventResets=()
processes=()
logfiles=()

# Trap
function terminate () {
	# Check if something is running
	if [ ${#processes[@]} -gt 0 ]; then
		echo -e "\nStopping emulation"
	fi

	# Stop xboxdrv
	for i in "${processes[@]}"; do
		kill $i
	done

	# Delete logfiles
	for i in "${logfiles[@]}"; do
		rm "$i"
	done

	# Reset event permissions
	for i in "${eventResets[@]}"; do
		chmod "$eventPermission" "/dev/input/$i"
	done

        exit 0
}

# Find OUYA event id
function get_new_device() {
	devices="$(cat /proc/bus/input/devices)"
	controller_info="$(echo -e "$devices" | awk "/$1/" RS="\n\n" ORS="\n\n")"
	handlers="$(echo -e "$controller_info" | grep Handler)"

	# Loop through found controllers
	while read -r line; do
		# Skip empty lines
		if [ -z "$line" ]; then
			continue
		fi

		events=(${line#*=})
		controllerTempMap=()

		# Parse event handler information
		for i in "${events[@]}"; do
	                if [[ $i == js* ]]; then
        	                controllerTempMap[js]="$i"
	                elif [[ $i == mouse* ]]; then
        	                controllerTempMap[mouse]="$i"
	                elif [[ $i == event* ]]; then
                	        controllerTempMap[event]="$i"
				event="$i"
        	        fi
	        done

		# Break if we found one we haven't registered yet
		if [ -z "${controllerVirtMap["$event.event"]}" ]; then
			echo "Found an unemulated controller"
			break;
		fi
	done <<< "$handlers"
}


function register_controller() {
    get_new_device "OUYA Game Controller"
    eventReal="${controllerTempMap[event]}"

    # Emulate Xbox360 controller if it's not ready emulated
    if [ ! -z "$eventReal" ] && [ -z "${controllerVirtMap[$eventReal.event]}" ]; then

    	# Make sure we exit gracefully
    	trap terminate SIGINT SIGHUP SIGTERM

    	# Remove js0
    	#if [ ! -z "${controllerTempMap[js]}" ] && [ -e "/dev/input/${controllerTempMap[js]}" ]; then
    	#	rm "/dev/input/${controllerTempMap[js]}"
    	#fi

    	# Emulate
    	echo "Initalizing emulation..."

    	logfile="$TMPDIR/ouya2xbox-${#controllers[@]}"
    	xboxdrv --evdev "/dev/input/$eventReal" --evdev-absmap ABS_X=x1,ABS_Y=y1,ABS_RX=x2,ABS_RY=y2 --axismap -Y1=Y1,-Y2=Y2 --evdev-keymap BTN_A=a,BTN_X=b,BTN_B=x,BTN_C=y,BTN_Y=lb,BTN_Z=rb,BTN_TL=tl,BTN_TR=tr,BTN_TL2=du,BTN_TR2=dd,BTN_SELECT=dl,BTN_START=dr,BTN_MODE=lt,BTN_THUMBL=rt,BTN_THUMBR=start --mimic-xpad --silent --detach-kernel-driver > $logfile &
    	processes+=($!)
    	sleep 1

    	logfiles+=("$logfile")
    	emulationInfo="$(cat "$logfile")"

    	if [ -z "$emulationInfo" ]; then
    		echo "Error! Emulation failed to start";

    	else
    		echo "Controller emulated as:"

    		# Map virtual
    		controllerVirtMap["$eventReal.event"]="$(basename "$(echo -e "$emulationInfo" | grep /dev/input/event | xargs)")"
    		controllerVirtMap["$eventReal.js"]="$(basename "$(echo -e "$emulationInfo" | grep /dev/input/js | xargs)")"

    		chmod 664 /dev/input/"${controllerVirtMap["$eventReal.event"]}"
    		chmod 664 /dev/input/"${controllerVirtMap["$eventReal.js"]}"

    		echo /dev/input/"${controllerVirtMap["$eventReal.event"]}"
    		echo /dev/input/"${controllerVirtMap["$eventReal.js"]}"

    		# Map real
    		eventVirt="${controllerVirtMap["$eventReal.event"]}"
    		controllerRealMap["$eventVirt.event"]="${controllerTempMap[event]}"
    		controllerRealMap["$eventVirt.mouse"]="${controllerTempMap[mouse]}"
    		controllerRealMap["$eventVirt.js"]="${controllerTempMap[js]}"

		# Add controller
                controllers+=("$eventVirt")

    		# hide original event
    		eventResets+=("$eventReal")
    		eventPermission="$(stat -c "%a" "/dev/input/$eventReal")"
    		chmod 000 "/dev/input/$eventReal"
		chmod 000 "/dev/input/${controllerTempMap[js]}"

    	fi
    else
    	echo "Cannot find an unemulated OUYA Controller (total emulated: ${#controllers[@]})"
    fi
}

# Verify that we run as root
if [ "$(whoami)" != "root" ]; then
        echo "Please run script as root"
        exit 1
fi


# Make sure we exit gracefully
echo "Press Ctrl+C to exit"
trap terminate SIGINT SIGHUP SIGTERM

while true; do
	register_controller
	sleep 3
done
