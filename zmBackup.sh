#!/bin/bash

ARGS_NB=$#
ARGS=$@

### SCRIPT CONFIGURATION
LOCAL_DIR="/backup"
REMOTE_USER="jeremy"
REMOTE_HOST="192.168.0.80"
REMOTE_DIR="/home/jeremy/tmp"
MAIL_TO="jdescamps@capensis.fr"


### FUNCTIONS
function print_usage {
	echo -e "zmBackup is used to backup AND restore Zimbra's accounts to/from remote server through SSH.\n"
	echo -e "First, edit the \"CONFIGURATION\" part of the script.\n"
	echo
	echo -e "zmBackup usage :\n"
	echo -e "- backing up # ./zmBackup -b|--backup : backup accounts according to the \"CONFIGURATION\" part.\n"
	echo -e "- restoring # ./zmBackup -r|--restore : restore all accounts according to the \"CONFIGURATION\" part.\n"
}

function checkConf {
	if [[ ! -d $LOCAL_DIR ]]; then
		echo -e "$LOCAL_DIR is not a directory. Please check the zmBackup \"CONFIGURATION\" part.\n"
		exit 5
	fi

	if [[ $REMOTE_USER == '' ]]; then
		echo -e "'REMOTE_USER' configuration is required.\n"
		exit 5
	fi

	if [[ $REMOTE_HOST == '' ]]; then
		echo -e "'REMOTE_HOST' configuration is required.\n"
		exit 5
	fi

	if [[ $REMOTE_DIR == '' ]]; then
		echo -e "'REMOTE_DIR' configuration is required.\n"
		exit 5
	fi

	if [[ $MAIL_TO == '' ]]; then
		echo -e "'MAIL_TO' configuration is required.\n"
		exit 5
	fi
}

function restoreAccounts {
	# Select date to restore
	count=0
	echo "Select a specific backup to restore : "
	for dir in `ssh ${REMOTE_USER}@${REMOTE_HOST} "ls $REMOTE_DIR"`; do
		((count=$count + 1))
		echo $count '. ' $dir
		TO_RESTORE[$count]=$dir
	done
	
	if [[ $count != 0 ]]; then
		read USER
	else
		echo "No backup to restore."
		exit 4
	fi

	# Retrieve it
	echo -e "Retrieving accounts from ${TO_RESTORE[$USER]} ...\n"
	scp -r ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/${TO_RESTORE[$USER]} ${LOCAL_DIR} 2>&1 >> /dev/null

	# Ask for temporary password for non-existent account
	echo -e "Some mailboxes could not exist anymore. Need to recreate them."
	echo -e "Temporary password for them :"
	read PWD

	# Restore it
	for mbox in `ls ${LOCAL_DIR}/${TO_RESTORE[$USER]}/*.tgz`; do
		mail=$(basename $mbox)
		mail=${mail:0:-4}

		echo -e "Restoring $mail ..." | tee -a ${LOCAL_DIR}/${TO_RESTORE[$USER]}/zimbra-backup.txt

		/opt/zimbra/bin/zmmailbox -z -m $mail postRestURL "//?fmt=tgz&resolve=skip" $mbox 2>&1 | tee -a ${LOCAL_DIR}/${TO_RESTORE[$USER]}/zimbra-backup.txt
		if [[ $? == 2 ]]; then
			# if mailbox does not exist, create it with password, restoring account and force user to change password
			/opt/zimbra/bin/zmprov ca $mail $PWD 2>&1 | tee -a ${LOCAL_DIR}/${TO_RESTORE[$USER]}/zimbra-backup.txt
			/opt/zimbra/bin/zmprov ma $mail zimbraPasswordMustChange TRUE
			/opt/zimbra/bin/zmmailbox -z -m $mail postRestURL "//?fmt=tgz&resolve=skip" $mbox 2>&1 | tee -a ${LOCAL_DIR}/${TO_RESTORE[$USER]}/zimbra-backup.txt
		fi
	done
}

