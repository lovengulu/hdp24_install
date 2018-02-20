#!/usr/bin/bash 

# The Initial setup is described here: https://docs.hortonworks.com/HDPDocuments/Ambari-2.4.3.0/bk_ambari-installation/content/ch_Getting_Ready.html
# TODO: UPDATE THIS LINK: 
# The install procedure is described here: https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.6.4/bk_command-line-installation/bk_command-line-installation.pdf


fqdn_hostname=`hostname -f`

function setup_password_less_ssh { 
	if [ ! -f /root/.ssh/id_rsa ]; then
		cat /dev/zero | ssh-keygen -q -N ""
	fi

	cd /root/.ssh
	cat id_rsa.pub >> authorized_keys
	chmod 700 ~/.ssh
	chmod 600 ~/.ssh/authorized_keys
	
	echo "######  ...... INSTRUCTIONS ......  >>>>>>>"
	echo "Testing that setup password-less ssh done correctly"
	echo "please reply 'yes' if asked: Are you sure you want to continue connecting (yes/no)? "
	echo "If you are asked to enter a password, it means that something went wrong while setting up. Please resolve manually."
	echo "###### ^^^^^^ INSTRUCTIONS ^^^^^^^  <<<<<<<"
	echo
	reply=`ssh -o StrictHostKeyChecking=no $fqdn_hostname date`
	if [ -z "$reply" ]; then
		echo 'Error in ssh-keygen process. Please confirm manually and run the script again'
		echo 'Exiting ... '
		exit
	fi
    cd -
}


function prepare_the_environment {
	
	yum install -y ntp
	systemctl is-enabled ntpd
	systemctl enable ntpd
	systemctl start ntpd	
	
	systemctl disable firewalld
	service firewalld stop
	
	# Disable SELinux (Security Enhanced Linux).
	setenforce 0

	# Turn off iptables. 
	iptables -L		; # but first check its status 
	iptables -F
	
	# TODO - Disable PackageKit 
	# Not clear - 
	# I found that PackageKit is running (using:  service packagekit status) and stopped it (using: service packagekit stop ) 
	# However, There is no file /etc/yum/pluginconf.d/refresh-packagekit.conf
	# Need to review once again. 
	service packagekit status
	service packagekit stop
	
	umask 0022

	# set ulimit
	ulimit_sn=`ulimit -Sn`
	ulimit_hn=`ulimit -Hn`
	
	if [ "$ulimit_sn" -lt 10000 -a "$ulimit_hn" -lt 10000 ] 
	then
		echo "Setting: ulimit -n 10000"
		ulimit -n 10000
	fi
	
}


function ambari_install {
	echo "INFO: ambari_install: "
	echo "This section downloads the required packages to run ambari-server."
	
	#Attempt to install HDP 2.4 with Ambari 2.4 fails. Using 2.6 instead
	#wget -nv http://public-repo-1.hortonworks.com/ambari/centos7/2.x/updates/2.4.3.0/ambari.repo -O /etc/yum.repos.d/ambari.repo
	wget -nv http://public-repo-1.hortonworks.com/ambari/centos7/2.x/updates/2.6.1.0/ambari.repo -O /etc/yum.repos.d/ambari.repo
	yum repolist
	
	yum install -y ambari-server 
	
}

function setup_mysql {
	#wget http://repo.mysql.com/mysql-community-release-el7-5.noarch.rpm
	#rpm -ivh mysql-community-release-el7-5.noarch.rpm
	yum update -y 

	yum install mysql-server -y 
	# Be aware that the server binds to localhost. good enough for this test. 
	systemctl start mysqld
	
	# Download connector page: https://dev.mysql.com/downloads/connector/j/
	wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.45.tar.gz -O /tmp/mysql-connector-java-5.1.45.tar.gz
	# TBD: confirm this is the proper place for it:
	cd /usr/lib
	tar xvfz /tmp/mysql-connector-java-5.1.45.tar.gz
	ln -s /usr/lib/mysql-connector-java-5.1.45/mysql-connector-java-5.1.45-bin.jar /usr/share/java/mysql-connector-java.jar
	cd - 
	
}


