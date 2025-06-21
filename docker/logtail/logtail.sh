#!/bin/bash

INSTALLER_VERSION="1.5.6"
#install user
RUNUSER=root
RUNUID=$(id -u $RUNUSER)

if [ $UID -ne $RUNUID ]; then
    # Run as root if not run as root
    if command -v runuser &>/dev/null && runuser -l root -c pwd &>/dev/null; then
        # runuser command exists
        runuser -l $RUNUSER -c "$0 $*"
        exit $?
    elif command -v sudo &>/dev/null && sudo pwd &>/dev/null; then
        # sudo command exists
        sudo "$0" "$@"
        exit $?
    elif command -v su &>/dev/null && su root -c pwd &>/dev/null; then
        su $RUNUSER -c "$0 $*"
        exit $?
    else
        echo "You must have root privilige to run this script." 1>&2
        exit 1
    fi
fi

##Region
CORP_POSTFIX="-corp"
INTERNET_POSTFIX="-internet"
INNER_POSTFIX="-inner"
FINANCE_POSTFIX="-finance"
ACCELERATION_POSTFIX="-acceleration"
INTERNAL_POSTFIX="-internal"

CN_HANGZHOU_FINANCE="cn-hangzhou-finance"
CN_SHANGHAI_FINANCE="cn-shanghai-finance"
CN_SHENZHEN_FINANCE="cn-shenzhen-finance"
CN_HANGZHOU_IDPT_2="cn-hangzhou-idpt-2"

##logtail package
PACKAGE_NAME="logtail-linux64.tar.gz"

##ilogtaild script
CONTROLLER_DIR="/etc/init.d"
CONTROLLER_FILE="ilogtaild"
LOONGCOLLECTOR_CONTROLLER_FILE="loongcollectord"
SYSTEMD_SERVICE_DIR="/etc/systemd/system"
SYSTEMD_SERVICE_NAME="${CONTROLLER_FILE}.service"
LOONGCOLLECTOR_SYSTEMD_SERVICE_NAME="${LOONGCOLLECTOR_CONTROLLER_FILE}.service"

##ilogtail binary
BIN_DIR="/usr/local/ilogtail"
BIN_FILE="ilogtail"

LOGTAIL_SYS_CONF_DIR="/etc/ilogtail"

##config file
README_FILE="README"
CA_CERT_FILE="ca-bundle.crt"
CONFIG_FILE="ilogtail_config.json"

##os version
CENTOS_OS="CentOS"
UBUNTU_OS="Ubuntu"
DEBIAN_OS="Debian"
ALIYUN_OS="Aliyun"
OPENSUSE_OS="openSUSE"
OTHER_OS="other"

#install ebpf dependencies
EBPF=false

CURRENT_DIR=$(dirname "$0")
CURRENT_DIR=$(
    cd $CURRENT_DIR
    pwd
)
cd $CURRENT_DIR

logError() {
    echo -n '[Error]:   ' $*
    echo -en '\033[120G \033[31m' && echo [ Error ]
    echo -en '\033[0m'
}

REGION=""
ALIUID=""
HAS_META_SERVER=-1

kernel_version=$(uname -r)
OS_VERSION=$OTHER_OS
os_issue=$(cat /etc/issue | tr A-Z a-z)
ARCH=$(uname -m)

# prepare download funcion
# some distribution such as Fedora CoreOS does not have wget
# some distribution such as Alpine/Busybox does not have curl
CONNECTION_TIMEOUT=5
WGET_INSTALLED=true && wget --version &> /dev/null || WGET_INSTALLED=false
CURL_INSTALLED=true && curl --version &> /dev/null || CURL_INSTALLED=false
download() {
    local download_url=$1
    local destination=$2
    [ $WGET_INSTALLED == true ] && {
        wget ${download_url} -nv --connect-timeout ${CONNECTION_TIMEOUT} -O ${destination} || {
            >&2 echo "Failed to download from ${download_url} to ${destination}, Please check your network service."
            return 1
        }
    } || {
        curl ${download_url} -sSfL --connect-timeout ${CONNECTION_TIMEOUT} -o ${destination} || {
            >&2 echo "Failed to download from ${download_url} to ${destination}, Please check your network service."
            return 1
        }
    }
    return 0
}

urlopen() {
    local download_url=$1
    [ $CURL_INSTALLED == true ] && {
        curl ${download_url} -sSfL --connect-timeout ${CONNECTION_TIMEOUT} || {
            echo "Failed to open ${download_url}, Please check your network service." 1>&2
            return 1
        }
    } || {
        wget ${download_url} -nv --connect-timeout ${CONNECTION_TIMEOUT} -O- || {
            echo "Failed to open ${download_url}, Please check your network service." 1>&2
            return 1
        }
    }
    return 0
}

build_package_address() {
    local package_address="$1"
    local package_name="$2"
    if [ "$VERSION" != "" ]; then
        case $ARCH in
            'x86_64')
                package_address="$package_address/$VERSION"
                ;;
            *)
                package_address="$package_address/$VERSION/$ARCH"
                ;;
        esac
    else
        case $ARCH in
            'x86_64')
                package_address="$package_address"
                ;;
            *)
                package_address="$package_address/$ARCH"
                ;;
        esac
    fi
    echo "${package_address}/${package_name}"
}

refresh_meta() {
    local last_timeout=${CONNECTION_TIMEOUT}
    CONNECTION_TIMEOUT=$1
    urlopen "http://100.100.100.200/latest/meta-data/region-id" &>/dev/null
    HAS_META_SERVER=$?
    if [ $HAS_META_SERVER -eq 0 ] && [ -z "$ALIUID" ]; then
        ALIUID=$(urlopen "http://100.100.100.200/latest/meta-data/owner-account-id")
        re='^[0-9]+$'
        if [[ $ALIUID =~ $re ]]; then
            echo "Fetch aliuid from meta server: $ALIUID"
        else
            ALIUID=""
        fi
    fi
    CONNECTION_TIMEOUT=${last_timeout}
}

# Test (with shorter timeout) if meta server is existing? If yes, fetch aliuid.
refresh_meta 1

normalize_region() {
    # Convert all _ in $REGION to -.
    REGION=$(echo $REGION | sed 's/_/-/g')
    # Remove -vpc
    REGION=$(echo $REGION | sed 's/-vpc//g')
}

