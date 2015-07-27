#!/bin/bash


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

    # HDP sometimes has client dirs
    if ( [ -z "$HADOOP_MAPRED_HOME" ] || [ -z "$HADOOP_CONF_DIR" ] ); then
        if [ -d /usr/hdp/current ]; then
            echo "# DEBUG: HDP DETECTED"
            if ( [ -z "$HADOOP_CONF_DIR" ] && [ -d /etc/hadoop/conf ] ); then
                export HADOOP_CONF_DIR=/etc/hadoop/conf
            fi
            if ( [ -z "$HADOOP_MAPRED_HOME" ] && [ -d /usr/hdp/current/hadoop-mapreduce-client ] ); then
                export HADOOP_MAPRED_HOME=/usr/hdp/current/hadoop-mapreduce-client
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

            # HADOOP_CONF_DIR
            if ( [[ "$CP" == */conf* ]] && [[ "$CP" == */hadoop/* ]] ); then
                
                if ( [ -d $CP ] && [ -f $CP/core-site.xml ] ); then
                    export HADOOP_CONF_DIR=$CP
                    continue
                fi
            fi

            # HADOOP_MAPRED_HOME (use the path with the most jars)
            JARCOUNT=$(ls $CP/hadoop-mapreduce*.jar 2>/dev/null | wc -l)
            if [ $JARCOUNT -gt 0 ]; then
                if ( [ $JARCOUNT -gt $MAXMR ] ); then
                    export HADOOP_MAPRED_HOME=$CP                
                    MAXMR=$JARCOUNT
                fi
            fi
        done

    fi

    echo "# DEBUG: HADOOP_CONF_DIR=$HADOOP_CONF_DIR"
    echo "# DEBUG: HADOOP_MAPRED_HOME=$HADOOP_MAPRED_HOME"

}


export ITEST="0.7.0"

# SET BIGTOP_HOME AND JAVA_HOME
export BIGTOP_HOME=/tmp/bigtop_home
echo "# DEBUG: BIGTOP_HOME=$BIGTOP_HOME"
if [ ! -d $BIGTOP_HOME ]; then
    echo "# DEBUG: cloning $BIGTOP_HOME from github"
    git clone --depth 1 https://github.com/apache/bigtop $BIGTOP_HOME
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
echo "# Use --debug/--info/--stacktrace for addtional detail"

# EXECUTE TESTS
export TESTS="mapreduce"
cd $BIGTOP_HOME/bigtop-tests/smoke-tests/
./gradlew clean test -Dsmoke.tests=$TESTS $@

# COPY RESULTS
