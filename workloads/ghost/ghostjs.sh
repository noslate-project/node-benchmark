#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT
#
# Description of the test:
# This script runs the 'ghost.js workload container'

set -e

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
RESULT_DIR="${SCRIPT_PATH}/results"
DOCKERFILE="${SCRIPT_PATH}/Dockerfile"
NUM_CONTAINERS="$1"
# Env variables
RUNTIME="${RUNTIME:-runc}"
TEST_NAME="${TEST_NAME:-ghostjs}"
IMAGE="${2:-ghost4.4.0-node16.14.2-base-http}"
NODE_VERSION="${3:-16.14.2}"
PROTOCOL="${4:-http}"
OPT_TYPE="${5:-base}"
# Directory to run the test on
# This is run inside of the container
TESTDIR="${TESTDIR:-/testdir}"
file_path="/home/ghost/Ghost"
file_name="output"
# Directory where the workload  results are stored
TMP_DIR=$(mktemp --tmpdir -d ghostjs.XXXXXXXXXX)

# This timeout is related with the amount of time that
# webtool benchmark needs to run inside the container
timeout=1200
# This timeout is related with the amount of time that
# is needed to launch a container - Up status
timeout_running=$((5 * "$NUM_CONTAINERS"))

# Mount options to control the start of the workload once a $trigger_file is created in the $dst_dir path
dst_dir="/host"
src_dir=$(mktemp --tmpdir -d ghostjsM.XXXXXXXXXX)
trigger_file="$RANDOM.txt"
guest_trigger_file="$dst_dir/$trigger_file"
host_trigger_file="$src_dir/$trigger_file"
start_script="ghostjs_start.sh"
CMD="$dst_dir/$start_script"
MOUNT_OPTIONS="type=bind,source=$src_dir,destination=$dst_dir"

declare -a CONTAINERS_ID
declare -a json_array_array

remove_tmp_dir() {
	rm -rf "$TMP_DIR"
	rm -rf "$src_dir"
}

trap remove_tmp_dir EXIT

# Show help about this script
help()	{
cat << EOF
Usage: $0 <count> <docker-image-name> <node-version> <protocol> <opt_type>
   Example: ghostjs.sh 96 ghost4.4.0-node16.14.2-base-http 16.14.2 http base
   Description:
	<count> : Number of containers to run.
        <docker-image-name>: Name of containers to run.
        <node-version>: the node version string.
        <protocol>: the testing protocol: http or https.
        <opt_type>: the optimization type of running: base or opt.
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
	# If the timeout has not been set, default it to 30s
	# Docker has a built in 10s default timeout, so make ours
	# longer than that.
	local docker_timeout="${docker_timeout:-30}"
	
	perf_containers=$(timeout "${docker_timeout}" docker ps -aq --filter='name=perf-container' | paste -sd "|" -)

	if [ ! -z "$perf_containers" ]; then
  		containers_running=$(timeout "${docker_timeout}" docker ps -q | grep -v -E "$perf_containers" || true)
	else
		containers_running=$(timeout "${docker_timeout}" docker ps -q -f ancestor=$IMAGE)
	fi

	if [ ! -z "$containers_running" ]; then
		# First stop all containers that are running
		# Use kill, as the containers are generally benign, and most
		# of the time our 'stop' request ends up doing a `kill` anyway
		timeout "${docker_timeout}" docker kill "$containers_running"
	fi

	# Remove all containers except Jenkins itself
	if [ ! -z "$perf_containers" ]; then
		containers_all=$(timeout "${docker_timeout}" docker ps -aq | grep -v -E "$perf_containers" || true)
	else
		containers_all=$(timeout "${docker_timeout}" docker ps -aq -f ancestor=$IMAGE)
	fi
	echo "$containers_all"

	if [ ! -z "$containers_all" ]; then
 		# Remove all containers
		# timeout "${docker_timeout}" docker rm -f $(docker ps -qa -f ancestor=$IMAGE) >/dev/null
		timeout "${docker_timeout}" docker rm -f $containers_all
	fi
}

