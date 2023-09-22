#! /usr/bin/python
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


import logging
import requests
import os
import argparse
from fabric import Connection
from utils import get_pgofile_name


def execute_shell(cmd):
    with Connection('localhost') as c:
        result = c.local(cmd)
        if result.exited == "0":
            return result.exited, result.stdout, result.stderr
        return result.exited, result.stdout, result.stderr

class PGO_GENERATE:
    def __init__(
        self,
        image_mgr,
        node_image_name,
        WORKLOAD_DIR,
        address,
        cfg_args,
        nocache
    ):
        
        self.image_mgr = image_mgr
        self.node_name = node_image_name
        self.path = WORKLOAD_DIR
        self.address = address
        self.nocache = nocache
        
        self.file_name = get_pgofile_name(node_image_name)
        self.param = None

        self.pgo_image_name = f'pgo-{node_image_name[len("node-"):]}'
        self.context_path_pgo = self.path / cfg_args.get("docker_path", {}).get("pgo")
        self.context_path_node = self.path / 'node/build'
        self.dockerfile = self.context_path_pgo / 'Dockerfile'
    
    def set_params(self, param):
        self.param = param
        print(self.param["NODEJS_URL"])
    
    def get_file_name(self):
        return self.file_name
    
    def download_file_pgo(self):
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
                logging.info(f"No suitable pgofile. Should Build a new one.")
                return False
            
        except Exception as e:
            logging.error(str(e))
            exit(1)
    
    def generate_file_pgo(self):
        self.build_generate_image()
        self.run_generate_image()
    
    def check_pgo_file(self):
        if self.image_mgr.registry == "No":
            logging.info("No storage server. Try to find locally again.")
            pgo_file_path = os.path.join(self.context_path_pgo, "patches", self.file_name)
            if os.path.exists(pgo_file_path):
                logging.info("PGO file is ready.")
            else:
                logging.info(f"No PGO file found. Try to generate a new pgo file for [{self.node_name}]")
                self.generate_file_pgo()
            return
        try:
            if not self.download_file_pgo():
                logging.info(f"Try to generate a new pgo file for [{self.node_name}]")
                self.generate_file_pgo()

            else:
                logging.info("Download pgo file is OK.")
                
        except Exception as e:
            logging.error(str(e))
            exit(1)

    def build_generate_image(self):
        image = None
        
        if not self.nocache:
            logging.info('cache enabled, try to find image from registry')
            if self.image_mgr.registry == "No":
                image = self.image_mgr.is_local_image(self.pgo_image_name)
            else:
                image = self.image_mgr.pull_image(self.pgo_image_name)
                logging.info(f"Skip building stage. Pull image from registry.")
        
        if not image:
            flags_for_gen = self.param["NODE_BUILD_FLAGS"].replace("--enable-pgo-use", "--enable-pgo-generate")
            image_param = {
                "NODEJS_URL": self.param["NODEJS_URL"],
                "NODEJS_VERSION": self.param["NODEJS_VERSION"],
                "NODE_BUILD_FLAGS": flags_for_gen,
                "PGO_USE": "true",
                "PGO_TYPE": "generate"
            }
            
            if self.image_mgr.build_image(self.context_path_pgo, self.dockerfile, self.pgo_image_name, image_param, True):
                if not self.image_mgr.push_image(self.pgo_image_name):
                    if self.image_mgr.registry == "No":
                        logging.info("No registry.")
                    else:
                        exit(1)
            else:
                logging.error(f"Failed to build image [{self.pgo_image_name}] based on node image [{self.node_name}]")
                exit(1)

    def run_generate_image(self):
        image = self.image_mgr.pull_image(self.pgo_image_name) or self.image_mgr.is_local_image(self.pgo_image_name)
        if (not image):
            logging.error(f'image [{self.pgo_image_name}] not!')
            exit(1)
        else:
            logging.info(f"collect pgo file from [{self.pgo_image_name}]")
            cmd = f"bash {self.context_path_pgo}/collect.sh {self.pgo_image_name} {self.file_name} {self.context_path_node}/patches"
            code, *arg = execute_shell(cmd)
            
            # push pgo-file to server
            cmd = f"curl http://{self.address}/upload -F \"file=@./{self.file_name}\""
            if not self.image_mgr.registry == "No":
                code, *arg = execute_shell(cmd)
            