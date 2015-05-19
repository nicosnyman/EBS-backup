# EBS-backup
Backup AWS EBS volumes with a simple bash Script

Usage:  $PROGNAME [OPTION] [Args]
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
