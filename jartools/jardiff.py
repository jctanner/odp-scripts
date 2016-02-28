#!/usr/bin/env python

import difflib
import json
import os
import sys


def main():
    print sys.argv
    jarA = sys.argv[1]
    jarB = sys.argv[2]

    with open(jarA, 'rb') as f:
        jarAdata = json.loads(f.read())

    with open(jarB, 'rb') as f:
        jarBdata = json.loads(f.read())

    # check the fqns first
    for k in sorted(jarAdata.keys()):
        if k not in jarBdata:
            print "%s does not contain %s" % (jarB, k)
            #pass

    for k in sorted(jarAdata.keys()):
        if k not in jarBdata:
            continue
        #print k
        if jarAdata[k] != jarBdata[k]:
            diff = difflib.unified_diff([x+'\n' for x in jarAdata[k].splitlines()], 
                                        [x+'\n' for x in jarBdata[k].splitlines()])

            lines = []
            for line in diff:
                #sys.stdout.write(line)
                lines.append(line)

            # how many lines start with '-' implying the line was changed
            deletes = 0                
            for line in lines:
                if line.startswith('---'):
                    continue
                if line.startswith('-'):
                    deletes += 1    
            if deletes > 0:
                print "signature of %s differs" % k
                for line in lines:
                    sys.stdout.write(line)                    
            #import pdb; pdb.set_trace()

if __name__ == "__main__":
    main()
