#! /usr/bin/python
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


import sys
import argparse
from pathlib import Path

CURRENT_DIR = Path(__file__).resolve().parent
WORKLOAD_DIR = CURRENT_DIR.parent / "docs-workload"
sys.path.append(CURRENT_DIR)

from utils import get_node_image_name, parse_yaml, get_workload_image_name

parser = argparse.ArgumentParser("run_workload")
parser.add_argument("--workload", "-w", type=str, dest='workload', help="workload")
parser.add_argument("--fix-build", "-n", type=str, dest='fixed_build', default='', help="node build flags")
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
parser.add_argument('--bolt', type=str, default="false", help="bolt optimization")
args = parser.parse_args()

config_file_path = WORKLOAD_DIR / 'configure/configure.yml'
cfg_args = parse_yaml(config_file_path)

node_branch = args.branch
apply_bolt = True if args.bolt.lower() == 'true' else False
if (not node_branch):
    node_branch = cfg_args.get("NODE_VERSION")

node_image_name = get_node_image_name(args.repo, node_branch, args.fixed_build, apply_bolt)
workload_iamge_name = get_workload_image_name(args.workload, node_image_name)
print(workload_iamge_name)