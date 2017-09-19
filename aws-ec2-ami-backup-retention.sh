#!/usr/bin/env bash
# title           :aws-ec2-ami-backup-retention
# description     :Bash Script to make AMI backup from EC2 instance with retention and delete old AMI if these doesn't be in use without downtime.
# author          :isaac88
# date            :20170901
# version         :1.0
# usage           :./aws-ec2-ami-backup-retention instance-name 3 default
# notes           :We should pass 3 parameters to script, Instance Name, number of retention days and aws cli profile .aws/config
# ==================================================================================================================================================


set +e

# Constants
AWS_EXEC="sudo /usr/bin/aws"

# Variables / Mandatory Input parameters
EC2_NAME=$1
RETENTION_DAYS=$2
PROFILE=$3

# Function Confirm that the AWS CLI are installed.
prq_check() {
    echo "1 - Confirm that the AWS CLI are installed"
    for prerequisite in aws wget; do
        hash $prerequisite &> /dev/null
        if [[ $? == 1 ]]; then
            echo "In order to use this script, the executable \"$prerequisite\" must be installed." 1>&2; exit 70
        fi
    done
}

# Funciton Create AMI from instance
create_ami_from_instance ()
{
    echo "Create AMI of Instance : $EC2_NAME"
    # Check only 1 instance not more
    COUNTEC2=$(echo $1 |wc -l)
    if [ $COUNTEC2 -ge 2 ]
    then
    	echo "There are more than 1 Instances running with the same TAG Name"
    fi
    CREATEAMIEC2=$($AWS_EXEC ec2 create-image --no-reboot --profile $PROFILE --instance-id $1 --name "$2-$DATE" --description "Ami EC2 Backup Jenkins Instance $2") #Create AMI WHIOUT EBS INTEGRITY 
    AMIID=$(echo $CREATEAMIEC2 | awk -F ':' '{print $2}' | awk -F '"' '{print $2}' | awk -F '}' '{print $1}')
    # Create tag for the AMI 
    CREATETAG=$($AWS_EXEC ec2 create-tags --profile $PROFILE --resources "$AMIID" --tags Key=Name,Value=$2 Key=$3,Value=$2 Key=CreationDate,Value=$DATE Key=InstanceID,Value=$1)
    STATE=$($AWS_EXEC ec2 describe-images --profile $PROFILE --filters Name=image-id,Values="$AMIID" --query 'Images[*].{State:State}' --output text)
    echo "AMI creation status : .. $STATE .."
    while [ "$STATE" != "available" ]
    do
    	sleep 20
    	STATE=$($AWS_EXEC ec2 describe-images --profile $PROFILE --filters Name=image-id,Values="$AMIID" --query 'Images[*].{State:State}' --output text)
    	printf "%s" ".. $STATE .."
    done
    echo "AMI creation status Completed : .. $STATE .."

    # Create tag for all EBS snap of AMI
    AMISNAPID=$($AWS_EXEC ec2 describe-images --profile $PROFILE --filters Name=image-id,Values="$AMIID" --query 'Images[*].BlockDeviceMappings[*].[DeviceName,Ebs.SnapshotId]' --output text |awk -F" " '{print $2}')

    for SNAPID in $(echo $AMISNAPID)
    do
    	AMIVOLSNAP=$($AWS_EXEC ec2 describe-images --profile $PROFILE --filters Name=image-id,Values="$AMIID" --query 'Images[*].BlockDeviceMappings[*].[DeviceName,Ebs.SnapshotId]' --output text |grep $SNAPID |awk -F" " '{print $1}')
    	# Create tag for each EBS Snapshot
        CREATETAG=$($AWS_EXEC ec2 create-tags --profile $PROFILE --resources "$SNAPID" --tags Key=Name,Value=$2-$AMIVOLSNAP Key=CreationDate,Value=$DATE Key=InstanceID,Value=$1  Key=AmiID,Value=$AMIID Key=Volume,Value=$AMIVOLSNAP)
    done
    echo "Created AMIID : $AMIID of Instance : $EC2_NAME"
    echo "Name AMI : "$CREATEAMIEC2
}

# Funciton to delete AMI and Snapshots
delete_snapshots_ami()
{
    # Delete AMI and EBS Snapshot 
    AMISNAPIDEL=$($AWS_EXEC ec2 describe-images --profile $PROFILE --filters Name=image-id,Values="$1" --query 'Images[*].BlockDeviceMappings[*].Ebs.{SnapshotId:SnapshotId}' --output text)
    AMIDELETE=$($AWS_EXEC ec2 deregister-image --image-id "$1" --profile $PROFILE)
    STATE=$($AWS_EXEC ec2 describe-images --profile $PROFILE --filters Name=image-id,Values="$1" --query 'Images[*].{State:State}' --output text)
    echo "Status : .. $STATE .."
    while [ "$STATE" == "available" ]
    do
    	sleep 20
    	STATE=$($AWS_EXEC ec2 describe-images --profile $PROFILE --filters Name=image-id,Values="$1" --query 'Images[*].{State:State}' --output text)
    	printf "%s" ".. $STATE .."
    done
    echo "Completed : .. $STATE .."
    echo "Ami deregistred : $1"
    for SNAPIDEL in $(echo $AMISNAPIDEL)
    do
        # Delete each EBS Snapshot of AMI
        DELETESNAP=$($AWS_EXEC ec2 delete-snapshot --snapshot-id "$SNAPIDEL" --profile $PROFILE)
        # Show the state of snapshot deleted
    done
}

