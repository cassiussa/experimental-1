#!/bin/bash

APP_DOMAIN="app.okd.supercass.com"
ACCOUNTS_PREFIX="accounts"
GIT_PREFIX="git"

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
ORIGINAL_PROJECT_NAME="${DISPLAY_NAME,,}"
CUSTOMER_ID="${ID}"
PROJECT_NAME="${CUSTOMER_ID}-${ORIGINAL_PROJECT_NAME}"
# Replace spaces with -
PROJECT_NAME="$(echo ${PROJECT_NAME} | sed 's/ \+/-/g')"
ORIGINAL_PROJECT_NAME="$(echo ${ORIGINAL_PROJECT_NAME} | sed 's/ \+/-/g')"


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


function outputMode() {
  THIS_OUTPUT="${1}"
  [[ "${MODE}" == "html" ]] && THIS_OUTPUT="echo \"<pre>${THIS_OUTPUT}</pre>\"" || THIS_OUTPUT="echo \"${THIS_OUTPUT}\""
  eval "${THIS_OUTPUT}"
}

outputMode " "
outputMode " "
outputMode "ACCOUNT-LEVEL USERS"
outputMode "======================================================================================================"
outputMode "ADMIN USER  : ${ADMIN_USER}  : An admin user with full permissions over all Projects you own"
outputMode " "
outputMode "ACCOUNT-LEVEL GROUPS"
outputMode "======================================================================================================"
outputMode "ADMIN GROUP : ${ADMIN_GROUP} : This group has admin permissions on all Projects you own"
outputMode "PROD GROUP  : ${PROD_GROUP}  : If SysOps are responsible for Production environments in all Project, add them to this group"
outputMode "QA GROUP    : ${QA_GROUP}    : If QA staff are responsible for QA environments in all Projects, add them to this group"
outputMode "DEV GROUP   : ${DEV_GROUP}   : If developers are responsible for DEV environments in all Projects, add them to this group"
outputMode " "
outputMode "PROJECT-LEVEL GROUPS"
outputMode "======================================================================================================"
outputMode "PROJECT ADMIN GROUP : ${PROJECT_ADMIN_GROUP} : This group has admin permissions of this Project only."
outputMode "PROJECT PROD GROUP  : ${PROJECT_PROD_GROUP}  : If SysOps are reponsible for Production environments only at the Project-level, add them to this group."
outputMode "PROJECT QA GROUP    : ${PROJECT_QA_GROUP}    : If QA staff are reponsible for QA environments only at the Project-level, add them to this group."
outputMode "PROJECT DEV GROUP   : ${PROJECT_DEV_GROUP}   : If DEV staff are reponsible for DEV environments only at the Project-level, add them to this group."
outputMode " "
outputMode " "
outputMode " "




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


# RETRY COMMAND INSTEAD OF JUST FAILING FIRST ATTEMPT
# Accepts 3 parameters: ${1} Number of retries, ${2} time between retries, ${3} command to run
function retryCommand() {
  # Iterate over the number of retries passed into the retryCommand function as 1st parameter
  for retries in $(seq 1 $(echo "${1}")); do
    # Log into the cluster
    ocLogin
    # Run the command ${3} parameter.  If it succeeds, return from function.  Otherwise echo failed and then retry ${1} number of times
    eval ${3} > /dev/null 2>&1 && return 
    #eval ${3} && return
    [[ "${retries}" > 1 ]] && outputMode "Trying again in ${2} seconds"
    sleep ${2}
    # Exit out completely if we've failed to run the command ${1} times
    # Error Code #395 - Can't create Project, Project exists already, or cannot connect to the cluster via the 'oc' command.  The scipt's account may also have gotten logged out.
    [[ "${retries}" == "${1}" ]] && return 1
  done
}

function createAdminUser() {
  ocLogin
  unset COMMAND
  THIS_ADMIN_USER="${1}"
  THIS_FULL_NAME="${2}"
  COMMAND="oc create user ${THIS_ADMIN_USER} --full-name='${THIS_FULL_NAME}'"
  eval "${COMMAND}" > /dev/null && return
}


