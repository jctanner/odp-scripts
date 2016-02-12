#!/usr/bin/env python

# command_patcher.py
#   Usage: 
#       python command_patcher.py
#   Purpose:
#       Introspect execution of a bash script and record all variables
#       set or exported. Replace 'exec' calls and recurse into those
#       scripts as well and stop once the exec calls a binary.

import re
import os
import sys
import subprocess
import tempfile
try:
    import yaml
    hasyaml = True
except:
    hasyaml = False

def run_command_live(args, timeout=True):

    #import pdb; pdb.set_trace()
    if timeout:
        args = "timeout -s SIGKILL 30s %s" % args

    p = subprocess.Popen(args,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            shell=True)
    so = ""
    while p.poll() is None:
        lo = p.stdout.readline() # This blocks until it receives a newline.
        sys.stdout.write(lo)
        so += lo
    print p.stdout.read()
    
    return (p.returncode, so, "")    

def run_command(cmd):
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (so, se) = p.communicate()
    return (p.returncode, so, se)    

def which(cmd):

    ''' Get the path for a command '''

    cmd = "which %s" % cmd
    (rc, so, se) = run_command(cmd)
    return so.strip()    

def is_script(filepath):
    ''' Is a file text or is it binary? '''
    # EL6: Bourne-Again shell script text executable
    # EL7: Bourne-Again shell script, ASCII text executable
    # EL7: bin/sparkling-shell: a /usr/bin/env bash script, ASCII text executable
    cmd = "file %s | fgrep -i -e 'shell script' -e 'bash script'" % filepath
    (rc, so, se) = run_command(cmd)
    if rc == 0:
        return True
    else:
        return False

def get_exec_lines_in_file(filepath):

    ''' Find all lines in a bash script that call exec '''

    with open(filepath, 'rb') as f:
        rawtext = f.read()
    indexes = get_exec_lines_in_string(rawtext)
    for idx,x in enumerate(indexes):
        newtup = (filepath, x[1], x[2], x[3])
        indexes[idx] = newtup
    return indexes

def get_exec_lines_in_string(rawtext):

    ''' Find all lines in a string that call exec '''

    indexes = []
    lines = rawtext.split('\n')
    for idx,x in enumerate(lines):
        x = x.replace('+', '')
        x = x.strip()
        if x.startswith('exec ') or ' exec ' in x:
            if not x.strip().startswith('exec '):
                import pdb; pdb.set_trace()

            parts = x.split()
                            
            indexes.append((None, idx, parts[1], " ".join(parts[2:])))

    # spark inspired (no exec at the top level) ...            
    if not indexes:
        # iterate backwards to the first script found
        possible_script = None
        rlines = [x for x in reversed(lines)]
        for idx, x in enumerate(rlines):
            # skip stdout
            xparts = x.split()
            if not xparts:
                continue
            #import pdb; pdb.set_trace()
            #if not x.startswith('+') and not is_script(xparts[0]):
            #    continue
            #import pdb; pdb.set_trace()
            x = x.replace('+', '')
            x = x.strip()
            parts = x.split()
            if is_script(parts[0]):
                print x
                indexes.append((None, idx, parts[0], " ".join(parts[1:])))
                break
            if 'shell' in x:
                import pdb; pdb.set_trace()

        #import pdb; pdb.set_trace()
    return indexes


def parse_bashx(rawtext):

    #(Pdb) m = re.match(r'^[A-Z,_]+.*=', line) ; print m.group()                                           
    #BIGTOP_DEFAULTS_DIR=

    # export HADOOP_LIBEXEC_DIR=///usr/lib/hadoop/libexec

    evars = {}
    evars_order = []
    lines = rawtext.split('\n')
    for line in lines:
        # get rid of the preceding plus symbols indicating level
        line = line.replace('+', '')
        # get rid of the export keyword
        line = line.replace('export ', '', 1)
        line = line.strip()

        if '=' in line and not line.startswith('exec'):
            #print line
            m = re.match(r'^[A-Z,_]+.*=', line)
            if not m:
                m = re.match(r'^[a-z,_]+.*=', line)
                if not m:
                    #print line
                    #import pdb; pdb.set_trace()
                    continue

            varname = line.split('=', 1)[0]
            varname = varname.strip()

            if varname.startswith('exec'):
                import pdb; pdb.set_trace()

            if len(varname.split()) > 1:
                #import pdb; pdb.set_trace()
                continue

            #print "evar:",varname
            if varname not in evars:
                evars[varname] = []

            value = line.replace(varname + '=', '', 1)
            print "value:",value
            evars[varname].append(value)
            #import pdb; pdb.set_trace()
            evars_order.append(varname)

    # dedupe values
    for k,v in evars.iteritems():
        if len(sorted(set(v))) == 1:
            evars[k] = sorted(set(v))
    print evars

    '''
    # substitute known vars
    for k,v in evars.iteritems():
        for idx,x in enumerate(v):
            if '$' in x:
                # (${JAVA7_HOME_CANDIDATES[@]} ${JAVA8_HOME_CANDIDATES[@]} ... )
                print x
                import pdb; pdb.set_trace()                    
    '''
    #import pdb; pdb.set_trace()
    return (evars, evars_order)

def create_debug_script(evars, evars_order, exec_indexes):

    fo,fn = tempfile.mkstemp()

    script = "#!/bin/bash\n"
    for evar in evars_order:
        #print evar
        if not evars[evar][0].startswith('('):
            line = "export %s=%s\n" % (evar, evars[evar][-1])
        else:
            # bash arrays can not be exported, so
            # this one can only be SET.
            line = "%s=%s\n" % (evar, evars[evar][-1])
        script += line

    for eindex in exec_indexes:
        # ('/usr/bin/hadoop', 7, '/usr/lib/hadoop/bin/hadoop', '"$@"')
        # exec /usr/java/jdk1.7.0_67-cloudera/bin/java ...
        if not 'java' in eindex[2]:
            #print eindex
            line = "bash -x %s %s\n" % (eindex[2], eindex[3])
            script += line
        else:
            print eindex
            import pdb; pdb.set_trace()

    with open(fn, 'wb') as f:
        f.write(script)                
    return fn

