# Dragon-Creek Node.js performance suites

The Dragon-Creek Node.js performance suites provide a framework for contructing and measuring node.js workloads performance and a few workloads are already included. As the major target is server side performance,  the workload is normally packed as Docker container, and the execution modes covers single instance for single core performance and multiple instances for full cores performance.

The project also supports performance reporting, and workload profiling by using tools like emon and perf.  Notably, this framework offers versatile compatibility, accommodating a wide range of workload types across various programming languages such as Node.js, Java, PHP, and more.

## Prerequisites

Install the dependent softwares to enable our scripts.

- docker: Refer to [How to install Docker on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- python package: `pip3 install fabric pyyaml docker`


## Code structure

Within this framework, you will find the following folders and files:

- `manual-run`: This directory houses scripts essential for configuring, building, executing, and profiling specific workloads or benchmarks. It is crucial for users to consistently initiate the framework from within this folder.

- `tools`: This directory contains utility scripts that are utilized by the manual-run scripts. It's not necessary for users to directly invoke these scripts.

- `workloads`: User manual of writing workloads.

- `LICENSE`: The License file outlining the terms and conditions governing the use of this framework.

- `README.md`: The file you are currently reading, which serves as the main documentation and introductory guide for this framework.

## How to write workloads

A workload typically consists of a Dockerfile and specific scripts for running and profiling. In the Dockerfile, the workflow typically involves downloading the workload code from a public source and building the workload from its source code.

For a more detailed guide on how to create workloads, please refer to the `workloads` folder This folder provides comprehensive instructions for workload development. It will guide you to create efficient workloads that seamlessly integrate with the framework.

## How to configure workloads

To streamline the configuration process and avoid repetitive parameter entry, you can predefine certain environment variables within the config.sh file. Below, you'll find sample parameters outlined in the table below.

The build/run/profile scripts automatically access the configurations in the config.sh file by default. However, these settings can also be overridden by manually entered parameters provided by users through the command line.

### Supported configurations

|      Name      |                            Definition                            |                                                                         Example                                                                         |                         Default value                         |
| :------------: | :---------------------------------------------------------------: | :------------------------------------------------------------------------------------------------------------------------------------------------------: | :------------------------------------------------------------: |
| target machine |                        target to run WL on                        |                                                               ICX `<br>`SPR `<br>`AMD                                                               |                              SPR                              |
|      repo      |             Node repos, upstream or Intel local repos             |                 https://github.com/nodejs/node.git,`<br>`https://github.com/intel-innersource/applications.development.web.nodejs.git                 |               https://github.com/nodejs/node.git               |
|     branch     | branch/tag, seperate PRs and all-opt are maintained by branch/tag |           v18.14.2 for Node 18LTS baseline config `<br>`v18.14.2-opt for Node 18LTS all-opt config `<br>`v18.14.2-lcp for lcp patch config           |                      By default: v18.14.2                      |
|    workload    |                           workload name                           |                        webtooling `<br>`ghost_http `<br>`ghost_https `<br>`ghost_https_nginx `<br>`**ssr_calcom**                        |                     By default: webtooling                     |
|  build_flags  |                build parameters in `./configure`                | --v8-enable-hugepage `<br>`--v8-enable-short-builtin-calls `<br>`--experimental-enable-pointer-compression `<br>`--enable-pgo-use --openssl-no-asm |                               no                               |
|      bolt      |                   apply bolt optimiztion or not                   |                                                                        true/false                                                                        |                             false                             |
|     cache     |       use docker cached images or build image from scratch       |                                                                        true/false                                                                        |                              true                              |
|   run_flags   |                      Node.js CLI parameters                      |                                                                --max-semi-space-size=128                                                                |                               no                               |
|     cpuset     |                 use docker --cpuset-cpuse or not                 |                                                                        true/false                                                                        |                             false                             |
|      nums      |         container instance num to boot up, up to vcpu num         |                                                                 1 `<br>`64 `<br>`224                                                                 |                               1                               |
|   perf_args   |                       Events of perf record                       |                                  -e cycles,instructions --delay 5 --call-graph=fp --clockid=mono --output=perf.data -g                                  | --delay 5 --call-graph=fp --clockid=mono --output=perf.data -g |
|   pgonocache   |  ignore existing pgofile.tar.gz and re-generate pgo data or not  |                                                                        true/false                                                                        |                              true                              |

## How to build workloads

Build all workloads with different optimizations by `build.sh`.

### Definition of build parameters

| Option |          Definition          |           Usage           |           Note           |
| :----: | :---------------------------: | :-----------------------: | :----------------------: |
|   w   |     specify workload name     |       -w webtooling       |                          |
|   b   |    specify branch/tag name    |        -b v18.14.2        |                          |
|   n   |          build flags          | -n "--v8-enable-hugepage" | **"" is required** |
|   o   |       apply bolt or not       |            -o            |                          |
|   c   | clear(don't use) docker cache |            -c            |                          |
|   h   |      print help message      |            -h            |                          |

### Supported Configurations

- **Workload**: webtooling, ghost_http, ghost_https, ghost_https_nginx, fc_startup, fc_startup_cache, base64, ssr_calcom, nodeio (http, https, http2, grpc_unary, grpc_streaming)
- **Build Flags**: some optimization needs own build flags to be enabled, otherwise optimizations do not work

| Enable optimization |                Build flags                |            Version            |
| :-----------------: | :---------------------------------------: | :---------------------------: |
|      Huge Page      |           --v8-enable-hugepage           |                              |
| Short Builtin Calls |      --v8-enable-short-builtin-calls      | only work for Node.js >18.0.0 |
| Compression Pointer | --experimental-enable-pointer-compression |                              |
|         PGO         |     --enable-pgo-use --openssl-no-asm     |                              |

### Examples

Most common used command is to build baseline and all-in-one opt version for workload. If you find all-in-one opt needs too many build options, it is suggested to specify them in `config.sh:build_flags` before building.

```bash
# Build [webtooling] [node] [v18.14.2] [baseline]
./build.sh -w webtooling -b intel-v18.14.2 -n ""
# Build [webtooling] [node] [v18.14.2 all-in-one opt]
./build.sh -w webtooling -b intel-v18.14.2-opt -n "--openssl-no-asm --experimental-enable-pointer-compression --enable-pgo-use --v8-enable-hugepage --v8-enable-short-builtin-calls" -o
```

You can also combine build options per needs:

```bash
# Build [ghost_http] [node] [v16.19.1] [PGO]
./build.sh -w ghost_http -b v16.19.1 -n "--enable-pgo-use --openssl-no-asm"
# Build [ghost_https] [node] [v18.14.2] [PGO+BOLT]
./build.sh -w ghost_https -b v18.14.2 -n "--enable-pgo-use --openssl-no-asm" -o
```

## How to run workloads

Collect TPS by `run.sh`.
**_Important notice_** - build options passed to `run.sh` must be same as in `build.sh`.

### Definition of run parameters

| Option |                              Definition                              |             Usage             |                                                                     Note                                                                     |
| :----: | :------------------------------------------------------------------: | :----------------------------: | :-------------------------------------------------------------------------------------------------------------------------------------------: |
|   w   |                        specify workload name                        |         -w webtooling         |                                                                                                                                              |
|   b   |                       specify branch/tag name                       |          -b v18.14.2          |                                                                                                                                              |
|   n   |                             build flags                             |   -n "--v8-enable-hugepage"   | **"" is required `<br>`This parameter is mandatory when running workload <br />because it is used to tell which Docker image to use** |
|   o   |                              apply bolt                              |               -o               |                                                                                                                                              |
|   i   |                       specify instance numbers                       |             -i 64             |                                                                                                                                              |
|   r   |                              run flags                              | -r "--max-semi-space-size=128" |                                   **"" is required. Webtooling suggests 128 and Ghost suggests 256**                                   |
|   s   | enable `docker --cpuset-cpus` to make each container occupy 2 cpus |               -s               |                                                                                                                                              |
|   c   |                    clear(don't use) docker cache                    |               -c               |                                                                                                                                              |
|   h   |                          print help message                          |               -h               |                                                                                                                                              |

### Supported Configurations

- **Workload**: webtooling, ghost_http, ghost_https, ghost_https_nginx, fc_startup, fc_startup_cache, base64, ssr_calcom, nodeio (http, https, http2, grpc_unary, grpc_streaming)
- **Run Flags**: --max-semi-space-size=xxx

### Examples

Most common used command is to run baseline and all-in-one opt version for workload. If you find all-in-one opt needs too many run options, it is suggested to specify them in `config.sh:run_flags` before building.

```bash
# Run [webtooling] [node] [v18.14.2] [baseline]
./run.sh -w webtooling -b intel-v18.14.2 -n ""
# Run [webtooling] [node] [v18.14.2] [all-in-one opt]. Noted that -n is a mandatory option and same as building phase
# Webtooling: --max-semi-space-size=128
# Ghost.js: --max-semi-space-size=256 
./run.sh -w webtooling -b intel-v18.14.2-opt -n "--openssl-no-asm --experimental-enable-pointer-compression --enable-pgo-use --v8-enable-hugepage --v8-enable-short-builtin-calls" -r "--max-semi-space-size=128" -s -o
```

You can also combine build options per needs:

```bash
# Run [ghost_http] [node] [v16.19.1] [PGO]
./run.sh -w ghost_http -b v16.19.1 -n "--enable-pgo-use --openssl-no-asm"
# Run [ghost_https] [node] [v18.14.2] [PGO+BOLT]
./run.sh -w ghost_https -b v18.14.2 -n "--enable-pgo-use --openssl-no-asm" -o
# Run [ghost_https] [node] [v18.14.2] [PGO+BOLT] [max-semi-space-size]
./run.sh -w ghost_https -b v18.14.2 -n "--enable-pgo-use --openssl-no-asm" -o -r "--max-semi-space-size=256"
```

## How to collect emon/perf data

Collect emon and perf data seperately by `profile.sh`. The Results is in the corresponding workload folder, e.g.

- Webtooling
  - Emon - `workload/webtooling/emon.zip`
  - Profiling - `workload/webtooling/breakdown.zip`
- Ghost_http/Ghost_https/Ghost_https_nginx
  - Emon - `workload/ghost/common/emon/emon.zip`
  - Profiling - `workload/ghost/breakdown.zip`

The `emon.zip` contains excel files and `breakdown.zip` include breakdown ratios and perf.jitted.data, perf.data and flamechart svg file.

Collecting perf data works on cycles collection by default, and it only works on 1 instance for 5 seconds to avoid massive system overhead. The default perf configuration is defined in `config.sh:perf_args` as `--delay 5 --call-graph=fp --clockid=mono --output=perf.data -g` which means profiling for 5 seconds with callstack supported. If you want to change the perf configuration, modify `perf_args`, see samples below.

**_Important notice_** - When specifing `profiling[-p]` and `emon[-e]` at the same time, otherwise only `profiling` will be executed. Suggest Options passed to `profile.sh` be same as in `run.sh`.

### Definition of profile parameters

| Option |          Definition          |             Usage             |           Note           |
| :----: | :---------------------------: | :----------------------------: | :----------------------: |
|   w   |     specify workload name     |         -w webtooling         |                          |
|   b   |    specify branch/tag name    |          -b v18.14.2          |                          |
|   n   |          build flags          |   -n "--v8-enable-hugepage"   | **"" is required** |
|   o   |          apply bolt          |               -o               |                          |
|   i   |   specify instance numbers   |             -i 64             |                          |
|   r   |           run flags           | -r "--max-semi-space-size=128" | **"" is required** |
|   s   |   use docker --cpuset-cpus   |               -s               |                          |
|   c   | clear(don't use) docker cache |               -c               |                          |
|   p   |    collect profiling data    |               -p               |                          |
|   e   |       collect emon data       |               -e               |                          |
|   h   |      print help message      |               -h               |                          |

### Examples

Most common used command is to profile baseline and all-in-one opt version for workload. If you find all-in-one opt needs too many run options, it is suggested to specify them in `config.sh` before building.

```bash
# collect emon data [webtooling] [node] [v18.14.2] [baseline]
./profile.sh -w webtooling -b intel-v18.14.2 -n "" -e
# collect profiling data [webtooling] [node] [v18.14.2] [baseline]
./profile.sh -w webtooling -b intel-v18.14.2 -n "" -p
# collect emon data [webtooling] [node] [v18.14.2] [all-in-one opt]
./run.sh -w webtooling -b intel-v18.14.2-opt -n "--openssl-no-asm --experimental-enable-pointer-compression --enable-pgo-use --v8-enable-hugepage --v8-enable-short-builtin-calls" -r "--max-semi-space-size=256" -s -o -e
# collect perf data [webtooling] [node] [v18.14.2] [all-in-one opt]
./run.sh -w webtooling -b intel-v18.14.2-opt -n "--openssl-no-asm --experimental-enable-pointer-compression --enable-pgo-use --v8-enable-hugepage --v8-enable-short-builtin-calls" -r "--max-semi-space-size=256" -s -o -p
```

If you want to change the perf configuration, modify `perf_args` to e.g. `-e branch-misses, cache-misses --delay 20 --call-graph=fp --clockid=mono --output=perf.data -g`, then run above perf profiling command.
