#!/bin/bash
#
# Copyright (c) 2021 Intel Corporation
#
# Description of the test:
# This test runs the 'web tooling benchmark'
# https://github.com/v8/web-tooling-benchmark

set -e

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
RESULT_DIR="${SCRIPT_PATH}/../results"
NUM_CONTAINERS="${2:-1}"
# Env variables
RUNTIME="${RUNTIME:-runc}"
TEST_NAME="${TEST_NAME:-web-tooling}"
IMAGE="${1:-webtooling-baseline}"

# Directory to run the test on
# This is run inside of the container
TESTDIR="${TESTDIR:-/testdir}"
file_path="/web-tooling-benchmark"
file_name="output"
# Directory where the webtooling results are stored
TMP_DIR=$(mktemp --tmpdir -d webtool.XXXXXXXXXX)

# This timeout is related with the amount of time that
# webtool benchmark needs to run inside the container
timeout=6000

# Mount options to control the start of the workload once a $trigger_file is created in the $dst_dir path
dst_dir="/host"
src_dir=$(mktemp --tmpdir -d webtool.XXXXXXXXXX)
trigger_file="$RANDOM.txt"
guest_trigger_file="$dst_dir/$trigger_file"
host_trigger_file="$src_dir/$trigger_file"
start_script="webtooling_start.sh"
CMD="$dst_dir/$start_script"
MOUNT_OPTIONS="type=bind,source=$src_dir,destination=$dst_dir,readonly"


declare -a CONTAINERS_ID
declare -a json_array_array

TMP_DIR=$(mktemp --tmpdir -d webtool.XXXXXXXXXX)

remove_tmp_dir() {
	rm -rf "$TMP_DIR"
	rm -rf "$src_dir"
}

trap remove_tmp_dir EXIT

# Show help about this script
help()	{
cat << EOF
Usage: $0 <count>
   Description:
	<count> : Number of containers to run.
EOF
}

# Show help about this script
help()  {
cat << EOF
Usage: $0 <docker-image-name> <instances_count> 
   Example: webtooling.sh webtooling-base 1
   Description:
        <docker-image-name>: Name of containers to run.
        <instance_count> : Number of containers (webtooling instances) to run.
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
    CONTAINERS_ID=($(docker ps -a --format "table {{.ID}}" -f ancestor=$IMAGE | tail -n +2))
        if [ ! -z "$CONTAINERS_ID" ]; then
            docker rm -f "${CONTAINERS_ID[@]}"
        fi

        # If the timeout has not been set, default it to 300s
        # Docker has a built in 10s default timeout, so make ours
        # longer than that.
        local docker_timeout="${docker_timeout:-300}"
        containers_running=$(sudo timeout "${docker_timeout}" docker ps -q -f ancestor=$IMAGE)

        if [ ! -z "$containers_running" ]; then
                # First stop all containers that are running
                # Use kill, as the containers are generally benign, and most
                # of the time our 'stop' request ends up doing a `kill` anyway
                sudo timeout "${docker_timeout}" docker kill "$containers_running"
        fi

        containers_all=$(sudo timeout "${docker_timeout}" docker ps -qa -f ancestor=$IMAGE)
        if [ ! -z "$containers_all" ]; then
                # Remove all containers
                sudo timeout "${docker_timeout}" docker rm -f $(docker ps -qa -f ancestor=$IMAGE)
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
	json_filename="${RESULT_DIR}/${despaced_name}.json"

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

	local output
	local runccommit=$(grep commit <<< "$output" | sed 's/commit: //')
	local json="$(cat << EOF
	"runc-env" :
	{
		"Version": {
			"Commit": "$runccommit"
		}
	}
EOF
)"

	metrics_json_end_of_system
}

# Save out the final JSON file
metrics_json_save() {
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
		"units": "runs/s"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Config"
}

create_start_script() {
	rm -rf "$src_dir/$start_script"
cat <<EOF >>"$src_dir/$start_script"
#!/bin/bash
mkdir -p "${TESTDIR}"

until [ -f "$guest_trigger_file" ]; do
	sleep 1
done

pushd "$file_path"
node dist/cli.js > "$file_name"
EOF
	chmod +x "$src_dir/$start_script"
}