function ambari_server_config_and_start {
	echo "INFO: ambari_config_start:"
	echo "Please accept all defaults proposed while in the following steps configuring the server. "
	echo "If required, Detailed explanation and instructions for configuring ambari-server at:" 
	echo "https://docs.hortonworks.com/HDPDocuments/Ambari-2.6.1.0/bk_ambari-installation/content/set_up_the_ambari_server.html "
	
	# setup with the MySql connector installed previously
	# TODO: running "ambari-server setup ..." with the options below doesn't install Java and the other required things. Need to find out how to run the install once. 
	# TODO: Need to findout if I can use the flag "-s" for silent install !!!!!
	ambari-server setup -s 
	#ambari-server setup --jdbc-db=mysql --jdbc-driver=/usr/lib/mysql-connector-java-5.1.45/mysql-connector-java-5.1.45-bin.jar
	ambari-server setup --jdbc-db=mysql --jdbc-driver=/usr/share/java/mysql-connector-java.jar
	ambari-server start
} 

function ambari_agent_config_and_start {
	yum install ambari-agent -y 
	# in a single-node cluster, it is not mandatory
	sed /etc/ambari-agent/conf/ambari-agent.ini -i.ORIG -e "s/hostname=localhost/hostname=${fqdn_hostname}/"
	ambari-agent start   
}

function download_helper_files {
	wget http://public-repo-1.hortonworks.com/HDP/tools/2.4.3.0/hdp_manual_install_rpm_helper_files-2.4.3.0.227.tar.gz
	tar zxvf hdp_manual_install_rpm_helper_files-2.4.3.0.227.tar.gz
	PATH_HDP_MANUAL_INSTALL_RPM_HELPER_FILES=`pwd`/hdp_manual_install_rpm_helper_files-2.4.3.0.227
}



function set_hadoop_config {

	used_ram_gb=10
	container_ram=2024

	used_ram_mb="$((used_ram_gb * 1024))"
	used_ram_mb_div_10="$((used_ram_mb / 10))"
	
	# TODO: 
	# Not using the version as in the default: 
	#	"yarn.app.mapreduce.am.command-opts" : "-Xmx ...  -Dhdp.version=${hdp.version}",
	# Omitted:
	#   "mapreduce.task.io.sort.mb" 
	
# yarn.scheduler.minimum-allocation-mb=6144	  	: "$container_ram"			
# yarn.scheduler.maximum-allocation-mb=49152		: "$used_ram_mb"
# yarn.nodemanager.resource.memory-mb=49152		: "$used_ram_mb"
# mapreduce.map.memory.mb=6144					: "$container_ram"
# mapreduce.map.java.opts=-Xmx4915m				: "$used_ram_mb_div_10"
# mapreduce.reduce.memory.mb=6144				: "$container_ram"
# mapreduce.reduce.java.opts=-Xmx4915m			: "$used_ram_mb_div_10"
# yarn.app.mapreduce.am.resource.mb=6144			: "$container_ram"
# yarn.app.mapreduce.am.command-opts=-Xmx4915m	: "$used_ram_mb_div_10"
# mapreduce.task.io.sort.mb=2457
 
	
	

read -r -d '' YARN_SITE <<EOF
    {
      "yarn-site" : {
        "properties_attributes" : { },
        "properties" : {
		  "yarn.scheduler.minimum-allocation-mb" : "$container_ram",
		  "yarn.scheduler.maximum-allocation-mb" : "$used_ram_mb",
          "yarn.nodemanager.resource.memory-mb" : "$used_ram_mb"
        }
      }
    }
EOF

# There's another config, so add separator 
YARN_SITE=$YARN_SITE,

read -r -d '' MAPRED_SITE <<EOF
    {
      "mapred-site" : {
        "properties_attributes" : { },
        "properties" : {
			"mapreduce.map.memory.mb" :  "$container_ram",
			"mapreduce.map.java.opts" :  "-Xmx${used_ram_mb_div_10}m",
			"mapreduce.reduce.memory.mb" :  "$container_ram",
			"mapreduce.reduce.java.opts" :  "-Xmx${used_ram_mb_div_10}m",  
			"yarn.app.mapreduce.am.resource.mb" :  "$container_ram",
			"yarn.app.mapreduce.am.command-opts" :  "-Xmx${used_ram_mb_div_10}m"
        }
      }
    }
EOF

}  #########  end of function     set_hadoop_config  ################



