#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

check_json() {
  folder=$1
  found=0
  count=0

  while [ $found -eq 0 ]
  do
    find $folder -maxdepth 1 -name "*.json" | grep -q . && found=1 || found=0
    sleep 1
    echo "waiting result"
    count=$((count+1))
    if [ $count -gt 30 ]; then
      echo "Timeout. No .json file found in $folder"
      exit 1
    fi
  done
  echo "Found a .json file in $folder"
}

round() {
  printf "%.*f\n" "$2" "$1"
}

tpstotal=$1
machine=$2
workload=$3
result_dir=$4

case $machine in
  *AMD*) edp_architecture_codename="amd" ;;
  *ICX*) edp_architecture_codename="icelake" ;;
  *SPR*) edp_architecture_codename="sapphirerapids" ;;
  *Alderlake*) edp_architecture_codename="gracemont" ;;
  *) echo "[Error]: Unknown machine!" ; exit 1 ;;
esac

sockets_num=$(lscpu | grep Socket | awk -F: '{print $2}')
edp_architecture_sockets=${sockets_num//' '/''}"s"

check_json $result_dir

# Install ruby if not already
if ! command -v ruby &> /dev/null
then
    echo "Ruby is not installed"
    echo "Installing ruby..."
    sudo apt install ruby -y
fi

if [ -z "${edp_architecture_codename}" ]  || [ -z "${edp_architecture_sockets}" ]
then
        echo "Architecture codename and/or number of sockets are not set!"
        echo "Please set the edp_architecture_name and edp_architecture_sockets variables and rerun"
        exit 1
fi

echo "TPS Total = $tpstotal"

echo "Processing EMON for ${edp_architecture_codename} ${edp_architecture_sockets} and generating CSVs/XLSX..."

if [ ${edp_architecture_codename} == "cascadelake" ] || [ ${edp_architecture_codename} == "icelake" ] || [ ${edp_architecture_codename} == "sapphirerapids" ]; then
  # CLX, ICX, SPR
  metric_file="${edp_architecture_codename}_server_${edp_architecture_sockets}_private.xml"
  chart_file="chart_format_${edp_architecture_codename}_server_private.txt"

elif [ ${edp_architecture_codename} == "gracemont" ] || [ ${edp_architecture_codename} == "amd" ]; then
  # AMD, Alderlake
  metric_file="${edp_architecture_codename}_${edp_architecture_sockets}_private.xml"
  chart_file="chart_format_${edp_architecture_codename}_private.txt"
fi


round_tps=$(round $tpstotal)

cp /opt/intel/sep/config/edp/pyedp_config.txt .
cp /opt/intel/sep/config/edp/${metric_file} .
cp /opt/intel/sep/config/edp/${chart_file} .
sleep 2

sed -i "s/^#METRICS=.*/METRICS=$metric_file/g" pyedp_config.txt
sed -i "s/^#CHART_FORMAT=.*/CHART_FORMAT=$chart_file/g" pyedp_config.txt
sed -i "s/^#TPS=.*/TPS=$round_tps/g" pyedp_config.txt
sleep 2

emon -process-pyedp ./pyedp_config.txt
# delete old results
rm -rf $workload-emon-results

# new results
mkdir $workload-emon-results
mv __edp* emon* *.txt *.xml summary.xlsx $workload-emon-results/
cp $result_dir/*.json $workload-emon-results/
zip -r $workload-emon-$machine-$(date +%Y-%m-%d_%H-%M-%S).zip ./$workload-emon-results
exit 0