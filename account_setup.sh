#!/bin/bash

ID="123137"
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


ENABLE_DEV=false
ENABLE_QA=true
ENABLE_PROD=false

unset DEPLOYMENT_ENVIRONMENT

# ERROR OUT AND PROVIDE MESSAGE
function errorExit () {
    echo "Error: $1"
    exit 1
}




# LOGIN TO CLUSTER
function ocLogin() {
  LOGIN_COMMAND="oc login https://m.okd.supercass.com -u 7l-networks -p somepasss --insecure-skip-tls-verify=true"
  # Error Code #394 - could not log into the OKD cluster using the oc command
  eval ${LOGIN_COMMAND} > /dev/null && return || errorExit "Unable to process request. Please contact support and provide Error Code #394."
}


# RETRY COMMAND INSTEAD OF JUST FAILING FIRST ATTEMPT
# Accepts 3 parameters: ${1} Number of retries, ${2} time between retries, ${3} command to run
function retryCommand() {
  # Iterate over the number of retries passed into the retryCommand function as 1st parameter
  for retries in $(seq 1 $(echo "${1}")); do
    # Log into the cluster
#    ocLogin
    # Run the command ${3} parameter.  If it succeeds, return from function.  Otherwise echo failed and then retry ${1} number of times
    eval ${3} > /dev/null && return 
    echo "Attempt ${retries} of ${1} failed to create Project '${PROJECT_NAME}-${DEPLOYMENT_ENVIRONMENT,,}'.  Trying again in ${2} seconds"
    sleep ${2}
    # Exit out completely if we've failed to run the command ${1} times
    # Error Code #395 - Can't create Project, Project exists already, or cannot connect to the cluster via the 'oc' command.  The scipt's account may also have gotten logged out.
    [[ "${retries}" == "${1}" ]] && errorExit "Unable to create the Project.  Please contact support and provide Error Code #395."
  done
}


function addGroups() {
  unset DEPLOYMENT_ENVIRONMENT
  DEPLOYMENT_ENVIRONMENT="${1}"
  CHECK_FOR_GROUP="oc get group ${ADMIN_GROUP}"
  if [[ ! $(eval ${CHECK_FOR_GROUP} 2> /dev/null) ]]; then
    eval "oc adm groups new ${ADMIN_GROUP}" 2&1> /dev/null && echo "Created '${ADMIN_GROUP}' Group" || errorExit "Failed to create the '${ADMIN_GROUP}' Group"
    # Need the Project to exist already
    eval "oc adm policy add-role-to-group admin ${ADMIN_GROUP} -n ${PROJECT_NAME}-${DEPLOYMENT_ENVIRONMENT,,}" 2> /dev/null && echo "Added permissions to the '${ADMIN_GROUP}' Group" || errorExit "Failed to grant permissions to the '${ADMIN_GROUP}' Group"
  fi
}


# CREATE NEW PROJECT
function createProject() {
  unset DEPLOYMENT_ENVIRONMENT
  DEPLOYMENT_ENVIRONMENT="${1}"
  [ "${DEPLOYMENT_ENVIRONMENT}" == "PROD" ] && DISPLAY_NAME="${DISPLAY_NAME^^}"
  RUN="\
      oc new-project ${PROJECT_NAME}-${DEPLOYMENT_ENVIRONMENT,,} \
      --description='${DEPLOYMENT_ENVIRONMENT^^} environment for the \"${DISPLAY_NAME}\" project.' \
      --display-name='${DISPLAY_NAME} - ${DEPLOYMENT_ENVIRONMENT}'"
  retryCommand "3" "5" "${RUN}"
}



if [[ "${ENABLE_DEV}" == true ]]; then
  createProject "dev"
  addGroups "dev"
fi
if [[ "${ENABLE_QA}" == true ]]; then
  createProject "qa"
  addGroups "qa"
fi
if [[ "${ENABLE_PROD}" == true ]]; then
  createProject "PROD"
  addGroups "PROD"
fi