PACKAGE_REGION_ADDRESS=""
# Before calling this, set $REGION or pass "auto" as first parameter to update REGION from meta server.
# After calling successfully, PACKAGE_REGION_ADDRESS will be set.
###################################################################################################################################
# NOTICE: similar logic also exist in the run_logtail.sh for container, please also update the file when modify the following logics.
###################################################################################################################################
update_package_address() {
    if [ "$PACKAGE_REGION_ADDRESS" != "" ]; then
        return
    fi

    if [ $1 = "auto" ]; then
        if [ $HAS_META_SERVER -ne 0 ]; then
            # Double check, curl with longer timeout.
            refresh_meta 5
            if [ $HAS_META_SERVER -ne 0 ]; then
                echo "[FAIL] Sorry, fail to get region automatically, please specify region and try again."
                echo "[NOTE] 'auto' can only work on ECS VM."
                exit 1
            fi
        fi
        REGION=$(urlopen "http://100.100.100.200/latest/meta-data/region-id")
    fi

    local package_address=""
    if [ $(echo $REGION | grep "\b$CN_HANGZHOU_FINANCE_INTERNET\b" | wc -l) -ge 1 ]; then
        package_address="http://logtail-release-cn-hangzhou-finance-1.oss-cn-hzfinance.aliyuncs.com"
    elif [ $(echo $REGION | grep "\b$CN_HANGZHOU_FINANCE\b" | wc -l) -ge 1 ]; then
        package_address="http://logtail-release-cn-hangzhou-finance-1.oss-cn-hzfinance-internal.aliyuncs.com"
    elif [ $(echo $REGION | grep "\b$CN_SHENZHEN_FINANCE_INTERNET\b" | wc -l) -ge 1 ]; then
        package_address="http://logtail-release-sz-finance.oss-cn-shenzhen-finance-1.aliyuncs.com"
    elif [ $(echo $REGION | grep "\b$CN_SHENZHEN_FINANCE\b" | wc -l) -ge 1 ]; then
        package_address="http://logtail-release-sz-finance.oss-cn-shenzhen-finance-1-internal.aliyuncs.com"
    elif [ $(echo $REGION | grep "\b$CN_SHANGHAI_FINANCE_INTERNET\b" | wc -l) -ge 1 ]; then
        package_address="http://logtail-release-cn-shanghai-finance-1.oss-cn-shanghai-finance-1.aliyuncs.com"
    elif [ $(echo $REGION | grep "\b$CN_SHANGHAI_FINANCE\b" | wc -l) -ge 1 ]; then
        package_address="http://logtail-release-cn-shanghai-finance-1.oss-cn-shanghai-finance-1-internal.aliyuncs.com"
    elif [ $(echo $REGION | grep "\b$INTERNET_POSTFIX\b" | wc -l) -ge 1 ] ||
        [ $(echo $REGION | grep "\b$ACCELERATION_POSTFIX\b" | wc -l) -ge 1 ]; then
        local region_id=$(echo $REGION | sed "s/$INTERNET_POSTFIX//g")
        region_id=$(echo $region_id | sed "s/$ACCELERATION_POSTFIX//g")
        if [ "$region_id" == $CN_HANGZHOU_IDPT_2 ]; then
            package_address="http://logtail-release-$region_id.oss.$region_id.idptcloud01cs.com"
        else
            package_address="http://logtail-release-$region_id.oss-$region_id.aliyuncs.com"
        fi
    elif [ $(echo $REGION | grep "\b$INNER_POSTFIX\b" | wc -l) -ge 1 ]; then
        package_address="http://logtail-release-cn-hangzhou.oss-cn-hangzhou.aliyuncs.com"
    elif [ $(echo $REGION | grep "\b$CORP_POSTFIX\b" | wc -l) -ge 1 ]; then
        package_address="http://logtail-release-cn-hangzhou-zmf.oss-cn-hangzhou-zmf.aliyuncs.com"
    elif [ $(echo $REGION | grep "\b$INTERNAL_POSTFIX\b" | wc -l) -ge 1 ]; then
        local region_id=$(echo $REGION | sed "s/$INTERNAL_POSTFIX//g")
        if [ "$region_id" == $CN_HANGZHOU_IDPT_2 ]; then
            package_address="http://logtail-release-$region_id.oss-internal.$region_id.idptcloud01cs.com"
        else
            package_address="http://logtail-release-$region_id.oss-$region_id-internal.aliyuncs.com"
        fi
    else
        if [ "$REGION" == $CN_HANGZHOU_IDPT_2 ]; then
            package_address="http://logtail-release-$REGION.oss-internal.$REGION.idptcloud01cs.com"
        else
            package_address="http://logtail-release-$REGION.oss-$REGION-internal.aliyuncs.com"
        fi
    fi

    PACKAGE_REGION_ADDRESS="$package_address/linux64"
    echo "Package address: $PACKAGE_REGION_ADDRESS"
}

download_file() {
    update_package_address $1

    local package_address=$(build_package_address "$PACKAGE_REGION_ADDRESS" "$PACKAGE_NAME")

    download $package_address $PACKAGE_NAME
    if [ $? != 0 ]; then
        logError "Download logtail install file from $package_address failed."
        logError "Can not find available package address for region {$REGION}."
        logError "Please confirm the region you specified and try again."
        rm -f $PACKAGE_NAME
        exit 1
    fi
}

###################################################################################################################################
# NOTICE: similar logic also exist in the run_logtail.sh for container, please also update the file when modify the following logics.
###################################################################################################################################
download_vmlinux() {
    update_package_address $1
    rm -f /tmp/logtail_vmlist
    rm -rf /tmp/logtail-vmlinux
    mkdir -p /tmp/logtail-vmlinux
    download "$PACKAGE_REGION_ADDRESS/vmlinux/$ARCH/list" /tmp/logtail_vmlist
    local vmlinux_version=$(cat /tmp/logtail_vmlist | grep $kernel_version)
    if [ "$vmlinux_version" == "" ]; then
        echo Unmatch os version: $kernel_version, try to find nearest vmlinux version
        cal_last_version
    fi
    if [ "$vmlinux_version" == "" ]; then
        echo Unmatch os version: $kernel_version
        echo "Logtail ebpf feture would not work."
    else
        echo Vmlinux version: $vmlinux_version
        download  "$PACKAGE_REGION_ADDRESS"/vmlinux/$ARCH/$vmlinux_version /tmp/logtail-vmlinux/$vmlinux_version
        if [ $? != 0 ]; then
            logError "Download logtail vmlinux file from $PACKAGE_REGION_ADDRESS failed."
            logError "Please confirm the region you specified and try again."
            rm -f $PACKAGE_NAME
            exit 1
        fi
    fi
}

###################################################################################################################################
# NOTICE: similar logic also exist in the run_logtail.sh for container, please also update the file when modify the following logics.
###################################################################################################################################
function cal_last_version() {
    rm -f /tmp/logtail_vmlist_sort
    download $PACKAGE_REGION_ADDRESS/vmlinux/$ARCH/version_sortlist /tmp/logtail_vmlist_sort
    local os_vm_version=$(echo v-$kernel_version | awk -F '[-.]' '{print ($2*1000000000000)+($3*10000000000)+($4*10000000)+($5*1000)+($6*10)+($7)}')
    local vmlinux_version=""
    while read line; do
        cur_vm_version=($(echo $line | awk -F ' ' '{print $1" "$2 }'))

        if [ $os_vm_version -gt ${cur_vm_version[0]} ]; then
            vmlinux_version=${cur_vm_version[1]}
            echo Using nearest vmlinux version: $vmlinux_version
        else
            return
        fi
    done </tmp/logtail_vmlist_sort
}