function ensureAdminUserExist() {
  #outputMode "function ensureAdminUserExist"
  THIS_USER="${1}"
  POLL_FOR_USER="oc get user ${THIS_USER}"
  #outputMode "See if admin  user exists.  If not, create it"
  retryCommand "1" "3" "${POLL_FOR_USER}"
  POLL_FOR_USER_RESPONSE=$?
  if [[ "${POLL_FOR_USER_RESPONSE}" == 0 ]]; then
    outputMode "The admin user '${THIS_USER}' already exists. Skipping..."
    return
  else 
    outputMode "Creating new user: ${THIS_USER}"
    createAdminUser "${THIS_USER}" "some full name here"
    CREATE_ADMIN_USER_RESPONSE=$?
    [[ ${CREATE_ADMIN_USER_RESPONSE} ]] && outputMode "Created admin user '${THIS_USER}'"; return || errorExit "Unable to create user ${THIS_USER}"
  fi
}


function labelObject() {
  THIS_OBJECT_TYPE="${1}"
  THIS_OBJECT="${2}"
  THIS_KEY="${3}"
  THIS_VALUE="${4}"
  # ex: oc label <user> <username> <customerid>=<123111> --overwrite=true
  COMMAND="oc label ${THIS_OBJECT_TYPE} ${THIS_OBJECT} ${THIS_KEY}=${THIS_VALUE} --overwrite=true"
  retryCommand "1" "3" "${COMMAND}"
  COMMAND_RESPONSE=$?
  if [[ "${COMMAND_RESPONSE}" == 0 ]]; then
    outputMode "Labeled ${THIS_OBJECT_TYPE}"
  else
    errorExit "Error Code #393 - failed to label user."
  fi
}


function annotateObject() {
  unset THIS_OBJECT_TYPE
  unset THIS_OBJECT
  unset THIS_KEY
  unset THIS_VALUE
  unset ANNOTATE_COMMAND
  unset EXISTING_ANNOTATION
  unset ANNOTATE_COMMAND_RESPONSE

  THIS_OBJECT_TYPE="${1}"
  THIS_OBJECT="${2}"
  THIS_KEY="${3}"
  # The space at the end of the next line is on purpose
  THIS_VALUE="${4} "
  OVERWRIITE=""

  COMMAND="oc get ${THIS_OBJECT_TYPE} ${THIS_OBJECT} -o template --template '{{ index .metadata.annotations \"${THIS_KEY}\" }}'"
  retryCommand "1" "3" "${COMMAND}"
  COMMAND_RESPONSE=$?
  if [[ "${COMMAND_RESPONSE}" == 0 ]]; then
    EXISTING_ANNOTATION=$(eval ${COMMAND})
    if [[ "${EXISTING_ANNOTATION}" == "<no value>" ]]; then
      THIS_VALUE="${THIS_VALUE}"
    elif [[ "${EXISTING_ANNOTATION}" == *"${THIS_VALUE}"* ]]; then
      THIS_VALUE="${EXISTING_ANNOTATION}"
    else
      THIS_VALUE="${EXISTING_ANNOTATION} ${THIS_VALUE}"
    fi
    OVERWRITE="--overwrite=true"
  fi
  ANNOTATE_COMMAND="oc annotate ${THIS_OBJECT_TYPE} ${THIS_OBJECT} ${OVERWRITE} ${THIS_KEY}='${THIS_VALUE}'"

  retryCommand "1" "3" "${ANNOTATE_COMMAND}"
  ANNOTATE_COMMAND_RESPONSE=$?
  if [[ "${ANNOTATE_COMMAND_RESPONSE}" == 0 ]]; then
    return
  else
    errorExit "Error Code #396 - Could not add annotation to ${THIS_OBJECT_TYPE} ${THIS_OBJECT}."
  fi
}



