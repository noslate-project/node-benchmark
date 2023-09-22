#! /usr/bin/python
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


import os
import sys
import logging
import re
import subprocess

#perf report -i perf.data -F period,overhead,sample,comm,dso,symbol --header

#find . -name detail.txt | parallel  ~/backup/demangle_perf/demangle_perf.py
#find . -name "perf.data"

#PLEASE USE PYTHON2, NOT PYTHON3. ON LINUX, RUN APT-GET INSTALL PYTHON2 TO INSTALL
#PYTHON2

events_percent = {}

events_counts = {}

def GetModuleFromPerf(filename):
    with open('./tmp.txt', 'wt') as fout:
        getVersion = subprocess.Popen('perf report -i %s -F period,overhead,sample,comm,dso,symbol --header --no-children' % filename, shell=True, stdout=subprocess.PIPE).stdout
        output =  getVersion.read()
        for line in output:
            fout.write(str(line))
    p = re.compile('.*of event.*')
    outfile = ''
    event_name = ''

    v8cpp='v8::'
    v8cpp_turbofan='v8::internal::compiler'
    v8cpp_sparkplug='v8::internal::baseline'
    v8cpp_IC='IC'

    builtins_handler='BytecodeHandler:'
    builtins='Builtin:'
    builtins_IC='IC'

    libuv='uv_'
    TF_jitted='LazyCompile:'
    Baseline_jitted='Function:'
    regexp='Regexp:'

    kernel='[kernel.kallsyms]'

    with open('./tmp.txt', 'rt') as fin:
        for line in fin:
            m = p.match(line)
            if m != None:
                path = os.path.dirname(filename)
                event_name = line.split('\'')[1]
                outfile = os.path.join(path, event_name) + ".txt"
                with open(outfile, "w") as fout:
                    fout.write(line)
                
                events_counts[event_name] = {}
                events_counts[event_name]['sum'] = 0
                events_counts[event_name]['node_sum'] = 0
                events_counts[event_name]['v8cpp_others_sample'] = 0
                events_counts[event_name]['v8cpp_turbofan_sample'] = 0
                events_counts[event_name]['v8cpp_sparkplug_sample'] = 0
                events_counts[event_name]['v8cpp_IC_sample'] = 0
                events_counts[event_name]['builtins_handler_sample'] = 0
                events_counts[event_name]['builtins_other_sample'] = 0
                events_counts[event_name]['builtins_IC_sample'] = 0
                events_counts[event_name]['v8jitted_sample'] = 0
                events_counts[event_name]['libuv_sample'] = 0
                events_counts[event_name]['kernel_sample'] = 0
                
            elif outfile != '':
                data_p = re.compile(r'.*(\d+\.?\d*%)\s+\d+')
                m = data_p.match(line)
                if m != None:
                    with open(outfile, "a") as fout:
                        fout.write(line)
                    arrays = line.split()
                    events_counts[event_name]['sum'] += int(arrays[0])
                    if arrays[4] == "node":
                        events_counts[event_name]['node_sum'] += int(arrays[0])
                    function = ''.join(arrays[6:])
                    
                    if function.startswith(v8cpp):
                        if function.startswith(v8cpp_turbofan):
                            events_counts[event_name]['v8cpp_turbofan_sample'] += int(arrays[0])
                        elif function.startswith(v8cpp_sparkplug):
                            events_counts[event_name]['v8cpp_sparkplug_sample'] += int(arrays[0])
                        elif v8cpp_IC in function:
                            events_counts[event_name]['v8cpp_IC_sample'] += int(arrays[0])
                        else:
                            events_counts[event_name]['v8cpp_others_sample'] += int(arrays[0])
                    elif function.startswith(builtins):
                        if builtins_IC in function:
                            events_counts[event_name]['builtins_IC_sample'] += int(arrays[0])
                        else:
                            events_counts[event_name]['builtins_other_sample'] += int(arrays[0])
                    elif function.startswith(builtins_handler):
                        events_counts[event_name]['builtins_handler_sample'] += int(arrays[0])
                    elif function.startswith(libuv):
                        events_counts[event_name]['libuv_sample'] += int(arrays[0])
                    elif function.startswith(TF_jitted) or function.startswith(Baseline_jitted) or function.startswith(regexp):
                        events_counts[event_name]['v8jitted_sample'] += int(arrays[0])
                    elif arrays[4] == kernel:
                        events_counts[event_name]['kernel_sample'] += int(arrays[0])



