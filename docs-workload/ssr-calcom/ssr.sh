#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

# Please run build.sh before run this script

set -e

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
RESULT_DIR="${SCRIPT_PATH}/results"

# Parameters
NUM_CONTAINERS="${1:-1}"
SERVER_IMG="${2:-ssr-server:base}"     # Server
RUN_FLAGS=$3
CLIENT_IMG="ssr_calcom:client"
NUM_REQ="${4:-5000}"
CONCURRENCY="${5:-100}"
START_PORT="${6:-8000}"

# ssr env varialbes
socket0=()
socket1=()
ports=() # server ports
ip_prefix=""
server_start_time=30

# Env Variables
RUNTIME="${RUNTIME:-runc}"
TEST_NAME="${TEST_NAME:-ssr}"

# Directory to run the test on
# This is run inside of the container
TESTDIR="${TESTDIR:-/testdir}"
file_path="/home"
file_name="output"
# Directory where the workload results are stored
TMP_DIR=$(mktemp --tmpdir -d ssr.temp.XXXXXXXXXX)

# This timeout is related with the amount of time that
# the benchmark needs to run inside the container
timeout=600000
# This timeout is related with the amount of time that
# is needed to launch a container - Up status
timeout_running=$((5000 * "$NUM_CONTAINERS"))

# Mount options to control the start of the workload once a $trigger_file is created in the $dst_dir path
dst_dir="/host"
src_dir=$(mktemp --tmpdir -d ssr.calcom.XXXXXXXXXX)
trigger_file="$RANDOM.txt"
guest_trigger_file="$dst_dir/$trigger_file"
host_trigger_file="$src_dir/$trigger_file"
start_script="ssr_start.sh"
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
Usage: $0 <docker-server-image> <docker-client-image> <instances_count> <request num> <concurrency num>
   Example: runSSR_v2.sh ssr-server:base ssr-client:host 32 10000 1
   Description:
		<docker-server-image>: name of server container to run
        <docker-clienr-image>: name of client container to run: ssr-client:host && ssr-client:bridge
		<instances_count> : Number of containers to run.
		<request num>: Number of request in every client instance
		<concurrent num>: Number of concurrency in every client instance
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
clean_client_env() {
    # Sometime containers did not quit gracefully in middle execution so rm by force at first
    CONTAINERS_ID=($(docker ps -a --format "table {{.ID}}" -f ancestor=$CLIENT_IMG | tail -n +2))
	if [ ! -z "$CONTAINERS_ID" ]; then
	    docker rm -f "${CONTAINERS_ID[@]}"
	fi

	# If the timeout has not been set, default it to 300s
	# Docker has a built in 10s default timeout, so make ours
	# longer than that.
	local docker_timeout="${docker_timeout:-300}"
	containers_running=$(sudo timeout "${docker_timeout}" docker ps -q -f ancestor=$CLIENT_IMG)

	if [ ! -z "$containers_running" ]; then
		# First stop all containers that are running
		# Use kill, as the containers are generally benign, and most
		# of the time our 'stop' request ends up doing a `kill` anyway
		sudo timeout "${docker_timeout}" docker kill "$containers_running"
	fi

	containers_all=$(sudo timeout "${docker_timeout}" docker ps -qa -f ancestor=$CLIENT_IMG)
	if [ ! -z "$containers_all" ]; then
 		# Remove all containers
		sudo timeout "${docker_timeout}" docker rm -f $(docker ps -qa -f ancestor=$CLIENT_IMG)
	fi
}

clean_server_env() {
    # Sometime containers did not quit gracefully in middle execution so rm by force at first
    CONTAINERS_ID=($(docker ps -a --format "table {{.ID}}" -f ancestor=$SERVER_IMG | tail -n +2))
	if [ ! -z "$CONTAINERS_ID" ]; then
	    docker rm -f "${CONTAINERS_ID[@]}"
	fi

	# If the timeout has not been set, default it to 300s
	# Docker has a built in 10s default timeout, so make ours
	# longer than that.
	local docker_timeout="${docker_timeout:-300}"
	perf_containers=$(timeout "${docker_timeout}" docker ps -aq --filter='name=server-perf' | paste -sd "|" -)
	if [ ! -z "$perf_containers" ]; then
  		containers_running=$(sudo timeout "${docker_timeout}" docker ps -q | grep -v -E "$perf_containers" || true)
	else
		containers_running=$(sudo timeout "${docker_timeout}" docker ps -q -f ancestor=$SERVER_IMG)
	fi
	# containers_running=$(sudo timeout "${docker_timeout}" docker ps -q -f ancestor=$SERVER_IMG)

	if [ ! -z "$containers_running" ]; then
		# First stop all containers that are running
		# Use kill, as the containers are generally benign, and most
		# of the time our 'stop' request ends up doing a `kill` anyway
		sudo timeout "${docker_timeout}" docker kill "$containers_running"
	fi

	if [ ! -z "$perf_containers" ]; then
		containers_all=$(sudo timeout "${docker_timeout}" docker ps -aq | grep -v -E "$perf_containers" || true)
	else
		containers_all=$(sudo timeout "${docker_timeout}" docker ps -aq -f ancestor=$SERVER_IMG)
	fi

	# containers_all=$(sudo timeout "${docker_timeout}" docker ps -qa -f ancestor=$SERVER_IMG)
	if [ ! -z "$containers_all" ]; then
 		# Remove all containers
		sudo timeout "${docker_timeout}" docker rm -f $(docker ps -qa -f ancestor=$SERVER_IMG)
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
		"requests": "$NUM_REQ",
		"request_concurrency": "$CONCURRENCY",
		"image": "$CLIENT_IMG"
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

# Common parameter for port(network=host) or ip(network=bridge)
p1=\${1:-3000} 

pushd "$file_path"
touch $file_name
bash /home/docker-entrypoint.sh $NUM_REQ $CONCURRENCY \$p1 > $file_name 2>&1
EOF
    chmod 755 "$src_dir"
    chmod +x "$src_dir/$start_script"
}