function createAdminGroup() {
  ocLogin
  unset COMMAND
  THIS_ADMIN_GROUP=${1}
  COMMAND="oc adm groups new ${THIS_ADMIN_GROUP}"
  eval ${COMMAND} > /dev/null && return
}


function ensureAdminGroupExists() {
  #outputMode "function ensureAdminGroupExists"
  THIS_GROUP="${1}"
  POLL_FOR_GROUP="oc get group ${THIS_GROUP}"
  #outputMode "Verify the admin group exist.  If not, create it"
  retryCommand "1" "3" "${POLL_FOR_GROUP}"
  POLL_FOR_GROUP_RESPONSE=$?
  if [[ "${POLL_FOR_GROUP_RESPONSE}" == 0 ]]; then
    outputMode "The admin group '${THIS_GROUP}' already exists. Skipping..."
    return
  else
    outputMode "Creating new group: ${THIS_GROUP}"
    createAdminGroup "${THIS_GROUP}"
    CREATE_GROUP_RESPONSE=$?
    [[ ${CREATE_GROUP_RESPONSE} ]] && outputMode "Created admin group '${THIS_GROUP}'"; return || errorExit "Unable to create group ${THIS_GROUP}"
  fi
}



function createProject() {
  ocLogin
  unset COMMAND
  THIS_PROJECT_NAME=${1}
  THIS_DEPLOYMENT_ENVIRONMENT=${2}
  THIS_DISPLAY_NAME=${3}
  THIS_DESCRIPTION=${4}
  COMMAND="oc new-project ${THIS_PROJECT_NAME,,}-${THIS_DEPLOYMENT_ENVIRONMENT,,} --description='${THIS_DESCRIPTION}' --display-name='${THIS_DISPLAY_NAME} - ${THIS_DEPLOYMENT_ENVIRONMENT^^}'"
  eval ${COMMAND} > /dev/null && return
}

# CREATE NEW PROJECT
function ensureProjectExists() {
  #outputMode "function ensureProjectExists"
  unset THIS_DEPLOYMENT_ENVIRONMENT
  unset THIS_DISPLAY_NAME
  unset THIS_DESCRIPTION
  THIS_DEPLOYMENT_ENVIRONMENT=${1}
  THIS_PROJECT_NAME=${2}
  THIS_DISPLAY_NAME=${3}
  THIS_DESCRIPTION="${THIS_DEPLOYMENT_ENVIRONMENT^^} environment for the \"${THIS_DISPLAY_NAME}\" Project."
  # Make the PROD environment in CAPITAL letters to distiguish it visually from other environments
  if [ "${THIS_DEPLOYMENT_ENVIRONMENT}" == "prod" ]; then
    THIS_DEPLOYMENT_ENVIRONMENT="${THIS_DEPLOYMENT_ENVIRONMENT^^}"
    THIS_DISPLAY_NAME="${THIS_DISPLAY_NAME^^}"
    THIS_DESCRIPTION="${THIS_DESCRIPTION^^}"
  fi

  POLL_FOR_PROJECT="oc get project ${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT,,}"
  #outputMode "Verify the '${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT}' Project exist.  If not, create it"
  retryCommand "1" "3" "${POLL_FOR_PROJECT}"
  POLL_FOR_PROJECT_RESPONSE=$?
  if [[ "${POLL_FOR_PROJECT_RESPONSE}" == 0 ]]; then
    outputMode "The Project '${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT}' already exists.  Skipping..."
    return
  else
    outputMode "Creating new Project: ${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT,,}"
    #outputMode "createProject ${THIS_PROJECT_NAME} ${THIS_DEPLOYMENT_ENVIRONMENT,,} ${THIS_DISPLAY_NAME} ${THIS_DESCRIPTION}"
    createProject "${THIS_PROJECT_NAME}" "${THIS_DEPLOYMENT_ENVIRONMENT,,}" "${THIS_DISPLAY_NAME}" "${THIS_DESCRIPTION}"
    CREATE_PROJECT_RESPONSE=$?
    [[ ${CREATE_PROJECT_RESPONSE} ]] && outputMode "Created Project '${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT,,}'"; return || errorExit "Unable to create the Project.  Please contact support and provide Error Code #395."
  fi
}


