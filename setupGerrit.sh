#!/bin/bash
set -e

HOST_NAME=${HOST_NAME:-$1}
GERRIT_WEBURL=${GERRIT_WEBURL:-$2}
GERRIT_ADMIN_UID=${GERRIT_ADMIN_UID:-$3}
GERRIT_ADMIN_PWD=${GERRIT_ADMIN_PWD:-$4}
GERRIT_ADMIN_EMAIL=${GERRIT_ADMIN_EMAIL:-$5}
SSH_KEY_PATH=${SSH_KEY_PATH:-~/.ssh/id_rsa}
SSH_KNOWN_HOSTS=~/.ssh/known_hosts
CHECKOUT_DIR=./git-tmp


#Remove appended '/' if existed.
GERRIT_WEBURL=${GERRIT_WEBURL%/}

# Add ssh-key
cat "${SSH_KEY_PATH}.pub" | curl --data @- --user "${GERRIT_ADMIN_UID}:${GERRIT_ADMIN_PWD}"  ${GERRIT_WEBURL}/a/accounts/self/sshkeys

# Create project-with-verification 
# TODO: not tested
./createProject.sh project-with-verification $GERRIT_ADMIN_UID $GERRIT_ADMIN_PWD $GERRIT_ADMIN_EMAIL $GERRIT_WEBURL "http://$GERRIT_WEBURL" Administrators $SSH_KEY_PATH $SSH_KNOWN_HOSTS

#gather server rsa key
##TODO: This is not an elegant way.
[ -f $SSH_KNOWN_HOSTS ] && mv $SSH_KNOWN_HOSTS $SSH_KNOWN_HOSTS.bak
ssh-keyscan -p 29418 -t rsa ${HOST_NAME} > $SSH_KNOWN_HOSTS

#start ssh agent and add ssh key
eval $(ssh-agent)
ssh-add "${SSH_KEY_PATH}"

#checkout project.config from All-Project.git
[ -d ${CHECKOUT_DIR} ] && mv ${CHECKOUT_DIR}  ${CHECKOUT_DIR}.$$
mkdir ${CHECKOUT_DIR}

git init ${CHECKOUT_DIR}
cd ${CHECKOUT_DIR}

#git config
git config user.name  ${GERRIT_ADMIN_UID}
git config user.email ${GERRIT_ADMIN_EMAIL}
git remote add origin ssh://${GERRIT_ADMIN_UID}@${HOST_NAME}:29418/All-Projects
#checkout project.config
git fetch -q origin refs/meta/config:refs/remotes/origin/meta/config
git checkout meta/config

#Change global access right
##Remove anonymous access right.
git config -f project.config --unset access.refs/*.read "group Anonymous Users"
##add Jenkins access
git config -f project.config --add access.refs/heads/*.read "group Non-Interactive Users"
git config -f project.config --add access.refs/tags/*.read "group Non-Interactive Users"
##commit and push back
git commit -a -m "Add access right for Jenkins. Remove anonymous access right"
git push origin meta/config:meta/config

cd -
rm -rf ${CHECKOUT_DIR}
[ -d ${CHECKOUT_DIR}.$$ ] && mv ${CHECKOUT_DIR}.$$  ${CHECKOUT_DIR}

###########################################################################################################

#checkout project.config from All-Project.git
[ -d ${CHECKOUT_DIR} ] && mv ${CHECKOUT_DIR}  ${CHECKOUT_DIR}.$$
mkdir ${CHECKOUT_DIR}

git init ${CHECKOUT_DIR}
cd ${CHECKOUT_DIR}

#git config
git config user.name  ${GERRIT_ADMIN_UID}
git config user.email ${GERRIT_ADMIN_EMAIL}
git remote add origin ssh://${GERRIT_ADMIN_UID}@${HOST_NAME}:29418/project-with-verification
#checkout project.config
git fetch -q origin refs/meta/config:refs/remotes/origin/meta/config
git checkout meta/config

cat <<EOF > project.config
[access]
    inheritFrom = All-Projects
[access "refs/heads/*"]
    label-Verified = -1..+1 group Non-Interactive Users
    label-Verified = -1..+1 group Project Owners
    label-Presubmit-Ready = 0..+1 group Non-Interactive Users
    label-Presubmit-Ready = 0..+1 group Project Owners
    label-Presubmit-Ready = 0..+1 group Administrators
    label-Presubmit-Ready = 0..+1 group Registered Users
[label "Presubmit-Ready"]
    function = MaxWithBlock
    defaultValue = 0
    value = 0
    value = +1 Ready for tests
[label "Verified"]
    function = MaxWithBlock
    defaultValue = 0
    value = -1 Failed
    value = 0 No score
    value = +1 Verified
    copyMinScore = false
EOF

##commit and push back
git commit -a -m "Change access right."
git push origin meta/config:meta/config

cd -
rm -rf ${CHECKOUT_DIR}
[ -d ${CHECKOUT_DIR}.$$ ] && mv ${CHECKOUT_DIR}.$$  ${CHECKOUT_DIR}

#stop ssh agent
kill ${SSH_AGENT_PID}

rm -rf ./git-tmp
echo "Finish gerrit setup"
