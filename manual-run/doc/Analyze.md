# Introduction of how to analyze perf results

## Details
The perf.data is collected in docker container. In `breakdown.zip`, there are 6 files
- output.svg
- perf.data
- perf.report
- perf.profile
- perf.data.tar.bz2
- results.txt

## How to open `perf.data` outside container or another machine?

Here will introduce how to open perf.data with correct symbol outside container or on another machine. Collet data by `perf record` and get `perf.data` result.

### Step 1 - Install and Execute Perf Archive

There is a bug when use `perf archive` installed by `linux-tools`, so build perf-archive from source code.

```bash
# Linux kernel version
uname -r
# Install the dependency
apt install -y flex

# Version should correspond to the kernel version
version="linux-5.15" 
wget https://mirrors.edge.kernel.org/pub/linux/kernel/v5.x/$version.tar.xz
tar xvf $version.tar.xz

# Make build
cd $version/tools/perf
export CC=gcc
# perf-archive will be built under folder: tools/perf
make ARCH=x86_64
```

Run `perf-archive` as below:

```bash
<Execution path of perf-archive> perf.data --all-kcore

# Default path is ~/.debug
tar xvf perf.data.tar.bz2 -C ~/.debug
```

### Setp 2 - Re-open `perf.data`

The path should be same as `tar -C <path>` in Step 1 
```bash
# Copy and untar
mkdir ~/.debug && cd ~/.debug
cp <path to perf.data> <path to perf.data.tar.bz2> ~/.debug
tar xf perf.data.tar.bz2

# perf report is ready
perf report ...
```
