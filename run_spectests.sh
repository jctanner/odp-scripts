#!/bin/bash
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

install_java_tools() {
    CWD=$(pwd)

    echo "# DEBUG: checking links install"
    rpm -q elinks > /dev/null 2>&1 || sudo yum -y install elinks

    echo "# DEBUG: checking groovy install"
    rpm -q bigtop-groovy > /dev/null 2>&1 || sudo yum -y install bigtop-groovy

    echo "# DEBUG: checking unzip install"
    rpm -q unzip > /dev/null 2>&1 || sudo yum -y install unzip

    echo "# DEBUG: checking gradle install"
    which gradle > /dev/null 2>&1
    RC=$?
    if [[ $RC != 0 ]]; then
        GVERSION=2.11
        if [ ! -f gradle-$GVERSION-bin.zip ]; then
            curl -L -o gradle-$GVERSION-bin.zip https://services.gradle.org/distributions/gradle-$GVERSION-bin.zip
        fi 
        cd /opt
        sudo rm -rf /opt/gradle-*
        sudo unzip -e $CWD/gradle-$GVERSION-bin.zip
        sudo ln -s /opt/gradle-$GVERSION/bin/gradle /usr/bin/gradle
    fi
}    

locate_bigtop_detect_javahome() {

    #####################################################################
    # Iterate through possible locations for the detection script
    #####################################################################

    scriptpath=""
    scriptname="bigtop-detect-javahome"

    # iterate and preferring the checkout dir
    locations="$BIGTOP_HOME/bigtop-packages/src/common/bigtop-utils"
    locations="$locations ../../bigtop-packages/src/common/bigtop-utils"
    locations="$locations bigtop-packages/src/common/bigtop-utils"
    locations="$locations bin"
    locations="$locations /usr/lib/bigtop-utils"
    for location in $locations; do
        if [ -f $location/$scriptname ]; then
            scriptpath=$location/$scriptname
        fi
    done
    echo $scriptpath
}

set_java_home() {

    #####################################################################
    # Use bigtop's bigtop-detect-javahome if JAVA_HOME is not already set
    #####################################################################

    if [ -z "$JAVA_HOME" ]; then
        scriptpath=$(locate_bigtop_detect_javahome)
        if [ -z $scriptpath ]; then
            echo "ERROR: bigtop_detect_javahome was not found"
        fi
        echo "# DEBUG: sourcing $scriptpath"
        source $scriptpath
    fi

    echo "# DEBUG: JAVA_HOME=$JAVA_HOME"
}

get_and_set_envvars() {

    #####################################################################
    # Use the new envvars subcommand if available
    #####################################################################

    hadoop envvars > /dev/null 2>&1
    RC=$?
    if [[ $RC == 0 ]]; then
        echo "# DEBUG: using envvars subcommand to find vars"
        hadoop envvars > /tmp/vars.sh
        yarn envvars >> /tmp/vars.sh
        mapred envvars >> /tmp/vars.sh

        # sort and fix
        cat /tmp/vars.sh | sed "s/=\//=\'\//g" | sort -u > /tmp/vars_fix.sh

        # make the export commands
        echo "" > /tmp/vars_export.sh
        for line in $(cat /tmp/vars_fix.sh); do
            echo "# DEBUG: $line"
            echo "export $line" >> /tmp/vars_export.sh
        done
        
        source /tmp/vars_export.sh
    fi
}    

set_hadoop_vars() {

    #####################################################################
    # Set the HADOOP_MAPRED_HOME and HADOOP_CONF vars
    #####################################################################

    # ITEST wants the MR dir with the examples jar ...
    # java.lang.AssertionError: Can't find hadoop-examples.jar file

    get_and_set_envvars

    if ( [ -z "$HADOOP_HOME" ] && [ -d /usr/lib/hadoop ] ); then
      export HADOOP_HOME=/usr/lib/hadoop
    fi
    if ( [ -z "$HADOOP_CONF_DIR" ] && [ -d /etc/hadoop/conf ] ); then
      export HADOOP_CONF_DIR=/etc/hadoop/conf
    fi
    if ( [ -z "$HADOOP_MAPRED_HOME" ] && [ -d /usr/lib/hadoop-mapreduce-client ] ); then
      export HADOOP_MAPRED_HOME=/usr/lib/hadoop-mapreduce-client
    fi
    if ( [ -z "$HADOOP_MAPRED_HOME" ] && [ -d /usr/lib/hadoop-mapreduce ] ); then
      export HADOOP_MAPRED_HOME=/usr/lib/hadoop-mapreduce
    fi

    echo "# DEBUG: HADOOP_CONF_DIR=$HADOOP_CONF_DIR"
    echo "# DEBUG: HADOOP_MAPRED_HOME=$HADOOP_MAPRED_HOME"
}


print_tests() {
  echo "######################################################"
  echo "#                     RESULTS                        #"
  echo "######################################################"


  for FILE in $(find -L . -type f -name "*.html"); do
    echo "## $TESTDIR/$FILE"
    if [ $(which links) ]; then
        links $FILE -dump | egrep -e '\ testAll\[' | egrep -e 'passed' -e 'failed'
    else
        echo "PLEASE INSTALL LINKS: sudo yum -y install links"
    fi
    echo ""
  done
}


## MAKE SURE THE USER TELLS US WHERE THE CORRECT CHECKOUT DIR IS ...
if [ -z $1 ]; then
    echo "Please define the path to the bigtop checkout as the first argument"
    exit 1
fi    
export BIGTOP_HOME=$1

echo "######################################################"
echo "#              CHECKING PREREQS                      #"
echo "######################################################"
# install groovy and gradle
install_java_tools


echo "######################################################"
echo "#             SETTING ENVIRONMENT                    #"
echo "######################################################"

# SET HADOOP SERVICE HOMES
set_hadoop_vars

# SET JAVA_HOME
set_java_home

echo "## ENV ..."
for VAR in $(env | fgrep -e HOME -e DIR -e HADOOP -e YARN -e MAPRED); do
    echo "# DEBUG: $VAR"
done    

echo "######################################################"
echo "#             STARTING SPEC TESTS                    #"
echo "######################################################"
echo "# Use --debug/--info/--stacktrace for more details"

# SET THE DEFAULT TESTS
if [ -z "$ITESTS" ]; then
  export ITESTS="hcfs,hdfs,yarn,mapreduce"
fi
for s in `echo $ITESTS | sed -e 's#,# #g'`; do
  ALL_SMOKE_TASKS="$ALL_SMOKE_TASKS bigtop-tests:smoke-tests:$s:test"
done

cd $BIGTOP_HOME

# CALL THE GRADLE WRAPPER TO RUN THE FRAMEWORK
#./gradlew -q clean test -Psmoke.tests $ALL_SMOKE_TASKS --info
cd bigtop-tests/spec-tests
echo "# DEBUG PWD: $(pwd)"
#gradle tasks
gradle test

# SHOW RESULTS (HTML)
print_tests
