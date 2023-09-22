#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

# Please run build.sh before run this script

set -e

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
RESULT_DIR="${SCRIPT_PATH}/results"

# Parameters
NUM_CONTAINERS="${1:-1}"
IMG="${2:-base64-v18.14.2:base}"     # Server

# ssr env varialbes
cores=()
socket0=()
socket1=()
ports=() # server ports

# Env Variables
RUNTIME="${RUNTIME:-runc}"
TEST_NAME="${TEST_NAME:-base64}"

# Directory to run the test on
# This is run inside of the container
TESTDIR="${TESTDIR:-/testdir}"
file_path="/home"
file_name="output"
# Directory where the workload results are stored
TMP_DIR=$(mktemp --tmpdir -d base64.temp.XXXXXXXXXX)

# This timeout is related with the amount of time that
# the benchmark needs to run inside the container
timeout=600000
# This timeout is related with the amount of time that
# is needed to launch a container - Up status
timeout_running=$((5000 * "$NUM_CONTAINERS"))

# Mount options to control the start of the workload once a $trigger_file is created in the $dst_dir path
dst_dir="/host"
src_dir=$(mktemp --tmpdir -d base64.XXXXXXXXXX)
trigger_file="$RANDOM.txt"
guest_trigger_file="$dst_dir/$trigger_file"
host_trigger_file="$src_dir/$trigger_file"
start_script="base64_start.sh"
CMD="$dst_dir/$start_script"
MOUNT_OPTIONS="type=bind,source=$src_dir,destination=$dst_dir"

declare -a CONTAINERS_ID
declare -a json_array_array

remove_tmp_dir() {
	rm -rf "$TMP_DIR"
	rm -rf "$src_dir"
	echo "Temp files has been cleaned. Exit gracefully."
}

trap remove_tmp_dir EXIT

# Show help about this script
help()	{
cat << EOF
Usage: $0 <docker-image> <instances_count>
   Example: run.sh base-v18.14.2:base 112
   Description:
		<docker-image>: name of image to run
		<instances_count> : Number of containers to run.
EOF
}

# If we fail for any reason, exit through here and we should log that to the correct
# place and return the correct code to halt the run
die() {
	local msg="$*"
	echo "ERROR: $msg" >&2
	exit 1
}

info() {
        local msg="$*"
        echo "INFO: $msg"
}

# Clean environment, this function will try to remove all
# stopped/running containers.
clean_env() {
    # Sometime containers did not quit gracefully in middle execution so rm by force at first
    CONTAINERS_ID=($(docker ps -a --format "table {{.ID}}" -f ancestor=$IMG | tail -n +2))
	if [ ! -z "$CONTAINERS_ID" ]; then
	    docker rm -f "${CONTAINERS_ID[@]}"
	fi

	# If the timeout has not been set, default it to 300s
	# Docker has a built in 10s default timeout, so make ours
	# longer than that.
	local docker_timeout="${docker_timeout:-300}"
	containers_running=$(sudo timeout "${docker_timeout}" docker ps -q -f ancestor=$IMG)

	if [ ! -z "$containers_running" ]; then
		# First stop all containers that are running
		# Use kill, as the containers are generally benign, and most
		# of the time our 'stop' request ends up doing a `kill` anyway
		sudo timeout "${docker_timeout}" docker kill "$containers_running"
	fi

	containers_all=$(sudo timeout "${docker_timeout}" docker ps -qa -f ancestor=$IMG)
	if [ ! -z "$containers_all" ]; then
 		# Remove all containers
		sudo timeout "${docker_timeout}" docker rm -f $(docker ps -qa -f ancestor=$IMG)
	fi
}

# Generate a timestamp in milliseconds
timestamp_ms() {
 	echo $(($(date +%s%N)/1000000))
}

# Generate a random name - generally used when creating containers, but can
# be used for any other appropriate purpose
random_name() {
 	mktemp -u runc-XXXXXX
}

# Prepare to collect up array elements
metrics_json_start_array() {
	json_array_array=()
}