if __name__ == '__main__':

    if len(sys.argv) != 2:
        print ("usage: breakdown_perf perf.data")
        print (sys.argv)
        sys.exit()
    filename = sys.argv[1]

    GetModuleFromPerf(filename)

    print ("exported to files")



    for event_name in events_counts:
        if events_counts[event_name]['sum'] == 0:
            print ('Event %s: sample count is 0' % event_name)
            print ('\n')
        else:
            v8cpp_turbofan_percent = 100.0 * events_counts[event_name]['v8cpp_turbofan_sample'] / events_counts[event_name]['sum']
            v8cpp_sparkplug_percent = 100.0 * events_counts[event_name]['v8cpp_sparkplug_sample'] / events_counts[event_name]['sum']
            v8cpp_IC_percent = 100.0 * events_counts[event_name]['v8cpp_IC_sample'] / events_counts[event_name]['sum']
            v8cpp_others_percent = 100.0 * events_counts[event_name]['v8cpp_others_sample'] / events_counts[event_name]['sum']

            builtins_handler_percent = 100.0 * events_counts[event_name]['builtins_handler_sample'] / events_counts[event_name]['sum']
            builtins_other_percent = 100.0 * events_counts[event_name]['builtins_other_sample'] / events_counts[event_name]['sum']
            builtins_IC_percent = 100.0 * events_counts[event_name]['builtins_IC_sample'] / events_counts[event_name]['sum']

            v8jitted_percent = 100.0 * events_counts[event_name]['v8jitted_sample'] / events_counts[event_name]['sum']
            kernel_percent = 100.0 * events_counts[event_name]['kernel_sample'] / events_counts[event_name]['sum']
            libuv_percent = 100.0 * events_counts[event_name]['libuv_sample'] / events_counts[event_name]['sum']

            node_others = events_counts[event_name]['node_sum'] - events_counts[event_name]['v8cpp_turbofan_sample'] - events_counts[event_name]['v8cpp_sparkplug_sample'] - events_counts[event_name]['v8cpp_others_sample'] - events_counts[event_name]['v8cpp_IC_sample'] - events_counts[event_name]['libuv_sample']
            node_others_percent = 100.0 * node_others / events_counts[event_name]['sum'] # Luc: add node_others which is other parts in node component

            other_percent = 100.0 - node_others_percent - v8cpp_turbofan_percent - v8cpp_sparkplug_percent - v8cpp_IC_percent - v8cpp_others_percent - builtins_handler_percent - builtins_other_percent - builtins_IC_percent - v8jitted_percent - kernel_percent - libuv_percent

            res_list = [
                'Event %s: sample count is %d' % (event_name, events_counts[event_name]['sum']),
                'v8_sparkplug_cpp\t%s%%' % v8cpp_sparkplug_percent,
                'v8_turbofan_cpp\t%s%%' % v8cpp_turbofan_percent,
                'v8_IC_cpp\t%s%%' % v8cpp_IC_percent,
                'v8_others_cpp\t%s%%' % v8cpp_others_percent,
                'builtins_handler (jitted)\t%s%%' % builtins_handler_percent,
                'builtins_IC (jitted)\t%s%%' % builtins_IC_percent,
                'builtins_other (jitted)\t%s%%' % builtins_other_percent,
                'v8jitted\t%s%%' % v8jitted_percent,
                'node_cpp\t%s%%' % node_others_percent,
                'libuv_cpp\t%s%%' % libuv_percent,
                'kernel\t%s%%' % kernel_percent,
                'others\t%s%%' % other_percent
            ]
            print ('Event %s: sample count is %d' % (event_name, events_counts[event_name]['sum'])  )
            print ('v8_sparkplug_cpp\t%s%%' % v8cpp_sparkplug_percent                               )
            print ('v8_turbofan_cpp\t%s%%' % v8cpp_turbofan_percent                               )
            print ('v8_IC_cpp\t%s%%' % v8cpp_IC_percent                               )
            print ('v8_others_cpp\t%s%%' % v8cpp_others_percent                               )
            print ('builtins_handler(jitted)\t%s%%' % builtins_handler_percent                               )
            print ('builtins_IC(jitted)\t%s%%' % builtins_IC_percent                               )
            print ('builtins_other(jitted)\t%s%%' % builtins_other_percent                               )
            print ('v8jitted(jitted)\t%s%%' % v8jitted_percent                               )
            print ('node_cpp\t%s%%' % node_others_percent                               )
            print ('libuv_cpp\t%s%%' % libuv_percent                               )
            print ('kernel\t%s%%' % kernel_percent                               )            
            print ('libc_others\t%s%%' % other_percent                               )
            print ('\n'                                                                             )
            with open("./result.txt", "a") as f:
                for item in res_list:
                    f.write(item + "\n")