function ensureAdminGroupPermissions() {
  #outputMode "function ensureAdminGroupPermissions"
  unset COMMAND
  THIS_DEPLOYMENT_ENVIRONMENT="${1}"
  THIS_PROJECT_NAME="${2}"
  THIS_ADMIN_GROUP="${3}"
  outputMode "Set permissions for Group: '${THIS_ADMIN_GROUP}'"
  COMMAND="oc adm policy add-role-to-group admin ${THIS_ADMIN_GROUP} -n ${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT}"
  retryCommand "1" "3" "${COMMAND}"
  COMMAND_RESPONSE=$?
  if [[ "${COMMAND_RESPONSE}" == 0 ]]; then
    outputMode "Added administrative permissions to the '${THIS_ADMIN_GROUP}' Group on the '${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT}' Project"
    return
  else
    errorExit "Failed to grant administrative permissions to the '${THIS_ADMIN_GROUP}' Group on the '${THIS_PROJECT_NAME}-${THIS_DEPLOYMENT_ENVIRONMENT}' Project"
  fi
}



function addUserToGroup() {
  #outputMode "function addUserToGroup"
  unset COMMAND
  unset COMMAND_RESPONSE
  THIS_GROUP=${1}
  THIS_USER=${2}
  outputMode "Adding the ${THIS_USER} user to the '${THIS_GROUP}' Group"
  COMMAND="oc adm groups add-users ${THIS_GROUP} ${THIS_USER}"
  outputMode "${COMMAND}"
  retryCommand "1" "3" "${COMMAND}"
  COMMAND_RESPONSE=$?
  if [[ "${COMMAND_RESPONSE}" == 0 ]]; then
    outputMode "Added ${THIS_USER} to the '${THIS_GROUP}' Group"
    return
  else
    errorExit "Failed to add ${THIS_USER} to the '${THIS_GROUP}' Group"
  fi
}


function groupPermissions() {
  THIS_ENVIRONMENT="${1}"
  THIS_PROJECT_NAME="${2}"
  THIS_DISPLAY_NAME="${3}"
  THIS_ADMIN_GROUP="${4}"
  THIS_ENVIRONMENT_GROUP="${5}"
  THIS_ORIGINAL_PROJECT_NAME="${6}"

  ensureProjectExists "${THIS_ENVIRONMENT}" "${THIS_PROJECT_NAME}" "${THIS_DISPLAY_NAME}"
  ensureAdminGroupPermissions "${THIS_ENVIRONMENT}" "${THIS_PROJECT_NAME}" "${THIS_ADMIN_GROUP}"
  ensureAdminGroupExists ${THIS_ENVIRONMENT_GROUP}
  ensureAdminGroupPermissions "${THIS_ENVIRONMENT}" "${THIS_PROJECT_NAME}" "${THIS_ENVIRONMENT_GROUP}"
  ensureAdminGroupExists ${THIS_ENVIRONMENT_GROUP}-${THIS_ORIGINAL_PROJECT_NAME}
  ensureAdminGroupPermissions "${THIS_ENVIRONMENT}" "${THIS_PROJECT_NAME}" "${THIS_ENVIRONMENT_GROUP}-${THIS_ORIGINAL_PROJECT_NAME}"
  # Grant admin access to the application-level admin group (ex: dev, qa and prod)
  # TODO: Unsure about this next one.  What it?
  ensureAdminGroupPermissions "${THIS_ENVIRONMENT}" "${THIS_PROJECT_NAME}" "${THIS_ADMIN_GROUP}"
}


# SECRET_PUBLIC_KEY=""

