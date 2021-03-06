#!/bin/bash

set -ex

TEMPVENV=$(mktemp -td venv.XXXXXXXXXX)
VENV="$TEMPVENV/bin"

branch_slash_filter() {
    # The build system relies on an HTTP binary store that uses branches/refs
    # as URL parts.  A literal extra slash in the branch name is considered
    # illegal, so this function performs a check *and* prunes the common
    # `origin/branch-name` scenario (which is OK to have).
    RAW_BRANCH=$1
    branch_slashes=$(grep -o "/" <<< ${RAW_BRANCH} | wc -l)
    FILTERED_BRANCH=`echo ${RAW_BRANCH} | rev | cut -d '/' -f 1 | rev`

    # Prevent building branches that have slashes in their name
    if [ "$((branch_slashes))" -gt 1 ] ; then
        echo "Will refuse to build branch: ${RAW_BRANCH}"
        echo "Invalid branch name (contains slashes): ${FILTERED_BRANCH}"
        exit 1
    fi
    echo $FILTERED_BRANCH
}

install_python_packages () {
    # Use this function to create a virtualenv and install
    # python packages. Pass a list of package names.
    #
    # Usage:
    #
    #   to_install=( "ansible" "chacractl>=0.0.4" )
    #   install_python_packages "to_install[@]"

    # Create the virtualenv
    virtualenv $TEMPVENV

    # Define and ensure the PIP cache
    PIP_SDIST_INDEX="$HOME/.cache/pip"
    mkdir -p $PIP_SDIST_INDEX

    echo "Updating setuptools"
    $VENV/pip install --upgrade --exists-action=i --download="$PIP_SDIST_INDEX" setuptools

    echo "Ensuring latest pip is installed"
    $VENV/pip install --upgrade --exists-action=i --download="$PIP_SDIST_INDEX" pip
    $VENV/pip install --upgrade --exists-action=i --find-links="file://$PIP_SDIST_INDEX" --no-index pip

    pkgs=("${!1}")
    for package in ${pkgs[@]}; do
        echo $package
        # download packages to the local pip cache
        $VENV/pip install --upgrade --exists-action=i --download="$PIP_SDIST_INDEX" $package
        # install packages from the local pip cache, ignoring pypi
        $VENV/pip install --upgrade --exists-action=i --find-links="file://$PIP_SDIST_INDEX" --no-index $package
    done
}

make_chacractl_config () {
    # create the .chacractl config file
    if [ -z "$1" ]                           # Is parameter #1 zero length?
    then
      url=$CHACRACTL_URL
    else
      url=$1
    fi
    cat > $HOME/.chacractl << EOF
url = "$url"
user = "$CHACRACTL_USER"
key = "$CHACRACTL_KEY"
ssl_verify = False
EOF
}

get_rpm_dist() {
    # creates a DISTRO_VERSION and DISTRO global variable for
    # use in constructing chacra urls for rpm distros

    LSB_RELEASE=/usr/bin/lsb_release
    [ ! -x $LSB_RELEASE ] && echo unknown && exit

    ID=`$LSB_RELEASE --short --id`

    case $ID in
    RedHatEnterpriseServer)
        DISTRO_VERSION=`$LSB_RELEASE --short --release | cut -d. -f1`
        DISTRO=rhel
        ;;
    CentOS)
        DISTRO_VERSION=`$LSB_RELEASE --short --release | cut -d. -f1`
        DISTRO=centos
        ;;
    Fedora)
        DISTRO_VERSION=`$LSB_RELEASE --short --release`
        DISTRO=fedora
        ;;
    SUSE\ LINUX)
        DESC=`$LSB_RELEASE --short --description`
        DISTRO_VERSION=`$LSB_RELEASE --short --release`
        case $DESC in
        *openSUSE*)
                DISTRO=opensuse
            ;;
        *Enterprise*)
                DISTRO=sles
                ;;
            esac
        ;;
    *)
        DIST=unknown
        DISTRO=unknown
        ;;
    esac

}

check_binary_existence () {
    url=$1

    # we have to use ! here so thet -e will ignore the error code for the command
    # because of this, the exit code is also reversed
    ! $VENV/chacractl exists binaries/${url} ; exists=$?

    # if the binary already exists in chacra, do not rebuild
    if [ $exists -eq 1 ] && [ "$FORCE" = false ] ; then
        echo "The endpoint at ${chacra_endpoint} already exists and FORCE was not set, Exiting..."
        exit 0
    fi

}
