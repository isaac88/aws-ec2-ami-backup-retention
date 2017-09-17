# aws-ec2-ami-backup-retention
Bash Script to make AMI backup from EC2 instance with retention and delete old AMI if these doesn't be in use without downtime.

Requirements
-----------
1. You need install AWS Cli at your system.<br />
2. Configured AWS Cli. http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html .<br />
3. Script : aws-ec2-ami-backup-retention.sh with execute permissions.


Bash Script vairables | Input Parameters
------------------

1. EC2_NAME: You can find your instance name at AWS Manage Console.<br />
3. RETENTION_DAYS: If you want to keep X days AMI backups. <br />
4. PROFILE: Your aws cli profile.<br />


Usage and Examples
------------------

./aws-ec2-ami-backup-retention.sh instance-name 3 default