function createGitSecret() {
  ocLogin
  THIS_SECRET="${1}"
  THIS_PROJECT_NAMESPACE="${2}"
  THIS_CUSTOMER_ID="${3}"
  unset COMMAND
  COMMAND="ssh-keygen -C \"git-source-builder/${THIS_PROJECT_NAMESPACE}@${GIT_PREFIX}.${APP_DOMAIN}\" -f /tmp/${THIS_CUSTOMER_ID}-${THIS_SECRET} -N ''"
  eval ${COMMAND} > /dev/null
  COMMAND="oc create secret generic ${THIS_SECRET} \
           --from-file=ssh-privatekey=/tmp/${THIS_CUSTOMER_ID}-${THIS_SECRET} \
           --from-file=ssh-publickey=/tmp/${THIS_CUSTOMER_ID}-${THIS_SECRET}.pub \
           --type=kubernetes.io/ssh-auth \
           -n ${THIS_PROJECT_NAMESPACE}"
  eval ${COMMAND} > /dev/null
#  SECRET_PUBLIC_KEY=$(oc get secrets git-source-builder-key -o=jsonpath='{.data.ssh-publickey}' -n ${THIS_PROJECT_NAMESPACE} | base64 -d)
  COMMAND="rm -rf /tmp/${THIS_CUSTOMER_ID}-${THIS_SECRET}*"
  eval ${COMMAND} > /dev/null
  return
}


function ensureGitSecretExists() {
  THIS_SECRET="${1}"
  THIS_PROJECT_NAMESPACE="${2}"
  THIS_CUSTOMER_ID="${3}"
  POLL_FOR_SECRET="oc get secret ${THIS_SECRET} -n ${THIS_PROJECT_NAMESPACE}"
  retryCommand "1" "3" "${POLL_FOR_SECRET}"
  POLL_FOR_SECRET_RESPONSE=$?
  if [[ "${POLL_FOR_SECRET_RESPONSE}" == 0 ]]; then
    outputMode "The secret '${THIS_SECRET}' already exists. Skipping..."
    return
  else
    outputMode "Creating new secret: ${THIS_SECRET}"
    createGitSecret "${THIS_SECRET}" "${THIS_PROJECT_NAMESPACE}" "${THIS_CUSTOMER_ID}"
    CREATE_SECRET_RESPONSE=$?
    [[ ${CREATE_SECRET_RESPONSE} ]] && outputMode "Created secret '${THIS_SECRET}'"; return || errorExit "Unable to create secret ${THIS_SECRET}"
  fi
}




# Admin User
outputMode "ensureAdminUserExist"
ensureAdminUserExist ${ADMIN_USER}
outputMode "labelObject \"user\" \"${ADMIN_USER}\""
labelObject "user" "${ADMIN_USER}" "customerid" "${CUSTOMER_ID}"

# Groups and their Permissions
outputMode "ensureAdminGroupExists \"${ADMIN_GROUP}\""
ensureAdminGroupExists "${ADMIN_GROUP}"
outputMode "labelObject \"group\" \"${ADMIN_GROUP}\" \"customerid\" \"${CUSTOMER_ID}\""
labelObject "group" "${ADMIN_GROUP}" "customerid" "${CUSTOMER_ID}"
#annotateObject "group" "{ADMIN_GROUP}" "7L.com/projects" "${ADMIN_GROUP}"
outputMode "ensureAdminGroupExists \"${ADMIN_GROUP}-${ORIGINAL_PROJECT_NAME}\""
ensureAdminGroupExists "${ADMIN_GROUP}-${ORIGINAL_PROJECT_NAME}"
outputMode "labelObject \"group\" \"${ADMIN_GROUP}-${ORIGINAL_PROJECT_NAME}\" \"customerid\" \"${CUSTOMER_ID}\""
labelObject "group" "${ADMIN_GROUP}-${ORIGINAL_PROJECT_NAME}" "customerid" "${CUSTOMER_ID}"
#annotateObject "group" "${ADMIN_GROUP}-${ORIGINAL_PROJECT_NAME}" "7L.com/projects" "${PROJECT_NAME}"


