# setup_hdp24

This project is for automated install of Hadoop HDP stack and to allow performance test with various settings in batch mode. 

## Content
* hdp_2.4_install.sh        - Installs HDP using Ambari bluprints
* build_TeraSort_pkg.sh     - Download, build and execute TeraSort test from https://github.com/ehiggs/spark-terasort.git
* hdp_change_mem_config.sh  - Template script for changing services configuration and restart of the services.

### Using it

* Install the HDP stack
```
	yum install git -y 
	git clone https://github.com/lovengulu/hdp24_install.git
	cd hdp24_install
	./hdp_2.4_install.sh
```

* Build and run a TeraSort test:

```
# review / edit the parameters in build_TeraSort_pkg.sh. 
# run using: 
./build_TeraSort_pkg.sh
```

* Change HDP service configuration 
```
hdp_change_mem_config.sh 
```
is a working template script to alter configuration parameters of various services and restart those services. 
This allows to test various settings as part of a batch.  

## Known issues:
* Currently the install script support single node
* HDP2.6: hdp24_install script: 
    - hdp24_install script can install HDP 2.6 which a change of a hard-code parameter. Need to remove the hard-coding and allow this as option
    - HDP 2.6 installs fine but some of the services don't start automatically. Those services do start manually. 


