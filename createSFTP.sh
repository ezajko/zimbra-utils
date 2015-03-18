#! /bin/bash

######################################
#### USED TO CREATE A SFTP ACCESS ####
######################################

### Variable
SFTP_DIR=/sftp
VGNAME=VG_data
CONTACT=contact@mail.local

### Functions
function initVariables {
        echo "Initialing variables... "
        ERROR_MSG=''

        # add / to the end of $SFTP_DIR if needed
        [[ $SFTP_DIR == */ ]] || SFTP_DIR+=/

        # check $SFTP_DIR
        [[ -d $SFTP_DIR ]] || ERROR_MSG="Directory $SFTP_DIR does not exists ! Exiting ..."

        # check $VGNAME
        vgs --noheadings -o vg_free $VGNAME >/dev/null 2>&1 || ERROR_MSG="VG $VGNAME does not exists ! Exiting ..."

        # exit with error message
        if [[ ! -z $ERROR_MSG ]]; then
                echo $ERROR_MSG
                exit 1
        fi
}

function checkError {
        checkClientName $CLIENT
        checkAskedSpace $SPACE
        checkMountPoint $CLIENT
}

function checkClientName {
        if [[ ! -z $CLIENT ]]; then
                echo "Checking client name... "
                ERROR_MSG=''

                # client name must have valid format
                REG='^[a-zA-Z0-9-]$'
                [[ $CLIENT =~ $REG ]] || ERROR_MSG="$CLIENT is not a valid client name !"

                # check directory in $SFTP_DIR
                FULLDIR=${SFTP_DIR}${CLIENT}
                if [[ $FULLDIR != $SFTP_DIR && -d $FULLDIR ]]; then
                        ERROR_MSG="Directory $FULLDIR already exists !"
                fi

                # check LV
                FULLLV=/dev/${VGNAME}/LV_${CLIENT}
                lvs $FULLLV >/dev/null 2>&1 && ERROR_MSG="LV $FULLLV already exists !"

                # check user name
                cut -d: -f1 /etc/passwd|grep -Pqi "^${CLIENT}$" && ERROR_MSG="User $CLIENT already exists !"
                cut -d: -f1 /etc/passwd|grep -Pqi "^${CLIENT}lan$" && ERROR_MSG="User $CLIENT already exists !"

                # exit with error message
                if [[ ! -z $ERROR_MSG ]]; then
                        echo $ERROR_MSG
                        echo "Please choose a different client name"
                        exit 2
                else
                        echo " OK"
                fi
        fi
}

function checkAskedSpace {
        if [[ ! -z $SPACE ]]; then
                echo "Checking space needed... "
                ERROR_MSG=''

                # check the space entered by user (in Mo or Go) and transcript in Mo
                REG='^[0-9]+[m|g]$'
                [[ $SPACE =~ $REG ]] || ERROR_MSG="Space entered $SPACE is not valid ! Please re-specify space needed"
                if [[ $SPACE == *g ]]; then
                        SPACE=`echo $SPACE | tr -d g`
                        SPACE=`echo ${SPACE}*1024|bc`
                elif [[ $SPACE == *m ]]; then
                        SPACE=`echo $SPACE |tr -d m`
                fi

                # check if $VGNAME has sufficient space
                VGSPACE_AVAIL=`vgs --noheadings --units m -o vg_free ${VGNAME}|cut -f1 -d','`
                [[ $SPACE -gt $VGSPACE_AVAIL ]] && ERROR_MSG="Not enough space in ${VGNAME} ! Please contact administrators $CONTACT"

                # exit with error message
                if [[ ! -z $ERROR_MSG ]]; then
                        echo $ERROR_MSG
                        exit 3
                else
                        echo " OK"
                fi
        fi
}

