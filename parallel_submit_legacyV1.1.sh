#!/bin/bash
function printCommandLine {
    echo "Usage: parallel_submit.sh -s script -m free_memory_limit -c clean -h help"
    echo " where"
    echo "   -s The script (.sh) file you wish to run with arguments"
    echo "   -j The maximum number of jobs you want to run cocurrently"
    echo -e "   -c this deletes the .txt files this script creates, which really\n      aren't important to have except for debugging purposes"
    echo "   -m Try not to let free memory dip below this number (in kilobytes)"

    exit 1
}

#example of lists:
#let's say we want to run a script example.sh with
#a bunch of subjects. example.sh takes subjects and output directories
#as arguments. Therefore the user will make subjects.parallel and outDirs.parallel
#if I were to call 'cat subjects.parallel', I would see:
#341
#342
#343
#344
#etc...
#Of course without the "#" in front of them.
#Similarly, if I were to call 'cat outDirs.parallel', I would see:
#outDir/for/341
#outDir/for/342
#outDir/for/343
#outdir/for/344
#etc...
#again without the "#" in front.
#The 2 important things for these files are:
#1) each argument gets it's own line (i.e. 341 is on a different line than 342)
#2) The line in subjects.parallel corresponds to the same line in outDirs.parallel
#   (i.e. "343" in subjects.parallel is on the same line as "outDir/for/343" in outDirs.parallel)


#the scary code
########################################################
#Collect the inputs from the user.
while getopts “f:l:j:s:m:ch” OPTION
do
    case $OPTION in
	j)
	    max_jobs=$OPTARG
	    ;;
	s)
		script=($OPTARG)
		;;
	c)
		clean=1
		;;
	m)
		free_memory_limit_kb=$OPTARG
		;;
	h)
	    printCommandLine
	    ;;
	?)
	    echo "ERROR: Invalid option"
	    printCommandLine
	    ;;
    esac
done
OS=$(uname -s)
if [ "${OS}" != "Darwin" ] && [ "${OS}" != "Linux" ];then
	echo "WARNING: this program was not designed for this system"
fi



#complain and exit if there isn't a script provided
if [ "${script[0]}" == "" ]; then
	echo "-s option is required, please enter your script below and press [ENTER]"
	read -t 15 script
	if [ "${script}" == "" ]; then
		echo "Too slow! Exiting with a helpful message"
		printCommandLine
	fi
fi
#chastise and continue if there is no max job set
if [ "${max_jobs}" == "" ]; then
	if [ "${OS}" == "Darwin" ]; then
		num_cores=$(sysctl -n hw.ncpu)
	elif [ ${OS} == "Linux" ]; then
		num_cores=$(nproc)
	else
		echo "WARNING, system not supported, expect error"
	fi
	echo -e "you didn't set -j, default 2,\n but you could potentially run ${num_cores} jobs or more cocurrently"
	echo "last chance, please enter the number of jobs you would like to run and press [ENTER]:"
	read -t 10 max_jobs
	if [ "${max_jobs}" == "" ]; then
		echo "fine, be that way"
		max_jobs=2
	fi
fi
#If you are running intensive jobs, then you may wish to wait until there is memory available
if [[ "${free_memory_limit_kb}" == "" ]]; then
	free_memory_limit_kb=0
fi





command=${script[0]}
num_args=$(echo "${#script[@]}-1" | bc)

declare -a flags
declare -a lists
#argument parsing (made more user friendly?)
#need to separate lists from repeated arguments

arg_index=0
for arg in $(seq ${num_args}); do
	if [[ ${script[${arg}]} == *.parallel ]] ; then
		flags[${arg_index}]="null"
		lists[${arg_index}]=${script[${arg}]}
	else 
		flags[${arg_index}]=${script[${arg}]}
		lists[${arg_index}]="null"
	fi
	arg_index=$((${arg_index}+1))
done

#check to make sure all .parallel files are the same length
	reference_value=0
	echo "lists is ${lists[@]}"
