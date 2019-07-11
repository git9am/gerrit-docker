#!/bin/bash
set -e

PROJECT_NAME=$1
LDAP_ADMIN_UID=$2
LDAP_ADMIN_PWD=$3
LDAP_ADMIN_EMAIL=$4
GERRIT_WEBURL=$5
GERRIT_WEBURL_WITH_PROTOCOL=$6
GROUP=$7
SSH_KEY_PATH=~/.ssh/id_rsa
SSH_KNOWN_HOSTS=~/.ssh/known_hosts

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# Update the ssh known host list
echo "*** Updating ssh known host list..."
[ -f ${SSH_KNOWN_HOSTS} ] && mv ${SSH_KNOWN_HOSTS} ${SSH_KNOWN_HOSTS}.bak
ssh-keyscan -p 29418 -t rsa ${GERRIT_WEBURL} > ${SSH_KNOWN_HOSTS}

# Create a project on Gerrit.
echo "*** Creating Gerrit project..."
curl --request PUT --user "${LDAP_ADMIN_UID}:${LDAP_ADMIN_PWD}" -d@- --header "Content-Type: application/json;charset=UTF-8" ${GERRIT_WEBURL}/a/projects/${PROJECT_NAME} < ${DIR}/config.template.json
sleep 3

# Create the target group if necessary.
echo "*** Ensuing group exists..."
echo $( ssh -p 29418 -i ${SSH_KEY_PATH} ${GERRIT_WEBURL} -l ${LDAP_ADMIN_UID} gerrit create-group "${GROUP}" 2>&1 )
GROUP_ID=$( ssh -p 29418 -i ${SSH_KEY_PATH} ${GERRIT_WEBURL} -l ${LDAP_ADMIN_UID} gerrit ls-groups -v | awk '-F\t' '$1 == "'${GROUP}'" {print $2}' )
ADMIN_GROUP_ID=$( ssh -p 29418 -i ${SSH_KEY_PATH} ${GERRIT_WEBURL} -l ${LDAP_ADMIN_UID} gerrit ls-groups -v | awk '-F\t' '$1 == "Administrators" {print $2}' )

# Setup local git.
echo "*** Setting up local git..."
rm -rf ${DIR}/${PROJECT_NAME}
mkdir ${DIR}/${PROJECT_NAME}
git init ${DIR}/${PROJECT_NAME}
cd ${DIR}/${PROJECT_NAME}

#start ssh agent and add ssh key
echo "*** Configuring group accesses..."
eval $(ssh-agent)
ssh-add "${SSH_KEY_PATH}"

git config core.filemode false
git config user.name  ${LDAP_ADMIN_UID}
git config user.email ${LDAP_ADMIN_EMAIL}
git config push.default simple
git remote add origin ssh://${LDAP_ADMIN_UID}@${GERRIT_WEBURL}:29418/${PROJECT_NAME}
git fetch -q origin
git fetch -q origin refs/meta/config:refs/remotes/origin/meta/config

# Setup project access right.
## Registered users can change everything since it's just a project.
git checkout meta/config
cat > groups <<EOF
# UUID                                          Group Name
#
${ADMIN_GROUP_ID}	Administrators
${GROUP_ID}	${GROUP}
EOF
cp ${DIR}/project.config ./
sed -i -- "s/{GROUP_NAME}/${GROUP}/g" project.config
git add groups project.config
git commit -m "Add access right to ${GROUP}."
git push origin meta/config:meta/config

git checkout master
cat > .gitreview <<EOF
[gerrit]
host=${GERRIT_WEBURL}
port=29418
project=${PROJECT_NAME}
EOF
git add .gitreview
git commit -m "Init project"
git push origin

#stop ssh agent
kill ${SSH_AGENT_PID}
mv ${SSH_KNOWN_HOSTS}.bak ${SSH_KNOWN_HOSTS}

# Remove local git repository.
cd -
rm -rf ${DIR}/${PROJECT_NAME}
echo "Project \"${PROJECT_NAME}\" created."
