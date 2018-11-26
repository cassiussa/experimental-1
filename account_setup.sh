#!/bin/bash

ID="${1}"
# ERROR CODES
# Code #395 : Could not create Project or cannot connect to the cluster via the 'oc' command.  The user account may also have gotten logged out.
# Code #394 : Could not log into the cluster using the oc command

DISPLAY_NAME="Tester    Project a"
# Change to lower case
ORIGNAL_PROJECT_NAME="${DISPLAY_NAME,,}"
# Temporarily generate a random customer ID
#CUSTOMER_ID="$(shuf -i 123700-250000 -n 1)"
CUSTOMER_ID="${ID}"
PROJECT_NAME="${CUSTOMER_ID}-${ORIGNAL_PROJECT_NAME}"
# Replace spaces with -
PROJECT_NAME="$(echo ${PROJECT_NAME} | sed 's/ \+/-/g')"


### Account-level groups and accounts
ADMIN_GROUP="admin-group-${CUSTOMER_ID}" # Group has full permissions over all this customer's Projects' dev, qa, and prod environments
ADMIN_USER="admin-user-${CUSTOMER_ID}" # Member of the account-admin-group-N group
PROD_GROUP="prod-group-${CUSTOMER_ID}" # Group that can perform PROD-environment functions accross all Projects owned by this customer
QA_GROUP="qa-group-${CUSTOMER_ID}" #Group that can perform QA-environment functions accross all Projects owned by this customer
DEV_GROUP="dev-group-${CUSTOMER_ID}" #Group that can perform DEV-environment functions accross all Projects owned by this customer
### Project-level groups and accounts
PROJECT_ADMIN_GROUP="admin-group-${PROJECT_NAME}" # Group has full permissions over the dev, qa, prod Projects for this Project
PROJECT_PROD_GROUP="prod-group-${PROJECT_NAME}"
PROJECT_QA_GROUP="qa-group-${PROJECT_NAME}"
PROJECT_DEV_GROUP="dev-group-${PROJECT_NAME}"

echo
echo 
echo "ACCOUNT-LEVEL USERS"
echo "======================================================================================================"
echo "ADMIN USER  : ${ADMIN_USER}  : An admin user with full permissions over all Projects you own"
echo
echo "ACCOUNT-LEVEL GROUPS"
echo "======================================================================================================"
echo "ADMIN GROUP : ${ADMIN_GROUP} : This group has admin permissions on all Projects you own"
echo "PROD GROUP  : ${PROD_GROUP}  : If SysOps are responsible for Production environments in all Project, add them to this group"
echo "QA GROUP    : ${QA_GROUP}    : If QA staff are responsible for QA environments in all Projects, add them to this group"
echo "DEV GROUP   : ${DEV_GROUP}   : If developers are responsible for DEV environments in all Projects, add them to this group"
echo 
echo "PROJECT-LEVEL GROUPS"
echo "======================================================================================================"
echo "PROJECT ADMIN GROUP : ${PROJECT_ADMIN_GROUP} : This group has admin permissions of this Project only."
echo "PROJECT PROD GROUP  : ${PROJECT_PROD_GROUP}  : If SysOps are reponsible for Production environments only at the Project-level, add them to this group."
echo "PROJECT QA GROUP    : ${PROJECT_QA_GROUP}    : If QA staff are reponsible for QA environments only at the Project-level, add them to this group."
echo "PROJECT DEV GROUP   : ${PROJECT_DEV_GROUP}   : If DEV staff are reponsible for DEV environments only at the Project-level, add them to this group."
echo
echo
echo


ENABLE_DEV=${2}
ENABLE_QA=${3}
ENABLE_PROD=${4}

unset DEPLOYMENT_ENVIRONMENT

# ERROR OUT AND PROVIDE MESSAGE
function errorExit () {
    echo "Error: $1"
    exit 1
}




