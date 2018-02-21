#!/bin/bash

# TODO: Header, version, 

cluster_name=$1
used_ram_mb=$2
container_ram=$3

function replace_number_value_of_parameter_in_cfg_file {
	# helpep function that replaces a NUMERIC value in the config line for the $parameter in the file $ cfg_file with $new_val 
	cfg_file=$1
	parameter=$2
	new_val=$3

	# get the line from the file and trim leading and trailing space 
	orig_config_line="$(grep $parameter $cfg_file | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
	new_config_line=$(echo $orig_config_line | sed "s/\([0-9][0-9]*\)/$new_val/")
	
	sed_repl_expression=s/$orig_config_line/$new_config_line/
	#echo $sed_repl_expression
	sed_repl_expression=$(printf "%q" "$sed_repl_expression")

	sed -i $cfg_file -e "$sed_repl_expression"
}


function set_hadoop_yarm_mem_config {
	# This function reads the $cluster_name and write it to *config.json files in the current directory. 
	# Then it changes some of the parameters according to the input $used_ram_mb and $container_ram
	# The config files are changed, leaving backup with current timestamp 
	# Once config files are revised, they are pushed into Ambari 
	# (For the changes to take effect, services restart is needed)
	
    cluster_name=$1
    used_ram_mb=$2
    container_ram=$3

    used_ram_mb_div_10="$((used_ram_mb / 10))"
	password=admin

	config_exe=/var/lib/ambari-server/resources/scripts/configs.py
	constant_params="--user=admin --password=$password --host=localhost --cluster=$cluster_name"
	$config_exe $constant_params --action=get --config-type=yarn-site --file=yarn_site_config.json
	$config_exe $constant_params --action=get --config-type=mapred-site --file=mapred-site_config.json

	#save backup of the configuration before changing it
    timestamp=$(date +%y%m%d-%H%M)
    cp -p yarn_site_config.json yarn_site_config.json.BAK.${timestamp}
    cp -p mapred-site_config.json mapred-site_config.json.BAK.${timestamp}

	# update the config
    replace_number_value_of_parameter_in_cfg_file  yarn_site_config.json 	 yarn.scheduler.minimum-allocation-mb  $container_ram
    replace_number_value_of_parameter_in_cfg_file  yarn_site_config.json	 yarn.scheduler.maximum-allocation-mb  $used_ram_mb
    replace_number_value_of_parameter_in_cfg_file  yarn_site_config.json	 yarn.nodemanager.resource.memory-mb   $used_ram_mb
                                                                            
    replace_number_value_of_parameter_in_cfg_file  mapred-site_config.json   mapreduce.map.memory.mb    $container_ram		
    replace_number_value_of_parameter_in_cfg_file  mapred-site_config.json   mapreduce.map.java.opts    $used_ram_mb_div_10	
    replace_number_value_of_parameter_in_cfg_file  mapred-site_config.json   mapreduce.reduce.memory.mb $container_ram      
    replace_number_value_of_parameter_in_cfg_file  mapred-site_config.json   mapreduce.reduce.java.opts $used_ram_mb_div_10	
    replace_number_value_of_parameter_in_cfg_file  mapred-site_config.json   yarn.app.mapreduce.am.resource.mb    $container_ram
    replace_number_value_of_parameter_in_cfg_file  mapred-site_config.json   yarn.app.mapreduce.am.command-opts   $used_ram_mb_div_10
    #replace_number_value_of_parameter_in_cfg_file mapred-site_config.json   mapreduce.task.io.sort.mb   2048 

	# update Ambari with the parameters changed
	$config_exe $constant_params --action=set --config-type=yarn-site --file=yarn_site_config.json
	$config_exe $constant_params --action=set --config-type=mapred-site --file=mapred-site_config.json

}


function restart_services {
	# Stop / start the list of services on $cluster_name raised on $host with Ambari admin $password.  
	# The list of service(s) to stop/start follow the mandatory parameters above. 

	cluster_name=$1
	shift
	host=$1
	shift
	password=$1
	shift
	
	# place here list of services to handle 
	services=( "$@" )
	
	# stop the listed services 
	payload='{"RequestInfo": {"context" :"Stop _service_ via REST"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}'
	for item in ${services[@]} ; do
		curl -u admin:$password -i -H 'X-Requested-By: ambari' -X PUT -d "${payload/_service_/$item}" http://$host:8080/api/v1/clusters/$cluster_name/services/$item
	done

	# wait so START requests can be queued 
	status=''
	while [[ $status != *"COMPLETED"* ]]; do
		sleep 15
		last_request=$(curl -u admin:$password -i -H 'X-Requested-By: ambari' http://localhost:8080/api/v1/clusters/host_group_1/requests/ | grep href | tail -1)
		echo $last_request 
		last_req_url=$(echo $last_request | awk  '{print $3}' | tr -d , | tr -d \" )
		echo $last_req_url

		status=$(curl -u admin:$password -H 'X-Requested-By: ambari' $last_req_url | grep status )
		echo $status
	done
	
	# and now START the stopped services 
	payload='{"RequestInfo": {"context" :"Start _service_ via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}'	
	for item in ${services[@]} ; do
		curl -u admin:$password -i -H 'X-Requested-By: ambari' -X PUT -d "${payload/_service_/$item}" http://$host:8080/api/v1/clusters/$cluster_name/services/$item
	done

}


#cluster_name=host_group_1
#password=admin
host=localhost 
	
set_hadoop_yarm_mem_config $cluster_name $used_ram_mb $container_ram
restart_services $cluster_name $host $password YARN MAPREDUCE2 HIVE
	
# example: ./hdp_change_mem_config.sh host_group_1 10240 2048

###########


	

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

	
# 
# grep mapreduce.map.java.opts mapred-site_config.json | sed $sed_repl_expression
# 
# # build sed expression for updating the config file
# unset sed_exp
# sed_exp="${sed_exp} $(replace_number_value_of_parameter_in_cfg_file mapred-site_config.json mapreduce.map.java.opts 1111) ; "
# echo $sed_exp
# sed_exp="${sed_exp} $(replace_number_value_of_parameter_in_cfg_file mapred-site_config.json mapreduce.reduce.java.opts 2222)"
# 
# echo $sed_exp
# grep java.opts mapred-site_config.json | sed  -e  "$sed_exp"
# 
# 						