generate_default_config_file() {
    local file_path="$1"
    local region_id=""
    local config_endpoint=""

    # Extract region_id, config/data endpoint from $REGION.
    if [ $(echo $REGION | grep "\b$INTERNET_POSTFIX\b" | wc -l) -ge 1 ]; then
        region_id=$(echo $REGION | sed "s/${INTERNET_POSTFIX}//g")
        if [ "$region_id" == $CN_HANGZHOU_IDPT_2 ]; then
            data_endpoint="log.${region_id}.idptcloud01cs.com"
        else
            data_endpoint="${region_id}.log.aliyuncs.com"
        fi
        config_endpoint="http://logtail.${data_endpoint}"
    elif [ $(echo $REGION | grep "\b$ACCELERATION_POSTFIX\b" | wc -l) -ge 1 ]; then
        region_id=$(echo $REGION | sed "s/${ACCELERATION_POSTFIX}//g")
        data_endpoint="log-global.aliyuncs.com"
        config_endpoint="http://logtail.${region_id}.log.aliyuncs.com"
    elif [ $(echo $REGION | grep "\b$INNER_POSTFIX\b" | wc -l) -ge 1 ]; then
        region_id=$(echo $REGION | sed "s/${INNER_POSTFIX}//g")
        data_endpoint="${region_id}-share.log.aliyuncs.com"
        config_endpoint="http://logtail.${data_endpoint}"
    elif [ $(echo $REGION | grep "\b$INTERNAL_POSTFIX\b" | wc -l) -ge 1 ]; then
        region_id=$(echo $REGION | sed "s/${INTERNAL_POSTFIX}//g")
        if [ "$region_id" == $CN_HANGZHOU_IDPT_2 ]; then
            data_endpoint="log-internal.${region_id}.idptcloud01cs.com"
        else
            data_endpoint="${region_id}-internal.log.aliyuncs.com"
        fi
        config_endpoint="http://logtail.${data_endpoint}"
    else
        region_id="$REGION"
        if [ "$region_id" == $CN_HANGZHOU_IDPT_2 ]; then
            data_endpoint="log-intranet.${region_id}.idptcloud01cs.com"
        else
            data_endpoint="${region_id}-intranet.log.aliyuncs.com"
        fi
        config_endpoint="http://logtail.${data_endpoint}"
    fi

    mkdir -p $(dirname ${file_path})
    echo "{" >${file_path}
    echo "    \"config_server_address\" : \"${config_endpoint}\"," >>${file_path}
    echo "    \"data_server_list\" :" >>${file_path}
    echo "    [" >>${file_path}
    echo "        {" >>${file_path}
    echo "            \"cluster\" : \"${region_id}\"," >>${file_path}
    echo "            \"endpoint\" : \"${data_endpoint}\"" >>${file_path}
    echo "        }" >>${file_path}
    echo '    ],' >>${file_path}
    echo '    "cpu_usage_limit" : 0.4,' >>${file_path}
    echo '    "mem_usage_limit" : 384,' >>${file_path}
    echo '    "max_bytes_per_sec" : 20971520,' >>${file_path}
    echo '    "bytes_per_sec" : 1048576,' >>${file_path}
    echo '    "buffer_file_num" : 25,' >>${file_path}
    echo '    "buffer_file_size" : 20971520,' >>${file_path}
    echo '    "buffer_map_num" : 5' >>${file_path}
    echo '}' >>${file_path}
}

# $1: config file path, must exist.
# return: install param, such as cn-hangzhou, cn-hangzhou-acceleration, etc.
# If can not find endpoint or region_id, echo nothing and return 1.
get_install_param_from_config_file() {
    local install_param=""
    CONFIG_FILE_PATH=$1
    network_type=""
    endpoint=""
    config_server_address=""
    local region_id=""
    config_info=""
    cluster=$(cat $CONFIG_FILE_PATH | grep "cluster" | head -n 1 |
        awk -F\: '{print $2}' | sed 's/ //g' | sed 's/\"//g' | sed 's/,//g')
    if [ "$cluster" != "" ]; then
        # The old version of the endpoint format.
        # Differentiate network type according to config_server_address and endpoint.
        # Step 1. endpoint == log-global.aliyuncs.com
        #   - true: Acceleration.
        #   - false: Step 2.
        # Step 2. config_server_address
        #   - *intranet/vpc.log.aliyuncs.com: VPC or traditional.
        #   - *share.log.aliyuncs.com: inner.
        #   - rest: internet.
        endpoint=$(cat $CONFIG_FILE_PATH | grep "endpoint" | head -n 1 |
            awk -F\: '{print $2}' | sed 's/ //g' | sed 's/\"//g')
        config_server_address=$(cat $CONFIG_FILE_PATH | grep "config_server_address" |
            awk -F\: '{print $2 ":" $3}' | sed 's/ //g' | sed 's/\"//g' | sed 's/,//g')
        cluster=$(cat $CONFIG_FILE_PATH | grep "cluster" | head -n 1 |
            awk -F\: '{print $2}' | sed 's/ //g' | sed 's/\"//g' | sed 's/,//g')
        region_id=$(echo $config_server_address | awk -F '/' '{ print $NF}' | awk -F '.' '{ i=NF-3; print $i}')
        config_info="config_server_address($config_server_address), endpoint($endpoint), cluster($cluster)"

        if [ "$endpoint" = "" ] || [ "$region_id" = "" ] || [ "$cluster" = "" ]; then
            return 1
        fi
    else
        # The new version of the endpoint format.
        # Differentiate network type according to config_servers and endpoint.
        # Step 1. endpoint == log-global.aliyuncs.com
        #   - true: Acceleration.
        #   - false: Step 2.
        # Step 2. config_servers
        #   - *intranet/vpc.log.aliyuncs.com: VPC or traditional.
        #   - *share.log.aliyuncs.com: inner.
        #   - rest: internet.
        endpoint=$(cat $CONFIG_FILE_PATH | sed -n '/data_servers/,/]/p' | grep ".com" | head -n 1  | sed 's/ //g' | sed 's/\"//g' | sed 's/,//g')
        config_server_address=$(cat $CONFIG_FILE_PATH | sed -n '/config_servers/,/]/p' | grep ".com" | head -n 1  | sed 's/ //g' | sed 's/\"//g' | sed 's/,//g')
        cluster=$(cat $CONFIG_FILE_PATH | grep "region" | head -n 1 |
            awk -F\: '{print $2}' | sed 's/ //g' | sed 's/\"//g' | sed 's/,//g')
        region_id=$(echo $config_server_address | awk -F '/' '{ print $NF}' | awk -F '.' '{ i=NF-3; print $i}')
        config_info="config_server_address($config_server_address), endpoint($endpoint), region($cluster)"

        if [ "$endpoint" = "" ] || [ "$region_id" = "" ] || [ "$cluster" = "" ]; then
            return 1
        fi
    fi
    if [ "$(echo $endpoint | grep "\blog-global.aliyuncs.com\b" | wc -l)" -ge 1 ]; then
        network_type="acceleration"
    elif [ "$(echo $cluster | grep "\bcorp\b" | wc -l)" -ge 1 ]; then
        region_id="cn-hangzhou"
        network_type="corp"
    else
        if [ "$(echo $region_id | grep "\b-intranet\b" | wc -l)" -ge 1 ] ||
            [ "$(echo $region_id | grep "\b-vpc\b" | wc -l)" -ge 1 ]; then
            network_type="vpc"
            region_id=$(echo $region_id | sed 's/-intranet//g')
            region_id=$(echo $region_id | sed 's/-vpc//g')
        elif [ "$(echo $region_id | grep "\b-share\b" | wc -l)" -ge 1 ]; then
            network_type="inner"
            region_id=$(echo $region_id | sed 's/-share//g')
        elif [ "$(echo $region_id | grep "\b$INTERNAL_POSTFIX\b" | wc -l)" -ge 1 ]; then
            network_type="internal"
            region_id=$(echo $region_id | sed "s/$INTERNAL_POSTFIX//g")
        else
            network_type="internet"
        fi
    fi
    install_param=$region_id
    if [ "$network_type" != "vpc" ]; then
        install_param=$region_id-$network_type
    fi

    if [ "$(echo $install_param | grep -E "^[0-9a-z\-]+$")" = "" ]; then
        echo $config_info
        return 1
    fi
    echo $install_param
}

