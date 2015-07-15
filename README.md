# bash-parallel

Only talking about parallel_submit_legacyV1.1.sh, other scripts are depreciated 
Purpose: 
	bash script to submit commands/other scripts in parallel

Prerequisites:
	Tested mainly on MAC OSX, some testing on Ubuntu 14.04 LTS


Parameters:
	Mandatory
	-s The script you wish to run (write it out like how you would normally write it on the commandline)
	-j the maximum number of jobs you want to run cocurrently
	Optional
	-c deletes the intermediate .txt files (only useful for debugging)
	-m Try not to let free memory dip below this number (in kilobytes), takes precedence over the -j flag, but the -j flag still needs to be set

Notes about usage:
	The objects/inputs you wish to run cocurrently must be specified in a .parallel file. For example, if I needed processing to be completed on subjects 1001.nii.gz, 1002.nii.gz, and 1003.nii.gz, I would make a file named subs.parallel and if I were to call cat subs.parallel I would see as output:
	1001.nii.gz
	1002.nii.gz
	1003.nii.gz

Example usage:
	parallel_submit_legacyV1.1.sh -s "MBA.sh -s sub_MPRAGES.parallel -o /Volumes/VossLab/Repositories/Bike/FIRST_practice -a /Volumes/VossLab/Repositories/MBA_maps -b /Volumes/VossLab/Repositories/MBA_maps/brainPrior/Ave_brain.nii.gz" -j 8 

For more help see the top part of the parallel_submit_legacyV1.1.sh script.