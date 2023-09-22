#! /usr/bin/python
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


import os
import logging
import requests
import argparse
from fabric import Connection
from utils import get_boltfile_name, get_pgofile_name


def execute_shell(cmd):
    with Connection('localhost') as c:
        result = c.local(cmd)
        if result.exited == "0":
            return result.exited, result.stdout, result.stderr
        return result.exited, result.stdout, result.stderr

class BOLT_GENERATE:
    def __init__(
        self,
        image_mgr,
        node_image_name,
        WORKLOAD_DIR,
        address,
        cfg_args,
        nocache,
        ):
        
        self.image_mgr = image_mgr
        self.node_name = node_image_name
        self.path = WORKLOAD_DIR
        self.address = address
        self.nocache = nocache

        self.file_name = get_boltfile_name(node_image_name)
        self.param = None
        
        self.bolt_image_name = f'bolt-{node_image_name[len("node-"):]}'
        self.context_path_bolt = self.path / cfg_args.get("docker_path", {}).get("bolt")
        self.context_path_node = self.path / 'node/build'
        self.dockerfile = self.context_path_bolt / 'Dockerfile'

    def set_params(self, param):
        self.param = param
    
    def get_file_name(self):
        return self.file_name
    
    def download_file_bolt(self):
        try:
            logging.info(f"Try to get {self.file_name} from server")
            url = f"http://{self.address}/download?filename={self.file_name}" 
            r = requests.get(url)
            
            if r.status_code == 200 and not self.nocache:
                cmd = f"wget -O {self.context_path_node}/patches/{self.file_name} {url}"
                logging.info(cmd)
                code, *arg = execute_shell(cmd)
                if str(code) == "0":
                    logging.info(f"Download {self.file_name} into {self.context_path_node} successfully!")
                    return True
            
            else:
                logging.info(f"No suitable bolt file. Please check the generating stage.")
                return False

        except Exception as e:
            logging.error(str(e))
            exit(1)
    
    def generate_file_bolt(self):
            self.build_generate_image()
            self.run_generate_image()
    
    def check_file_bolt(self):
        if self.image_mgr.registry == "No":
            logging.info("No storage server. Try to find locally again.")
            bolt_file_path = os.path.join(self.context_path_bolt, "patches", self.file_name)
            if os.path.exists(bolt_file_path):
                logging.info("BOLT file is ready.")
            else:
                logging.info(f"No BOLT file found. Try to generate a new bolt file for [{self.node_name}]")
                self.generate_file_bolt()
            return
        try:
            if not self.download_file_bolt():
                logging.info(f"Try to generate a new bolt file for [{self.node_name}]")
                self.generate_file_bolt()
            else:
                logging.info("Downloading bolt file is OK.")
                
        except Exception as e:
            logging.error(str(e))
            exit(1)
    
    def build_generate_image(self):
        if self.param["PGO_USE"] == "true":
            logging.info("Check pgo file is ready for building BOLT.")
            pgo_file_name = get_pgofile_name(self.node_name)
            pgo_file_path = os.path.join(self.context_path_bolt, "patches", pgo_file_name)
            
            self.param["PGO_TYPE"] = "use"
            self.param["PGO_FILE"] = pgo_file_name
            
            if os.path.exists(pgo_file_path):
                logging.info("PGO file is ready.")
            else:
                logging.error("No suitable PGO file found!")
                exit(1)
            
        logging.info("Build BOLT-image for generating bolt file")
        image = None
        
        if not self.nocache:
            logging.info('cache enabled, try to find image from registry')
            if self.image_mgr.registry == "No":
                image = self.image_mgr.is_local_image(self.bolt_image_name)
            else:
                image = self.image_mgr.pull_image(self.bolt_image_name)
            logging.info(f"Skip building [{self.bolt_image_name}] stage. Pull image from registry.")
        
        if not image:
            if self.image_mgr.build_image(self.context_path_bolt, self.dockerfile, self.bolt_image_name, self.param, True):
                if not self.image_mgr.push_image(self.bolt_image_name):
                    if self.image_mgr.registry == "No":
                        logging.info("No registry.")
                    else:
                        exit(1)
            else:
                logging.error(f"Failed to build image [{self.bolt_image_name}] based on node image [{self.node_name}]")
                exit(1)
    
    def run_generate_image(self):
        image = self.image_mgr.pull_image(self.bolt_image_name) or self.image_mgr.is_local_image(self.bolt_image_name)
        if not image:
            logging.error(f'image [{self.bolt_image_name}] not !')
            exit(1)
        else:
            logging.info(f'Collect BOLT file from [{self.bolt_image_name}]')
            cmd = f"bash {self.context_path_bolt}/collect.sh {self.bolt_image_name} {self.file_name} {self.context_path_node}/patches"
            code, *arg = execute_shell(cmd)
            
            # more: shold copy the file to node/build
            # push perf.fdata.gz to server
            cmd = f"curl http://{self.address}/upload -F \"file=@./{self.file_name}\""
            if not self.image_mgr.registry == "No":
                code, *arg = execute_shell(cmd)
            