#!/bin/bash

# Customer ID
ID="${1}"
# Name of the Project (namespace)
DISPLAY_NAME="${2}"
# Configure a Development environment for the Project?
ENABLE_DEV=${3}
# Configure a QA environment for the Project?
ENABLE_QA=${4}
# Configure a Production environment for the Project?
ENABLE_PROD=${5}
MODE="${6}"

# Switch between HTML mode and BASH mode
#[[ "${MODE}" != "html" ]] && MODE=""

FORMAT="Incorrect invocation of the 'account_setup' script.  :  account_setup.sh <customer_id> \"<name of the Project>\" <enable DEV? (options: true, false)> <enable QA? (options: true, false)> <enable PROD? (options: true, false)>"

# ERROR CODES
# Code #395 : Could not create Project or cannot connect to the cluster via the 'oc' command.  The user account may also have gotten logged out.
# Code #394 : Could not log into the cluster using the oc command

# Change to lower case
ORIGNAL_PROJECT_NAME="${DISPLAY_NAME,,}"
CUSTOMER_ID="${ID}"
PROJECT_NAME="${CUSTOMER_ID}-${ORIGNAL_PROJECT_NAME}"
# Replace spaces with -
PROJECT_NAME="$(echo ${PROJECT_NAME} | sed 's/ \+/-/g')"
PATH_ORIGINAL_PROJECT_NAME="$(echo ${ORIGNAL_PROJECT_NAME} | sed 's/ \+/-/g')"
ORIGNAL_PROJECT_NAME="$(echo ${ORIGNAL_PROJECT_NAME} | sed 's/ \+/-/g')"


### Account-level groups and accounts
ADMIN_GROUP="admin-group-${CUSTOMER_ID}" # Group has full permissions over all this customer's Projects' dev, qa, and prod environments
ADMIN_USER="admin-user-${CUSTOMER_ID}" # Member of the account-admin-group-N group


function outputMode() {
  THIS_OUTPUT="${1}"
  [[ "${MODE}" == "html" ]] && THIS_OUTPUT="echo \"<pre>${THIS_OUTPUT}</pre>\"" || THIS_OUTPUT="echo \"${THIS_OUTPUT}\""
  eval "${THIS_OUTPUT}"
}


unset DEPLOYMENT_ENVIRONMENT

# ERROR OUT AND PROVIDE MESSAGE
function errorExit () {
    outputMode "Error: $1"
    exit 1
}


function debug() {
  eval "${1}"
}
# EXAMPLE: debug "echo \"here it is\""


[ -z "${ID}" ] && errorExit "${FORMAT}"
[ -z "${DISPLAY_NAME}" ] && errorExit "${FORMAT}"
[ -z "${ENABLE_DEV}" ] && errorExit "${FORMAT}"
[ -z "${ENABLE_QA}" ] && errorExit "${FORMAT}"
[ -z "${ENABLE_PROD}" ] && errorExit "${FORMAT}"

if [[ "${ENABLE_DEV}" == "false" && "${ENABLE_QA}" == "false" && "${ENABLE_PROD}" == "false" ]]; then
  errorExit "No projects will be created.  You must create at least 1 project"
fi


# LOGIN TO CLUSTER
function ocLogin() {
  LOGIN_COMMAND="oc login https://m.okd.supercass.com -u ${OKD_USERNAME} -p ${OKD_PASSWORD} --insecure-skip-tls-verify=true"
  # Error Code #394 - could not log into the OKD cluster using the oc command
  eval "${LOGIN_COMMAND}" > /dev/null && return || errorExit "Unable to process request. Please contact support and provide Error Code #394."
}


outputMode "####################################################"
outputMode "#                                                  #"
outputMode "#  Adding Git Groups, Projects and Users           #"
outputMode "#                                                  #"
outputMode "####################################################"

GIT_TOKEN="kVzRHEy3nzz8EPsZgK_h"
GIT_DOMAIN="git.app.okd.supercass.com"

ADMIN_ID=""
GROUP_ID=""
PROJECT_ID=""


function createGitAdminUser() {
  unset COMMAND
  THIS_ADMIN_USER="${1}"
  COMMAND="http --print=b POST https://${GIT_DOMAIN}/api/v4/users \
     email==cassius.s.adams@gmail.com \
     password==somepass \
     username==${THIS_ADMIN_USER} \
     name==${THIS_ADMIN_USER} \
     private_profile==true \
     skip_confirmation==true \
     PRIVATE-TOKEN:${GIT_TOKEN}"
  COMMAND_RESPONSE=$(eval ${COMMAND})
  ADMIN_ID="$(echo ${COMMAND_RESPONSE} | jq -r .id)"
}