if [[ "${ENABLE_DEV}" == true ]]; then
  outputMode "groupPermissions \"dev\" \"${PROJECT_NAME}\" \"${DISPLAY_NAME}\" \"${ADMIN_GROUP}\" \"${DEV_GROUP}\" \"${ORIGINAL_PROJECT_NAME}\""
  groupPermissions "dev" "${PROJECT_NAME}" "${DISPLAY_NAME}" "${ADMIN_GROUP}" "${DEV_GROUP}" "${ORIGINAL_PROJECT_NAME}"
  # LABELS
  outputMode "labelObject \"namespace\" \"${PROJECT_NAME}-dev\" \"customerid\" \"${CUSTOMER_ID}\""
  labelObject "namespace" "${PROJECT_NAME}-dev" "customerid" "${CUSTOMER_ID}"
  outputMode "labelObject \"namespace\" \"${PROJECT_NAME}-dev\" \"deployment_environment\" \"development\""
  labelObject "namespace" "${PROJECT_NAME}-dev" "deployment_environment" "development"
  outputMode "labelObject \"group\" \"${DEV_GROUP}\" \"customerid\" \"${CUSTOMER_ID}\""
  labelObject "group" "${DEV_GROUP}" "customerid" "${CUSTOMER_ID}"
  outputMode "labelObject \"group\" \"${DEV_GROUP}-${ORIGINAL_PROJECT_NAME}\" \"customerid\" \"${CUSTOMER_ID}\""
  labelObject "group" "${DEV_GROUP}-${ORIGINAL_PROJECT_NAME}" "customerid" "${CUSTOMER_ID}"
  outputMode "annotateObject \"group\" \"${DEV_GROUP}\" \"7L.com/projects\" \"${PROJECT_NAME}-dev\""
  annotateObject "group" "${DEV_GROUP}" "7L.com/projects" "${PROJECT_NAME}-dev"
  outputMode "annotateObject \"group\" \"${DEV_GROUP}-${ORIGINAL_PROJECT_NAME}\" \"7L.com/projects\" \"${PROJECT_NAME}-dev\""
  annotateObject "group" "${DEV_GROUP}-${ORIGINAL_PROJECT_NAME}" "7L.com/projects" "${PROJECT_NAME}-dev"
  outputMode "annotateObject \"group\" \"${ADMIN_GROUP}\" \"7L.com/projects\" \"${PROJECT_NAME}-dev\""
  annotateObject "group" "${ADMIN_GROUP}" "7L.com/projects" "${PROJECT_NAME}-dev"

  outputMode "annotateObject \"group\" \"${ADMIN_GROUP}-${ORIGINAL_PROJECT_NAME}\" \"7L.com/projects\" \"${PROJECT_NAME}-dev\""
  annotateObject "group" "${ADMIN_GROUP}-${ORIGINAL_PROJECT_NAME}" "7L.com/projects" "${PROJECT_NAME}-dev"

  # Generate Git Secret
  ensureGitSecretExists "git-source-builder-key-dev" "${PROJECT_NAME}-dev" "${CUSTOMER_ID}"
fi