def store_results(vars, execs, filename='/tmp/patcher_results.yml'):
    ddict = {}
    ddict['vars'] = vars
    ddict['execs'] = execs

    if hasyaml:
        with open(filename, 'wb') as f:
            f.write(yaml.dump(ddict))
    else:    
        import pdb; pdb.set_trace()


def trace_command(cmd, args, vars=None, vars_order=None, orig_cmd=None):

    final_vars = {}
    final_vars_order = []
    final_indexes = []

    # If vars are given, this is not a top level script
    # so skip calling it directly and go straight to
    # mocking out the exec call. This will typically happen
    # during recursion on commands such as hive.
    if not vars:
        # run the command once to get all the debug output
        indexes = get_exec_lines_in_file(cmd)
        tracecmd = "bash -x %s %s" % (cmd, args)
        (rc, so, se) = run_command_live(tracecmd)
        rawtext = str(so) + str(se)
        (evars, evars_order) = parse_bashx(rawtext)
        final_vars_order = evars_order
        try:
            orig_cmd = indexes[-1][2]
        except Exception as e:
            print e
            print indexes
            import pdb; pdb.set_trace()
    else:
        # Recursion ...
        evars = vars
        evars_order = vars_order
        index = (None, None, cmd, args)
        indexes = [index]
        #import pdb; pdb.set_trace()
        
    # Rebuild the underlying command and re-run it
    fn = create_debug_script(evars, evars_order, indexes)
    newcmd = "bash -x %s %s" % (fn, args)
    (rc2, so2, se2) = run_command_live(newcmd)
    rawtext2 = str(so2) + str(se2)
    indexes2 = get_exec_lines_in_string(rawtext2)
    (evars2, evars_order2) = parse_bashx(rawtext2)
    final_vars_order += evars_order2

    # Set original script name in the indexes
    for idx,x in enumerate(indexes2):
        if not x[0]:
            newtup = (orig_cmd, x[1], x[2], x[3])
            indexes2[idx] = newtup

    if len(indexes2) > 1:
        print "found more than one exec"
        import pdb; pdb.set_trace()

    # combine all the vars
    for k,v in evars.iteritems():
        final_vars[k] = v
    for k,v in evars2.iteritems():
        if k not in final_vars:
            final_vars[k] = v
        else:
            final_vars[k] += v
    
    
    # combine all the execs
    final_indexes = indexes + indexes2
    #import pdb; pdb.set_trace()

    # Is further recursion needed?
    if indexes2:
        script = is_script(indexes2[-1][2])
        #if not script:
        #    print "RECURSION NOT REQUIRED!"
        #    print indexes2[-1][2]
        #    import pdb; pdb.set_trace()
        if script:
            #print "RECURSION REQUIRED!"
            #print indexes2[-1][2]
            #import pdb; pdb.set_trace()

            # to recurse, we need to send all the known vars
            (evars3, indexes3) = trace_command(indexes2[-1][2], 
                                               indexes2[-1][3], 
                                               vars=final_vars,
                                               vars_order=final_vars_order,
                                               orig_cmd=indexes2[-1][2])
            print "indexes3:",indexes3
            # Set original script name in the indexes
            for idx,x in enumerate(indexes3):
                if not x[0]:
                    newtup = (indexes2[-1][2], x[1], x[2], x[3])
                    indexes3[idx] = newtup


            final_indexes += indexes3
            for k,v in evars3.iteritems():
                if k not in final_vars:
                    final_vars[k] = v
                else:
                    final_vars[k] += v
         
       
    if is_script(final_indexes[-1][3]):
        print final_indexes
        import pdb; pdb.set_trace()

    #import pdb; pdb.set_trace()
    return (final_vars, final_indexes)


def main():


    #import pdb; pdb.set_trace()
    print sys.argv

    if len(sys.argv) > 1:

        if len(sys.argv) > 2:
            (vars, execs) = trace_command(sys.argv[1], ' '.join(sys.argv[1:]))
        else:
            (vars, execs) = trace_command(sys.argv[1], ' ')
        store_results(vars, execs, filename='/tmp/patcher_results-testcommand.yml')


    else:
        hadoop = which('hadoop')
        (vars, execs) = trace_command(hadoop, 'fs -ls /')
        store_results(vars, execs, filename='/tmp/patcher_results-hadoop.yml')

        mapred = which('mapred')
        (vars, execs) = trace_command(mapred, 'job -list all')
        store_results(vars, execs, filename='/tmp/patcher_results-mapred.yml')

        yarn = which('yarn')
        (vars, execs) = trace_command(yarn, 'application -list')
        store_results(vars, execs, filename='/tmp/patcher_results-yarn.yml')

        hive = which('hive')
        (vars, execs) = trace_command(hive, '-e "show tables"')
        store_results(vars, execs, filename='/tmp/patcher_results-hive.yml')

        beeline = which('beeline')
        (vars, execs) = trace_command(beeline, '-u jdbc:hive2://localhost:10000 -u hive -p hive -e "show tables"')
        store_results(vars, execs, filename='/tmp/patcher_results-beeline.yml')

        spark = which('spark-shell')
        (vars, execs) = trace_command(spark, '--help')
        store_results(vars, execs, filename='/tmp/patcher_results-spark.yml')
          
    #import pdb; pdb.set_trace()


if __name__ == "__main__":
    main()
