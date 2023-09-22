#! /usr/bin/python
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


from pathlib import Path
import argparse
import logging
import sys
import os

CURRENT_DIR = Path(__file__).resolve().parent
WORKLOAD_DIR = CURRENT_DIR.parent / "docs-workload"
sys.path.append(CURRENT_DIR)

from utils import ImageManager, get_possible_parameters, \
    get_node_image_name, get_workload_image_name, \
    get_workload_image_client_name, \
    parse_build_flags

from get_bolt import BOLT_GENERATE
from get_pgo import PGO_GENERATE
from Handlers import ParamHandler

if __name__ == '__main__':
    parser = argparse.ArgumentParser("build_workload")
    parser.add_argument("--workload", "-w", type=str, dest='workload', help="workload")
    parser.add_argument("--fix-build", "-n", type=str, dest='fixed_build', help="node build flags")
    parser.add_argument("--tuning-build", "-t", type=str, dest='tuning_build', help="node tuning build flag")
    parser.add_argument("--repo", "-r", type=str, dest='repo', help="nodejs repo url")
    parser.add_argument("--branch", "-b", type=str, dest='branch', help="nodejs repo branch")
    parser.add_argument("--docker", "-d", type=str, dest='registry', default='localhost:5000', help="docker registry url")
    parser.add_argument("--nocache", "-c", type=str, dest='nocache', default='false', help="don't use cached image")
    parser.add_argument('--verbose', '-v', action='store_true', help="verbose mode")
    parser.add_argument('--storage', '-s', type=str, help="address of storage server", default='localhost:8001')
    parser.add_argument("--poc", type=str, default="false", help="don't use cached pgo image")
    parser.add_argument('--name', type=str, help="node image name")
    parser.add_argument('--bolt',  type=str, default="false", help="bolt optimization")
    parser.add_argument('--case', type=str, help="NodeIO workload case")
    parser.add_argument('--http-proxy', type=str, help="Build workload with http_proxy", default="http://child-prc.intel.com:913/")
    parser.add_argument('--https-proxy', type=str, help="Build workload with https_proxy", default="http://child-prc.intel.com:913/")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO if not args.verbose else logging.DEBUG,
                        format="\033[36m%(levelname)s [%(filename)s:%(lineno)d] %(message)s\033[0m")
    
    PHandler = ParamHandler(
        logging=logging,
        args=args,
        workload_dir=WORKLOAD_DIR,
        config_file='configure/configure.yml',
    )
    PHandler.parse_all_args(mode="build")

    workload = PHandler.workload
    nocache = PHandler.nocache
    apply_bolt = PHandler.apply_bolt
    node_branch = PHandler.node_branch
    storage_url = PHandler.storage_url
    build_client = PHandler.build_client
    cfg_args = PHandler.cfg_args
    logging.debug(f'Loaded yaml info: {cfg_args}')


    image_mgr = ImageManager(args.registry)

    # Build node image
    # for-cycle is only for tuning_build, not for fixed_build
    for build_flag in get_possible_parameters(args.fixed_build, args.tuning_build):
        # if node-image-name is not specified, use the default generated name
        if args.name:
            node_image_name = args.name
        else:
            node_image_name = get_node_image_name(args.repo, node_branch, build_flag, apply_bolt)
        logging.info(f'node image name for build flag [{build_flag}] is: [{node_image_name}]')

        try:
            image = None

            if not nocache["node"]:
                if image_mgr.registry == "No":
                    image = image_mgr.is_local_image(node_image_name)
                else:
                    logging.info('cache enabled, try to find image from registry')
                    image = image_mgr.pull_image(node_image_name)
                
            if (not image):
                context_path = WORKLOAD_DIR / 'node/build'

                param = {
                    "NODE_BUILD_FLAGS": build_flag,
                    "NODEJS_VERSION": node_branch,
                    "PGO_USE": "false",
                    "BOLT_USE": "false",
                }
                if args.repo:
                    param['NODEJS_URL'] = args.repo
                
                # PGO CHECK
                if "pgo" in parse_build_flags(build_flag):
                    if "--openssl-no-asm" not in parse_build_flags(build_flag):
                        logging.error("node-PGO should be built with '--openssl-no-asm' together!")
                        exit(1)
                    param["PGO_USE"] = "true"
                    
                    # PGO file are not related to BOLT file, so set apply_bolt=False.
                    temp_name = get_node_image_name(args.repo, node_branch, build_flag, False)
                    pgo_generator = PGO_GENERATE(
                        image_mgr=image_mgr,
                        node_image_name=temp_name,
                        WORKLOAD_DIR=WORKLOAD_DIR,
                        address=storage_url,
                        cfg_args=cfg_args,
                        nocache=nocache["PGO"]
                    )
                    
                    pgo_generator.set_params(param)
                    pgo_generator.check_pgo_file()
                    param["PGO_FILE"] = pgo_generator.get_file_name()
                
                # BOLT CHECK
                if apply_bolt:
                    param["BOLT_USE"] = "true"
                    
                    # PGO file are not related to BOLT file, so set apply_bolt=False.
                    temp_name = get_node_image_name(args.repo, node_branch, build_flag, False)
                    bolt_generator = BOLT_GENERATE(
                        image_mgr=image_mgr,
                        node_image_name=temp_name,
                        WORKLOAD_DIR=WORKLOAD_DIR,
                        address=storage_url,
                        cfg_args=cfg_args,
                        nocache=nocache["BOLT"]
                    )
                    
                    bolt_generator.set_params(param)
                    bolt_generator.check_file_bolt()
                    param["BOLT_FILE"] = bolt_generator.get_file_name()
                
                logging.info("\nBegin building image...")
                if image_mgr.build_image(context_path, context_path / 'Dockerfile', node_image_name, param, nocache["node"]):
                    if not image_mgr.push_image(node_image_name):
                        if image_mgr.registry == "No":
                            logging.info("No registry.")
                        else:
                            exit(1)
                else:
                    logging.error(f"Failed to build image [{node_image_name}] with build args [{build_flag}]")
                    exit(1)
            else:
                logging.info(f'found image [{node_image_name}] from registry, skip building...')

        except Exception as e:
            logging.error(str(e))
            exit(1)

        # build workload image
        try:
            workload_image_name = get_workload_image_name(workload, node_image_name)
            logging.info(f'workload image name for build flag [{build_flag}] is: [{workload_image_name}]')
            image = None

            if not nocache["workload"]:
                if image_mgr.registry == "No":
                    image = image_mgr.is_local_image(workload_image_name)
                else:
                    image = image_mgr.pull_image(workload_image_name)

            if (not image):
                PHandler.parse_dockerfile_path()
                context_path = PHandler.context_path_server
                dockerfile_path = PHandler.dockerfile_path_server

                # build workload image
                task_image_param = {
                    "BASIC_IMAGE": node_image_name,
                }
                
                if workload.startswith('ssr'):
                    task_image_param["HTTP_PROXY"] = args.http_proxy
                    task_image_param["HTTPS_PROXY"] = args.https_proxy
                
                if image_mgr.build_image(context_path, dockerfile_path, workload_image_name, task_image_param, nocache["workload"]):
                    if not image_mgr.push_image(workload_image_name):
                        if image_mgr.registry == "No":
                            logging.info("No registry.")
                        else:
                            exit(1)
                else:
                    logging.error(f"Failed to build image [{workload_image_name}] based on node image [{node_image_name}]")
                    exit(1)
            else:
                logging.info(f'found image [{workload_image_name}] from registry, skip building...')

        except Exception as e:
            logging.error(str(e))
            exit(1)

        # build client image
        try:
            if build_client:
                logging.info(f"Try to build client image of [{workload}]")
                workload_image_client_name = get_workload_image_client_name(workload)
                image = None
                
                if not nocache["workload"]:
                    image = image_mgr.pull_image(workload_image_client_name)
                
                if (not image):
                    PHandler.parse_dockerfile_path()
                    context_path = PHandler.context_path_client
                    dockerfile_path = PHandler.dockerfile_path_client
                    
                    task_image_param = {
                        "BASIC_IMAGE": node_image_name,
                    }
                    if image_mgr.build_image(context_path, dockerfile_path, workload_image_client_name, task_image_param, nocache["workload"]):
                        if not image_mgr.push_image(workload_image_client_name):
                            if image_mgr.registry == "No":
                                logging.info("No registry.")
                            else:
                                exit(1)
                    else:
                        logging.error(f"Failed to build image [{workload_image_client_name}]")
                        exit(1)
            else:
                logging.info("No client image needed to build")
        
        except Exception as e:
            logging.error(str(e))
            exit(1)

    logging.info('Build finished')
    exit(0)