function write_single_custer_blueprint_json {
# This function expect 3 parameters: blueprint_name, 

blueprint_name=${1:=single-node-hdp-cluster}
cluster_name=${2:=host_group_1}
fqdn_hostname=${3:=localhost}


echo "####################################################################"
echo DEBUG:  "$YARN_SITE" 	"$MAPRED_SITE"
echo "####################################################################"

# Create JSONs
cat <<EOF > hostmapping.json
{
  "blueprint" : "${blueprint_name}",
  "default_password" : "admin",
  "host_groups" :[
    {
      "name" : "${cluster_name}",
      "hosts" : [
        {
          "fqdn" : "${fqdn_hostname}"
        }
      ]
    }
  ]
}
EOF


cat <<EOF > cluster_configuration.json
{   "configurations" : [ 
	$YARN_SITE
	$MAPRED_SITE
	], 
	"host_groups" : [ { "name" : "${cluster_name}", "components" : [ 
        { "name" : "NODEMANAGER"},
        { "name" : "HIVE_SERVER"},
        { "name" : "METRICS_MONITOR"},
        { "name" : "HIVE_METASTORE"},
        { "name" : "TEZ_CLIENT"},
        { "name" : "ZOOKEEPER_CLIENT"},
        { "name" : "HCAT"},
        { "name" : "WEBHCAT_SERVER"},
        { "name" : "SECONDARY_NAMENODE"},
        { "name" : "ZOOKEEPER_SERVER"},
        { "name" : "METRICS_COLLECTOR"},
        { "name" : "SPARK_CLIENT"},
        { "name" : "YARN_CLIENT"},
        { "name" : "HDFS_CLIENT"},
        { "name" : "MYSQL_SERVER"},
        { "name" : "HISTORYSERVER"},
        { "name" : "NAMENODE"},
        { "name" : "PIG"},
        { "name" : "MAPREDUCE2_CLIENT"},
        { "name" : "AMBARI_SERVER"},
        { "name" : "DATANODE"},
        { "name" : "SPARK_JOBHISTORYSERVER"},
        { "name" : "APP_TIMELINE_SERVER"},
        { "name" : "HIVE_CLIENT"},
        { "name" : "RESOURCEMANAGER"}
      ],		
      "cardinality" : "1"
    }
  ],
  "Blueprints" : {
    "blueprint_name" : "${blueprint_name}",
    "stack_name" : "HDP",
    "stack_version" : "2.4"
  }
}
EOF

}   ###### end of: write_single_custer_blueprint_json   ##################################################


