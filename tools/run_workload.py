#! /usr/bin/python
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


# -*- coding: utf-8 -*-
import argparse
import hashlib
import json
import os
import sys
import traceback
import logging
from pathlib import Path
from fabric import Connection
import time
import shutil
import glob

CURRENT_DIR = Path(__file__).resolve().parent
WORKLOAD_DIR = CURRENT_DIR.parent / "docs-workload"
sys.path.append(CURRENT_DIR)

from utils import ImageManager, get_possible_parameters, \
    get_node_image_name, get_workload_image_name, parse_yaml, \
    check_cpu_idle

from get_node_tag import get_max_tag
from Handlers import ParamHandler

class WorkloadRunner(object):
    def __init__(self):
        pass

    def run_task(self, run_param, clean_prev_result = False):
        command = run_param.get("cmd")
        image = run_param.get("image")
        node_version = self.node_branch
        protocol = run_param.get("protocol", "")
        opt_type = "opt" if self.cpuset else run_param.get("opt_type", "")
        command = WORKLOAD_DIR / command
        node_run_flags = run_param.get("node_run_flags")

        is_ghost_workload = True if self.workload.startswith('ghost') else False
        is_fc_workload = True if self.workload.startswith('fc_startup') else False
        is_nodeio_workload = True if self.workload.startswith('nodeio') else False
        test_result = self.result_dir

        if (clean_prev_result):
            logging.info('Cleaning previous result')
            if (test_result.exists()):
                shutil.rmtree(str(test_result))

        # Create results folder if not exists
        if (not test_result.exists()):
            test_result.mkdir()
        
        # Move the temporary result file to staging folder
        if (not self.result_staging_dir.exists()):
            self.result_staging_dir.mkdir()

        if is_ghost_workload:
            # ghostjs
            cmd = f"{command} {self.instance_num} {image} {node_version} {protocol} {opt_type} {node_run_flags}"
        
        elif is_fc_workload:
            if self.cpuset:
                cmd = f'{command} {self.instance_num} {image} "{node_run_flags}" bind'
            else:
                cmd = f'{command} {self.instance_num} {image} "{node_run_flags}"'
        
        elif is_nodeio_workload:
            client_image = run_param.get("client_image")
            client_num = self.nodeio_params["client_num"]
            message_num = self.nodeio_params["message_num"]
            conn_num = self.nodeio_params["conn_num"]
            message_size = self.nodeio_params["message_size"]
            stream_num = self.nodeio_params["stream_num"]
            cmd = f'{command} -t {self.case} -C {client_num} -n {message_num} -c {conn_num} -m {message_size} -s {stream_num} -i {self.instance_num} -X {image} -Y {client_image} -R "{node_run_flags}"'
        
        else:
            # webtooling, ssr-calcom
            if self.cpuset:
                cmd = f'{command} {self.instance_num} {image} "{node_run_flags}" --cpuset'
            else:
                cmd = f'{command} {self.instance_num} {image} "{node_run_flags}"'

        logging.info(cmd)
        code, *arg = self.execute_shell(cmd)
        if str(code) == "0":
            logging.info("run task successfully!")
            
            if (is_ghost_workload):
                # Ghostjs workload doesn't create difference filename for each run,
                # the previous result will be overwrite by later run. We don't want
                # to modify the ghostjs script, so move it to a new file here
                score_file = test_result / 'ghostjs_score.json'
                if (not score_file.exists()):
                    logging.error(f"Can't find result file for ghost workload")
                    return False
                temp_filename = os.path.join(test_result, f'ghostjs_score-{image.replace("/", "-")}-{time.time()}.json')
                shutil.move(str(score_file), temp_filename)
                logging.info(f'Result file at {temp_filename}')
            
            # 1. Here we move results(.json) to staging_dir to avoid be delete when parameter_tuning.
            # 2. <score>.json will be moved to staging dir. Other files will remain under result_dir.
            files = glob.iglob(os.path.join(test_result, "*.json"))
            for file in files:
                if os.path.isfile(file):
                    shutil.move(file, self.result_staging_dir)
            
            return True
        else:
            logging.info("run task failed!")
            return False

    def extract_result(self, path, image, result_name):
        total = {}
        midian = 0
        res_file = None
        logging.info(f'extract median value from result...')
        logging.info(f'result name for workload [{self.workload}] is [{result_name}]')
        for file in os.listdir(path):
            print(file)
            if image in file:
                logging.debug(f'reading file {file}')
                file_name = os.path.join(path, file)
                res = self.read_content(file_name)
                average = res.get(res.get("test").get("testname")).get("Results")[0].get(result_name)
                total[file_name] = average
                logging.debug(f'file {file} average: [{average}]')
        res_sort = sorted(total.items(), key=lambda x: x[1])
        # delete smallest and largest value
        for index, val in enumerate(res_sort):
            if index == 1:
                midian = val[1]
                res_file = val[0]
                continue
            logging.debug(f'removing file {val[0]}')
            os.remove(val[0])

        logging.info(f'the median value is: [{midian}]')
        return res_file

    def run_median_strategy(self, run_param):
        """median strategy"""
        image = run_param.get("image")

        results = []
        for i in range(3):
            logging.info(f'### Round {i + 1}...')
            results.append(self.run_task(run_param, True if i == 0 else False))

        if (False in results):
            return False
        
        print(results)

        res_file = self.extract_result(self.result_dir, image, run_param.get('result_name'))

        # Move the temporary result file to staging folder
        if (not self.result_staging_dir.exists()):
            self.result_staging_dir.mkdir()

        logging.info(f'staging file {res_file}')
        shutil.move(res_file, str(self.result_staging_dir))

        return True

    def read_content(self, path):
        with open(path) as f:
            res = json.loads(f.read()) or {}
        return res

    def execute_shell(self, cmd):
        with Connection('localhost') as c:
            result = c.local(cmd)
            if result.exited == "0":
                return result.exited, result.stdout, result.stderr
            return result.exited, result.stdout, result.stderr

    def run(self):
        parser = argparse.ArgumentParser("run_workload")
        parser.add_argument("--workload", "-w", type=str, dest='workload', help="workload")
        parser.add_argument("--fix-build", "-n", type=str, dest='fixed_build', help="node build flags")
        parser.add_argument("--tuning-build", "-t", type=str, dest='tuning_build', help="node tuning build flag")
        parser.add_argument("--fix-run", "-l", type=str, dest='fixed_run', help="node run flags")
        parser.add_argument("--tuning-run", "-x", type=str, dest='tuning_run', help="node tuning run flag")
        parser.add_argument("--strategy", "-s", default=None, dest='strategy', help="median strategy")
        parser.add_argument("--repo", "-r", type=str, dest='repo', help="nodejs repo url")
        parser.add_argument("--branch", "-b", type=str, dest='branch', help="nodejs repo branch")
        parser.add_argument("--docker", "-d", type=str, dest='registry', default='localhost:5000', help="docker registry url")
        parser.add_argument("--nocache", "-c", type=str, dest='nocache', default='false', help="don't use cached image")
        parser.add_argument("--instance", "-i", type=str, dest='instance', default='1', help="instance num")
        parser.add_argument('--verbose', '-v', action='store_true', help="verbose mode")
        parser.add_argument('--name', type=str, help="node image name")
        parser.add_argument('--cpuset', type=str, default="false", help='Docker cpu set')
        parser.add_argument('--bolt', type=str, default="false", help="bolt optimization")
        parser.add_argument('--case', type=str, help="nodeio case type")
        parser.add_argument('--nodeio-key', type=str, help="nodeio params key")
        parser.add_argument('--nodeio-value', type=str, help="nodeio params value")
        args = parser.parse_args()

        logging.basicConfig(level=logging.INFO if not args.verbose else logging.DEBUG,
                            format="\033[36m%(levelname)s [%(filename)s:%(lineno)d] %(message)s\033[0m")

        logging.info('Checking CPU usage info')
        if (not check_cpu_idle()):
            logging.error('Stop execution due to high CPU usage (> 5%)')
            exit(1)
        logging.info('Pass CPU idle checking, continue execution')
        
        PHandler = ParamHandler(
            logging=logging,
            args=args,
            workload_dir=WORKLOAD_DIR,
            config_file='configure/configure.yml',
        )
        PHandler.parse_all_args(mode="run")
        
        workload = PHandler.workload
        org_workload = PHandler.org_workload  # Only for getting config params
        node_branch = PHandler.node_branch
        strategy = PHandler.strategy
        apply_bolt = PHandler.apply_bolt
        
        self.workload = workload
        self.node_branch = node_branch
        self.cpuset = PHandler.cpuset
        self.instance_num = PHandler.instance_num
        
        # NodeIO workload
        if workload.startswith('nodeio'):
            self.nodeio_params = PHandler.nodeio_params
            self.case = PHandler.case

        logging.info(f'Running workload [{workload}] with [{self.instance_num}] instances, cpuset is [{self.cpuset}]')

        image_mgr = ImageManager(args.registry)

        cfg_args = PHandler.cfg_args
        logging.debug(f'Loaded yaml info: {cfg_args}')

        # Must be defined in configure.yml for every workload
        # When running as parameter tuning, this dir will be removed for every parameter execution
        self.result_dir = WORKLOAD_DIR / cfg_args.get(org_workload).get('result_dir')
        # Used for parameter tuning, we will save the result file for
        # every run and copy to the result dir when all the execution finished, this dir will be removed
        # after all execution finished
        self.result_staging_dir = self.result_dir.parent / '_result_staging'
        self.raw_results_dir = self.result_dir.parent / 'raw_results'

        if (self.result_dir.exists()):
            shutil.rmtree(str(self.result_dir))

        if (self.result_staging_dir.exists()):
            shutil.rmtree(str(self.result_staging_dir))
        
        if (self.raw_results_dir.exists()):
            shutil.rmtree(str(self.raw_results_dir))

        for build_flag in get_possible_parameters(args.fixed_build, args.tuning_build):
            if args.name:
                node_image_name = args.name
            else:
                node_image_name = get_node_image_name(args.repo, node_branch, build_flag, apply_bolt)
            workload_image_name = get_workload_image_name(workload, node_image_name)
            logging.info(f'{workload_image_name}')

            image = ( image_mgr.pull_image(workload_image_name) or image_mgr.is_local_image(workload_image_name))
            if (not image):
                logging.error(f'image [{workload_image_name}] not ready, please check the build phase')
                exit(1)
            else:
                logging.info(f'found image [{workload_image_name}] from registry, ready for run...')

            run_flags = get_possible_parameters(args.fixed_run, args.tuning_run)
            for run_flag in run_flags:
                logging.info(f'run workload image [{workload_image_name}] with run flags: [{run_flag}]')
                run_param = cfg_args.get(org_workload)

                run_param["image"] = workload_image_name
                run_param["node_run_flags"] = run_flag.strip()
                if workload.startswith('nodeio'):
                    run_param["client_image"] = workload + ":client"

                if strategy:
                    if (not self.run_median_strategy(run_param)):
                        exit(1)
                else:
                    if (not self.run_task(run_param, True)):
                        exit(1)

        # After processing in function run_task, all files except <score>.json exist in result_dir.
        # The <score>.json file is in result_staging_dir.
        # Here we have done the following:
        # 1. result_dir -> raw_results_dir
        # 2. result_staging_dir -> result_dir  // <score>.json
        if (self.result_staging_dir.exists()):
            logging.info(f'Copy staging file to final result dir...')
            if (self.result_dir.exists()):
                shutil.move(str(self.result_dir), str(self.raw_results_dir))
            shutil.move(str(self.result_staging_dir), str(self.result_dir))

        logging.info(f'-------------------------------------------')
        logging.info(f'Finished running workload [{self.workload}]')
        logging.info(f'\tInstance: {self.instance_num}')
        logging.info(f'\tRun args ({len(run_flags)}):')
        for run_flag in run_flags:
            logging.info(f'\t\t{run_flag if run_flag else "empty"}')
        logging.info(f'strategy: {"median" if strategy else "single_run"}')
        logging.info(f'-------------------------------------------')

if __name__ == '__main__':
    runner = WorkloadRunner()
    runner.run()
    exit(0)