# Upgrade logtail according to local information.
do_upgrade() {
    use_local_package="$1"

    # Some necessary checks.
    $CONTROLLER_DIR/$CONTROLLER_FILE status
    if [ $? -ne 0 ]; then
        logError "Logtail status is not ok, stop upgrading"
        exit 1
    fi
    CONFIG_FILE_PATH=$BIN_DIR/$CONFIG_FILE
    if [ ! -f $CONFIG_FILE_PATH ]; then
        logError "Can not find config file: $CONFIG_FILE_PATH"
        exit 1
    fi
    if [ ! -f "$BIN_DIR/ilogtail" ] && [ ! -f "$BIN_DIR/loongcollector" ]; then
        logError "Can not find logtail binary"
        exit 1
    fi

    if [ "$use_local_package" == "" ]; then
        # Download latest package according to install param.
        install_param=$(get_install_param_from_config_file $CONFIG_FILE_PATH)
        if [ $? -ne 0 ]; then
            if [ "$install_param" != "" ]; then
                logError "Can not upgrade for logtail with config like $install_param"
            else
                logError "Can not get install_param according to $CONFIG_FILE_PATH"
            fi
            exit 1
        fi
        REGION=$install_param
        rm -f $PACKAGE_NAME
        echo "Downloading package from region $REGION ..."
        download_file $install_param
        if [ -f $PACKAGE_NAME ]; then
            echo "Download $PACKAGE_NAME successfully."
        else
            logError $PACKAGE_NAME" download fail, exit"
            exit 1
        fi
    else
        # Use local package.
        if [ ! -f $PACKAGE_NAME ]; then
            logError "Can not find local package $PACKAGE_NAME to upgrade"
            exit 1
        fi
    fi

    # Check if the latest logtail has already existed.
    if [ -f $BIN_DIR/ilogtail ]; then
        current_binary_version=$(ls -lh $BIN_DIR/ilogtail | awk -F"_" '{print $NF}')
    elif [ -f $BIN_DIR/loongcollector ]; then
        current_binary_version=$(ls -lh $BIN_DIR/loongcollector | awk -F"_" '{print $NF}')
    fi
    tar -zxf $PACKAGE_NAME
    new_binary_version=$(ls $CURRENT_DIR/logtail-linux64/bin/ilogtail_* | awk -F"_" '{print $NF}')
    if [ "$new_binary_version" == "$current_binary_version" ]; then
        logError "Already up to date."
        rm -rf logtail-linux64
        rm -f $PACKAGE_NAME
        exit 0
    fi

    # Stop logtail and start upgrading.
    echo "Try to stop logtail ..."
    for ((i = 0; i < 3; i++)); do
        $CONTROLLER_DIR/$CONTROLLER_FILE stop
        if [ $? -eq 0 ]; then
            break
        fi
        if [ $i -ne 2 ]; then
            logError "Stop logtail failed, sleep 3 seconds and retry..."
            sleep 3
        else
            rm -rf logtail-linux64
            rm -f $PACKAGE_NAME
            sleep 3
            $CONTROLLER_DIR/$CONTROLLER_FILE start
            logError "Stop logtail failed, exit: ",$status
            exit 1
        fi
    done
    echo "Stop logtail successfully."

    echo "Upgrading logtail files ..."
    # If dir of current version is not exist, create and backup.
    CURRENT_VERSION_DIR=$BIN_DIR/$current_binary_version
    if [ "$current_binary_version" != "" ] && [ ! -d $CURRENT_VERSION_DIR ]; then
        mkdir -p $CURRENT_VERSION_DIR
        cp $BIN_DIR/libPluginAdapter.so $CURRENT_VERSION_DIR/
        cp $BIN_DIR/libPluginBase.so $CURRENT_VERSION_DIR/
    fi
    # Create dir for new version.
    NEW_VERSION_DIR=$BIN_DIR/$new_binary_version
    mkdir -p $NEW_VERSION_DIR
    cp $CURRENT_DIR/logtail-linux64/bin/libPluginAdapter.so $NEW_VERSION_DIR/
    cp $CURRENT_DIR/logtail-linux64/bin/libPluginBase.so $NEW_VERSION_DIR/

    # Override current version.
    cp $CURRENT_DIR/logtail-linux64/bin/$BIN_FILE"_"$new_binary_version $BIN_DIR/
    cp $CURRENT_DIR/logtail-linux64/bin/LogtailInsight $BIN_DIR/
    cp $CURRENT_DIR/logtail-linux64/bin/libPluginAdapter.so $BIN_DIR/
    cp $CURRENT_DIR/logtail-linux64/bin/libPluginBase.so $BIN_DIR/
    rm $BIN_DIR/$BIN_FILE
    if [ -f $BIN_DIR/loongcollector ]; then
        rm $BIN_DIR/loongcollector
    fi
    ln -s $BIN_DIR/$BIN_FILE"_"$new_binary_version $BIN_DIR/$BIN_FILE
    cp $CURRENT_DIR/logtail-linux64/$README_FILE $BIN_DIR/
    cp $CURRENT_DIR/logtail-linux64/resources/$CA_CERT_FILE $BIN_DIR/
    cp $CURRENT_DIR/logtail-linux64/bin/ilogtaild $CONTROLLER_DIR/$CONTROLLER_FILE
    chmod 755 $BIN_DIR -R
    chown root $BIN_DIR -R
    chgrp root $BIN_DIR -R
    chmod 755 $CONTROLLER_DIR/$CONTROLLER_FILE
    chown root $CONTROLLER_DIR/$CONTROLLER_FILE
    chgrp root $CONTROLLER_DIR/$CONTROLLER_FILE
    # INSTANCE_SUFFIX is set, update ilogtaild.
    if [ ! -z ${INSTANCE_SUFFIX+x} ]; then
        # inject INSTANCE_SUFFIX into ilogtaild to enable suffix filtering in checkStatus.
        local line_no=$(grep -n "BIN_DIR=\"/usr/local/ilogtail\"" $CONTROLLER_DIR/$CONTROLLER_FILE | awk -F":" '{print $1}')
        line_no=$((line_no - 1))
        sed -i "${line_no}c INSTANCE_SUFFIX=\"$INSTANCE_SUFFIX\"" $CONTROLLER_DIR/$CONTROLLER_FILE
        line_no=$(grep -n "# processname: ilogtaild" $CONTROLLER_DIR/$CONTROLLER_FILE | awk -F":" '{print $1}')
        sed -i "${line_no}c # processname: $CONTROLLER_FILE" $CONTROLLER_DIR/$CONTROLLER_FILE
    fi
    systemctl --version &> /dev/null
    local service_file_path="$SYSTEMD_SERVICE_DIR/$SYSTEMD_SERVICE_NAME"
    if [ $? -eq 0 ] && [ -d "$SYSTEMD_SERVICE_DIR" ] && [ -f "$service_file_path" ] && cat "$service_file_path" | grep "loongcollectord"; then
        echo "Use systemd for startup"
        echo service_file_path: $service_file_path
        rm -f $service_file_path
        echo "[Unit]" >>$service_file_path

        echo "Description=ilogtail" >>$service_file_path
        echo "After=cloud-init.service" >>$service_file_path
        echo "" >>$service_file_path
        echo "[Service]" >>$service_file_path
        echo "Type=oneshot" >>$service_file_path
        echo "User=$RUNUSER" >>$service_file_path
        echo "RemainAfterExit=yes" >>$service_file_path
        echo "ExecStart=$CONTROLLER_DIR/$CONTROLLER_FILE start" >>$service_file_path
        echo "ExecStop=$CONTROLLER_DIR/$CONTROLLER_FILE stop" >>$service_file_path
        echo "" >>$service_file_path
        echo "[Install]" >>$service_file_path
        echo "WantedBy=default.target" >>$service_file_path
        systemctl enable $SYSTEMD_SERVICE_NAME
        if [ $? -eq 0 ]; then
            echo "systemd startup successfully."
        else
            rm -f $service_file_path
            # echo "systemd startup failed."
        fi
    fi
    echo "Upgrade logtail files successfully."

    # Start logtail, print the latest info.
    echo "Starting logtail ..."
    $CONTROLLER_DIR/$CONTROLLER_FILE start
    if [ $? -eq 0 ]; then
        echo "Upgrade logtail successfully."
    else
        logError "Start logtail fail, you'd better reinstall logtail."
        rm -rf logtail-linux64
        rm -f $PACKAGE_NAME
        exit 1
    fi
    sleep 3
    local appinfo=$BIN_DIR"/app_info.json"
    if [ -f $appinfo ]; then
        cat $appinfo
    fi
    rm -rf logtail-linux64
    rm -f $PACKAGE_NAME
}

