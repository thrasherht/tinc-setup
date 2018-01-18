#!/bin/bash
#Author: Thrasherht

#Script to setup tincd on remote server
#V1 assumes tinc is already setup on central node
#V2 (Planned) Will be able to setup central tinc node.

#main function to build out the script logic
main() {
	#setup starting Variables and reset terminal
	start_var
	reset_term
	#get package installer
	installer_get

	#Make sure there is a key file on the local machine
	file_check $keyfile 600

	#Verify that Tinc is installed locally
	if binary_check tincd
		then
			: #tinc installed, good to setup new node
		else
			echo "It looks like this server does not have tinc installed."
			read -p "Would you like to setup a new central node? (y/n)" cental_setup
	fi

	if [ '$cental_setup' == 'y' ]
		then
			: #central node setup goes here
		else
			user_var_node
	fi

	#Check to ensure tinc is installed on remote server
	binary_check tindc remote

	#generate configurations on remote server
	conf_gen | ssh_connect

	#Generate keypairs and fix permissions
	echo "tincd -n $network_name -K4096" | ssh_connect &> /dev/null
	echo "chmod 755 $network_dir/tinc-*" | ssh_connect

	#Pull copy of host file to central server
	rsync -avHP -e "ssh -i $ssh_key" root@$server:$network_dir/hosts/$node $network_dir/hosts/$node &> /dev/null

	#Push copy of host file to new node
	rsync -avHP $network_dir/hosts/$primary_node_name -e "ssh -i $ssh_key" root@$server:$network_dir/hosts/$primary_node_name &> /dev/null

	#set network to start on boot
	echo "echo 'servernet' >> $install_dir/nets.boot" | ssh_connect

	#Attempt to start service
	sleep 2 #wait before performing the restart
	echo "Attempting to start tinc service...."
	echo "systemctl restart tinc" | ssh_connect

	printf "Setup finished${reset}"
}

#Functions
#############################
start_var() {
	#Set base variables
	#User modifiable variables (Defaults should be ok)
	network_name="datanet"
	primary_node_name="headnode"
	install_dir="/etc/tinc"
	keyfile="tinc-setup"
	central_ip="172.16.10.1"

	#Set constants
	network_dir="/tmp/$install_dir/$network_name"

	#Blank out input variables
	node=""
	host=""

	#function for color coding
	red=`tput setaf 1`
	green=`tput setaf 2`
	yellow=`tput setaf 3`
	blue=`tput setaf 4`
	purple=`tput setaf 5`
	white=`tput setaf 7`
	reset=`tput sgr0`
	bold=`tput bold`
}

user_var_node() {
	#Ask user for variables
	read -p "${bold}Enter name of node: ${reset}" node
	read -p "${bold}Enter address of server being setup (IP or hostname): ${reset}" host
}

user_var_central() {
	read -p "Name of central node? (Default: $primary_node_name): " primary_node_name
	read -p "What IP to use internal IP on $primary_node_name (Default: $central_ip): " central_ip
}

#clear terminal and set color to white
reset_term() {
	clear; echo "${white}"
}

#Perform SSH connection and pass commands to remote server
#arguments provided act as command input. No arguments can also be used.
ssh_connect() {
	local key=$keyfile
	local server=$host
	local commands="$@"

	ssh -i $key root@$host $commands
}

#Use ping find the first non-responding IP to use for new node.
#No input variables. Pulls starting IP from configuration files.
find_ip() {
	local x=1
	local iprange=$(grep "Subnet" $network_dir/hosts/$primary_node_name | awk {'print $3'} |cut -d. -f1,2,3)
	local new_ip="n"

	#Internal function to perform looping ping test
	ping_test() {
		while [[ $? == 0 ]]
			do ((x++))
				ping -c1 -w1 $iprange.$x > /dev/null
			done
	}

while [ "$new_ip" == "n" ]
	do
		ping_test
		read -p "IP $iprange.$x is the first to not respond, would you like to use this for the new node (y/n)" new_ip
	done

	#set IP to be used for new node
	node_ip="$iprange.$x"
}

#Check if binary exists in PATH
#Input variables
#1: binary to be checked
#2: remote to perform check on remote server. Server is based on $host variable.
binary_check() {
	local binary=$1
	local remote=$2

	if [ "$#" -eq 1 ]; then
			if [ "$(which $binary)" != "" ]
				then
					#success
					:
				else
					#check failed, kill script.
					echo "${red}Binary check failed on $binary. (Local)"
					exit 1
			fi
	elif [ "$remote" == "remote" ]
		then
			if [ "$(ssh_connect $server $key which $binary)" != "" ]
				then
					#success
					:
				else
					echo "${red}Remote binary check failed on $binary for server $server"
					exit 1
			fi
	fi
}

#Check if file exist, and if permission is provided verify permission.
#Will correct permission if it is wrong.
#inputs 1: filepath 2: permission value
file_check() {
	local file=$1
	local perm=$2

	if [ "$#" -eq 1 ]; then
			if [ -f $file ]
				then
					#success
					:
				else
					#check failed, kill script.
					echo "${red}File check failed, $file doesn't exist"
					exit 1
			fi
	elif [ "$#" -eq 2 ]
		then
			if [ -f $file ]
				then
					if [ $(stat -c "%a" "$file") == "$perm" ]
						then
							#success
							:
						else
							#check failed, kill script
							echo "${blue}File permissions incorrect for $file, desired permissions $perm"
							echo "chmod performed on $file${reset}"
							#Fix permissions
							chown $perm $file
			fi
			else
				#check failed, kill script.
				echo "${red}File check failed, $file doesn't exist"
				exit 1
		fi
	fi
}

conf_gen() {
	#echo out commands for conf generation.
	echo "
	mkdir -p $network_dir/hosts
	touch $network_dir/tinc.conf
	touch $network_dir/tinc-up
	touch $network_dir/tinc-down
	touch $network_dir/hosts/$node
	echo 'ifconfig \$INTERFACE down' > $network_dir/tinc-down
	echo 'ifconfig \$INTERFACE $IP netmask 255.255.255.0' > $network_dir/tinc-up
	echo 'Name = $node
	AddressFamily = ipv4
	Interface = tun0
	ConnectTo = $primary_node_name' > $network_dir/tinc.conf
	echo 'Subnet = $IP/32' > $network_dir/hosts/$node"
}

installer_get() {
	if [ "$(which apt)" != '' ]
		then
			installer="apt"
			echo "${green} Server appears to use apt. Using apt for package installs"
		else
			installer="yum -y"
			echo "${green} Server appears to use yum. Using yum for package installs"
	fi
	echo "${reset}"
}

main