# LOGIN TO CLUSTER
function ocLogin() {
  LOGIN_COMMAND="oc login https://m.okd.supercass.com -u 7l-networks-bot -p somepass --insecure-skip-tls-verify=true"
  # Error Code #394 - could not log into the OKD cluster using the oc command
  eval ${LOGIN_COMMAND} > /dev/null && return || errorExit "Unable to process request. Please contact support and provide Error Code #394."
}


# RETRY COMMAND INSTEAD OF JUST FAILING FIRST ATTEMPT
# Accepts 3 parameters: ${1} Number of retries, ${2} time between retries, ${3} command to run
function retryCommand() {
  # Iterate over the number of retries passed into the retryCommand function as 1st parameter
  for retries in $(seq 1 $(echo "${1}")); do
    # Log into the cluster
    ocLogin
    # Run the command ${3} parameter.  If it succeeds, return from function.  Otherwise echo failed and then retry ${1} number of times
    eval ${3} > /dev/null 2>&1 && return 
    #echo "Attempt ${retries} of ${1} failed to create '${3}'."
    [[ "${retries}" > 1 ]] && echo "Trying again in ${2} seconds"
    sleep ${2}
    # Exit out completely if we've failed to run the command ${1} times
    # Error Code #395 - Can't create Project, Project exists already, or cannot connect to the cluster via the 'oc' command.  The scipt's account may also have gotten logged out.
    [[ "${retries}" == "${1}" ]] && return 1
  done
}




function createAdminUser() {
  ocLogin
  unset COMMAND
  THIS_ADMIN_USER=${1}
  THIS_FULL_NAME=${2}
  COMMAND="oc create user ${THIS_ADMIN_USER} --full-name=\"${THIS_FULL_NAME}\""
  eval ${COMMAND} > /dev/null && return
}

function ensureAdminUserExist() {
  echo "function ensureAdminUserExist"
  THIS_USER="${1}"
  POLL_FOR_USER="oc get user ${THIS_USER}"
  echo "See if admin  user exists.  If not, create it"
  retryCommand "1" "3" "${POLL_FOR_USER}"
  POLL_FOR_USER_RESPONSE=$?
  if [[ "${POLL_FOR_USER_RESPONSE}" == 0 ]]; then
    echo "The admin user '${THIS_USER}' already exists"
    return
  else 
    echo "Creating new user: ${THIS_USER}"
    createAdminUser ${THIS_USER} "some full name here"
    CREATE_ADMIN_USER_RESPONSE=$?
    [[ ${CREATE_ADMIN_USER_RESPONSE} ]] && echo "Created admin user '${THIS_USER}'"; return || errorExit "Unable to create user ${THIS_USER}"
  fi
}

ensureAdminUserExist ${ADMIN_USER}

function createAdminGroup() {
  ocLogin
  unset COMMAND
  THIS_ADMIN_GROUP=${1}
  COMMAND="oc adm groups new ${THIS_ADMIN_GROUP}"
  eval ${COMMAND} > /dev/null && return
}


function ensureAdminGroupExists() {
  echo "function ensureAdminGroupExists"
  THIS_ADMIN_GROUP="${1}"
  POLL_FOR_GROUP="oc get group ${THIS_ADMIN_GROUP}"
  echo "Verify the admin group exist.  If not, create it"
  retryCommand "1" "3" "${POLL_FOR_GROUP}"
  POLL_FOR_GROUP_RESPONSE=$?
  if [[ "${POLL_FOR_GROUP_RESPONSE}" == 0 ]]; then
    echo "The admin group '${THIS_ADMIN_GROUP}' already exists"
    return
  else
    echo "Creating new group: ${THIS_ADMIN_GROUP}"
    createAdminGroup ${THIS_ADMIN_GROUP}
    CREATE_ADMIN_GROUP_RESPONSE=$?
    [[ ${CREATE_ADMIN_GROUP_RESPONSE} ]] && echo "Created admin group '${THIS_ADMIN_GROUP}'"; return || errorExit "Unable to create group ${THIS_ADMIN_GROUP}"
  fi
}

ensureAdminGroupExists ${ADMIN_GROUP}