function backupAccounts {
	# Dated directory
	LOCAL_DIR="${LOCAL_DIR}/$(date +"%Y%m%d-%H%M%S")"
	if [[ ! -d $LOCAL_DIR ]]; then
		mkdir $LOCAL_DIR
	fi

	# Lock file handler
	LOCKFILE=/tmp/zimbra-backup.lock
	if [[ -e ${LOCKFILE} ]] && kill -0 `cat ${LOCKFILE}`; then
		echo $(date '+%y-%m-%d %H:%M') " zmBackup seems to be already running. Please wait for it before restarting." >> ${LOCAL_DIR}/zimbra-backup.txt
		echo $(date '+%y-%m-%d %H:%M') " zmBackup seems to be already running. Please wait for it before restarting."
		exit 2
	fi

	trap "rm -f ${LOCKFILE}; exit" INT TERM EXIT
	echo $$ > ${LOCKFILE}
	 
	# Save each account
	echo $(date '+%y-%m-%d %H:%M') " zmBackup process started" > ${LOCAL_DIR}/zimbra-backup.txt
	ZIMBRA_ACCOUNTS=$(/opt/zimbra/bin/zmprov -l gaa);
	for ZIMBRA_ACCOUNT in $ZIMBRA_ACCOUNTS; do
		echo "backing up: "$ZIMBRA_ACCOUNT
		echo $(date '+%y-%m-%d %H:%M') " backing up: "$ZIMBRA_ACCOUNT >> ${LOCAL_DIR}/zimbra-backup.txt
		/opt/zimbra/bin/zmmailbox -z -m $ZIMBRA_ACCOUNT getRestURL "//?fmt=tgz" > ${LOCAL_DIR}/${ZIMBRA_ACCOUNT}.tgz 2>> ${LOCAL_DIR}/zimbra-backup.txt
	done;

	# Save LDAP DB
	echo $(date '+%y-%m-%d %H:%M') " Making full backup of LDAP DB for disaster recovery" >> ${LOCAL_DIR}/zimbra-backup.txt
	/opt/zimbra/libexec/zmslapcat $LOCAL_DIR
	 
	# Send it to remote
	scp -r $LOCAL_DIR ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR} >> ${LOCAL_DIR}/zimbra-backup.txt
	echo $(date '+%y-%m-%d %H:%M') " backup process completed" >> ${LOCAL_DIR}/zimbra-backup.txt
	 
	# Notification
	errCount=$(cat ${LOCAL_DIR}/zimbra-backup.txt | grep -o ERROR | wc -l)
	if [ $errCount -ne 0 ]; then
		cat ${LOCAL_DIR}/zimbra-backup.txt | mail -s "Zimbra backup unusual error(s) detected" $MAIL_TO
		exit 0
	else
		cat ${LOCAL_DIR}/zimbra-backup.txt | mail -s "Zimbra backup successfully completed" $MAIL_TO
	fi
	 
	rm -f ${LOCKFILE}
}

function checkUser {
	WHO=`whoami`
	if [[ $WHO != 'zimbra' ]]; then
		echo -e "Execute this scipt as zimbra user.\n"
		exit 1
	fi
}

function parseArgs {
	if [[ $# == 1 ]]; then
		if [[ $1 == "-b" || $1 == "--backup" ]]; then
			# Just backup accounts
			RESTORE=0
		elif [[ $1 == "-r" || $1 == "--restore" ]]; then
			# Restore accounts
			RESTORE=1
		else
			# Unknown argument
			print_usage
			exit 3
		fi
	else
		# Unknown argument
		print_usage
		exit 3
	fi
}

### SCRIPT CORE
checkUser;
checkConf;
parseArgs $ARGS;
if [[ $RESTORE == 1 ]]; then
	restoreAccounts
else
	backupAccounts
fi
