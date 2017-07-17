#Script to setup tinc
#SSH key specifically for this script should first be added to the destination server

#function for color coding
red=`tput setaf 1`
green=`tput setaf 2`
purple=`tput setaf 5`
white=`tput setaf 7`
reset=`tput sgr0`
bold=`tput bold`

#initial clear of terminal
clear
echo "${white}"

#Prereq checks
#check for tinc on local server
printf "checking if tinc is installed on Local server.\n"
if [ "$(which tincd)" == "" ]
	then 
		printf "Tinc not found on local server.\n"
		exit 1
	else 
		printf "Tinc found, continuing with setup.\n"
fi

#########################################################
#Set base variables
#User modifiable variables (Defaults should be ok)
network_name="servernet"
primary_node_name="collectionpoint"
install_dir="/etc/tinc"
ssh_key="~/.ssh/tinc-setup"
#########################################################


#Set constants
network_dir="$install_dir/$network_name"

#Ping checking function
ping_check() {
	x=1
while [[ $? == 0 ]]
	do ((x++))
		ping -c1 -w2 $1.$x > /dev/null
	done
		echo "$1.$x is the first IP that did not ping"
}

#Blank out input variables
node=""
server=""
IP=""

#Ask user for variables
read -p "Enter name of node: " node
read -p "Enter address of server being setup (IP or hostname): " server
read -p "Would you like me to automatically find subnet for network? (y/n)" auto_subnet

#Perform Subnet check
if [ $auto_subnet = "y" ]
	then
		#Pull IP range from main configuration file
		RANGE=$(grep "Subnet" $network_dir/hosts/$primary_node_name | awk {'print $3'} |cut -d. -f1,2,3)
	else
		#Ask user for IP range
		read -p "IP range to use: " IPRANGE
		RANGE=$(echo $IPRANGE | cut -d. -f1,2,3)
fi

#Set SSH connect command
ssh_connect="ssh -i $ssh_key root@$server"

#Check for usable IP address and output first
echo "Ping checking for usable IPs in range"
#ping and find first available ip in range and display that IP
ping_check $RANGE

#find out which IP user wants to use.
read -p "Enter IP for this node to use: " IP

#Check to ensure tinc is installed on remote server
printf "checking if tinc is installed on remote server."
sleep 1
if [ "$($ssh_connect which tincd)" == "" ]
	then 
		printf "Tinc not found on remote server.\n"
		exit 1
	else 
		printf "Tinc found, continuing with setup.\n"
fi

#Create configuration files
echo "Creating configuration files"
$ssh_connect "mkdir -p $network_dir/hosts
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
echo 'Subnet = $IP/32' > $network_dir/hosts/$node
"

#Generate keypairs
$ssh_connect "tincd -n $network_name -K4096" &> /dev/null
printf "Key pair generated\n"
$ssh_connect "chmod 755 $network_dir/tinc-*"

#Pull copy of host file to central server
rsync -avHP -e "ssh -i $ssh_key" root@$server:$network_dir/hosts/$node $network_dir/hosts/$node &> /dev/null
echo "$node host file copied to $primary_node_name"

#Push copy of host file to new node
rsync -avHP $network_dir/hosts/$primary_node_name -e "ssh -i $ssh_key" root@$server:$network_dir/hosts/$primary_node_name &> /dev/null
echo "$primary_node_name host file copied to $node"

#set network to start on boot
$ssh_connect "echo 'servernet' >> $install_dir/nets.boot"

#Attempt to start service
sleep 5 #wait before performing the restart
echo "Attempting to start tinc service...."
$ssh_connect "systemctl restart tinc"

printf "Setup finished${reset}\n\n\n\n\n\n"