if [[ "${ENABLE_QA}" == true ]]; then
  outputMode "groupPermissions \"qa\" \"${PROJECT_NAME}\" \"${DISPLAY_NAME}\" \"${ADMIN_GROUP}\" \"${QA_GROUP}\" \"${ORIGINAL_PROJECT_NAME}\""
  groupPermissions "qa" "${PROJECT_NAME}" "${DISPLAY_NAME}" "${ADMIN_GROUP}" "${QA_GROUP}" "${ORIGINAL_PROJECT_NAME}"
  # LABELS
  outputMode "labelObject \"namespace\" \"${PROJECT_NAME}-qa\" \"customerid\" \"${CUSTOMER_ID}\""
  labelObject "namespace" "${PROJECT_NAME}-qa" "customerid" "${CUSTOMER_ID}"
  outputMode "labelObject \"namespace\" \"${PROJECT_NAME}-qa\" \"deployment_environment\" \"quality-assurance\""
  labelObject "namespace" "${PROJECT_NAME}-qa" "deployment_environment" "quality-assurance"
  outputMode "labelObject \"group\" \"${QA_GROUP}\" \"customerid\" \"${CUSTOMER_ID}\""
  labelObject "group" "${QA_GROUP}" "customerid" "${CUSTOMER_ID}"
  outputMode "labelObject \"group\" \"${QA_GROUP}-${ORIGINAL_PROJECT_NAME}\" \"customerid\" \"${CUSTOMER_ID}\""
  labelObject "group" "${QA_GROUP}-${ORIGINAL_PROJECT_NAME}" "customerid" "${CUSTOMER_ID}"
  outputMode "annotateObject \"group\" \"${QA_GROUP}\" \"7L.com/projects\" \"${PROJECT_NAME}-qa\""
  annotateObject "group" "${QA_GROUP}" "7L.com/projects" "${PROJECT_NAME}-qa"
  outputMode "annotateObject \"group\" \"${QA_GROUP}-${ORIGINAL_PROJECT_NAME}\" \"7L.com/projects\" \"${PROJECT_NAME}-qa\""
  annotateObject "group" "${QA_GROUP}-${ORIGINAL_PROJECT_NAME}" "7L.com/projects" "${PROJECT_NAME}-qa"
  outputMode "annotateObject \"group\" \"${ADMIN_GROUP}\" \"7L.com/projects\" \"${PROJECT_NAME}-qa\""
  annotateObject "group" "${ADMIN_GROUP}" "7L.com/projects" "${PROJECT_NAME}-qa"

  outputMode "annotateObject \"group\" \"${ADMIN_GROUP}-${ORIGINAL_PROJECT_NAME}\" \"7L.com/projects\" \"${PROJECT_NAME}-qa\""
  annotateObject "group" "${ADMIN_GROUP}-${ORIGINAL_PROJECT_NAME}" "7L.com/projects" "${PROJECT_NAME}-qa"

  # Generate Git Secret
  ensureGitSecretExists "git-source-builder-key-qa" "${PROJECT_NAME}-qa" "${CUSTOMER_ID}"
fi

if [[ "${ENABLE_PROD}" == true ]]; then
  groupPermissions "prod" "${PROJECT_NAME}" "${DISPLAY_NAME}" "${ADMIN_GROUP}" "${PROD_GROUP}" "${ORIGINAL_PROJECT_NAME}"
  # LABELS
  labelObject "namespace" "${PROJECT_NAME}-prod" "customerid" "${CUSTOMER_ID}"
  labelObject "namespace" "${PROJECT_NAME}-prod" "deployment_environment" "production"
  labelObject "group" "${PROD_GROUP}" "customerid" "${CUSTOMER_ID}"
  labelObject "group" "${PROD_GROUP}-${ORIGINAL_PROJECT_NAME}" "customerid" "${CUSTOMER_ID}"
  annotateObject "group" "${PROD_GROUP}" "7L.com/projects" "${PROJECT_NAME}-prod"
  annotateObject "group" "${PROD_GROUP}-${ORIGINAL_PROJECT_NAME}" "7L.com/projects" "${PROJECT_NAME}-prod"
  annotateObject "group" "${ADMIN_GROUP}" "7L.com/projects" "${PROJECT_NAME}-prod"
  annotateObject "group" "${ADMIN_GROUP}-${ORIGINAL_PROJECT_NAME}" "7L.com/projects" "${PROJECT_NAME}-prod"
fi



# Add Users
outputMode "addUserToGroup \"${ADMIN_GROUP}\" \"${ADMIN_USER}\""
addUserToGroup "${ADMIN_GROUP}" "${ADMIN_USER}"
outputMode "addUserToGroup \"${PROJECT_ADMIN_GROUP}\" \"${ADMIN_USER}\""
addUserToGroup "${PROJECT_ADMIN_GROUP}" "${ADMIN_USER}"




outputMode "DONE OKD ACCOUNTS, PROJECTS, GROUPS, PERMISSIONS"




