# WebOps Team's OpenShift user accounts

The purpose of this repository is to create a web interface in which Digital Products team members
can create their account on OpenShift, or change their existing passwords.

# Process Flow
### This git repo is represented by "ocp-accounts" box located in webops within Stash

Note: Currently we are not kicking off new `build`s or `deployment`s via Bamboo.  Both should be done within
OCP in the `webops` `namespace` for the time-being.  Additionally, we're technically pulling
the base image from `images` in OCP - not Red Hat's external registry.

![OCP Users - architecutural process flow](ocp-accounts.png)

# Details

The source code, while named `index.html`, is actually a bash script.  An Apache web server runs
inside the container and uses the `cgi-bin` as the website's root directory.  This way, when a
user visits the site, they immediately get the output produced by the bash script.
