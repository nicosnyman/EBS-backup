    #!/bin/bash
     
    # Heavily adapted by Nico
    # Original script:
    # http://www.stardothosting.com/blog/2012/05/automated-amazon-ebs-snapshot-backup-script-with-7-day-retention/
     
    ### ebs-snapshot.sh
    # Usage:        $PROGNAME [OPTION] [Args]
    #Take snapshot of AWS volumes marked with a specific tag.
    #
    # -t, --tags    match tags of volumes to back up, in format
    #                               key:value (default=Environment:Production)
    #                               For a specific server use Name:ServerName
    # -d, --days    number of days old snapshot should
    #                               be kept, integer (default=9999)
    # -v, --device  Match a specific attached device, in format
    #                               /dev/sdxx. Default is no filter
    # -h, --help    Displays this usage message.   
    #
    # If no tags are specified all attached volumes for the
    # default tag pair will be snapshot.
    #
    # Typical example use:
    #
    # ./ebs-snapshot.sh -t Name:DEV_REST1 -v /dev/sda1 -d 7
     
    # PURPOSE:
    # - Gather a list of all volume IDs with either or:
    #       * Specific tag key/value pairs (default: Environment:Production)
    #       * Specific device name (for instance /dev/sda1
    # - Take a snapshot of each volume
    # - The script will then delete all associated snapshots taken by the script that are older than a set number of days
     
    ## AWS CLI: This script requires the AWS CLI tools to be installed.
    # Read more about AWS CLI at: https://aws.amazon.com/cli/
    # AWS must be set upwith region and AWS ID and Secret key defined.
    # Configure AWS with "aws configure"
     
    ## SCRIPT SETUP:
    # Copy this script to /opt/aws/ebs-snapshot.sh
    # And make it exectuable: chmod +x /opt/aws/ebs-snapshot.sh
     
    # Then setup a crontab job for nightly backups:
    # AWS_CONFIG_FILE="/root/.aws/config"
    # 00 06 * * *     root    /opt/aws/ebs-snapshot.sh >> /var/log/ebs-snapshot.log 2>&1
     
     
    # Safety feature: exit script if error is returned, or if variables not set -disabled for now
    # Exit if a pipeline results in an error.
    #set -ue
    #set -o pipefail
     
    export PATH=$PATH:/usr/local/bin/:/usr/bin
     
    ## Variables
    days=9999       #Number of days to keep snapshots
    tags="Name=tag:Environment,Values=Production"   #Default filter tags to take snapshots of
    device=         #Set device to filter by to blank (no filter)
    PROGNAME=$(basename $0) #Sets PROGNAME to the name of the script
     
    today=`date +"%m-%d-%Y"+"%T"` #Used to determine differences in date when removing snapshots
    logfile="/var/log/ebs-snapshot.log" #Set up the log file name
    tempfile="/tmp/volume_info.txt" #Sets up the temp file for volume lists
     
     
    ## Functions
     
    clean_up() {
     
            # Perform program exit housekeeping
            rm $tempfile
            echo "$PROGNAME aborted by user"       
            exit
    }
     
    #usage - print script help
    usage() {
     
            # Display usage message on standard error
            echo "Usage:    $PROGNAME [OPTION] [Args]
    Take snapshot of AWS volumes marked with a specific tag.
     
     -t, --tags     match tags of volumes to back up, in format
                    key:value (default=Environment:Production)
                    For a specific server use Name:ServerName
     -d, --days     number of days old snapshot should
                    be kept, integer (default=9999)
     -v, --device   Match a specific attached device, in format
                    /dev/sdxx. Default is no filter
     -h, --help     Displays this usage message.   
     
    If no tags are specified all attached volumes for the
    default tag pair will be snapshot.
     
    Typical example use:
    Take a snapshot of a specific device on a specific server,
    remove snapshots older than 7 days
    [user@machine]$./ebs-snapshot.sh -t Name:DEV_REST1 -v /dev/sda1 -d 7
     
    Take a snapshot of all devices attached to all servers with
    the tag Environment:Development
    [user@machine]$./ebs-snapshot.sh -t Environment:Development
    " 1>&2
    }
     
    #volume_info() - Get a list of all volumes with the correct tags, write to /tmp/volume_info.txt
    volume_info () {
                    aws ec2 describe-volumes --filter $tags $device --query Volumes[*].{ID:VolumeId} --output text | tr '\t' '\n' > $tempfile 2>&1
    }
     
    #create_snapshots(): Take a snapshot of all volumes with correct tags
    create_snapshots(){
            for volume_id in $(cat /tmp/volume_info.txt)
            do
                    #Create a decription for the snapshot that describes the volume: servername.device-backup-date
                    instance_name=$(aws ec2 describe-volumes --volume-ids $volume_id --filter $tags $device --query 'Volumes[*].[Tags[*], Attachments[0].Device]' --output text|awk '{if (/[/]/) pat1=$0; if ($1 ~/Name/) pat2=$2;}{gsub(/[/]/,"",pat1)}{if (pat1 && pat2) {print pat2,pat1;pat1=pat2=""}}')
            description="$instance_name-backup-$(date +%Y-%m-%d)"
                    description=${description// /.}
                    echo "Volume ID is $volume_id" >> $logfile
       
                    #Take a snapshot of the current volume, and capture the resulting snapshot ID
                    snapresult=$(aws ec2 create-snapshot --output=text --description $description --volume-id $volume_id --query SnapshotId)
           
                    echo "New snapshot is $snapresult" >> $logfile
             
                    # And then we're going to add a "CreatedBy:AutomatedBackup" tag to the resulting snapshot.
                    # Why? Because we only want to purge snapshots taken by the script later, and not delete snapshots manually taken.
                    aws ec2 create-tags --resource $snapresult --tags Key=CreatedBy,Value=AutomatedBackup
            done
    }
     
    #delete_snapshots(): delete snapshots older than a specific time - this will stick with criteria specified earlier
    delete_snapshots(){
            rm /tmp/snapshot_info.txt --force       #Remove old list of snapshots (the ones we create earlier)
           
    #Get all snapshot IDs associated with each volume previously conforming to filter - goes into snapshot_info.txt
            for vol_id in $(cat /tmp/volume_info.txt)
            do
                    aws ec2 describe-snapshots --output=text --filters "Name=tag:CreatedBy,Values=AutomatedBackup", "Name=volume-id,Values=$vol_id" --query Snapshots[].SnapshotId | tr '\t' '\n' | sort | uniq >> /tmp/snapshot_info.txt 2>&1
            done
     
    # Purge all instance volume snapshots created by this script that are older than number of days set earlier in script
            for snapshot_id in $(cat /tmp/snapshot_info.txt)
            do
                    echo "Checking $snapshot_id..."
                    snapshot_date=$(aws ec2 describe-snapshots --output=text --snapshot-ids $snapshot_id --query Snapshots[].StartTime | awk -F "T" '{printf "%s\n", $1}')
                    snapshot_date_in_seconds=`date "--date=$snapshot_date" +%s`
     
                    if [ $snapshot_date_in_seconds <= $retention_date_in_seconds ]; then
                            echo "Deleting snapshot $snapshot_id ..." >> $logfile
                            aws ec2 delete-snapshot --snapshot-id $snapshot_id
                    else
                            echo "Not deleting snapshot $snapshot_id ..." >> $logfile
                    fi
            done
    #One last carriage-return in the logfile...
    echo "" >> $logfile
    }
     
     
    read_parameters() {
    while [ "$1" != "" ]; do
        case $1 in
            -t | --tags )           shift
                                    tags=$1
                                                                    tags="Name=tag:"${tags//":"/,"Values="}
                                                                    ;;
            -d | --days )                   shift
                                                                    days=$1
                                                                    retention_date_in_seconds=`date +%s --date "$days days ago"`  #Set oldest date snapshots should be kept
                                    ;;
                    -v | --device )                 shift
                                                                    device=$1
                                                                    device="Name=attachment.device,Values="$device  #Set device to filter by
                                                                    ;;
            -h | --help )           shift
                                                                    usage
                                    exit 0
                                    ;;
            * )                     usage
                                    exit 1
        esac
        shift
    done
    }
     
    ###Main script###
    #################
     
    trap clean_up SIGHUP SIGINT SIGTERM #Set traps for user interupt
     
    echo $today >> $logfile #Start a logfile with today's date
    read_parameters $@      #Pass the command line parameters ($@) to function read_parameters to parse
    volume_info     #build a list of volumes to snapshot
    create_snapshots        #create snapshots as per previous list
    delete_snapshots
     
    echo $days, $tags, $device
    #echo $retention_date_in_seconds
    echo "Results logged to $logfile"
