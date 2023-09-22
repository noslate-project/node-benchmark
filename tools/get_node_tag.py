#! /usr/bin/python
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

# This script will call the shell script that reads the latest tag from the Node.js repo
# It will print the tag name to the standard output

from utils import execute_shell

repo_url = "https://github.com/nodejs/node.git"

def get_max_tag(mode="run"):
    # Define the shell script name
    SHELL_SCRIPT = "./get_node_tag.sh"
    cmd = SHELL_SCRIPT + " " + mode
    return_code, stdout, stderr = execute_shell(cmd)

    # Check if the execution was successful
    if return_code == 0:
        # Print the tag name
        return stdout.strip()
    else:
        # Print an error message
        print(f"Failed to execute the shell script: {result.returncode}")
        exit(1)

if __name__ == "__main__":
    a = get_max_tag()
    print(a)