# This function performs a build on the image names
# passed in, to ensure that we have the latest changes from
# the dockerfiles
build_dockerfile_image() {
	local image="$1"
	local dockerfile_path="$2"
	local dockerfile_dir=${2%/*}

	echo "docker building $image"
	if ! docker build --label "$image" --tag "${image}" -f "$dockerfile_path" "$dockerfile_dir"; then
		die "Failed to docker build image $image"
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
		"image": "$IMAGE",
		"units": "runs/s",
		"node_run_flags": "$NODE_RUN_FLAGS"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Config"
}

create_start_script() {
       #echo "!!! mounted src dir is: ${src_dir}"
       mkdir -p "$src_dir/warmup_done/"
       chmod 777 "$src_dir/warmup_done/"
       rm -rf "$src_dir/$start_script"
cat <<EOF >>"$src_dir/$start_script"
#!/bin/bash
until [ -f "$guest_trigger_file" ]; do
       sleep 1
done
pushd "$file_path"
touch $file_name
./quickrun.sh $NODE_VERSION $PROTOCOL '$NODE_RUN_FLAGS'
EOF
       chmod 755 "$src_dir"
       chmod +x "$src_dir/$start_script"
}

function main() {
	# Verify enough arguments
	if [ $# -lt 5 ]; then
		echo >&2 "error: incorrect number of arguments [$@]"
		help
		exit 1
	fi

	NODE_RUN_FLAGS=""
	if [ $# -eq 6 ]; then
		NODE_RUN_FLAGS=$6
		echo "Node runtime flags: $NODE_RUN_FLAGS"
	fi

	local containers=()
	local not_started_count="$NUM_CONTAINERS"
        local i=0
	clean_env

	#build_dockerfile_image "$IMAGE" "$DOCKERFILE" //daoming: building is too long
	metrics_json_init

	save_config
	create_start_script
	rm -rf "$host_trigger_file"

	for ((i=1; i<= "$NUM_CONTAINERS"; i++)); do
		containers+=($(random_name))
		if [ $OPT_TYPE == "opt" ] && [ $i -le `nproc` ] ; then
                  im=$(($i-1))
                  in=$(($i))
                  if [ $i == `nproc` ]; then
                      in=0
                  fi
		  docker run --cpus=2 --cpuset-cpus="$im,$in" --privileged --name "${containers[-1]}" -td --runtime="$RUNTIME" --mount "$MOUNT_OPTIONS" "$IMAGE" bash -c "$CMD" >/dev/null;
		else
		  docker run --cpus=2 --privileged --name "${containers[-1]}" -td --runtime="$RUNTIME" --mount "$MOUNT_OPTIONS" "$IMAGE" bash -c "$CMD" >/dev/null;
		fi

		((not_started_count--))
		echo -ne "Launching containers with $OPT_TYPE docker run: [$i/$NUM_CONTAINERS]\r"
	done
	echo ""


	# We verify that number of containers that we selected
	# are running
	for i in $(seq "$timeout_running") ; do
		echo "Verify that the containers are running"
		containers_launched=$(docker ps -a | grep "$IMAGE" | grep "Up" | wc -l)
		[ "$containers_launched" -eq "$NUM_CONTAINERS" ] && break
		sleep 1
		[ "$i" == "$timeout_running" ] && return 1
	done

	touch "$host_trigger_file"
	info "All containers are running the workload..."

	# Now that containers were launched, we need to verify that they finished
	# running the webtootl benchmark
	warmup_done=0
	for i in $(seq "$timeout") ; do
		#echo "Verify that the containers are exited"
		containers_exited=$(docker ps -a | grep "$IMAGE" | grep "Exited" | wc -l)
		if [ "$warmup_done" -lt "$NUM_CONTAINERS" ] ; then
			warmup_done=$(ls ${src_dir}/warmup_done | wc -l)
			echo -n "."
		else
			echo -n "*"
		fi
		#echo "exited $containers_exited, target $NUM_CONTAINERS"
		[ "$containers_exited" -eq "$NUM_CONTAINERS" ] && break
		sleep 1
		[ "$i" == "$timeout" ] && return 1
	done
	echo "DONE"

	info "Calculating the performance score"
	# Get container's ids
	CONTAINERS_ID=($(docker ps -a --filter ancestor=$IMAGE --format "table {{.ID}}\t{{.Image}}" | tail -n +2 | grep $IMAGE | awk '{print $1}'))
	for i in "${CONTAINERS_ID[@]}"; do
		docker cp "$i:$file_path/$file_name" "$TMP_DIR"
		docker cp "$i:$file_path/ablog.tar" "$TMP_DIR"
		docker cp "$i:$file_path/runoutput" "$TMP_DIR"
		pushd "$TMP_DIR" > /dev/null
		cat "$file_name" >> "results"
		cat runoutput >> "runoutputs"
		mv ${TMP_DIR}/ablog.tar $TMP_DIR/${i}_ablog.tar
		popd > /dev/null
	done
	cp $TMP_DIR/results $RESULT_DIR/rawresults
	cp $TMP_DIR/runoutputs $RESULT_DIR/runoutputs
	tar cf $RESULT_DIR/ablogs.tar $TMP_DIR/*.tar >/dev/null 2>&1

	# Save configuration
	metrics_json_start_array

	local output=$(cat "$TMP_DIR/results")
	local cut_results="cut -d':' -f2 | sed -e 's/^[ \t]*//'| cut -d ' ' -f1 | tr '\n' ',' | sed 's/.$//'"
	local geometric_mean=$(echo "$output" | grep -w "Average RPS" | eval "${cut_results}")
	local average_tps=$(echo "$geometric_mean" | sed "s/,/+/g;s/.*/(&)\/$NUM_CONTAINERS/g" | bc -l)
	local total_tps=$(echo "$average_tps*$NUM_CONTAINERS" | bc -l)
	local failures=$(echo "$output" | grep -w "Average %failed" | eval "${cut_results}")
	local average_failure=$(echo "$failures" | sed "s/,/+/g;s/.*/(&)\/$NUM_CONTAINERS/g" | bc -l)

	local json="$(cat << EOF
 	{
		"Total TPS" : "$total_tps",
                "Average %Failed" : "$average_failure"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"
	metrics_json_save

	# Sleep 10s to wait Emon-Collect detecting the exited containers
	info "Removing all the containers running the ghost.js workload"
	sleep 10
	
	docker rm -f "${CONTAINERS_ID[@]}" >/dev/null
	clean_env
	echo "Total TPS: "$total_tps
	echo "Average %Failed:"$average_failure
}

main "$@"
