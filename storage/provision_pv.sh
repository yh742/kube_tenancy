# Creates a virtual volume on host for kube local provisioner 
# https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner/blob/master/docs/getting-started.md
# PLEASE ONLY ATTEMPT TO RUN THIS ON THE JUJU HOST
# VHDS ARE SAVED ON /MEDIA FOLDER AND MOUNTED TO /MNT/FAST-DISKS/ FOLDER
# KUBERNETES LOCAL STATIC PROVISIONER PICKS UP FAST-DISKS AUTOMATICALLY 
# Uninstall by: (1) sudo umount /mnt/fast-disks/pvc-<uid> (2) sudo rm -f /media/pv-<uid>
#!/bin/bash

if [ "$#" -ne 2 ] 
then
	echo "ERROR: must specify both ip address of the machine as well as space to provision"
	echo "ERROR: ./provision_pv.sh <ip address> <space to provision in G>"
	echo "EXAMPLE: ./provision_pv.sh 172.27.180.23 10G"
	exit 1
fi

space_format=${2: -1}
if [ "$space_format" != "G" ]  
then
	echo "ERROR: This is NOT the right format!"
	echo "ERROR: Space should be provided in Gibibyte (G)"
	echo "EXAMPLE: ./provision_pv.sh 172.27.180.23 10G"
	exit 1
fi

space_wanted=$2
space_wanted=${space_wanted::-1}

ssh -q ubuntu@$1 <<EOF
space_left=\$(df -h --total / | grep -i total | awk '{ print int( \$4 ) }')
echo "INFO: space left: \$space_left"
space_taken=\$(df -h | grep -i /mnt/fast-disks/ | awk '{sum+=\$2;} END{print int( sum );}')
space_left="\$((\$space_left-\$space_taken))"
echo "INFO: space wanted: $space_wanted"
echo "INFO: space taken already: \$space_taken"
echo "INFO: actual space left (including allocated to vhds): \$space_left"

if [ "$space_wanted" -gt "\$space_left" ]; then
        echo "ERROR: there's not enough space left on the machine"
        echo "ERROR: space_wanted=$space_wanted, space_left=\$space_left"
        exit 1
fi
uid=\$RANDOM
while true
do
        if [ -f "/media/pv-\$uid" ]; then
                echo "script: file exists"
                uid=\$RANDOM
                echo "script: assigned new uid=\$uid"
        else
                break
        fi
done
sudo truncate -s $2 "/media/pv-\$uid"
sudo mkfs -t ext4 /media/pv-\$uid
sudo mkdir /mnt/fast-disks/pvc-\$uid
sudo mount -t auto -o loop /media/pv-\$uid /mnt/fast-disks/pvc-\$uid
EOF