function blueprint_install {

# PUT /api/v1/stacks/:stack/versions/:stackVersion/operating_systems/:osType/repositories/:repoId
STACK="HDP"
STACK_VERSION="2.4"
OS_TYPE="redhat7"
REPO_ID="HDP-2.4"
BASE_URL_HDP=http://public-repo-1.hortonworks.com/HDP/centos7/2.x/updates/2.4.3.0"
BASE_URL_UTILS=http://public-repo-1.hortonworks.com/HDP-UTILS-1.1.0.20/repos/centos7"
 
hdp_json={ \"Repositories\":{ \"base_url\":\"${BASE_URL_HDP}\", \"verify_base_url\":true } }
 
}

#	"repo_name": "HDP-2.4.3.0",   
#HDP Version - HDP-2.4.3.0

function write_repo_json {
	
cat <<EOF > repo.json
{  
   "Repositories":{
   "repo_name": "HDP-2.4.3.0",   
      "base_url":"http://public-repo-1.hortonworks.com/HDP/centos7/2.x/updates/2.4.3.0",
      "verify_base_url":true
   }
}
EOF

cat <<EOF > utils.json
{
  "Repositories": {
  "repo_name": "HDP-UTILS",
    "base_url": "http://public-repo-1.hortonworks.com/HDP-UTILS-1.1.0.20/repos/centos7",
    "verify_base_url": true
  }
}
EOF

}
	

##########################################

setup_password_less_ssh 
prepare_the_environment 
ambari_install 
setup_mysql
ambari_server_config_and_start 
ambari_agent_config_and_start

#download_helper_files



date

fqdn_hostname=`hostname -f`
blueprint_name=single-node-hdp-cluster
cluster_name=host_group_1
set_hadoop_config
write_single_custer_blueprint_json $blueprint_name $cluster_name $fqdn_hostname 
write_repo_json

wget -nv http://public-repo-1.hortonworks.com/HDP/centos7/2.x/updates/2.4.3.0/hdp.repo -O /etc/yum.repos.d/hdp.repo


curl -H "X-Requested-By: ambari" -X PUT -u admin:admin http://localhost:8080/api/v1/stacks/HDP/versions/2.4.3/operating_systems/redhat7/repositories/HDP-2.4.3 -d @repo.json
curl -H "X-Requested-By: ambari" -X PUT -u admin:admin http://localhost:8080/api/v1/stacks/HDP/versions/2.4.3/operating_systems/redhat7/repositories/HDP-UTILS-1.1.0.20 -d @utils.json

#blueprint_install

curl -H "X-Requested-By: ambari" -X POST -u admin:admin http://localhost:8080/api/v1/blueprints/${blueprint_name} -d @cluster_configuration.json
curl -H "X-Requested-By: ambari" -X POST -u admin:admin http://localhost:8080/api/v1/clusters/${cluster_name} -d @hostmapping.json



# and now let's check what is happing ... 

curl -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8080/api/v1/clusters/${cluster_name}/requests/
date

#curl -H "X-Requested-By: ambari" -X DELETE -u admin:admin http://localhost:8080/api/v1/clusters/${cluster_name}
#curl -H "X-Requested-By: ambari" -X DELETE -u admin:admin http://localhost:8080/api/v1/blueprints/${blueprint_name}
exit





##########################################

function fetch_hdp_manual_install_rpm_helper_files {
	cd /tmp
	wget http://public-repo-1.hortonworks.com/HDP/tools/2.6.0.3/hdp_manual_install_rpm_helper_files-2.6.0.3.8.tar.gz
	tar zxvf hdp_manual_install_rpm_helper_files-2.6.0.3.8.tar.gz
	
	PATH_HDP_MANUAL_INSTALL_RPM_HELPER_FILES=/tmp/hdp_manual_install_rpm_helper_files-2.6.0.3.8
	
}


function users_and_groups() { 
	# Comments: 
	#	1. users created below with hardcoded values - TODO use the variables properly - low priority 
	#	2. missing users from this procedure: pig
	#	3. Seems that there are some users that are not really needed for the purpose of this one node cluster. TODO: review again - low priority

	cd $PATH_HDP_MANUAL_INSTALL_RPM_HELPER_FILES
	
	.  scripts/usersAndGroups.sh
	
	# Create the required groups 

	groupadd  $HADOOP_GROUP
	groupadd  mapred
	groupadd  nagios

	useradd -G $HADOOP_GROUP			$HDFS_USER
	useradd -G $HADOOP_GROUP			$YARN_USER

	# The install doc  lists mapred differently.  
	# TODO: review in low priority - the way written in the install doc does not work properly. this fix seems to work fine.
	useradd -G $HADOOP_GROUP 			$MAPRED_USER
	useradd -G $HADOOP_GROUP			$HIVE_USER
	useradd -G $HADOOP_GROUP			$WEBHCAT_USER
	useradd -G $HADOOP_GROUP			$HBASE_USER
	# TODO: Need to find out if I need the following users that created without using variable  
	useradd -G $HADOOP_GROUP			falcon
	useradd -G $HADOOP_GROUP			sqoop
	useradd -G $HADOOP_GROUP			$ZOOKEEPER_USER
	useradd -G $HADOOP_GROUP			$OOZIE_USER
	useradd -G $HADOOP_GROUP			knox
	useradd -G nagios			nagios
}


# Not sure what is the diff between the two instructions set. Need to review once again. 

# https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.6.4/bk_command-line-installation/content/ch_getting_ready_chapter.html
# https://cwiki.apache.org/confluence/display/AMBARI/Installation+Guide+for+Ambari+2.6.1

function set_environment() {
	# This page describes the environment variables that need to be set: 
	# https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.6.4/bk_command-line-installation/content/def-environment-parameters.html

	cd $PATH_HDP_MANUAL_INSTALL_RPM_HELPER_FILES/scripts
	
	
	sed directories.sh -i.ORIG 	-e "s=TODO-LIST-OF-NAMENODE-DIRS=/hadoop/hdfs/namenode=
					    s=TODO-LIST-OF-DATA-DIRS=/hadoop/hdfs/data=
					    s=TODO-LIST-OF-SECONDARY-NAMENODE-DIRS=/hadoop/hdfs/namesecondary=
					    s=TODO-LIST-OF-YARN-LOCAL-DIRS=/hadoop/yarn/local=	
					    s=TODO-LIST-OF-YARN-LOCAL-LOG-DIRS=/hadoop/yarn/log=
					    s=TODO-ZOOKEEPER-DATA-DIR=/hadoop/zookeeper="

# TODO - local backup. Be sure to remove from final version
#	sed directories.sh -i.ORIG 	-e "s/TODO-LIST-OF-NAMENODE-DIRS/\/hadoop\/hdfs\/namenode/
#									s/TODO-LIST-OF-DATA-DIRS/\/hadoop\/hdfs\/data/
#									s/TODO-LIST-OF-SECONDARY-NAMENODE-DIRS/\/hadoop\/hdfs\/namesecondary/
#									s/TODO-LIST-OF-YARN-LOCAL-DIRS/\/hadoop\/yarn\/local/	
#									s/TODO-LIST-OF-YARN-LOCAL-LOG-DIRS/\/hadoop\/yarn\/log/
#									s/TODO-ZOOKEEPER-DATA-DIR/\/hadoop\/zookeeper/   "
#

	. directories.sh
	
}



function install_haddop_core {
	cd
	umask 0022
	wget -nv http://public-repo-1.hortonworks.com/HDP/centos7/2.x/updates/2.6.3.0/hdp.repo -O /etc/yum.repos.d/hdp.repo
	yum repolist
	
	yum install -y hadoop hadoop-hdfs hadoop-libhdfs hadoop-yarn hadoop-mapreduce hadoop-client openssl
	yum install -y snappy snappy-devel
	yum install -y lzo lzo-devel hadooplzo hadooplzo-native

	# Create the NameNode Directories
	mkdir -p $DFS_NAME_DIR;
	chown -R $HDFS_USER:$HADOOP_GROUP $DFS_NAME_DIR;
	chmod -R 755 $DFS_NAME_DIR;
	

	# Create the SecondaryNameNode Directories 
	# TODO: Not sure this is required - low priority

	mkdir -p $FS_CHECKPOINT_DIR;
	chown -R $HDFS_USER:$HADOOP_GROUP $FS_CHECKPOINT_DIR; 
	chmod -R 755 $FS_CHECKPOINT_DIR;	

	# Create DataNode and YARN NodeManager Local Directories
	mkdir -p $DFS_DATA_DIR;
	chown -R $HDFS_USER:$HADOOP_GROUP $DFS_DATA_DIR;
	chmod -R 750 $DFS_DATA_DIR;

	mkdir -p $YARN_LOCAL_DIR;
	chown -R $YARN_USER:$HADOOP_GROUP $YARN_LOCAL_DIR;
	chmod -R 755 $YARN_LOCAL_DIR;

	mkdir -p $YARN_LOCAL_LOG_DIR;
	chown -R $YARN_USER:$HADOOP_GROUP $YARN_LOCAL_LOG_DIR; 
	chmod -R 755 $YARN_LOCAL_LOG_DIR;

	# Create the Log and PID Directories
	mkdir -p $HDFS_LOG_DIR;
	chown -R $HDFS_USER:$HADOOP_GROUP $HDFS_LOG_DIR;
	chmod -R 755 $HDFS_LOG_DIR;

	mkdir -p $YARN_LOG_DIR; 
	chown -R $YARN_USER:$HADOOP_GROUP $YARN_LOG_DIR;
	chmod -R 755 $YARN_LOG_DIR;

	mkdir -p $HDFS_PID_DIR;
	chown -R $HDFS_USER:$HADOOP_GROUP $HDFS_PID_DIR;
	chmod -R 755 $HDFS_PID_DIR;

	mkdir -p $YARN_PID_DIR;
	chown -R $YARN_USER:$HADOOP_GROUP $YARN_PID_DIR;
	chmod -R 755 $YARN_PID_DIR;

	mkdir -p $MAPRED_LOG_DIR;
	chown -R $MAPRED_USER:$HADOOP_GROUP $MAPRED_LOG_DIR;
	chmod -R 755 $MAPRED_LOG_DIR;

	mkdir -p $MAPRED_PID_DIR;
	chown -R $MAPRED_USER:$HADOOP_GROUP $MAPRED_PID_DIR;
	chmod -R 755 $MAPRED_PID_DIR;


	#TODO: Pg 46:  using hdp-select failed. think that is not important in this context. 
	
}


function setup_hadoop_config {
	# This function revises the config template files. The original template file is saved with the suffix ".ORIG_HELPER".
	# The changes are according to Section 4 of the manual (Setting Up the Hadoop Configuration, pp. 48 - 53)

	# TODO: Test that nothing is left as "TODO". 
	
	
	cd $PATH_HDP_MANUAL_INSTALL_RPM_HELPER_FILES/configuration_files/core_hadoop
	
	sed core-site.xml -i.ORIG -e s/TODO-NAMENODE-HOSTNAME:PORT/${fqdn_hostname}:8020/ 
	 
	# Secondary Namenode is NOT a backup. The following blog describes its function: http://blog.madhukaraphatak.com/secondary-namenode---what-it-really-do/ 

	sed hdfs-site.xml  -i.ORIG_HELPER    -e  "s=TODO-DFS-DATA-DIR=file:///${DFS_DATA_DIR}=               ;
						  s=TODO-NAMENODE-HOSTNAME:50070=${fqdn_hostname}:50070=      ;
						  s=TODO-DFS-NAME-DIR=${DFS_NAME_DIR}=			;		
						  s=TODO-FS-CHECKPOINT-DIR=${FS_CHECKPOINT_DIR}=              ; 
						  s=TODO-SECONDARYNAMENODE-HOSTNAME:50090=${fqdn_hostname}:50090="
	
	sed yarn-site.xml -i.ORIG_HELPER -e "s=TODO-YARN-LOCAL-DIR=$YARN_LOCAL_DIR=                   ;
	                              	     s/TODO-RMNODE-HOSTNAME:19888/${fqdn_hostname}:19888/     ;
	                              	     s/TODO-RMNODE-HOSTNAME:8141/${fqdn_hostname}:8141/	      ;
	                                     s=TODO-YARN-LOCAL-LOG-DIR=$YARN_LOCAL_LOG_DIR=           ;
	                                     s/TODO-RMNODE-HOSTNAME:8025/${fqdn_hostname}:8025/	      ;
	                                     s/TODO-RMNODE-HOSTNAME:8088/${fqdn_hostname}:8088/	      ;								
	                                     s/TODO-RMNODE-HOSTNAME:8050/${fqdn_hostname}:8050/	      ;
	                                     s/TODO-RMNODE-HOSTNAME:8030/${fqdn_hostname}:8030/       "
							
	# TODO: Don't know what to do with this comment (Page 49):
	# The maximum value of the NameNode new generation size (- XX:MaxnewSize ) should be 1/8 of the maximum heap size (-Xmx). 
	# Ensure that you check the default setting for your environment.


	sed mapred-site.xml -i.ORIG_HELPER -e "s/TODO-JOBHISTORYNODE-HOSTNAME:10020/${fqdn_hostname}:10020/
	                                s/TODO-JOBHISTORYNODE-HOSTNAME:19888/${fqdn_hostname}:19888/	"


	touch $HADOOP_CONF_DIR/dfs.exclude
	JAVA_HOME=/usr/java/default
	
	echo "### Settings for Haddop " >> /etc/profile
	echo "export JAVA_HOME=$JAVA_HOME"  >> /etc/profile
	echo "export HADOOP_CONF_DIR=$HADOOP_CONF_DIR" 	>> /etc/profile
	echo "export PATH=\$PATH:\$JAVA_HOME:\$HADOOP_CONF_DIR	" 	>> /etc/profile
	echo "###" 	>> /etc/profile
	
	# skipped optional step: Optional: Configure MapReduce to use Snappy Compression. (pg 51)
	# Skipped optional step: Optional: If you are using the LinuxContainerExecutor ... 

	# TODO - bullet 6 -  memory configuration settings
	
#	#The instructions (bullet 7) propose to wipe out $HADOOP_CONF_DIR and create it again using the "helper files" from above. 
#	#Seems better to retain the original as it includes the tags descriptions in addition to the value. 
#       
#	cd $PATH_HDP_MANUAL_INSTALL_RPM_HELPER_FILES/configuration_files/core_hadoop/
#        	
#	files_to_copy=$(ls *.ORIG_HELPER)
#	for file in $files_to_copy
#	do
#	   file_no_suffix=${file%".ORIG_HELPER"}
#	   cmd="cp -p $file_no_suffix $HADOOP_CONF_DIR"
#	   echo "$cmd "
#	   eval $cmd
#	done
#	
#	cp -p *.ORIG_HELPER $HADOOP_CONF_DIR

	cp -p $PATH_HDP_MANUAL_INSTALL_RPM_HELPER_FILES/configuration_files/core_hadoop/  $HADOOP_CONF_DIR

	
	cd $HADOOP_CONF_DIR
	chown -R $HDFS_USER:$HADOOP_GROUP $HADOOP_CONF_DIR/../
	chmod -R 755 $HADOOP_CONF_DIR/../

	sed $HADOOP_CONF_DIR/hadoop-env.sh -i.old -e "s/#export JAVA_HOME=\${JAVA_HOME}/export JAVA_HOME=\${JAVA_HOME}/"

	# TODO: I'm unhappy with the changes to /etc/profile. to verify if I can relay on $HADOOP_CONF_DIR/hadoop-env.sh instead !!! - high priority !!!

	
	# TODO: Sec 8 - not sure about the instruction. I guess need to edit $HADOOP_CONF_DIR/hadoop-env.sh
	# Currently, the parameter HADOOP_NAMENODE_OPTS is commented out. 
	# This looks like fine tunning that I can return to it back later. 
	
}

function validate_core_hadoop_installation {

if [ `stat -c %A /dev/null | sed 's/.....\(.\)..\(.\).\+/\1\2/'` != "ww" ] 
then
    # For some strange reason, /dev/null is not writeable to all. Someone probably regular file to /dev/null by mistake. 
    # So fix it ..
    rm /dev/null
    mknod /dev/null c 1 3
    chmod 666 /dev/null
fi

#
# Format and start HDFS
#

# Execute the following commands on the NameNode host machine:
su -c -l $HDFS_USER "/usr/hdp/current/hadoop-hdfs-namenode/../hadoop/bin/hdfs namenode -format"
su -c -l $HDFS_USER "/usr/hdp/current/hadoop-hdfs-namenode/../hadoop/sbin/hadoop-daemon.sh --config $HADOOP_CONF_DIR start namenode"

# Execute the following commands on the SecondaryNameNode:
su -c -l $HDFS_USER "/usr/hdp/current/hadoop-hdfs-secondarynamenode/../hadoop/sbin/hadoop-daemon.sh --config $HADOOP_CONF_DIR start secondarynamenode"

# Execute the following commands on all DataNodes:
su -c -l $HDFS_USER "/usr/hdp/current/hadoop-hdfs-datanode/../hadoop/sbin/hadoop-daemon.sh --config $HADOOP_CONF_DIR start datanode"


}

### yf stopped here: 20180117 - page 52 of: https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.6.4/bk_command-line-installation/bk_command-line-installation.pdf 									




# TODO: Some functions removed for test purposes. Be sure to include them all!!!

setup_password_less_ssh 
prepare_the_environment 
ambari_install 
setup_mysql
ambari_config_start 

yum install ambari-agent -y 
# in a single-node cluster, it is not mandatory
sed /etc/ambari-agent/conf/ambari-agent.ini -i.ORIG -e "s/hostname=localhost/hostname=${fqdn_hostname}/"
ambari-agent start   

date
fqdn_hostname=`hostname -f`
blueprint_name=single-node-hdp-cluster
cluster_name=host_group_1

write_single_custer_blueprint_json $blueprint_name $cluster_name $fqdn_hostname 


curl -H "X-Requested-By: ambari" -X POST -u admin:admin http://localhost:8080/api/v1/blueprints/${blueprint_name} -d @cluster_configuration.json

curl -H "X-Requested-By: ambari" -X POST -u admin:admin http://localhost:8080/api/v1/clusters/${cluster_name} -d @hostmapping.json

# and now let's check what is happning ... 
curl -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8080/api/v1/clusters/${cluster_name}/requests/
date


#curl -H "X-Requested-By: ambari" -X DELETE -u admin:admin http://localhost:8080/api/v1/clusters/${cluster_name}
#curl -H "X-Requested-By: ambari" -X DELETE -u admin:admin http://localhost:8080/api/v1/blueprints/${blueprint_name}
exit


wget -nv http://public-repo-1.hortonworks.com/HDP/centos7/2.x/updates/2.4.3.0/hdp.repo -O /etc/yum.repos.d/hdp.repo


fetch_hdp_manual_install_rpm_helper_files 
.  $PATH_HDP_MANUAL_INSTALL_RPM_HELPER_FILES/scripts/usersAndGroups.sh
#users_and_groups    
set_environment
install_haddop_core 
setup_hadoop_config
validate_core_hadoop_installation 

exit


wget http://public-repo-1.hortonworks.com/HDP/tools/2.4.3.0/hdp_manual_install_rpm_helper_files-2.4.3.0.227.tar.gz
tar zxvf hdp_manual_install_rpm_helper_files-2.4.3.0.227.tar.gz

wget http://public-repo-1.hortonworks.com/HDP/tools/2.6.0.3/hdp_manual_install_rpm_helper_files-2.6.0.3.8.tar.gz

tar zxvf hdp_manual_install_rpm_helper_files-2.6.0.3.8.tar.gz

###############
# Notes Thu-25-Jan-18 - 20180125 

# Notes from automated installation video: https://www.youtube.com/watch?v=HLMGUElI9hQ My notes with timestamps below

# https://www.youtube.com/watch?v=HLMGUElI9hQ#t=10m15s :
yum install ambari-agent -y 
#edit: /etc/ambari-agent/conf/ambari-agent.ini
#but on my installation I see it is already configured. May need to figure out when it was installed and configured.  
ambari-agent start   

# https://www.youtube.com/watch?v=HLMGUElI9hQ#t=17m38s : 
Time: 17:38 

The video is missing the files that are posted. 

Testing with this:
https://cwiki.apache.org/confluence/display/AMBARI/Blueprints#Blueprints-Introduction

# Not sure what this is doing ("get the blueprint registered"):
curl -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8080/api/v1/blueprints
# Here I found the name of my cluster ("test") and the hostname ("hdptst06")
curl -v -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8080/api/v1/hosts
# returns a long JSON of the cluster.

curl -v -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8080/api/v1/clusters/test?format=blueprint -o BluePrint-cluster-test-node-hdptst06.json

# This what I did on root@hdptst07:
mkdir ~/Ambari-blueprint
cd ~/Ambari-blueprint
hdptst06=10.200.1.250
#hdptst07=10.200.1.239

curl -v -H "X-Requested-By: ambari" -X GET -u admin:admin http://${hdptst06}:8080/api/v1/clusters/test?format=blueprint -o BluePrint-cluster-test-node-hdptst06.json
sed -i.OLD BluePrint-cluster-test-node-hdptst06.json -e "s/hdptst06/hdptst07/g"

yum install ambari-agent -y
# Skipping edit /etc/ambari-agent/conf/ambari-agent.ini as this is localhost anyway. May need to go back to it. 
ambari-agent start

fqdn_hostname=`hostname -f`

# # Create JSONs - very minimal stack
# cat <<EOF > hostmapping.json
# {
#   "blueprint" : "single-node-hdp-cluster",
#   "default_password" : "admin",
#   "host_groups" :[
#     {
#       "name" : "yfhdp",
#       "hosts" : [
#         {
#           "fqdn" : "${fqdn_hostname}"
#         }
#       ]
#     }
#   ]
# }
# EOF
# 
# 
# cat <<EOF > cluster_configuration.json
# {
#   "configurations" : [ ],
#   "host_groups" : [
#     {
#       "name" : "yfhdp",
#       "components" : [
#         {
#           "name" : "NAMENODE"
#         },
#         {
#           "name" : "SECONDARY_NAMENODE"
#         },
#         {
#           "name" : "DATANODE"
#         },
#         {
#           "name" : "HDFS_CLIENT"
#         },
#         {
#           "name" : "RESOURCEMANAGER"
#         },
#         {
#           "name" : "NODEMANAGER"
#         },
#         {
#           "name" : "YARN_CLIENT"
#         },
#         {
#           "name" : "HISTORYSERVER"
#         },
#         {
#           "name" : "APP_TIMELINE_SERVER"
#         },
#         {
#           "name" : "MAPREDUCE2_CLIENT"
#         },
#         {
#           "name" : "ZOOKEEPER_SERVER"
#         },
#         {
#           "name" : "ZOOKEEPER_CLIENT"
#         }
#       ],
#       "cardinality" : "1"
#     }
#   ],
#   "Blueprints" : {
#     "blueprint_name" : "single-node-hdp-cluster",
#     "stack_name" : "HDP",
#     "stack_version" : "2.6"
#   }
# }
# EOF
# 
# curl -H "X-Requested-By: ambari" -X POST -u admin:admin http://localhost:8080/api/v1/blueprints/single-node-hdp-cluster -d @cluster_configuration.json
# 
# curl -H "X-Requested-By: ambari" -X POST -u admin:admin http://localhost:8080/api/v1/clusters/yfhdp -d @hostmapping.json
# 
### curl -H "X-Requested-By: ambari" -X DELETE -u admin:admin http://localhost:8080/api/v1/blueprints/single-node-hdp-cluster 


####### MY SCARATCH AREA ##############################	

echo "# The end #" 

exit


# NTP: Sec 4.3 # https://docs.hortonworks.com/HDPDocuments/Ambari-2.2.1.0/bk_Installing_HDP_AMB/content/_enable_ntp_on_the_cluster_and_on_the_browser_host.html


# set hostname to FQDN:  
#		hostname `hostname -f`

# Firewall - BE SURE TO PERFORM EVERY TIME AFTER REBOOT



####################


echo "copy the URL below to your browser: "
echo "http://`hostname`:8080"