function createProject() {
  ocLogin
  unset COMMAND
  THIS_PROJECT_NAME=${1}
  THIS_DEPLOYMENT_ENVIRONMENT=${2}
  THIS_DISPLAY_NAME=${3}
  THIS_DESCRIPTION=${4}
  COMMAND="oc new-project ${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT} --description='${THIS_DESCRIPTION}' --display-name='${THIS_DISPLAY_NAME} - ${THIS_DEPLOYMENT_ENVIRONMENT}'"
  eval ${COMMAND} > /dev/null && return
}

# CREATE NEW PROJECT
function ensureProjectExists() {
  echo "function ensureProjectExists"
  THIS_DEPLOYMENT_ENVIRONMENT="${1}"
  THIS_PROJECT_NAME="${2}"
  THIS_DISPLAY_NAME="${3}"
  THIS_DESCRIPTION="${THIS_DEPLOYMENT_ENVIRONMENT} environment for the \"${THIS_DISPLAY_NAME}\" Project.'"
  # Make the PROD environment in CAPITAL letters to distiguish it visually from other environments
  [ "${THIS_DEPLOYMENT_ENVIRONMENT}" == "prod" ] && THIS_DESCRIPTION="${THIS_DESCRIPTION^^}"

  POLL_FOR_PROJECT="oc get project ${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT}"
  echo "Verify the '${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT}' Project exist.  If not, create it"
  retryCommand "1" "3" "${POLL_FOR_PROJECT}"
  POLL_FOR_PROJECT_RESPONSE=$?
  if [[ "${POLL_FOR_PROJECT_RESPONSE}" == 0 ]]; then
    echo "The Project '${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT}' already exists"
    return
  else
    echo "Creating new Project: ${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT}"
    createProject ${THIS_PROJECT_NAME} ${THIS_DEPLOYMENT_ENVIRONMENT} ${THIS_DISPLAY_NAME} ${THIS_DESCRIPTION}
    CREATE_PROJECT_RESPONSE=$?
    [[ ${CREATE_PROJECT_RESPONSE} ]] && echo "Created Project '${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT}'"; return || errorExit "Unable to create the Project.  Please contact support and provide Error Code #395."
  fi
}



function ensureAdminGroupPermissions() {
  echo "ensureAdminGroupPermissions"
  ocLogin
  unset COMMAND
  THIS_DEPLOYMENT_ENVIRONMENT="${1}"
  THIS_PROJECT_NAME="${2}"
  THIS_ADMIN_GROUP="${3}"
  echo "Set permissions for the '${THIS_ADMIN_GROUP}' Group"
  COMMAND="oc adm policy add-role-to-group admin ${THIS_ADMIN_GROUP} -n ${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT}"
  retryCommand "1" "3" ${COMMAND}
  COMMAND_RESPONSE=$?
  if [[ "${COMMAND_RESPONSE}" == 0 ]]; then
    echo "Added administrative permissions to the '${THIS_ADMIN_GROUP}' Group on the '${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT}' Project"
    return
  else
    errorExit "Failed to grant administrative permissions to the '${THIS_ADMIN_GROUP}' Group on the '${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT}' Project"
  fi
}



if [[ "${ENABLE_DEV}" == true ]]; then
  ensureProjectExists "dev" ${PROJECT_NAME} ${DISPLAY_NAME}
  ensureAdminGroupPermissions "dev" ${PROJECT_NAME} ${ADMIN_GROUP}
fi
if [[ "${ENABLE_QA}" == true ]]; then
  ensureProjectExists "qa" ${PROJECT_NAME} ${DISPLAY_NAME}
  ensureAdminGroupPermissions "qa" ${PROJECT_NAME} ${ADMIN_GROUP}
fi
if [[ "${ENABLE_PROD}" == true ]]; then
  ensureProjectExists "prod" ${PROJECT_NAME} ${DISPLAY_NAME}
  ensureAdminGroupPermissions "prod" ${PROJECT_NAME} ${ADMIN_GROUP}
fi






exit 1