get_cpu_cores() {
	local tailor="sed 's/[^.0-9][^.0-9]*//g'"
	local cpus=$(cat "/proc/cpuinfo" | grep -w "physical id" | eval "${tailor}")
	local seq_core=0

	for id in $cpus; do
		if [ "$id" -eq "0" ]; then
        	socket0+=($seq_core)
    	else
        	socket1+=($seq_core)
    	fi
		seq_core=$(($seq_core+1))
	done

	if [ $seq_core -lt $NUM_CONTAINERS ]; then
		echo "error: number of instance is more than cpu cores $seq_core!"
		exit 1
	fi
	socket0+=(${socket0[0]}) #append first core for full-score containers
	socket1+=(${socket1[0]})
	#echo ${socket0[*]}
	#echo ${socket1[*]}
	echo "CPU Information Loaded."
}

get_free_ports() {
	for ((i=$START_PORT; i< "$START_PORT"+"$NUM_CONTAINERS"; i++)); do
		ports+=($i)
	done
}

get_default_docker_ip_prefix() {
    local docker0_ip=$(ifconfig | grep -A1 'docker0' | grep 'inet' | awk '{print $2;}')
    ip_prefix=$(echo $docker0_ip | cut -d. -f1-3)
}

function main() {
	# Verify enough arguments instance numbers
	if [ $# -lt 2 ]; then
		echo >&2 "error: Not enough arguments [$@]"
		help
		exit 1
	fi

	# get docker0 default bridge ip, cpu and ports
	get_default_docker_ip_prefix
	get_cpu_cores
	get_free_ports

	# Define containers' array and clean old contariners
	local containers_client=()
	local containers_server=()
	local not_started_client_count="$NUM_CONTAINERS"
	local not_started_server_count="$NUM_CONTAINERS"
    local i
	clean_client_env
	clean_server_env
	
	#Clean previous test result
	rm -f rawresults
	rm -f ssr_score.json
    metrics_json_init
    save_config
    create_start_script
	rm -rf "$host_trigger_file"

	info "Starting to launch the containers for ssr server with image $SERVER_IMG on socket0"
	for ((i=1; i<= "$NUM_CONTAINERS"; i++)); do
		containers_server+=($(random_name))
		cpu0=${socket0[i-1]}
		cpu1=${socket0[i]}
		echo "Server run at Core $cpu0 and $cpu1"
		if [ "$CLIENT_IMG" == "ssr-client:host" ]; then
			docker run --cpus=2 -p ${ports[i-1]}:3000 --cpuset-cpus=$cpu0,$cpu1 --privileged --name "${containers_server[-1]}" -td --runtime="$RUNTIME" "$SERVER_IMG" bash -c "/calcom/cal.com/docker-entrypoint.sh $RUN_FLAGS"
		else
			docker run --cpus=2 --cpuset-cpus=$cpu0,$cpu1 --privileged --name "${containers_server[-1]}" -td --runtime="$RUNTIME" "$SERVER_IMG" bash -c "/calcom/cal.com/docker-entrypoint.sh $RUN_FLAGS"
			echo "$cpu0,$cpu1 ${containers_server[-1]}" >> $SCRIPT_PATH/server.txt
		fi
		((not_started_server_count--))
		info "$not_started_server_count remaining server containers"
	done

	info "Waiting $server_start_time s for all server starting successfully"

	# Detect any error containers
	touch $SCRIPT_PATH/error.txt
	for container in $(docker ps -a --format "{{.Names}}")
	do
		status=$(docker inspect $container --format "{{.State.Status}}")
		if [ $status == "exited" ]
		then
			echo $container >> $SCRIPT_PATH/error.txt
		fi
	done

	python3 $SCRIPT_PATH/restart_server.py $SCRIPT_PATH/server.txt $SCRIPT_PATH/error.txt $SERVER_IMG "$RUN_FLAGS"
	rm $SCRIPT_PATH/server.txt $SCRIPT_PATH/error.txt
	sleep $server_start_time

	info "Starting to launch the containers for ssr benchmark with image $CLIENT_IMG on socket1"
    for ((i=1; i<= "$NUM_CONTAINERS"; i++)); do
		containers_client+=($(random_name))
		cpu0=${socket1[i-1]}
		cpu1=${socket1[i]}
		echo "Client run at Core $cpu0 and $cpu1"
		if [ "$CLIENT_IMG" == "ssr-client:host" ]; then
			CMD="$dst_dir/$start_script ${ports[i-1]}"	
			docker run --cpus=2 --network=host --cpuset-cpus=$cpu0,$cpu1 --privileged --name "${containers_client[-1]}" -td --runtime="$RUNTIME" --mount "$MOUNT_OPTIONS" "$CLIENT_IMG" bash -c "$CMD"
		else
			local addr_num=$(echo $i+1 | bc)
			CMD="$dst_dir/$start_script $ip_prefix.$addr_num"
			docker run --cpus=2 --cpuset-cpus=$cpu0,$cpu1 --privileged --name "${containers_client[-1]}" -td --runtime="$RUNTIME" --mount "$MOUNT_OPTIONS" "$CLIENT_IMG" bash -c "$CMD"
		fi
		echo "Exec $CMD in client container..."
		((not_started_client_count--))
		info "$not_started_client_count remaining client containers"
	done

	# We verify that number of containers that we selected are running
	for i in $(seq "$timeout_running") ; do
		echo "Verify that the containers are running"
		containers_launched=$(docker ps -a | grep "$CLIENT_IMG" | grep "Up" | wc -l)
		[ "$containers_launched" -eq "$NUM_CONTAINERS" ] && break
		sleep 1
		[ "$i" == "$timeout_running" ] && return 1
	done

	touch "$host_trigger_file"
    info "All containers are running the workload..."

	# Now that containers were launched, we need to verify that they finished running the ssr micro
    for i in $(seq "$timeout") ; do
		#echo "Verify that the containers are exited"
		containers_exited=$(docker ps -a | grep "$CLIENT_IMG" | grep "Exited" | wc -l)
		echo -n "."
		echo "exited $containers_exited, target $NUM_CONTAINERS"
		[ "$containers_exited" -eq "$NUM_CONTAINERS" ] && break
		sleep 1
		[ "$i" == "$timeout" ] && return 1
	done
    echo "Done"

	# Get container's ids
	# CONTAINERS_ID=($(docker ps -a --format "table {{.ID}}" -f ancestor=$CLIENT_IMG | tail -n +2))
	CONTAINERS_ID=($(docker ps -a --filter ancestor=$CLIENT_IMG --format "table {{.ID}}\t{{.Image}}" | tail -n +2 | grep $CLIENT_IMG | awk '{print $1}'))
	for i in "${CONTAINERS_ID[@]}"; do
		docker cp "$i:$file_path/$file_name" "$TMP_DIR"
		pushd "$TMP_DIR"
		cat "$file_name" >> "rawresults" || true
		cat "$file_name" | grep "Requests per second:"  >> "results" || true  #for ab
		cat "$file_name" | grep "Failed requests:" >> "failed_results" || true
		# cat "$file_name" | grep "finished"  >> "results" || true #for h2load
		popd
	done
	cp $TMP_DIR/rawresults $RESULT_DIR/rawresults
	cp $TMP_DIR/results $RESULT_DIR/results
	cp $TMP_DIR/failed_results $RESULT_DIR/failed_results

	metrics_json_start_array

	local output=$(cat "$TMP_DIR/results")
	local tailor="sed 's/[^.0-9][^.0-9]*//g'"
	local rps_list=$(echo "$output" | grep -w "per" | eval "${tailor}")
	local rps_list_sum=$(echo $rps_list | sed 's/ /+/g' | bc)

	local failed=$(cat "$TMP_DIR/failed_results")
	local failed_list=$(echo "$failed" | grep -w "Failed" | eval "${tailor}")
	local failed_list_sum=$(echo $failed_list | sed 's/ /+/g' | bc)

	local rps_sum=$(echo "$rps_list_sum*(1-$failed_list_sum/($NUM_REQ*$NUM_CONTAINERS))" | bc -l)
	local rps_per_instance=$(echo $rps_sum/$NUM_CONTAINERS | bc -l)

	local json="$(cat << EOF
 	{
		"Average TPS" : "$rps_per_instance",
		"Total TPS" : "$rps_sum"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"
	metrics_json_save
	
	# Sleep 5s to wait Emon-Collect detecting the exited containers
	sleep 5
	docker rm -f "${CONTAINERS_ID[@]}"

	while true; do
  		running=$(docker ps | grep "server-perf" || true)
  		if [ -n "$running" ]; then
    		echo "server-perf is running..."
    		sleep 1
  		else
    		echo "Now here is no server-perf."
    		break
  		fi
	done
	sleep 10
	echo "Ready to clear server and client now."
	clean_client_env
	clean_server_env
	sleep 2
	echo "Average throughput: "$rps_per_instance
	echo "Total throughput: "$rps_sum
}

main "$@"