#!/bin/bash 
#
# Install TeraSort 
#

#
# 1. Assuming JAVA  jdk1.8.0_112 already installed (TBD: how to handle later releases at a later date)
# 2. Install MAVEN. Needed to build Terasort. (Instructions:  https://maven.apache.org/install.html)
# 3. Buile Terasort from: https://github.com/ehiggs/spark-terasort.git 
# 4. Create Directories for generated files. 
# 5. Copy the JAR file to location accessible by TBD 

DATA_HOME_DIR=/
JAR_PATH=$DATA_HOME_DIR/data

# Handle dependencies 
mkdir -p /root/SPARK/
cd /root/SPARK/
wget http://apache.spd.co.il/maven/maven-3/3.5.2/binaries/apache-maven-3.5.2-bin.tar.gz
tar xvfz apache-maven-3.5.2-bin.tar.gz
export PATH=$PATH:`pwd`/apache-maven-3.5.2/bin
export JAVA_HOME=/usr/jdk64/jdk1.8.0_112


# Build spark-terasort
yum install git -y
git clone https://github.com/ehiggs/spark-terasort.git
cd /root/SPARK/spark-terasort
mvn install 

mkdir -p $DATA_HOME_DIR/data
chmod 777 $DATA_HOME_DIR/data
cp -p /root/SPARK/spark-terasort/target/spark-terasort-1.1-SNAPSHOT-jar-with-dependencies.jar $JAR_PATH


#### Test that all is running 

# set the sort size for the test 
sortsize=1

# Flags for spark-submit
FLAGS="--master yarn --deploy-mode cluster --num-executors 2 --executor-cores 2"
spark_client_path=/usr/hdp/current/spark-client/

# Delete remains of previous runs
rm -rf $DATA_HOME_DIR/data/terasort_*
#free -g && sync && echo 3 > /proc/sys/vm/drop_caches && free -g 

# Generate sample files to sort of $sortsize GiB at $DATAHOME/data/terasort_in_${sortsize}g 
time sudo -u hdfs $spark_client_path/bin/spark-submit $FLAGS --class com.github.ehiggs.spark.terasort.TeraGen $JAR_PATH/spark-terasort-1.1-SNAPSHOT-jar-with-dependencies.jar ${sortsize}g file://$DATA_HOME_DIR/data/terasort_in_${sortsize}g
# Sort 
time sudo -u hdfs $spark_client_path/bin/spark-submit $FLAGS --class com.github.ehiggs.spark.terasort.TeraSort $JAR_PATH/spark-terasort-1.1-SNAPSHOT-jar-with-dependencies.jar file://$DATA_HOME_DIR/data/terasort_in_${sortsize}g file://$DATA_HOME_DIR/data/terasort_out
# Verify the sort
time $spark_client_path/bin/spark-submit --class com.github.ehiggs.spark.terasort.TeraValidate  $JAR_PATH/spark-terasort-1.1-SNAPSHOT-jar-with-dependencies.jar file://$DATA_HOME_DIR/data/terasort_out file://$DATA_HOME_DIR/data/terasort_validate
#time $spark_client_path/bin/spark-submit $FLAGS --class com.github.ehiggs.spark.terasort.TeraValidate  $JAR_PATH/spark-terasort-1.1-SNAPSHOT-jar-with-dependencies.jar file://$DATA_HOME_DIR/data/terasort_out file://$DATA_HOME_DIR/data/terasort_validate


