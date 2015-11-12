#!/bin/bash

# https://github.com/apache/bigtop/tree/master/bigtop-test-framework

# "ITEST" is an integration testing framework written for and by the
# apache bigtop project. It consists of typical java tools/libraries
# such as junit, gradle and maven.

# This script is a helper to run itest on any hadoop system without
# requiring intimate knowledge of bigtop. If running for the first
# time, simply execute ./run_itest.sh without any arguments. If you 
# want more information, use these additional parameters:
#
#   --info          - turns on the log4j output
#   --debug         - turns up the log4j output to maximum
#   --traceback     - shows tracebacks from tests

set_hdfs_home() {

    HDFS_HOMEDIR="/user/$(whoami)"

    # Validate it exists ...    
    hadoop fs -test -d $HDFS_HOMEDIR
    RC=$?
    if [ $RC != 0 ];then
        echo "Creating hdfs:/$HDFS_HOMEDIR"
        su -l hdfs -c "hadoop fs -mkdir $HDFS_HOMEDIR"
    fi

    # Validate the owner is you ...
    OWNER=$(hadoop fs -stat "%u" /user/root)
    if [[ "$OWNER" != "$(whoami)" ]]; then
        echo "Chowning hdfs:/$HDFS_HOMEDIR"
        su -l hdfs -c "hadoop fs -chown -R $(whoami) $HDFS_HOMEDIR"
    fi

}

set_java_home() {

    #####################################################################
    # Use bigtop's bigtop-detect-javahome if JAVA_HOME is not already set
    #####################################################################

    REPO_URL="https://github.com/apache/bigtop/blob/master"
    SCRIPT_PATH="bigtop-packages/src/common/bigtop-utils/bigtop-detect-javahome"
    SCRIPT_URL="$REPO_URL/$SCRIPT_PATH"

    if [ -z "$JAVA_HOME" ]; then

        # Get the javahome script if not already available
        if [ ! -f $BIGTOP_HOME/$SCRIPT_PATH ]; then
            if [ ! -f /tmp/bigtop-detect-javahome ]; then
                curl $SCRIPT_URL -o /tmp/bigtop-detect-javahome
            fi
            source /tmp/bigtop-detect-javahome
        else
            source $BIGTOP_HOME/$SCRIPT_PATH
        fi

    fi

    echo "# DEBUG: JAVA_HOME=$JAVA_HOME"
}