for list in $(echo ${lists[@]} | tr ' ' '\n' | grep \.parallel$); do
	if [ ${reference_value} -eq 0 ]; then
		reference_value=$(cat ${list} | wc -l)
	else
		comp_value=$(cat ${list} | wc -l)
		if [ ! ${comp_value} -eq ${reference_value} ]; then
			echo "${list} is a different length from the first .parallel file, exiting"
			exit 1
		fi
	fi
done



#in case you had to use escape characters to pass arguments
flag_index=0
for flag in ${flags[@]}; do
	flags[${flag_index}]=$(echo ${flag} | sed 's/\\//g')
	flag_index=$((${flag_index} + 1 ))
done

#this array will be used to hold the flags and arguments to pass into xargs
declare -a command_args

#number of flags indicates number of arguments, right? 
#nope
num_flags=${#flags[@]}
num_lists=${#lists[@]}
echo "prepping flags"
#possible some flags don't have arguments
#need to make the same number of flags as there are arguments in a list
num_items=${reference_value}
echo "num items is: ${num_items}"


for arg_num in $(seq 0 $(echo "${num_args}-1" | bc)); do
	if [ "${flags[${arg_num}]}" == "null" ]; then
		echo "we are setting index ${arg_num} to ${lists[${arg_num}]}"
		command_args[${arg_num}]=${lists[${arg_num}]}
	else
		#check to see if this script was ran before
		if [ -e flag_${arg_num}.txt ]; then
			rm flag_${arg_num}.txt
		fi
		#reiterate the flag for the number of subjects being ran
	 	for arg in $(seq ${num_items}); do
			echo "${flags[${arg_num}]}" >> flag_${arg_num}.txt
		done
		#placeholder for the arguments
		command_args[${arg_num}]="flag_${arg_num}.txt"
	fi
done
echo "this is all the command txt files ${command_args[@]}"
echo "putting together command and submiting"


#xargs likes to know how many items it should take as input (flags + arguments)
#num_args=$(echo "${num_flags}+${num_lists}" | bc)


command_name=$(basename ${command})
command_name_strip=${command_name/.*/""}

######################################################################################
#set up argument array
declare -a arg_arr

#inefficient processing to get arguments in a useful array
#where each index in arg_arr represents all the arguments necesary to
#run one instance of the script.
i=0
paste ${command_args[@]} > all_${command_name_strip}_args.txt

while read args; do
	arg_arr[${i}]=${args}
	i=$((${i}+1))
done < all_${command_name_strip}_args.txt
######################################################################################
#final initializations/tidbits before we start the main loop.

#index to count set of arguments we are using
x=0
#arrays to keep track of the pids (process id's) and the time the pids started
declare -a pid_arr
declare -a time_arr

#do some housekeeping to keep clutter down
if [[ ${clean} -eq 1 ]]; then
	if [ -e ${command_name_strip}_times.txt ]; then
		rm ${command_name_strip}_times.txt
	fi
fi

echo "if you would like to kill everything, press \"k\" and hit [ENTER]"
#option to end script safely?
kill_signal=no

######################################################################################
#The big magical loop

first_iteration=1
#keep going until all the scripts are submitted or until kill signal is initiated.
while [[ ${#arg_arr[@]} -gt ${#pid_arr[@]} ]] &&\
	  [ "${kill_signal}" != "k" ]; do
	  	if [ ${first_iteration} -eq 1 ]; then
	  		sh ${script} ${arg_arr[${x}]} &>${command_name_strip}_${x}.txt & pid_arr[${x}]=$!
			echo "${script} ${arg_arr[${x}]} submitted"

			#keep track of the time this script was started
			time_arr[${x}]=$(date +%s)

			#keeps track of which instance of the script we are planning on running
			x=$((${x}+1))
			first_iteration=0
		else
		  	#the kill signal
		  	read -t 1 kill_signal

		  	#doesn't work in MAC-OS
		  	#got to keep updating/reseting to get accurate measures
			if [ "${OS}" == "Linux" ]; then
				free_memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
			elif [ "${OS}" == "Darwin" ]; then
				free_memory_kb=$(vm_stat | grep Pages\ free | awk '{print $3}' | sed 's/\./\*4/' | bc)
			fi
		  	active_jobs=0
		  	
		  	#two purposes:
		  	#1) find out how many active jobs are running
			#2) if a job finished, write its run time to a text file
		  	for job in $(seq 0 $(echo "${#pid_arr[@]}-1" |bc)); do
		  		if ps -p ${pid_arr[${job}]} > /dev/null; then
		  			active_jobs=$((${active_jobs}+1))
		  		else
		  			if [ "${time_arr[${job}]}" != "wrote" ]; then
			  			end_time=$(date +%s)
			  			run_time=$(echo "scale=2; (${end_time}-${time_arr[${job}]})/60" | bc -l)
			  			echo "${command_name_strip}_${job} ran ${run_time} minutes" >> ${command_name_strip}_times.txt
			  			time_arr[${job}]=wrote
		  			fi
		  		fi
		  	done
		  	
		  	
		
		  	#if there isn't enough memory or we've reached the max jobs we can submit...
		  	#don't do anything else until we have enough memory & fewer than max jobs are running
		  	if [[ ${free_memory_limit_kb} -gt ${free_memory_kb} ]] ||\
		  	   [[ ${active_jobs} -eq ${max_jobs} ]]; then
		  		continue
		  	fi
		  	
		  	echo "There are ${active_jobs} job(s) running"
		  	#This does a few things
		  	#1)submits the script
			#2)redirects output to a text file
			#3)records the pid of that process
			sh ${command} ${arg_arr[${x}]} &>${command_name_strip}_${x}.txt & pid_arr[${x}]=$!
			echo "${command} ${arg_arr[${x}]} submitted"

			#keep track of the time this script was started
			time_arr[${x}]=$(date +%s)

			#keeps track of which instance of the script we are planning on running
			x=$((${x}+1))
		fi
done

#if the kill signal was issued, kill the jobs
if [ "${kill_signal}" == "k" ]; then
	echo "killing all jobs"
		for pid in ${pid_arr[@]}; do
			kill ${pid} &> /dev/null
		done
	exit 1
fi


echo "All jobs submitted, if you want to see how many are currently running, press \"j\" and hit [ENTER]"
echo "Additionally if you would like to kill remaining jobs, press \"k\" and hit [ENTER]"


#the waiting period for all remaining scripts to end
#can kill scripts here too, if they are failing
#future: add option to kill specific scripts?
while [[ ${active_jobs} -gt 0 ]]; do
	ans=n #default value, so "j" doesn't continue to be true forever, filling the terminal with trash
	read -t 1 ans
	active_jobs=0
  	for job in $(seq 0 $(echo "${#pid_arr[@]}-1" |bc)); do
	  		if ps -p ${pid_arr[${job}]} > /dev/null; then
	  			active_jobs=$((${active_jobs}+1))
	  		else
	  			if [ "${time_arr[${job}]}" != "wrote" ]; then
		  			end_time=$(date +%s)
		  			run_time=$(echo "scale=2; (${end_time}-${time_arr[${job}]})/60" | bc -l)
		  			echo "${command_name_strip}_${job} ran ${run_time} minutes" >> ${command_name_strip}_times.txt
		  			time_arr[${job}]=wrote
	  			fi
	  		fi
	  	done

	if [ "${ans}" == "j" ];then
		echo "there are ${active_jobs} job(s) remaining"
	fi

	if [ "${ans}" == "k" ]; then
		echo "killing all jobs"
		for pid in ${pid_arr[@]}; do
			kill ${pid} &> /dev/null
		done
		exit 1
	fi
done


#clean up the crap made by this script
if [[ ${clean} = 1 ]]; then
	for arg_num in $(seq 0 $(echo "${num_flags}-1" | bc)); do
		if [ -e flag_${flags[${arg_num}]}.txt ]; then
			rm flag_${flags[${arg_num}]}.txt
		fi
		if [ -e list_${flags[${arg_num}]}.txt ]; then
		    rm list_${flags[${arg_num}]}.txt
		fi
	done
	if [ -e all_${command_name_strip}_args.txt ]; then
		rm all_${command_name_strip}_args.txt
	fi
fi