do_install_agent() {
    REGION=$1
    normalize_region
    local agent=$2
    echo "Start to install agent $agent from $REGION"

    update_package_address $REGION
    local package_name="${agent}.tar.gz"
    local package_address=$(build_package_address "$PACKAGE_REGION_ADDRESS/${agent}" "$package_name")
    download $package_address $package_name
    if [ $? != 0 ]; then
        logError "Download $package_name from $package_address failed."
        logError "Can not find available package address for region {$REGION}."
        logError "Please confirm the region you specified and try again."
        rm -f $package_name
        exit 1
    fi

    local destination_dir="$LOGTAIL_SYS_CONF_DIR/$agent"
    if [ -d ${destination_dir} ]; then
        rm -rf "${destination_dir}.bak"
        mv ${destination_dir} "${destination_dir}.bak"
    fi
    tar -zxf $package_name
    rm -f $package_name
    cp -rf $agent $destination_dir
    rm -rf $agent
    chmod +x "$destination_dir/${agent}" &> /dev/null 
    chmod +x "$destination_dir/${agent}d" &> /dev/null 

    echo "Install agent $agent successfully"
}

do_install_agent_stub() {
    local agent=$1
    local agent_dir="$LOGTAIL_SYS_CONF_DIR/$agent"
    if [ ! -d $agent_dir ]; then
        mkdir -p $agent_dir
    fi
    local region=$REGION
    local script_path="$agent_dir/install.sh"
    local name="logtail_install_${agent}.sh"
    cp $CURRENT_DIR/$(basename "$0") $agent_dir/logtail.sh
    chmod +x "$agent_dir/logtail.sh"
    echo "#!/bin/bash" >$script_path
    echo "" >>$script_path
    echo "cp $agent_dir/logtail.sh /tmp/$name" >>$script_path
    echo "chmod +x /tmp/$name" >>$script_path
    echo "/tmp/$name install-agent $region $agent" >>$script_path
    echo "rm /tmp/$name" >>$script_path
    echo "agent stub for $agent has been installed"
    chmod +x $script_path
}