set_hadoop_vars() {

    #####################################################################
    # Set the HADOOP_MAPRED_HOME and HADOOP_CONF vars
    #####################################################################

    # ITEST wants the MR dir with the examples jar ...
    # java.lang.AssertionError: Can't find hadoop-examples.jar file

    if ( [ -z "$HADOOP_MAPRED_HOME" ] || [ -z "$HADOOP_CONF_DIR" ] ); then
        # ODP follows an HDP convention ...
        if [ -d /usr/odp/current ]; then
            echo "# DEBUG: ODP DETECTED"
            if ( [ -z "$HADOOP_CONF_DIR" ] && [ -d /etc/hadoop/conf ] ); then
                export HADOOP_CONF_DIR=/etc/hadoop/conf
            fi
            if ( [ -z "$HADOOP_MAPRED_HOME" ] && [ -d /usr/odp/current/hadoop-mapreduce-client ] ); then
                export HADOOP_MAPRED_HOME=/usr/odp/current/hadoop-mapreduce-client
            fi

        # HDP sometimes has client dirs
        elif [ -d /usr/hdp/current ]; then
            echo "# DEBUG: HDP DETECTED"
            if ( [ -z "$HADOOP_CONF_DIR" ] && [ -d /etc/hadoop/conf ] ); then
                export HADOOP_CONF_DIR=/etc/hadoop/conf
            fi
            if ( [ -z "$HADOOP_MAPRED_HOME" ] && [ -d /usr/hdp/current/hadoop-mapreduce-client ] ); then
                export HADOOP_MAPRED_HOME=/usr/hdp/current/hadoop-mapreduce-client
            fi

        # CDH may or may not have been deployed with parcels ...
        elif [ -d /opt/cloudera/parcels/CDH/jars ]; then
            echo "# DEBUG: CDH DETECTED"
            if ( [ -z "$HADOOP_CONF_DIR" ] && [ -d /etc/hadoop/conf ] ); then
                export HADOOP_CONF_DIR=/etc/hadoop/conf
            fi

            if ( [ -z "$HADOOP_MAPRED_HOME" ] ); then
                # This is the only dir that contains the examples jars on cdh5.2.x
                export HADOOP_MAPRED_HOME=/opt/cloudera/parcels/CDH/jars
            fi
          
        fi


    fi

    if ( [ -z "$HADOOP_MAPRED_HOME" ] || [ -z "$HADOOP_CONF_DIR" ] ); then
        echo "# DEBUG: HADOOP_MAPRED_HOME OR HADOOP_CONF not set"

        ###############################
        # Discover non-HDP paths
        ###############################

        # try using "hadoop classpath" output
        MAXMR=0
        for CP in $(hadoop classpath | tr ':' '\n'); do

            # os.path.abspath
            CP=$(readlink -e $CP)

            if [ -z "$HADOOP_CONF_DIR" ]; then
                # HADOOP_CONF_DIR
                if ( [[ "$CP" == */conf* ]] && [[ "$CP" == */hadoop/* ]] ); then
                    
                    if ( [ -d $CP ] && [ -f $CP/core-site.xml ] ); then
                        export HADOOP_CONF_DIR=$CP
                        continue
                    fi
                fi
            fi

            if [ -z "$HADDOOP_MAPRED_HOME" ]; then
                # HADOOP_MAPRED_HOME (use the path with the most jars)
                JARCOUNT=$(ls $CP/hadoop-mapreduce*.jar 2>/dev/null | wc -l)
                if [ $JARCOUNT -gt 0 ]; then
                    if ( [ $JARCOUNT -gt $MAXMR ] ); then
                        export HADOOP_MAPRED_HOME=$CP                
                        MAXMR=$JARCOUNT
                    fi
                fi
            fi

        done

    fi

    echo "# DEBUG: HADOOP_CONF_DIR=$HADOOP_CONF_DIR"
    echo "# DEBUG: HADOOP_MAPRED_HOME=$HADOOP_MAPRED_HOME"

}


print_tests() {

    echo "######################################################"
    echo "#                     RESULTS                        #"
    echo "######################################################"

    for TEST in $(echo $ITESTS | tr ',' '\n'); do

        TESTDIR=$BIGTOP_HOME/bigtop-tests/smoke-tests/$TEST/build

        if [ -d $TESTDIR ]; then

            cd $TESTDIR

            for FILE in $(find -L reports/tests/classes -type f -name "*.html"); do
                echo "## $TESTDIR/$FILE"
                if [ $(which links) ]; then
                    links $FILE -dump
                else
                    echo "PLEASE INSTALL LINKS: sudo yum -y install links"
                fi
                echo ""
            done

        fi
        
    done

}



export ITEST="0.7.0"
export ODP_HOME="/tmp/odp"

# Check the hdfs homedir
set_hdfs_home

# SET BIGTOP_HOME AND GET THE CODE
export BIGTOP_HOME=/tmp/bigtop_home
echo "# DEBUG: BIGTOP_HOME=$BIGTOP_HOME"
if [ ! -d $BIGTOP_HOME ]; then
    echo "# DEBUG: cloning $BIGTOP_HOME from github"
    git clone --depth 1 https://github.com/apache/bigtop -b branch-1.0 $BIGTOP_HOME
else
    echo "# DEBUG: $BIGTOP_HOME already cloned"
fi

# SET JAVA_HOME
set_java_home

# SET HADOOP SERVICE HOMES
set_hadoop_vars

echo "######################################################"
echo "#                 STARTING ITEST                     #"
echo "######################################################"
echo "# Use --debug/--info/--stacktrace for more details"

# SET THE DEFAULT TESTS
if [ -z "$ITESTS" ]; then
    #export ITESTS="odp-example,mapreduce"
    export ITESTS="mapreduce"
fi

# Link the example odp test into the tests dir
if [ ! -L $BIGTOP_HOME/bigtop-tests/smoke-tests/odp-example ]; then
    ln -s $PWD/odp_itest_example $BIGTOP_HOME/bigtop-tests/smoke-tests/odp-example
fi

# CALL THE GRADLE WRAPPER TO RUN THE FRAMEWORK
cd $BIGTOP_HOME/bigtop-tests/smoke-tests/
./gradlew clean test -Dsmoke.tests=$ITESTS $@

# SHOW RESULTS (HTML)
print_tests 