function main() {
	# Verify enough arguments
	if [ $# != 2 ]; then
		echo >&2 "error: Not enough arguments [$@]"
		help
		exit 1
	fi

	local containers=()
	local not_started_count="$NUM_CONTAINERS"
	local i=0
	clean_env

	metrics_json_init

	if [ ! -d "${RESULT_DIR}" ];then
		mkdir -p "${RESULT_DIR}"
	fi


	save_config
        create_start_script
        rm -rf "$host_trigger_file"

	for ((i=1; i<= "$NUM_CONTAINERS"; i++)); do
		containers+=($(random_name))
		# Web tool benchmark needs 2 cpus to run completely in its cpu utilization
		docker run --cpus=2 --name "${containers[-1]}" -td --runtime="$RUNTIME"  --mount "$MOUNT_OPTIONS" "$IMAGE" bash -c "$CMD"
		((not_started_count--))
 		info "$not_started_count remaining containers"
	done

	# We verify that number of containers that we selected
	# are running
	for i in $(seq "$timeout") ; do
		echo "Verify that the containers are running"
		containers_launched=$(docker ps -a | grep "$IMAGE" | grep "Up" | wc -l)
		[ "$containers_launched" -eq "$NUM_CONTAINERS" ] && break
		sleep 1
		[ "$i" == "$timeout" ] && return 1
	done

	touch "$host_trigger_file"
	info "All containers are running the workload..."

	# Now that containers were launched, we need to verify that they finished
	# running the webtootl benchmark
	for i in $(seq "$timeout") ; do
		echo -n "."
		containers_exited=$(docker ps -a | grep "$IMAGE" | grep "Exited" | wc -l)
		[ "$containers_exited" -eq "$NUM_CONTAINERS" ] && break
		sleep 1
		[ "$i" == "$timeout" ] && return 1
	done

	# Get container's ids
	CONTAINERS_ID=($(docker ps -a --format "table {{.ID}}" -f ancestor=$IMAGE | tail -n +2))
	for i in "${CONTAINERS_ID[@]}"; do
			docker cp "$i:$file_path/$file_name" "$TMP_DIR"
			pushd "$TMP_DIR"
			cat "$file_name" >> "results"
			popd
	done
	cp $TMP_DIR/results $RESULT_DIR/rawresults

	# Save configuration
	metrics_json_start_array

	local output=$(cat "$TMP_DIR/results")
	local cut_results="cut -d':' -f2 | sed -e 's/^[ \t]*//'| cut -d ' ' -f1 | tr '\n' ',' | sed 's/.$//'"

	local acorn=$(echo "$output" | grep -w "acorn" | eval "${cut_results}")
	local babel=$(echo "$output" | grep -w "babel" | sed '/babel-minify/d' | eval "${cut_results}")
	local babel_minify=$(echo "$output" | grep -w "babel-minify" | eval "${cut_results}")
 	local babylon=$(echo "$output" | grep -w "babylon" | eval "${cut_results}")
	local buble=$(echo "$output" | grep -w "buble" | eval "${cut_results}")
	local chai=$(echo "$output" | grep -w "chai" | eval "${cut_results}")
	local coffeescript=$(echo "$output" | grep -w "coffeescript" | eval "${cut_results}")
	local espree=$(echo "$output" | grep -w "espree" | eval "${cut_results}")
	local esprima=$(echo "$output" | grep -w "esprima" | eval "${cut_results}")
	local jshint=$(echo "$output" | grep -w "jshint" | eval "${cut_results}")
	local lebab=$(echo "$output" | grep -w "lebab" | eval "${cut_results}")
	local postcss=$(echo "$output" | grep -w "postcss" | eval "${cut_results}")
	local prepack=$(echo "$output" | grep -w "prepack" | eval "${cut_results}")
	local prettier=$(echo "$output" | grep -w "prettier" | eval "${cut_results}")
	local source_map=$(echo "$output" | grep -w "source-map" | eval "${cut_results}")
	local terser=$(echo "$output" | grep -w "terser" | eval "${cut_results}")
	local typescript=$(echo "$output" | grep -w "typescript" | eval "${cut_results}")
	local uglify_js=$(echo "$output" | grep -w "uglify-js" | eval "${cut_results}")
	local geometric_mean=$(echo "$output" | grep -w "Geometric" | eval "${cut_results}")
	local average_tps=$(echo "$geometric_mean" | sed "s/,/+/g;s/.*/(&)\/$NUM_CONTAINERS/g" | bc -l)
	local total_tps=$(echo "$average_tps*$NUM_CONTAINERS" | bc -l)

	local json="$(cat << EOF
 	{
 		"Acorn" : "$acorn",
 		"Babel" : "$babel"
		"Babel minify" : "$babel_minify",
		"Babylon" : "$babylon",
		"Buble" : "$buble",
		"Chai" : "$chai",
		"Coffeescript" : "$coffeescript",
		"Espree" : "$espree",
		"Esprima" : "$esprima",
		"Jshint" : "$jshint",
		"Lebab" : "$lebab",
		"Postcss" : "$postcss",
		"Prepack" : "$prepack",
 		"Prettier" : "$prettier",
 		"Source map" : "$source_map",
		"Terser" : "$terser",
		"Typescript" : "$typescript",
		"Uglify js" : "$uglify_js",
		"Geometric mean" : "$geometric_mean",
		"Average TPS" : "$average_tps",
		"Total TPS" : "$total_tps"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"
	metrics_json_save
	docker rm -f "${CONTAINERS_ID[@]}"
	clean_env
}

main "$@"