do_install() {
    echo RUNUSER:$RUNUSER
    REGION=$2
    normalize_region
    if [ $3 = "install" ]; then
        rm -f $PACKAGE_NAME
        echo "Downloading package from region $REGION ..."
        download_file $2
    fi
    if [ -f $PACKAGE_NAME ]; then
        echo "Download $PACKAGE_NAME successfully."
    else
        logError $PACKAGE_NAME" download failed, exit"
        exit 1
    fi
    tar -zxf $PACKAGE_NAME
    local binary_version=$(ls $CURRENT_DIR/logtail-linux64/bin/ilogtail_* | awk -F"_" '{print $NF}')
    local conf_file_path="${CURRENT_DIR}/logtail-linux64/conf/${REGION}/${CONFIG_FILE}"
    if [ ! -f ${conf_file_path} ]; then
        echo "Can not find ready-made config file for specifed parameter ${REGION}. Generating config ..."
        generate_default_config_file "$conf_file_path"
        echo "Generate config successfully."
    fi
    if [ ! -f ${conf_file_path} ]; then
        logError "Can not find specific config file ${conf_file_path}"
        rm -rf logtail-linux64
        rm -f $PACKAGE_NAME
        exit 1
    fi

    echo "Installing in $BIN_DIR ..."
    mkdir -p $BIN_DIR
    mkdir -p $CONTROLLER_DIR
    cp $CURRENT_DIR/logtail-linux64/bin/$BIN_FILE"_"$binary_version $BIN_DIR/
    cp $CURRENT_DIR/logtail-linux64/bin/LogtailInsight $BIN_DIR/
    cp $CURRENT_DIR/logtail-linux64/bin/libPluginAdapter.so $BIN_DIR/
    cp $CURRENT_DIR/logtail-linux64/bin/libPluginBase.so $BIN_DIR/

    if [ $EBPF == "true" ]; then
        echo "Preparing ebpf enviroment ..."
        download_vmlinux $REGION
        if [ $? != 0 ]; then
            echo "Prepare ebpf env failed, please check your OS version."
        else
            cp $CURRENT_DIR/logtail-linux64/bin/libpcap.so $BIN_DIR/
            cp $CURRENT_DIR/logtail-linux64/bin/libebpf.so $BIN_DIR/
            cp /tmp/logtail-vmlinux/* $BIN_DIR/
        fi
        echo "Prepare ebpf env successfully"
    fi

    ln -s $BIN_DIR/$BIN_FILE"_"$binary_version $BIN_DIR/$BIN_FILE
    cp $CURRENT_DIR/logtail-linux64/$README_FILE $BIN_DIR/
    cp $CURRENT_DIR/logtail-linux64/resources/$CA_CERT_FILE $BIN_DIR/
    cp $CURRENT_DIR/logtail-linux64/conf/$REGION"/"$CONFIG_FILE $BIN_DIR/$CONFIG_FILE
    cp $CURRENT_DIR/logtail-linux64/bin/ilogtaild $CONTROLLER_DIR/$CONTROLLER_FILE

    chmod 755 $BIN_DIR -R
    chown $RUNUSER $BIN_DIR -R
    chgrp $RUNUSER $BIN_DIR -R
    chmod 755 $CONTROLLER_DIR/$CONTROLLER_FILE
    chown $RUNUSER $CONTROLLER_DIR/$CONTROLLER_FILE
    chgrp $RUNUSER $CONTROLLER_DIR/$CONTROLLER_FILE
    mkdir -p $LOGTAIL_SYS_CONF_DIR/users
    if [ ! -z "$ALIUID" ]; then
        touch $LOGTAIL_SYS_CONF_DIR/users/$ALIUID
    fi
    [ -e $LOGTAIL_SYS_CONF_DIR ] && chown -R $RUNUSER $LOGTAIL_SYS_CONF_DIR
    [ -e /tmp/logtail.sock ] && chown -R $RUNUSER /tmp/logtail.sock
    [ -e /tmp/logtail_check_point ] && chown -R $RUNUSER /tmp/logtail_check_point

    do_install_agent_stub telegraf
    do_install_agent_stub jvm

    # INSTANCE_SUFFIX is set, update ilogtail_config.json and ilogtaild.
    if [ ! -z ${INSTANCE_SUFFIX+x} ]; then
        # add some suffix related parameters to ilogtail_config.json.
        # the first line of ilogtail_config.json must be '{'.
        if [ "$INSTANCE_SUFFIX" != "" ]; then
            sed -i "1a \"logtail_sys_conf_dir\":\"$LOGTAIL_SYS_CONF_DIR/\",\n\"check_point_filename\":\"/tmp/logtail_check_point$INSTANCE_SUFFIX\"," $BIN_DIR/$CONFIG_FILE
        fi

        # inject INSTANCE_SUFFIX into ilogtaild to enable suffix filtering in checkStatus.
        local line_no=$(grep -n "BIN_DIR=\"/usr/local/ilogtail\"" $CONTROLLER_DIR/$CONTROLLER_FILE | awk -F":" '{print $1}')
        line_no=$((line_no - 1))
        sed -i "${line_no}c INSTANCE_SUFFIX=\"$INSTANCE_SUFFIX\"" $CONTROLLER_DIR/$CONTROLLER_FILE
        line_no=$(grep -n "# processname: ilogtaild" $CONTROLLER_DIR/$CONTROLLER_FILE | awk -F":" '{print $1}')
        sed -i "${line_no}c # processname: $CONTROLLER_FILE" $CONTROLLER_DIR/$CONTROLLER_FILE
    fi
    echo "Install logtail files successfully."

    echo "Configuring logtail service ..."
    local startup_status=""
    systemctl --version &> /dev/null
    if [ $? -eq 0 ] && [ -d "$SYSTEMD_SERVICE_DIR" ]; then
        echo "Use systemd for startup"
        local service_file_path="$SYSTEMD_SERVICE_DIR/$SYSTEMD_SERVICE_NAME"
        echo service_file_path: $service_file_path
        rm -f $service_file_path
        echo "[Unit]" >>$service_file_path

        echo "Description=ilogtail" >>$service_file_path
        echo "After=cloud-init.service" >>$service_file_path
        echo "" >>$service_file_path
        echo "[Service]" >>$service_file_path
        echo "Type=oneshot" >>$service_file_path
        echo "User=$RUNUSER" >>$service_file_path
        echo "RemainAfterExit=yes" >>$service_file_path
        echo "ExecStart=$CONTROLLER_DIR/$CONTROLLER_FILE start" >>$service_file_path
        echo "ExecStop=$CONTROLLER_DIR/$CONTROLLER_FILE stop" >>$service_file_path
        echo "" >>$service_file_path
        echo "[Install]" >>$service_file_path
        echo "WantedBy=default.target" >>$service_file_path
        systemctl enable $SYSTEMD_SERVICE_NAME
        if [ $? -eq 0 ]; then
            startup_status="ok"
            echo "systemd startup successfully."
        else
            rm -f $service_file_path
            # echo "systemd startup failed."
        fi
    fi

    if [ "$startup_status" != "ok" ]; then
        if [ $1 = $ALIYUN_OS ] || [ $1 = $CENTOS_OS ] || [ $1 = $OPENSUSE_OS ]; then
            chkconfig --add $CONTROLLER_FILE
            chkconfig $CONTROLLER_FILE on
            echo "chkconfig add ilogtaild successfully."
        elif [ $1 = $DEBIAN_OS ] || [ $1 = $UBUNTU_OS ]; then
            update-rc.d $CONTROLLER_FILE start 55 2 3 4 5 . stop 45 0 1 6 .
            echo "update-rc.d add ilogtaild successfully."
        else
            ln -s $CONTROLLER_DIR/$CONTROLLER_FILE /etc/rc.d/rc0.d/K45$CONTROLLER_FILE
            ln -s $CONTROLLER_DIR/$CONTROLLER_FILE /etc/rc.d/rc1.d/K45$CONTROLLER_FILE
            ln -s $CONTROLLER_DIR/$CONTROLLER_FILE /etc/rc.d/rc2.d/S55$CONTROLLER_FILE
            ln -s $CONTROLLER_DIR/$CONTROLLER_FILE /etc/rc.d/rc3.d/S55$CONTROLLER_FILE
            ln -s $CONTROLLER_DIR/$CONTROLLER_FILE /etc/rc.d/rc4.d/S55$CONTROLLER_FILE
            ln -s $CONTROLLER_DIR/$CONTROLLER_FILE /etc/rc.d/rc5.d/S55$CONTROLLER_FILE
            ln -s $CONTROLLER_DIR/$CONTROLLER_FILE /etc/rc.d/rc6.d/K45$CONTROLLER_FILE
            echo "add ilogtail into /etc/rc.d/ successfully."
        fi
    fi
    echo "Configure logtail successfully."

    echo "Starting logtail ..."
    $CONTROLLER_DIR/$CONTROLLER_FILE start
    if [ $? -eq 0 ]; then
        echo "Start logtail successfully."
    else
        logError "Start logtail failed."
        rm -rf logtail-linux64
        rm -f $PACKAGE_NAME
        exit 1
    fi

    sleep 3
    local appinfo=$BIN_DIR"/app_info.json"
    if [ -f $appinfo ]; then
        cat $appinfo
    fi
    rm -rf logtail-linux64
    rm -f $PACKAGE_NAME
}

do_uninstall_loongcollector() {
    if [ -f $CONTROLLER_DIR/$LOONGCOLLECTOR_CONTROLLER_FILE ]; then
        $CONTROLLER_DIR/$LOONGCOLLECTOR_CONTROLLER_FILE stop
        if [ $? -eq 0 ]; then
            echo "Stop loongcollector successfully."
        else
            logError "Stop loongcollector failed."
        fi
    else
       return
    fi

    local service_file_path="$SYSTEMD_SERVICE_DIR/$LOONGCOLLECTOR_SYSTEMD_SERVICE_NAME"
    if [ -f $service_file_path ]; then
        systemctl disable $LOONGCOLLECTOR_SYSTEMD_SERVICE_NAME
        rm -f $service_file_path
        echo "systemd delete loongcollectord successfully."
    fi

    if [ $1 = $ALIYUN_OS ] || [ $1 = $CENTOS_OS ] || [ $1 = $OPENSUSE_OS ]; then
        chkconfig $LOONGCOLLECTOR_CONTROLLER_FILE off 2>/dev/null
        chkconfig --del $LOONGCOLLECTOR_CONTROLLER_FILE 2>/dev/null
        echo "chkconfig del loongcollectord successfully."
    elif [ $1 = $DEBIAN_OS ] || [ $1 = $UBUNTU_OS ]; then
        update-rc.d -f $LOONGCOLLECTOR_CONTROLLER_FILE remove
        echo "update-rc.d del loongcollectord successfully."
    else
        if [ -f /etc/rc.d/rc0.d/K45$LOONGCOLLECTOR_CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc0.d/K45$LOONGCOLLECTOR_CONTROLLER_FILE
        fi
        if [ -f /etc/rc.d/rc1.d/K45$LOONGCOLLECTOR_CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc1.d/K45$LOONGCOLLECTOR_CONTROLLER_FILE
        fi
        if [ -f /etc/rc.d/rc2.d/S55$LOONGCOLLECTOR_CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc2.d/S55$LOONGCOLLECTOR_CONTROLLER_FILE
        fi
        if [ -f /etc/rc.d/rc3.d/S55$LOONGCOLLECTOR_CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc3.d/S55$LOONGCOLLECTOR_CONTROLLER_FILE
        fi
        if [ -f /etc/rc.d/rc4.d/S55$LOONGCOLLECTOR_CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc4.d/S55$LOONGCOLLECTOR_CONTROLLER_FILE
        fi
        if [ -f /etc/rc.d/rc5.d/S55$LOONGCOLLECTOR_CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc5.d/S55$LOONGCOLLECTOR_CONTROLLER_FILE
        fi
        if [ -f /etc/rc.d/rc6.d/K45$LOONGCOLLECTOR_CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc6.d/K45$LOONGCOLLECTOR_CONTROLLER_FILE
        fi
        echo "del loongcollectord from /etc/rc.d/ successfully."
    fi
    if [ -f $CONTROLLER_DIR/$LOONGCOLLECTOR_CONTROLLER_FILE ]; then
        rm -f $CONTROLLER_DIR/$LOONGCOLLECTOR_CONTROLLER_FILE
    fi
    echo "Uninstall loongcollector successfully."
}

do_uninstall() {
    if [ -f $CONTROLLER_DIR/$CONTROLLER_FILE ]; then
        $CONTROLLER_DIR/$CONTROLLER_FILE stop
        if [ $? -eq 0 ]; then
            echo "Stop logtail successfully."
        else
            logError "Stop logtail failed."
        fi
    fi

    local service_file_path="$SYSTEMD_SERVICE_DIR/$SYSTEMD_SERVICE_NAME"
    if [ -f $service_file_path ]; then
        systemctl disable $SYSTEMD_SERVICE_NAME
        rm -f $service_file_path
        echo "systemd delete ilogtaild successfully."
    fi

    if [ $1 = $ALIYUN_OS ] || [ $1 = $CENTOS_OS ] || [ $1 = $OPENSUSE_OS ]; then
        chkconfig $CONTROLLER_FILE off 2>/dev/null
        chkconfig --del $CONTROLLER_FILE 2>/dev/null
        echo "chkconfig del ilogtaild successfully."
    elif [ $1 = $DEBIAN_OS ] || [ $1 = $UBUNTU_OS ]; then
        update-rc.d -f $CONTROLLER_FILE remove
        echo "update-rc.d del ilogtaild successfully."
    else
        if [ -f /etc/rc.d/rc0.d/K45$CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc0.d/K45$CONTROLLER_FILE
        fi
        if [ -f /etc/rc.d/rc1.d/K45$CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc1.d/K45$CONTROLLER_FILE
        fi
        if [ -f /etc/rc.d/rc2.d/S55$CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc2.d/S55$CONTROLLER_FILE
        fi
        if [ -f /etc/rc.d/rc3.d/S55$CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc3.d/S55$CONTROLLER_FILE
        fi
        if [ -f /etc/rc.d/rc4.d/S55$CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc4.d/S55$CONTROLLER_FILE
        fi
        if [ -f /etc/rc.d/rc5.d/S55$CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc5.d/S55$CONTROLLER_FILE
        fi
        if [ -f /etc/rc.d/rc6.d/K45$CONTROLLER_FILE ]; then
            unlink /etc/rc.d/rc6.d/K45$CONTROLLER_FILE
        fi
        echo "del ilogtaild from /etc/rc.d/ successfully."
    fi

    if [ -d $BIN_DIR ] || [ -f $BIN_DIR ]; then
        rm -rf $BIN_DIR
    fi
    if [ -f $CONTROLLER_DIR/$CONTROLLER_FILE ]; then
        rm -f $CONTROLLER_DIR/$CONTROLLER_FILE
    fi
    echo "Uninstall logtail successfully."
}



check_arch() {
    if [ x$ARCH == x ]; then
        echo "Can not get arch with uname -i!"
        exit
    fi
    case $ARCH in
    'x86_64')
        echo
        ;;
    'aarch64')
        echo
        ;;
    *)
        echo "Arch:$ARCH not supported, exit"
        exit 1
        ;;
    esac
    echo -e "OS Arch:\t"$ARCH
}

get_os_version() {
    if [ $(echo $os_issue | grep debian | wc -l) -ge 1 ]; then
        OS_VERSION=$DEBIAN_OS
    elif [ $(echo $os_issue | grep ubuntu | wc -l) -ge 1 ]; then
        OS_VERSION=$UBUNTU_OS
    elif [ $(echo $os_issue | grep centos | wc -l) -ge 1 ]; then
        OS_VERSION=$CENTOS_OS
    elif [ $(echo $os_issue | grep 'red hat' | wc -l) -ge 1 ]; then
        OS_VERSION=$CENTOS_OS
    elif [ $(echo $os_issue | grep aliyun | wc -l) -ge 1 ]; then
        OS_VERSION=$ALIYUN_OS
    elif [ $(echo $os_issue | grep opensuse | wc -l) -ge 1 ]; then
        OS_VERSION=$OPENSUSE_OS
    fi
}


check_os_version() {
    get_os_version
    if [ $OS_VERSION = $OTHER_OS ]; then
        # echo -e "Can not get os version from /etc/issue, try lsb_release"
        os_issue=$(lsb_release -a 2>/dev/null)
        get_os_version
    fi

    if [ $OS_VERSION = $OTHER_OS ]; then
        # echo -e "Can not get os version from lsb_release, try check specific files"
        if [ -f "/etc/redhat-release" ]; then
            OS_VERSION=$CENTOS_OS
        elif [ -f "/etc/debian_version" ]; then
            OS_VERSION=$DEBIAN_OS
        elif command -v chkconfig &> /dev/null; then
            OS_VERSION=$CENTOS_OS
        elif command -v update-rc.d &> /dev/null; then
            OS_VERSION=$DEBIAN_OS
        else
            logError "Can not get os verison"
        fi
    fi
    echo -e "OS Distribution:\t"$OS_VERSION
}

check_cpu_flags() {
    case $ARCH in
    'x86_64')
        CPU_CAPABILITIES=$(cat /proc/cpuinfo | grep flags | head -n 1| awk '{print tolower($0)}')
        if [[ ! "$CPU_CAPABILITIES" =~ "sse4_2" ]]; then
            echo "The currently recognized CPU architecture is x86_64. The minimum requirement for Logtail to run is to support the sse4_2 instruction set. The current CPU cannot meet the requirements and therefore exits."
            exit 1
        fi    
        ;;   
    'aarch64')
        CPU_CAPABILITIES=$(cat /proc/cpuinfo | grep Features | head -n 1| awk '{print tolower($0)}')
        if [[ ! "$CPU_CAPABILITIES" =~ "asimddp" ]] || [[ ! "$CPU_CAPABILITIES" =~ "asimdhp" ]]; then
            echo "The currently recognized CPU architecture is aarch64. The minimum requirement for Logtail to run is the ARMv8.2-A structure. The current CPU cannot meet the requirements and therefore exits."
            exit 1
        fi
        ;;   
    *)
        echo "Arch:$ARCH not supported, exit"
        exit 1
    ;;
    esac
}


check_glibc_version() {
    # get glibc version
    glibc_version=$(ldd --version | head -n1 | awk '{print $NF}')
    # split version
    IFS='.' read -ra VERSION_PARTS <<< "$glibc_version"
    major=${VERSION_PARTS[0]}
    minor=${VERSION_PARTS[1]}
    # compare version
    if [[ $major -gt 2 ]] || { [[ $major -eq 2 ]] && [[ $minor -ge 12 ]]; }; then
        echo "current glibc version is : $glibc_version"
    else
        echo "The minimum glibc version requirement for Logtail to run is 2.12. The current glibc version $glibc_version cannot meet the requirements and therefore exits."
        exit 1
    fi
}

CN_BEIJING="cn-beijing"
CN_BEIJING_INTERNET=$CN_BEIJING$INTERNET_POSTFIX
CN_BEIJING_INNER=$CN_BEIJING$INNER_POSTFIX
CN_BEIJING_ACCELERATION=$CN_BEIJING$ACCELERATION_POSTFIX

CN_QINGDAO="cn-qingdao"
CN_QINGDAO_INTERNET=$CN_QINGDAO$INTERNET_POSTFIX
CN_QINGDAO_INNER=$CN_QINGDAO$INNER_POSTFIX
CN_QINGDAO_ACCELERATION=$CN_QINGDAO$ACCELERATION_POSTFIX

CN_SHANGHAI="cn-shanghai"
CN_SHANGHAI_INTERNET=$CN_SHANGHAI$INTERNET_POSTFIX
CN_SHANGHAI_INNER=$CN_SHANGHAI$INNER_POSTFIX
CN_SHANGHAI_FINANCE=$CN_SHANGHAI$FINANCE_POSTFIX
CN_SHANGHAI_FINANCE_INTERNET=$CN_SHANGHAI_FINANCE$INTERNET_POSTFIX
CN_SHANGHAI_ACCELERATION=$CN_SHANGHAI$ACCELERATION_POSTFIX

CN_HANGZHOU="cn-hangzhou"
CN_HANGZHOU_INTERNET=$CN_HANGZHOU$INTERNET_POSTFIX
CN_HANGZHOU_FINANCE=$CN_HANGZHOU$FINANCE_POSTFIX
CN_HANGZHOU_FINANCE_INTERNET=$CN_HANGZHOU_FINANCE$INTERNET_POSTFIX
CN_HANGZHOU_INNER=$CN_HANGZHOU$INNER_POSTFIX
CN_HANGZHOU_ACCELERATION=$CN_HANGZHOU$ACCELERATION_POSTFIX

CN_SHENZHEN="cn-shenzhen"
CN_SHENZHEN_INTERNET=$CN_SHENZHEN$INTERNET_POSTFIX
CN_SHENZHEN_FINANCE=$CN_SHENZHEN$FINANCE_POSTFIX
CN_SHENZHEN_FINANCE_INTERNET=$CN_SHENZHEN_FINANCE$INTERNET_POSTFIX
CN_SHENZHEN_INNER=$CN_SHENZHEN$INNER_POSTFIX
CN_SHENZHEN_ACCELERATION=$CN_SHENZHEN$ACCELERATION_POSTFIX

AP_NORTHEAST_1="ap-northeast-1"
AP_NORTHEAST_1_INTERNET=$AP_NORTHEAST_1$INTERNET_POSTFIX
AP_NORTHEAST_1_INNER=$AP_NORTHEAST_1$INNER_POSTFIX
AP_NORTHEAST_1_ACCELERATION=$AP_NORTHEAST_1$ACCELERATION_POSTFIX

EU_CENTRAL_1="eu-central-1"
EU_CENTRAL_1_INTERNET=$EU_CENTRAL_1$INTERNET_POSTFIX
EU_CENTRAL_1_INNER=$EU_CENTRAL_1$INNER_POSTFIX
EU_CENTRAL_1_ACCELERATION=$EU_CENTRAL_1$ACCELERATION_POSTFIX

ME_EAST_1="me-east-1"
ME_EAST_1_INTERNET=$ME_EAST_1$INTERNET_POSTFIX
ME_EAST_1_INNER=$ME_EAST_1$INNER_POSTFIX
ME_EAST_1_ACCELERATION=$ME_EAST_1$ACCELERATION_POSTFIX

US_WEST_1="us-west-1"
US_WEST_1_INTERNET=$US_WEST_1$INTERNET_POSTFIX
US_WEST_1_INNER=$US_WEST_1$INNER_POSTFIX
US_WEST_1_ACCELERATION=$US_WEST_1$ACCELERATION_POSTFIX

print_help() {
    echo "Usage:"
    echo -e "\tlogtail.sh [install <REGION> [user]]  [uninstall]  [install-local <REGION>]  [upgrade] [upgrade-local <REGION>]"
    echo "Parameter:"
    echo -e "\t<REGION>:"
    echo -e "\t(for all ECS VM in VPC) you can use 'auto' to ask logtail.sh decide your region automatically (./logtail.sh install auto)."
    echo -e "\t(for ECS VM if 'auto' not work) $CN_BEIJING $CN_QINGDAO $CN_SHANGHAI $CN_HANGZHOU $CN_SHENZHEN $AP_NORTHEAST_1 $EU_CENTRAL_1 $ME_EAST_1 $US_WEST_1, etc (./logtail.sh install $CN_BEIJING)."
    echo -e "\t(for Non-ECS VM or other IDC) $CN_BEIJING_INTERNET $CN_QINGDAO_INTERNET $CN_SHANGHAI_INTERNET $CN_HANGZHOU_INTERNET $CN_SHENZHEN_INTERNET $AP_NORTHEAST_1_INTERNET $EU_CENTRAL_1_INTERNET $ME_EAST_1_INTERNET $US_WEST_1_INTERNET, etc."
    echo -e "\t(for ECS VM in Finance) $CN_HANGZHOU_FINANCE $CN_HANGZHOU_FINANCE_INTERNET $CN_SHANGHAI_FINANCE $CN_SHANGHAI_FINANCE_INTERNET $CN_SHENZHEN_FINANCE $CN_SHENZHEN_FINANCE_INTERNET."
    echo -e "\t(for Machine inner Alibaba Group) $CN_BEIJING_INNER $CN_QINGDAO_INNER $CN_SHANGHAI_INNER $CN_HANGZHOU_INNER $CN_SHENZHEN_INNER $AP_NORTHEAST_1_INNER $EU_CENTRAL_1_INNER $ME_EAST_1_INNER $US_WEST_1_INNER, etc."
    echo -e "\t(for Global Acceleration) $CN_BEIJING_ACCELERATION $CN_QINGDAO_ACCELERATION $CN_SHANGHAI_ACCELERATION $CN_HANGZHOU_ACCELERATION $CN_SHENZHEN_ACCELERATION $AP_NORTHEAST_1_ACCELERATION $EU_CENTRAL_1_ACCELERATION $ME_EAST_1_ACCELERATION $US_WEST_1_ACCELERATION, etc."
    echo "Commands:"
    echo -e "\tinstall $CN_BEIJING:\t (recommend) auto download package, install logtail to /usr/local/ilogtail, for $CN_BEIJING region"
    echo -e "\tuninstall:\t uninstall logtail from /usr/local/ilogtail"
    echo -e "\tupgrade:\t upgrade logtail to latest version"
    echo -e "\tinstall-agent $CN_BEIJING telegraf"
    echo "Options:"
    echo -e "\t-v <version>: specify logtail version to install or upgrade, eg. ./logtail.sh install cn-hangzhou -v 0.16.36"
}
echo "logtail.sh version: "$INSTALLER_VERSION


# Check whether the environment meets expectations
check_arch
check_os_version
check_cpu_flags
check_glibc_version

argc=$#
# -s <instance_suffix> -v <version>
for ((i = 1; i <= "$#"; i++)); do
    if [ "${!i}" == "-s" ] && [ "$i" -lt "$#" ]; then
        i=$((i + 1))
        INSTANCE_SUFFIX=${!i}
        argc=$((argc - 2))
    elif [ "${!i}" == "-v" ] && [ "$i" -lt "$#" ]; then
        i=$((i + 1))
        VERSION=${!i}
        echo "logtail version is specified: $VERSION"
        argc=$((argc - 2))
    elif [ "${!i}" == "-u" ] && [ "$i" -lt "$#" ]; then
        i=$((i + 1))
        RUNUSER=${!i}
        argc=$((argc - 2))
    elif [ "${!i}" == "-ebpf" ] && [ "$i" -lt "$#" ]; then
        i=$((i + 1))
        EBPF=${!i}
        argc=$((argc - 2))
    fi
done
# INSTANCE_SUFFIX is set, update BIN_DIR and CONTROLLER_FILE
if [ ! -z "${INSTANCE_SUFFIX+x}" ]; then
    BIN_DIR="$BIN_DIR$INSTANCE_SUFFIX"
    CONTROLLER_FILE="$CONTROLLER_FILE$INSTANCE_SUFFIX"
    LOONGCOLLECTOR_CONTROLLER_FILE="$LOONGCOLLECTOR_CONTROLLER_FILE$INSTANCE_SUFFIX"
    SYSTEMD_SERVICE_NAME="${CONTROLLER_FILE}.service"
    LOONGCOLLECTOR_SYSTEMD_SERVICE_NAME="$LOONGCOLLECTOR_CONTROLLER_FILE$INSTANCE_SUFFIX"
    LOGTAIL_SYS_CONF_DIR="$LOGTAIL_SYS_CONF_DIR$INSTANCE_SUFFIX"
    echo "instance suffix ($INSTANCE_SUFFIX) is specified, update BIN_DIR and CONTROLLER_FILE"
    echo "BIN_DIR: $BIN_DIR"
    echo "CONTROLLER_FILE: $CONTROLLER_FILE"
    echo "LOGTAIL_SYS_CONF_DIR: $LOGTAIL_SYS_CONF_DIR"
fi

case $argc in
0)
    print_help
    exit 1
    ;;
1)
    case $1 in
    uninstall)
        do_uninstall_loongcollector $OS_VERSION
        do_uninstall $OS_VERSION
        ;;
    upgrade)
        do_upgrade
        do_uninstall_loongcollector $OS_VERSION
        ;;
    upgrade-local)
        do_upgrade "use_local_package"
        do_uninstall_loongcollector $OS_VERSION
        ;;
    *)
        print_help
        exit 1
        ;;
    esac
    ;;
2)
    if [ $1 = "install" ] || [ $1 = "install-local" ]; then
        do_uninstall_loongcollector $OS_VERSION
        do_uninstall $OS_VERSION
        do_install $OS_VERSION $2 $1
    else
        print_help
        exit 1
    fi
    
    ;;
3)
    if [ $1 == "install-agent" ]; then
        do_install_agent $2 $3
    else
        print_help
        exit 1
    fi
    ;;
*)
    print_help
    exit 1
    ;;
esac

exit 0