# Add a (complete) element to the current array
metrics_json_add_array_element() {
	local data=$1

	# Place on end of array
	json_array_array[${#json_array_array[@]}]="$data"
}

# Add a top level (complete) JSON fragment to the data
metrics_json_add_fragment() {
 	local data=$1

	# Place on end of array
	json_result_array[${#json_result_array[@]}]="$data"
}

# Close the current array
metrics_json_end_array() {
	local name=$1

	local maxelem=$(( ${#json_array_array[@]} - 1 ))
	local json="$(cat << EOF
 	"$name": [
		$(for index in $(seq 0 "$maxelem"); do
			if (( index != maxelem )); then
				echo "${json_array_array[$index]},"
			else
				echo "${json_array_array[$index]}"
			fi
		done)
	]
EOF
)"

	# And save that to the top level
	metrics_json_add_fragment "$json"
}

# Intialise the json subsystem
metrics_json_init() {
	# Clear out any previous results
	json_result_array=()

	despaced_name="$(echo ${TEST_NAME} | sed 's/[ \/]/-/g')"
	json_filename="${RESULT_DIR}/${despaced_name}_score.json"

	local json="$(cat << EOF
	"@timestamp" : $(timestamp_ms)
EOF
)"
	metrics_json_add_fragment "$json"

	local json="$(cat << EOF
	"date" : {
 		"Date": "$(date -u +"%Y-%m-%dT%T.%3N")"
	}
EOF
)"
	metrics_json_add_fragment "$json"

	local json="$(cat << EOF
	"test" : {
		"runtime": "${RUNTIME}",
		"testname": "${TEST_NAME}"
	}
EOF
)"
	metrics_json_add_fragment "$json"

	local output=$(runc -v)
	local runcversion=$(grep version <<< "$output" | sed 's/runc version //')
	local runccommit=$(grep commit <<< "$output" | sed 's/commit: //')
	local json="$(cat << EOF
	"runc-env" :
	{
		"Version": {
			"Semver": "$runcversion",
			"Commit": "$runccommit"
		}
	}
EOF
)"

	metrics_json_end_of_system
}

# Save out the final JSON file
metrics_json_save() {
	if [ ! -d "${RESULT_DIR}" ];then
		mkdir -p "${RESULT_DIR}"
	fi

	local maxelem=$(( ${#json_result_array[@]} - 1 ))
	local json="$(cat << EOF
{
$(for index in $(seq 0 "$maxelem"); do
	# After the standard system data, we then place all the test generated
	# data into its own unique named subsection.
	if (( index == system_index )); then
		echo "\"${despaced_name}\" : {"
	fi
	if (( index != maxelem )); then
		echo "${json_result_array[$index]},"
	else
		echo "${json_result_array[$index]}"
	fi
done)
	}
}
EOF
)"

	echo "$json" > $json_filename

	# If we have a JSON URL or host/socket pair set up, post the results there as well.
	# Optionally compress into a single line.
	if [[ $JSON_TX_ONELINE ]]; then
		json="$(sed 's/[\n\t]//g' <<< ${json})"
	fi

	if [[ $JSON_HOST ]]; then
		echo "socat'ing results to [$JSON_HOST:$JSON_SOCKET]"
		socat -u - TCP:${JSON_HOST}:${JSON_SOCKET} <<< ${json}
	fi

	if [[ $JSON_URL ]]; then
		echo "curl'ing results to [$JSON_URL]"
		curl -XPOST -H"Content-Type: application/json" "$JSON_URL" -d "@-" <<< ${json}
 	fi
}

metrics_json_end_of_system() {
	system_index=$(( ${#json_result_array[@]}))
}

save_config(){
	metrics_json_start_array

	local json="$(cat << EOF
	{
		"containers": "$NUM_CONTAINERS",
		"image": "$IMG"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Config"
}

create_start_script() {
    rm -rf "$src_dir/$start_script"
cat << EOF >>"$src_dir/$start_script"
#!/bin/bash
until [ -f "$guest_trigger_file" ]; do
       sleep 0.1
done

pushd "$file_path"
touch $file_name
bash /home/start.sh > $file_name 2>&1
EOF
    chmod 755 "$src_dir"
    chmod +x "$src_dir/$start_script"
}

get_cpu_cores() {
	local tailor="sed 's/[^.0-9][^.0-9]*//g'"
	local cpus=$(cat "/proc/cpuinfo" | grep -w "physical id" | eval "${tailor}")
	local seq_core=0

	for id in $cpus; do
        cores+=($seq_core)
		seq_core=$(($seq_core+1))
	done

	if [ $seq_core -lt $NUM_CONTAINERS ]; then
		echo "error: number of instance is more than cpu cores $seq_core!"
		exit 1
	fi
	cores+=(${cores[0]}) #append first core for full-score containers
	echo "CPU Information Loaded."
}

function main() {
	# Verify enough arguments instance numbers
	if [ $# -lt 2 ]; then
		echo >&2 "error: Not enough arguments [$@]"
		help
		exit 1
	fi

	# get paras
	get_cpu_cores

	# Define containers' array and clean old contariners
	local containers=()
	local not_started_count="$NUM_CONTAINERS"
    local i
	clean_env
	
	#Clean previous test result
	rm -f rawresults
	rm -f ssr_score.json
    metrics_json_init
    save_config
    create_start_script
	rm -rf "$host_trigger_file"

	info "Starting to launch the containers with image $IMG"
	CMD="$dst_dir/$start_script"
	for ((i=1; i<= "$NUM_CONTAINERS"; i++)); do
		containers+=($(random_name))
		cpu0=${cores[i-1]}
		cpu1=${cores[i]}
		echo "Container Run at Core $cpu0 and $cpu1"
        docker run --cpus=2 --cpuset-cpus=$cpu0,$cpu1 --privileged --name "${containers[-1]}" -td --runtime="$RUNTIME" --mount "$MOUNT_OPTIONS" "$IMG" bash -c "$CMD"
		((not_started_count--))
		info "$not_started_count remaining containers"
	done

	# We verify that number of containers that we selected are running
	for i in $(seq "$timeout_running") ; do
		echo "Verify that the containers are running"
		containers_launched=$(docker ps -a | grep "$IMG" | grep "Up" | wc -l)
		[ "$containers_launched" -eq "$NUM_CONTAINERS" ] && break
		sleep 1
		[ "$i" == "$timeout_running" ] && return 1
	done

	touch "$host_trigger_file"
    info "All containers are running the workload..."

	# Now that containers were launched, we need to verify that they finished running the ssr micro
    for i in $(seq "$timeout") ; do
		#echo "Verify that the containers are exited"
		containers_exited=$(docker ps -a | grep "$IMG" | grep "Exited" | wc -l)
		echo -n "."
		echo "exited $containers_exited, target $NUM_CONTAINERS"
		[ "$containers_exited" -eq "$NUM_CONTAINERS" ] && break
		sleep 1
		[ "$i" == "$timeout" ] && return 1
	done
    echo "Done"

	# Get container's ids
	CONTAINERS_ID=($(docker ps -a --format "table {{.ID}}" -f ancestor=$IMG | tail -n +2))
	for i in "${CONTAINERS_ID[@]}"; do
		docker cp "$i:$file_path/$file_name" "$TMP_DIR"
		pushd "$TMP_DIR"
		cat "$file_name" >> "rawresults" || true
		# cat "$file_name" | grep "finished"  >> "results" || true #for h2load
		popd
	done
	cp $TMP_DIR/rawresults $RESULT_DIR/rawresults

	metrics_json_start_array

	local output=$(cat "$TMP_DIR/rawresults")
	local tailor="sed -r 's/.*[^0-9]+([0-9]+\.[0-9]*)$/\1/'"
	local rps_list=$(echo "$output" | eval "${tailor}")
	local rps_list_sum=$(echo $rps_list | sed 's/ /+/g' | bc)

	local json="$(cat << EOF
 	{
		"Total RPS" : "$rps_list_sum"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"
	metrics_json_save
	sleep 3
	docker rm -f "${CONTAINERS_ID[@]}"
	clean_env
	echo "Total throughput: "$rps_list_sum
}

main "$@"