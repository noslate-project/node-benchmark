#! /usr/bin/python
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


import docker
import logging
from pathlib import Path
import hashlib
import json
import yaml
from fabric import Connection
import signal
import os

class ImageManager:
    def __init__(self, registry) -> None:
        self.docker = docker.from_env()
        self.registry = registry

    def pull_image(self, image_name):
        try:
            repository = f'{self.registry}/{image_name}'
            image = self.docker.images.pull(repository)
            image.tag(image_name)
            self.docker.images.remove(repository)
            return self.docker.images.get(image_name)
        except Exception as e:
            logging.error(str(e))
            logging.info(f"didn't find image {image_name} from registry {self.registry}")
            return None
    
    def is_local_image(self, image_name):
        client = docker.from_env()
        
        try:
            image = client.images.get(image_name)
            print(f"The image {image_name} exists locally.")
            return True
        except docker.errors.ImageNotFound:
            print(f"The image {image_name} does not exist locally.")
            return False
        except docker.errors.APIError as e:
            print(f"An error occurred: {e}")
            exit(1)
        

    def push_image(self, image_name):
        try:
            logging.info(f"pushing image [{image_name}] to registry [{self.registry}]")
            repository = f'{self.registry}/{image_name}'
            image = self.docker.images.get(image_name)
            image.tag(repository)
            self.docker.images.push(repository)
            self.docker.images.remove(repository)
            return True
        except Exception as e:
            logging.error(str(e))
            logging.warning(f"failed to push image {image_name} to registry {self.registry}")
            return False

    def build_image(self, context_path, dockerfile_path, target_name, build_arg, nocache=False):
        try:
            logging.info(f"building docker image {target_name} ...")
            cli = docker.APIClient()
            out_stream = cli.build(path=str(context_path), dockerfile=str(
                    dockerfile_path), buildargs=build_arg, tag=target_name, nocache=nocache, use_config_proxy=True)
            for line in out_stream:
                content = json.loads(line.decode("utf-8"))
                if 'errorDetail' in content:
                    logging.error('build docker failed:')
                    logging.error(content['errorDetail'])
                    return False
                if 'stream' in content:
                    print(content['stream'], end='')
            logging.info(f"building docker image {target_name} finished")

            return True

        except Exception as e:
            logging.error(str(e))
            return False

def _handler_range_arg(item):
    """
    handler arg type:
        --arg={start:end} or --arg {start:step:end}
    """
    result = []
    separator = ' ' if ' ' in item else '='
    key, val = item.strip().split(separator)
    key = key.strip('"')

    start, *end = val.strip('"').strip("{}").split(":")
    if len(end) > 1:
        step = end[0]
    else:
        step = 1
    for i in range(int(start), int(end[-1]) + 1, int(step)):
        result.append(f"{key}{separator}{i}")

    return key, result

def _handler_enumeration(item):
    """
    handler arg type:
        --arg={xx|yy|zz} or --arg {xx|yy|zz}
    """
    result = []
    separator = ' ' if ' ' in item else '='
    key, val = item.strip().split(separator)
    key = key.strip('"')
    res = val.strip('"').strip("{")
    res = res.strip("}")
    for i in res.split("|"):
        result.append(f"{key}={i.strip()}")
    return key, result

def _handler_range_enumeration(params : str):
    """ There may be three kinds of tuning args:
        1. range: --arg={start:end} or --arg {start:end}
        2. enum: --arg={xx|yy|zz} or --arg {xx|yy|zz}
        3. boolean: --arg
        Only one tuning parameter is allowed at one time
    """
    param = params.strip('\n').strip()
    results = []
    if '{' in param and '}' in param:
        if ":" in param:
            key, results = _handler_range_arg(param)
        elif "|" in param:
            key, results = _handler_enumeration(param)
    elif param:
        results = ['', param]

    return results

def get_possible_parameters(fixed, tuning):
    """processing input args"""
    result = []
    fixed = (fixed or "").strip()
    tuning = (tuning or "").strip()

    logging.info(f'processing args:')
    logging.info(f'  [fixed] {fixed}')
    logging.info(f'  [tuning] {tuning}')

    result = []

    for tuning_arg in _handler_range_enumeration(tuning):
        result.append((f'{fixed} {tuning_arg}').strip())

    if (len(result) == 0):
        result = [fixed]

    logging.info(f'  [result] {result}')

    return result

def get_node_image_name(node_repo, node_branch, build_arg, apply_bolt):
    '''
        node image name is: node-{branch}:md5(repo type + build flags)
    '''
    if ((not node_repo) or (node_repo == 'https://github.com/nodejs/node')):
        repo_identity = 'upstream'
    else:
        repo_identity = 'internal'

    sorted_build_arg = parse_build_flags(build_arg)
    if not apply_bolt:
        return f"node-{node_branch}:{hashlib.sha3_256((repo_identity + sorted_build_arg).encode('utf-8')).hexdigest()}"
    else:
        extra = "bolt"
        return f"node-{node_branch}:{hashlib.sha3_256((repo_identity + sorted_build_arg + extra).encode('utf-8')).hexdigest()}"

def get_workload_image_name(workload, node_image_name):
    return f'{workload}-{node_image_name[len("node-"):]}'

def get_workload_image_client_name(workload):
    return f'{workload}:client'

def get_pgofile_name(node_image_name):
    return f'pgo-{node_image_name.replace("node-", "").replace(":", "-")}.tar.gz'

def get_boltfile_name(node_image_name):
    return f'perf-{node_image_name.replace("node-", "").replace(":", "-")}.fdata.gz'

def parse_yaml(path):
    with open(path, "r", encoding="utf-8") as f:
        cfg = f.read()
        res = yaml.load(cfg, Loader=yaml.SafeLoader)
        return res

def parse_build_flags(build_flags):
    sorted_builds = build_flags.split(" ")
    sorted_builds.sort()
    sorted_build_flags = ""
    for flag in sorted_builds:
        sorted_build_flags += flag
    return sorted_build_flags

def execute_shell(cmd):
    with Connection('localhost') as c:
            result = c.local(cmd)
            if result.exited == "0":
                return result.exited, result.stdout, result.stderr
            return result.exited, result.stdout, result.stderr

def check_cpu_idle():
    cmd = "sar 1 10 | grep Average: | awk '{print $8}'"
    _, result, err = execute_shell(cmd)
    logging.info(f'CPU idle rate is {result}')
    try:
        if float(result) > 95.0:
            return True
        else:
            return False
    except Exception as e:
        logging.error(f"Can't parse CPU idle rate [{result}]")
        logging.error(str(e))
        return False