function ensureGitAdminUserExists() {
  THIS_ADMIN_USER="${1}"
  COMMAND="http --print=b GET https://${GIT_DOMAIN}/api/v4/users username==${THIS_ADMIN_USER} PRIVATE-TOKEN:${GIT_TOKEN}"
  POLL_FOR_USER="$(eval ${COMMAND})"
  if [[ "${POLL_FOR_USER}" != "[]" ]]; then
    ADMIN_ID=$(echo ${POLL_FOR_USER} | jq -r ".[].id")
    outputMode "The admin '${THIS_ADMIN_USER}' already exists. Skipping..."
  else
    outputMode "Creating new admin user: ${THIS_ADMIN_USER}"
    createGitAdminUser "${THIS_ADMIN_USER}"
    CREATE_ADMIN_RESPONSE=$?
    [[ ${CREATE_ADMIN_RESPONSE} ]] && outputMode "Created admin user '${THIS_ADMIN_USER}'"; return || errorExit "Unable to create user ${THIS_ADMIN_USER}"
  fi
}



function createGitGroup() {
  unset COMMAND
  THIS_CUSTOMER_ID="${1}"
  COMMAND="http --print=b POST https://${GIT_DOMAIN}/api/v4/groups  \
     name==${THIS_CUSTOMER_ID} \
     path==${THIS_CUSTOMER_ID} \
     visibility==private \
     lfs_enabled==false \
     PRIVATE-TOKEN:${GIT_TOKEN}"
   COMMAND_RESPONSE=$(eval ${COMMAND})
   GROUP_ID="$(echo ${COMMAND_RESPONSE} | jq -r .id)"
}

function ensureGitGroupExists() {
  THIS_CUSTOMER_ID="${1}"
  COMMAND="http --print=b GET https://${GIT_DOMAIN}/api/v4/groups search==${THIS_CUSTOMER_ID} PRIVATE-TOKEN:${GIT_TOKEN}"
  POLL_FOR_GROUP=$(eval ${COMMAND})
  THIS_GROUP_ID=$(echo ${POLL_FOR_GROUP} | jq -r ".[].id")
  if [[ "${THIS_GROUP_ID}" != "" ]]; then
    outputMode "The group '${THIS_CUSTOMER_ID}' already exists. Skipping..."
  else 
    outputMode "Creating new group: ${THIS_CUSTOMER_ID}"
    createGitGroup "${THIS_CUSTOMER_ID}"
    CREATE_GROUP_RESPONSE=$?
    [[ ${CREATE_GROUP_RESPONSE} ]] && outputMode "Created group '${THIS_CUSTOMER_ID}'"; return || errorExit "Unable to create group ${THIS_CUSTOMER_ID}"
  fi
  GROUP_ID="${THIS_GROUP_ID}"
}




function addUserToGitGroup() {
  unset COMMAND
  THIS_USER_ID="${1}"
  THIS_GROUP_ID="${2}"
  COMMAND="http --print=b POST https://${GIT_DOMAIN}/api/v4/groups/${THIS_GROUP_ID}/members \
     user_id==${THIS_USER_ID} \
     access_level==50 \
     PRIVATE-TOKEN:${GIT_TOKEN}"
  COMMAND_RESPONSE=$(eval ${COMMAND})
  #echo "COMMAND_RESPONSE=${COMMAND_RESPONSE}"
}

function ensureUserInGroup() {
  THIS_ADMIN_ID="${1}"
  THIS_GROUP_ID="${2}"
  COMMAND="http --print=b GET https://${GIT_DOMAIN}/api/v4/groups/${THIS_GROUP_ID}/members/${THIS_ADMIN_ID} PRIVATE-TOKEN:${GIT_TOKEN}"
  POLL_FOR_USER_IN_GROUP=$(eval ${COMMAND})
  POLL_RESULT=$(echo ${POLL_FOR_USER_IN_GROUP})
  if [[ "${POLL_RESULT}" != *"404"* ]]; then
    outputMode "The group '${CUSTOMER_ID}' already has user '${ADMIN_USER}'. Skipping..."
  else
    outputMode "Adding user ${ADMIN_USER} as a member of group: ${CUSTOMER_ID}"
    addUserToGitGroup "${THIS_ADMIN_ID}" "${THIS_GROUP_ID}"
    ADD_MEMBER_TO_GROUP_RESPONSE=$?
    [[ ${ADD_MEMBER_TO_GROUP_RESPONSE} ]] && outputMode "Added the user '${ADMIN_USER}' to the group '${CUSTOMER_ID}'"; return || errorExit "Unable to add ${THIS_ADMIN_ID} to group ${THIS_GROUP_ID}"
  fi
}



function addProjectToGit() {
  unset COMMAND
  THIS_PATH_ORIGINAL_PROJECT_NAME="${1}"
  COMMAND="http --print=b POST https://${GIT_DOMAIN}/api/v4/projects \
     name=='${DISPLAY_NAME}' \
     path==${THIS_PATH_ORIGINAL_PROJECT_NAME} \
     namespace_id==${GROUP_ID} \
     visibility==private \
     lfs_enabled==false \
     container_registry_enabled==true \
     PRIVATE-TOKEN:${GIT_TOKEN}"
  COMMAND_RESPONSE=$(eval ${COMMAND})
  PROJECT_ID="$(echo ${COMMAND_RESPONSE} | jq -r .id)"
}