function checkMountPoint {
        if [[ ! -z $CLIENT ]]; then
                echo "Checking mountpoint... "
                ERROR_MSG=''

                # check the mountpoint in /etc/fstab
                grep -Pqi "^/dev/${VGNAME}/LV_${CLIENT}$" /etc/fstab && ERROR_MSG="Mountpoint /dev/${VGNAME}/LV_${CLIENT} already exists ! Please contact administrators $CONTACT"

                # exit with error message
                if [[ ! -z $ERROR_MSG ]]; then
                        echo $ERROR_MSG
                        exit 4
                else
                        echo " OK"
                fi
        fi
}

function createAccessForClient {
        echo "Creating access for ${CLIENT}"
        createUsers $CLIENT
        createPwd $CLIENT
}

function createUsers {
        useradd -d ${SFTP_DIR}${CLIENT} -G sftpusers -s /sbin/nologin $CLIENT >/dev/null 2>&1
        useradd -d ${SFTP_DIR}${CLIENT} -G sftpusers -s /sbin/nologin ${CLIENT}lan >/dev/null 2>&1
}

function createPwd {
        PWD_CLIENT=`openssl rand -hex 5`
        PWD_CLIENTLAN=`openssl rand -hex 5`
        echo $PWD_CLIENT| passwd --stdin $CLIENT >/dev/null 2>&1
        echo $PWD_CLIENTLAN| passwd --stdin ${CLIENT}lan >/dev/null 2>&1
}

function createRightsForClient {
        mkdir -p ${SFTP_DIR}${CLIENT}/writeable
        chmod 750 ${SFTP_DIR}${CLIENT}
        chown root:sftpusers ${SFTP_DIR}${CLIENT}
        chown $CLIENT ${SFTP_DIR}${CLIENT}/writeable
        chmod 700 ${SFTP_DIR}${CLIENT}/writeable
        setfacl -R -dm u:${CLIENT}lan:rwx /sftp/${CLIENT}/writeable/
        setfacl -R -m u:${CLIENT}lan:rwx /sftp/${CLIENT}/writeable/
}

function createDiskForClient {
        echo "Creating disk for ${CLIENT}... "
        createLV $CLIENT
        makeFS $CLIENT
}

function createLV {
        lvcreate -n LV_${CLIENT} -L ${SPACE}M ${VGNAME} >/dev/null 2>&1
}

function makeFS {
        mkfs.ext4 /dev/${VGNAME}/LV_${CLIENT} >/dev/null 2>&1
}

function createMountPoint {
        echo "Creating mountpoint for ${CLIENT}..."
        mkdir ${SFTP_DIR}${CLIENT}
        echo -e "/dev/${VGNAME}/LV_${CLIENT}\t${SFTP_DIR}${CLIENT}\text4\tdefaults,acl\t1 2" >>/etc/fstab
}

function mountDiskForClient {
        echo "Mounting mountpoint for ${CLIENT}..."
        mount ${SFTP_DIR}${CLIENT}
}

function doActions {
        createMountPoint $CLIENT
        createAccessForClient $CLIENT
        createDiskForClient $CLIENT
        mountDiskForClient $CLIENT
        createRightsForClient $CLIENT
}

function resume {
        echo "#########################################################"
        echo "#"
        echo "# Internal user : $CLIENT"
        echo "# Internal user password : $PWD_CLIENT"
        echo "#"
        echo "# External user : ${CLIENT}lan"
        echo "# External user password : $PWD_CLIENTLAN"
        echo "#"
        echo "# Internal IP : 10.10.2.18"
        echo "# Internal port : 222"
        echo "# External IP : 10.10.2.210"
        echo "# External port : 222"
        echo "#"
        echo "#########################################################"
}

### Core
initVariables

while ! checkError || test -z $CLIENT ; do
        echo -n "Client name: "
        read CLIENT
        CLIENT=`echo $CLIENT| tr '[:upper:]' '[:lower:]'`
        echo -n "Space needed (M or G): "
        read SPACE
        SPACE=`echo ${SPACE}|tr '[:upper:]' '[:lower:]'|tr -d '[:space:]'`
done

# everything seems to be OK, let's create all stuff
doActions $CLIENT
resume|tee >(mail -s "MESSENGER: creation SFTP" $CONTACT )
