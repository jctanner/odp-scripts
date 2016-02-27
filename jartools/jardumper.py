#!/usr/bin/env python

import json
import os
import sys
import subprocess
import tempfile

def run_command(cmd):
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (so, se) = p.communicate()
    return (p.returncode, so, se)

def which(cmd):

    ''' Get the path for a command '''

    cmd = "which %s" % cmd
    (rc, so, se) = run_command(cmd)
    return so.strip()

def listjarcontents(jarfile):
    # jar tf ~/jars/commons-io-2.4.jar
    jarfiles = []
    jarcmd = which('jar')
    thiscmd = "%s tf %s" % (jarcmd, jarfile)
    (rc, so, se) = run_command(thiscmd)
    jarfiles = so.split('\n')
    jarfiles = [x.strip() for x in jarfiles if x.strip()]
    return jarfiles

def processjar(jarfile):

    classes = {}

    javap = which('javap')

    # list files
    jarfiles = listjarcontents(jarfile)

    for jf in jarfiles:
        if not jf.endswith('.class'):
            continue
        print jf
        thiscmd = javap + ' -classpath ' + jarfile 
        thiscmd += ' ' + jf.replace('.class', '')
        (rc, so, se) = run_command(thiscmd)
        classes[jf] = so
        #import pdb; pdb.set_trace()
    #import pdb; pdb.set_trace()
    return classes

def main():
    print "hello world"
    print sys.argv
    jarA = sys.argv[1]
    classes = processjar(jarA)
    outfile = os.path.basename(jarA)
    outfile = outfile.replace('.jar', '.data')
    with open(outfile, 'wb') as f:
        f.write(json.dumps(classes,indent=2))


if __name__ == "__main__":
    main()