# Function retention AMI
backup_retention_ami()
{
    echo "2 - AMI backup from EC2 instances with retention and delete old AMI if these doesn't be in use without downtime."
    # Get current date
    DATE=`date +%Y%m%d%H%M%S`
    # Find Instance to build a AMI by tag Name
    EC2ID=$($AWS_EXEC ec2 describe-instances --profile $PROFILE --filters Name=tag:Name,Values=$1|grep InstanceId|awk '{print $2}'|cut -d "\"" -f2)
    # EC2 is found it
    if [ ! -z "$EC2ID" ] 
    then
    	# Count total AMI has EC2 found it
    	COUNTEC2AMIID=$($AWS_EXEC ec2 describe-images --profile $PROFILE --filters Name=tag-key,Values=$3  Name=tag-value,Values=$2 --query 'Images[*].{ID:ImageId}'|grep ID |wc -l)

        let COUNTEC2AMIID=$COUNTEC2AMIID
        # If EC2 has more than x(RETENTION_DAYS) AMI Created check first
        if [ $COUNTEC2AMIID -ge $RETENTION_DAYS ]
        then
        	echo "Delete the oldest AMI of the instance : "$EC2ID
            # Search the oldest AMI from EC2 because this shouldn't be in use. 
            AMIOLD=$($AWS_EXEC ec2 describe-images --profile $PROFILE --filters Name=tag-key,Values=$3  Name=tag-value,Values=$2 --query 'Images[*].{ImageId:ImageId,CreationDate:CreationDate}' --output text |sort -k1 |awk '{print $2}' |head -1)
            # Check if AMI Oldest is used
            AMIUSE=$($AWS_EXEC ec2 describe-instances --profile $PROFILE --filters Name=image-id,Values=$AMIOLD --query 'Reservations[0].Instances[*].{ImageId:ImageId}' --output text |grep $AMIOLD |wc -l)
            if [ $AMIUSE -ge 1 ]
        	then
            	echo "Oldest AMI is used in some instances. The AMI:$AMIOLD will not deleted in this moment. Please check this"
                # Search other AMI old to delete because there are minimun 2 AMIs. 
                for OAMIOLD in $($AWS_EXEC ec2 describe-images --profile $PROFILE --filters Name=tag-key,Values=$3  Name=tag-value,Values=$2 --query 'Images[*].{ImageId:ImageId,CreationDate:CreationDate}' --output text |sort -k1 |awk '{print $2}')
                do
                	if [ "$OAMIOLD" != "$AMIOLD" ]
                    then
                    	# Check if OAMIOLD is used
                    	AMIUSE=$($AWS_EXEC ec2 describe-instances --profile $PROFILE --filters Name=image-id,Values=$OAMIOLD --query 'Reservations[0].Instances[*].{ImageId:ImageId}' --output text |grep $AMIOLD |wc -l)
                        if [ $AMIUSE -le 0 ]
                        then
                        	# Call function delete AMI SNAP EBS 
     						delete_snapshots_ami $OAMIOLD
                            let COUNTEC2AMIID--
                        fi
                    fi
                	echo "Other Ami old : "$OAMIOLD
                done
            else
            	# Oldest AMI doesn't used Call function delete AMI SNAP EBS 
                delete_snapshots_ami $AMIOLD
                let COUNTEC2AMIID--
            fi
            # Create new AMI after retention check.
            create_ami_from_instance $EC2ID $2 $3
            let COUNTEC2AMIID++
            
        else
        	# Create new AMI after retention check.
            # AMI's < RETENTION_DAYS. 
        	create_ami_from_instance $EC2ID $2 $3
    		let COUNTEC2AMIID++
    	fi

        echo "Retention AMIS : $COUNTEC2AMIID of instance : $EC2_NAME"
    # EC2 doesn't found it
    else
    	echo "EC2 Name : $EC2_NAME not found. Please insert a existing EC2 instance name."
    	exit 1
    fi

}

# Void main function
main ()
{

        # 1 - Confirm that the AWS CLI are installed
        prq_check
        # 2 - AMI backup from EC2 instances with retention and delete old AMI if these doesn't be in use without downtime
        backup_retention_ami $EC2_NAME $EC2_NAME-backup 'Ami'$EC2_NAME'Backup' 

}

# Void main
main
