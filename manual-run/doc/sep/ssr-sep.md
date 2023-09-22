# Manual Run Sep in Container
## Step 0
Buid node with `--enable-vtune-profiling` with 2 methods
- Build by `manual-run` scripts
- Manual building in container (Not recommended)

```bash
mkdir -p /home/ubuntu/work/
cd /home/ubuntu/work/
git clone --depth 1 --branch v18.14.2 https://github.com/nodejs/node.git

cd node
./configure --enable-vtune-profiling
```

## Step 1 - Start the container

**_Tips_**: `--privileged` and `--cpuset-cpus`
```bash
# Server
docker run -it --privileged --name sep-server --cpuset-cpus=0,167 ssr_calcom-intel-v18.14.2:d2857fbf486b3931f98713bfcc6d75ab /bin/bash

# Client
docker run -it --privileged --name sep-client --cpuset-cpus=56,223 ssr_calcom:client /bin/bash
./docker-entrypoint.sh 5000 100 "192.168.0.2"
```

## Step 2 - Install packages in server container

```bash
apt-get install -y kmod vim
apt install -y linux-headers-`uname -r` ncurses-term
mkdir -p /root/report
```

## Step 3 - Copy the sep-related installation package to the container

**_Tips_**: Run outside conatiner

```bash
docker cp sep_private_5_39_linux_03132007fb4d77b.tar.bz2 sep-server:/root
docker cp l_oneapi_vtune_p_2023.1.0.44286_offline.sh sep-server:/root
```

## Step 4

### 1 install sep and vtune
```bash
tar xf sep_private_5_39_linux_03132007fb4d77b.tar.bz2
cd sep_private_5_39_linux_03132007fb4d77b
./sep-installer.sh --no-udev
source /opt/intel/sep/sep_vars.sh
bash l_oneapi_vtune_p_2023.1.0.44286_offline.sh
```

### 2 modify env
```bash
echo "export INTEL_JIT_PROFILER32=/opt/intel/oneapi/vtune/latest/lib32/runtime/libittnotify_collector.so" >> ~/.bashrc
echo "export INTEL_JIT_PROFILER64=/opt/intel/oneapi/vtune/latest/lib64/runtime/libittnotify_collector.so" >> ~/.bashrc
echo "export INTEL_ITTNOTIFY_CONFIG=:resumed:0:0:0:0:sys:task:/root/report" >> ~/.bashrc
source ~/.bashrc
```

## Step 5 - Start enough instance
**_Tips_**: Run outside conatiner, and the instance nums should be adjusted according to the actual situation.
```bash
./run.sh -w ssr_calcom -n "" -i 99
```

## Step 6 - Start sep collecting in server container

```
sep -start -ec "INST_RETIRED.ANY","CPU_CLK_UNHALTED.THREAD","BR_INST_RETIRED.ALL_BRANCHES","BR_MISP_RETIRED.ALL_BRANCHES","BR_MISP_RETIRED.COND","BR_MISP_RETIRED.COND_NTAKEN","BR_MISP_RETIRED.COND_TAKEN","BR_MISP_RETIRED.INDIRECT","BR_MISP_RETIRED.INDIRECT_CALL","BR_MISP_RETIRED.RET","ICACHE_DATA.STALLS","DTLB_STORE_MISSES.STLB_HIT","DTLB_LOAD_MISSES.STLB_HIT","DTLB_LOAD_MISSES.WALK_COMPLETED","DTLB_STORE_MISSES.WALK_COMPLETED","DSB2MITE_SWITCHES.PENALTY_CYCLES","L2_RQSTS.ALL_CODE_RD","L1D.REPLACEMENT","ITLB_MISSES.STLB_HIT","ITLB_MISSES.WALK_COMPLETED" -app "yarn" -args "start"
```