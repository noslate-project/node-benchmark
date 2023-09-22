#! /usr/bin/python
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


import logging
from get_node_tag import get_max_tag
from utils import parse_yaml


class ParamHandler:
    """
    As many as possible to handle more params here.
    To avoid much if-else in main code.    
    """
    def __init__(
        self, 
        logging: logging, 
        args, 
        workload_dir: str,
        config_file: str
    ):
        self.logging = logging
        self.args = args
        
        # Store the orginal name of workload
        # In nodeio, workload name will be modify with [nodeio + case]
        self.org_workload: str = args.workload
        self.case: str = args.case
        self.workload_dir = workload_dir
        
        config_path = workload_dir / config_file
        self.cfg_args = parse_yaml(config_path)
        self.nocache = {}
        
        self._need_client = ["ssr_calcom", "nodeio"]

    def _parse_workload(self):
        workload = self.org_workload
        
        if not workload:
            self.logging.error('Must specify a workload')
            exit(1)
        
        if workload == "nodeio":
            case = self.case
            if not case:
                self.logging.error('NodeIO must be specified with param: [--case]')
                exit(1)
            if case == "socket":
                self.logging.error('NodeIO don\'t support [socket] case now.')
                exit(1)
            workload = workload + '_' + case

        self.workload = workload
    
    def _parse_branch(self):
        node_branch = self.args.branch
        
        if not node_branch:
            node_branch = self.cfg_args.get("NODE_VERSION")
        
        if node_branch == "main":
            node_branch = get_max_tag(mode="build")
        
        self.node_branch = node_branch

    def parse_all_args(self, mode):
        """
        Handle all params of args. 
        1. Handle the common parameters of run and build.
        2. Mode determines which type of argument is processed.
        """
        
        self._parse_workload()
        self._parse_branch()
        
        if mode == "build":
            self._parse_build_args()
        
        if mode == "run":
            self._parse_run_args()
    
    def _parse_build_args(self):
        args = self.args
        
        self.storage_url = args.storage
        
        # Nocache: node(N), workload(W), PGO(P), BOLT(B)
        self.nocache["node"] = True if "N" in args.nocache else False
        self.nocache["workload"] = True if "W" in args.nocache else False
        self.nocache["PGO"] = True if "P" in args.nocache else False
        self.nocache["BOLT"] = True if "B" in args.nocache else False
        
        # Keep the old version available
        if args.nocache.lower() in ['true', 'false']:
            for param in ["node", "workload", "PGO", "BOLT"]:
                self.nocache[param] = True if args.nocache.lower() == 'true' else False
        
        self.pgo_nocache = True if args.poc.lower() == 'true' else False
        self.apply_bolt = True if args.bolt.lower() == 'true' else False
        self.build_client = True if self.org_workload in self._need_client else False
    
    def _parse_run_args(self):
        args = self.args
        
        self.instance_num = int(args.instance)
        self.cpuset = True if args.cpuset.lower() == 'true' else False
        self.apply_bolt = True if args.bolt.lower() == 'true' else False
        self.strategy = args.strategy
        
        if self.workload.startswith('nodeio'):
            nodeio_key = args.nodeio_key.split()
            nodeio_value = args.nodeio_value.split()
            self.nodeio_params = dict(zip(nodeio_key, nodeio_value))
    
    def parse_dockerfile_path(self):
        workload = self.workload
        if not workload:
            logging.error("Workload name is None. Please check the parse_all_args().")
            exit(1)
        
        # Server Path
        # Default context and dockerfile path
        context_path = self.workload_dir / self.cfg_args.get("docker_path", {}).get(self.org_workload)
        dockerfile_path = context_path / 'Dockerfile'
        
        if (workload.startswith('ghost') or workload.startswith('fc_startup')):
            context_path_server = context_path.parent
            dockerfile_path_server = dockerfile_path
        
        elif workload.startswith('ssr_calcom'):
            context_path_server = context_path / 'server'
            if self.node_branch >= "intel-v18.0.0" or self.node_branch >= "v18.0.0":
                dockerfile_path_server = context_path_server / 'v2.9.6' / 'Dockerfile'
            else:
                dockerfile_path_server = context_path_server / 'v2.5.5' / 'Dockerfile'
            
        elif workload.startswith('nodeio'):
            context_path_server = context_path / self.case / 'server'
            if self.case.endswith("streaming"):
                context_path_server = context_path / 'grpc' / 'streaming'
            if self.case.endswith("unary"):
                context_path_server = context_path / 'grpc' / 'unary'
                
            dockerfile_path_server = context_path_server / 'Dockerfile'
        
        else:
            context_path_server = context_path
            dockerfile_path_server = dockerfile_path
        
        self.context_path_server = context_path_server
        self.dockerfile_path_server = dockerfile_path_server

        # Client Path
        if self.build_client:
            if workload.startswith('ssr_calcom'):
                context_path_client = context_path / 'client'
                dockerfile_path_client = context_path_client / 'Dockerfile'
            
            if workload.startswith('nodeio'):
                context_path_client = context_path / self.case / 'client'
                if self.case.startswith("grpc"):
                    context_path_client = context_path / 'grpc' / 'client'
                dockerfile_path_client = context_path_client / 'Dockerfile'
            
            self.context_path_client = context_path_client
            self.dockerfile_path_client = dockerfile_path_client
            logging.debug(f"context_path_client is {self.context_path_client}")
            logging.debug(f"dockerfile_path_client is {self.dockerfile_path_client}")
        
        logging.debug(f"context_path_server is {self.context_path_server}")
        logging.debug(f"dockerfile_path_server is {self.dockerfile_path_server}")
        
