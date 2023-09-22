# Nodejs tools

## Automation server setup
These files are part of the nodejs automation server, please refer to [../deploy/README.md](../deploy/README.md) for the deployment instructions

## Manual setup setup
It's also possible to use these files without automation server, please follow the below steps:

### Required files

These scripts assumes that it is executed in current repo, if you want to extract necessary files from the repository, please keep this path relationship:

``` bash
workload
├── configure
│   └── configure.yml
├── tools
│   ├── build_workload.py
│   ├── run_workload.py
│   ├── requirements.txt
│   └── utils.py
├── node
│   └── build
│       ├── auto_parameter
│       │   └── Dockerfile
│       └── Dockerfile
└── any workload you want (webtooling | ghost | nextjs ...)
```

1. install required software components
    ``` bash
    sudo apt update && sudo apt install -y python3 python3-pip runc sysstat docker.io
    ```

2. Install python dependencies

    ``` bash
    pip3 install -r requirements.txt
    ```

3. Deploy docker registry

    ``` bash
    docker run -d -p 5000:5000 --restart=always --name jenkins-registry registry:2
    ```

4. Build node and workload image

    ``` bash
    python3 build_workload.py <workload_name>
    # e.g. webtooling, using upstream repo
    python3 build_workload.py webtooling
    # e.g. webtooling, using specified repo and branch
    python3 build_workload.py webtooling -r="https://$USER@$PAT:github.com/xxxx.git" -b="main"
    # e.g. nextjs_stateless, using custom build parameters
    python3 build_workload.py nextjs_stateless -n="-DXXXXXX -DXXXX"
    # e.g. webtooling, using docker registry from another host
    python3 build_workload.py webtooling -d="xx.xx.xx.xx:5000"
    # e.g. webtooling, don't use docker cache
    python3 build_workload.py webtooling -c true
    ```

    > Note: Docker will always try to use cache if you have built the same image previously, if you want to rebuild the image after some change in your node repo, don't forget to use `-c true` to force build a new image

    > Note: This step will build both node image and workload image, and push them to the docker registry.
    > - The node image is named as:
    `node-<node_branch>:<md5(node_repo + node_build_args)>`
    > - The workload image is named as:
    `<workload_name>-<node_branch>:<md5(node_repo + node_build_args)>`

5. Run the workload

    ``` bash
    python3 run_workload.py -w <workload_name>
    # e.g. webtooling, using upstream repo
    python3 run_workload.py -w webtooling
    # e.g. webtooling, with custom run flags
    python3 run_workload.py -w webtooling -l="--xxxxx=xx"
    # e.g. nextjs_stateless, with 2 instances
    python3 run_workload.py -w nextjs_stateless -i 2
    ```

    > Note: other parameters such as `--repo` remains the same with `build_workload.py`, that's for convenience with automation server, they will not influence the execution.
### Tuning Args
- https://github.com/intel-innersource/frameworks.web.pnp.cloud-runtime.pnp-activities/issues/237
### Notes
1. Upload/Download files from server
```bash
curl http://10.238.151.112:8001/upload -F "file=@./$pgofile_name"
wget -O a.txt http://10.238.151.112:8001/download?filename=requirements.txt
```