function ensureProjectExists() {
  THIS_PATH_ORIGINAL_PROJECT_NAME="${1}"
  THIS_DISPLAY_NAME="${2}"
  COMMAND="http --print=b GET https://${GIT_DOMAIN}/api/v4/projects search==${THIS_PATH_ORIGINAL_PROJECT_NAME} PRIVATE-TOKEN:${GIT_TOKEN}"
  POLL_FOR_PROJECT=$(eval ${COMMAND})
  if [[ "${POLL_FOR_PROJECT}" != "[]" ]]; then
    PROJECT_ID=$(echo ${POLL_FOR_PROJECT} | jq -r ".[0].id")
    outputMode "The project '${THIS_PATH_ORIGINAL_PROJECT_NAME}' already exists. Skipping..."
  else
    outputMode "Adding project ${THIS_DISPLAY_NAME}."
    addProjectToGit "${THIS_PATH_ORIGINAL_PROJECT_NAME}"
    ADD_PROJECT_RESPONSE=$?
    [[ ${ADD_PROJECT_RESPONSE} ]] && outputMode "Added the Project '${THIS_DISPLAY_NAME}'"; return || errorExit "Unable to add Project ${THIS_DISPLAY_NAME}."
  fi
}





function createGitDeployKey() {
  unset COMMAND
  THIS_PROJECT_ID="${1}"
  THIS_SECRET="${2}"
  THIS_PROJECT_NAMESPACE="${3}"
  ocLogin
  THIS_SECRET_PUBLIC_KEY=$(oc get secrets ${THIS_SECRET} -o=jsonpath='{.data.ssh-publickey}' -n ${THIS_PROJECT_NAMESPACE} | base64 -d)
  COMMAND="http --print=b POST https://${GIT_DOMAIN}/api/v4/projects/${THIS_PROJECT_ID}/deploy_keys  \
     title==${THIS_SECRET} \
     key=='${THIS_SECRET_PUBLIC_KEY}' \
     can_push==false \
     PRIVATE-TOKEN:${GIT_TOKEN}"
   COMMAND_RESPONSE=$(eval ${COMMAND})
   CREATION_DATE="$(echo ${COMMAND_RESPONSE} | jq -r .created_at)"
}

function ensureGitDeployKey() {
  THIS_PROJECT_ID="${1}"
  THIS_SECRET="${2}"
  THIS_PROJECT_NAMESPACE="${3}"
  COMMAND="http --print=b GET https://${GIT_DOMAIN}/api/v4/projects/${THIS_PROJECT_ID}/deploy_keys PRIVATE-TOKEN:${GIT_TOKEN}"
  POLL_FOR_DEPLOY_KEYS=$(eval ${COMMAND})
  THIS_DEPLOY_KEY_ID=$(echo ${POLL_FOR_DEPLOY-KEYS} | jq -r '.[] | select(.title=="${THIS_SECRET}") | .id')
  if [[ "${THIS_DEPLOY_KEY_ID}" != "" ]]; then
    outputMode "The deployment key ${THIS_SECRET} already exists. Skipping..."
  else
    outputMode "Creating new deploy key: ${THIS_SECRET}"
    createGitDeployKey "${THIS_PROJECT_ID}" "${THIS_SECRET}" "${THIS_PROJECT_NAMESPACE}"
    CREATE_DEPLOY_KEY_RESPONSE=$?
    [[ ${CREATE_DEPLOY_KEY_RESPONSE} ]] && outputMode "Created deploy key '${THIS_SECRET}'"; return || errorExit "Unable to create deploy key ${THIS_SECRET}"
  fi
}








ensureGitAdminUserExists "${ADMIN_USER}"
ensureGitGroupExists "${CUSTOMER_ID}"
ensureUserInGroup "${ADMIN_ID}" "${GROUP_ID}"
ensureProjectExists "${PATH_ORIGINAL_PROJECT_NAME}" "${DISPLAY_NAME}"


if [[ "${ENABLE_DEV}" == true ]]; then
  ensureGitDeployKey "${PROJECT_ID}" "builder-key-dev" "${CUSTOMER_ID}-${PATH_ORIGINAL_PROJECT_NAME}-dev"
fi


if [[ "${ENABLE_QA}" == true ]]; then
  outputMode "QA is enabled"
  ensureGitDeployKey "${PROJECT_ID}" "builder-key-qa" "${CUSTOMER_ID}-${PATH_ORIGINAL_PROJECT_NAME}-qa"
fi


if [[ "${ENABLE_PROD}" == true ]]; then
  outputMode "PROD is enabled"
fi


outputMode "Done Git stuff"


#echo "ADMIN_ID=${ADMIN_ID}"
#echo "GROUP_ID=${GROUP_ID}"




