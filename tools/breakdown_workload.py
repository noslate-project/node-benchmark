#! /usr/bin/python
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


import argparse
import logging
import sys
import shutil
from pathlib import Path
from fabric import Connection

CURRENT_DIR = Path(__file__).resolve().parent
WORKLOAD_DIR = CURRENT_DIR.parent / "docs-workload"
sys.path.append(CURRENT_DIR)

from utils import ImageManager, get_possible_parameters, \
    get_node_image_name, get_workload_image_name, parse_yaml, \
    check_cpu_idle

class ModuleBreakDown:
    def __init__(self):
        self.result_dir = None
        self.instance_num = None
        self.emon = False
        self.machine = None
        self.workload = None
        self.cpuset = None
    
    def execute_shell(self, cmd):
        with Connection('localhost') as c:
            result = c.local(cmd)
            if result.exited == "0":
                return result.exited, result.stdout, result.stderr
            return result.exited, result.stdout, result.stderr
    
    def check_cpu_idle(self):
        if (not check_cpu_idle()):
            logging.error('Stop execution due to high CPU usage (> 5%)')
            exit(1)

    def run_task(self, run_param, clean_prev_result = False):
        command = run_param.get("breakdown")
        image = run_param.get("image")
        # no meaning of version
        node_version = run_param.get("node_version", "")
        protocol = run_param.get("protocol", "")
        
        opt_type = "opt" if self.cpuset == "true" else run_param.get("opt_type", "")
        emon = "true" if self.emon else "false"
        
        test_result = self.result_dir
        
        is_ghost_workload = True if self.workload.startswith('ghost') else False
        is_base64_workload = True if self.workload.startswith('base64') else False
        
        command = WORKLOAD_DIR / command
        node_run_flags = run_param.get("node_run_flags")
        
        if (clean_prev_result):
            logging.info('Cleaning previous result')
            if (test_result.exists()):
                shutil.rmtree(str(test_result))
        
        # Create results folder if not exists
        if (not test_result.exists()):
            test_result.mkdir()
        
        if is_ghost_workload:
            cmd = f'{command} {self.instance_num} {image} {node_version} {protocol} {opt_type} {self.machine} "{node_run_flags}" "{self.perf_args}"' 
        elif is_base64_workload:
            cmd = f'{command} -n {self.instance_num} -i {image} -p "{self.perf_args}"'
        else:
            cmd = f'{command} -n {self.instance_num} -i {image} -r "{node_run_flags}" -e {emon} -m {self.machine} -c {self.cpuset} -p "{self.perf_args}"'

        logging.info(cmd)
        code, *arg = self.execute_shell(cmd)
        if str(code) == "0":
            logging.info("run task successfully!")
            return True
        else:
            logging.info("run task failed!")
            return False
        
    def breakdown(self):
        parser = argparse.ArgumentParser("module_breakdown")
        parser.add_argument("--workload", "-w", type=str, dest='workload', help="workload")
        parser.add_argument("--fix-build", "-n", type=str, dest='fixed_build', help="node build flags")
        parser.add_argument("--tuning-build", "-t", type=str, dest='tuning_build', help="node tuning build flag")
        parser.add_argument("--fix-run", "-l", type=str, dest='fixed_run', help="node run flags")
        parser.add_argument("--tuning-run", "-x", type=str, dest='tuning_run', help="node tuning run flag")
        parser.add_argument("--repo", "-r", type=str, dest='repo', help="nodejs repo url")
        parser.add_argument("--branch", "-b", type=str, dest='branch', help="nodejs repo branch")
        parser.add_argument("--docker", "-d", type=str, dest='registry', default='localhost:5000', help="docker registry url")
        parser.add_argument("--nocache", "-c", type=str, dest='nocache', default='false', help="don't use cached image")
        parser.add_argument("--instance", "-i", type=str, dest='instance', default='1', help="instance num")
        parser.add_argument('--verbose', '-v', action='store_true', help="verbose mode")
        parser.add_argument('--emon', action='store_true', help="Use Emon or not")
        parser.add_argument('--machine', '-m', type=str, help="Verify machine name when collecting emon")
        parser.add_argument('--cpuset', type=str, help='Docker cpu set')
        parser.add_argument('--bolt', type=str, default="false", help="bolt optimization")
        parser.add_argument('--perf', '-p', type=str, default="--delay 5 --call-graph=fp --clockid=mono --output=perf.data -g", help="args of perf record")
        args = parser.parse_args()
        
        logging.basicConfig(level=logging.INFO if not args.verbose else logging.DEBUG,
                            format="\033[36m%(levelname)s [%(filename)s:%(lineno)d] %(message)s\033[0m")
        
        logging.info('Checking CPU usage info')
        # self.check_cpu_idle()
        logging.info('Pass CPU idle checking, continue execution')
        
        workload = args.workload
        node_branch = args.branch
        machine = args.machine
        cpuset = args.cpuset
        perf_args = args.perf
        
        self.workload = workload
        self.machine = machine
        self.instance_num = int(args.instance)
        self.cpuset = cpuset.lower()
        self.perf_args = perf_args
        if args.emon:
            self.emon = "true"
        self.machine = machine
        apply_bolt = True if args.bolt.lower() == 'true' else False
        logging.info(f'Module Breakdown: workload [{self.workload}] with [{self.instance_num}] instances')
        logging.info(f'Cpuset is [{self.cpuset}] and machine is [{self.machine}]')
    
        config_file_path = WORKLOAD_DIR / 'configure/configure.yml'
    
        image_mgr = ImageManager(args.registry)
        cfg_args = parse_yaml(config_file_path)
        logging.debug(f'Loaded yaml info: {cfg_args}')
        
        if (not node_branch):
            node_branch = cfg_args.get("NODE_VERSION")
        
        self.result_dir = WORKLOAD_DIR / cfg_args.get(workload).get('result_breakdown_dir')
        
        for build_flag in get_possible_parameters(args.fixed_build, args.tuning_build):
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
                run_param = cfg_args.get(workload)

                run_param["image"] = workload_image_name
                run_param["node_run_flags"] = run_flag.strip()
                
                self.run_task(run_param, True)

if __name__ == '__main__':
    task = ModuleBreakDown()
    task.breakdown()
    exit(0)
    
    
    