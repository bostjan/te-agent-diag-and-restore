#!/bin/bash
#
# ThousandEyes Enterprise Agent fixup and system/crash data collection script (unofficial)
#



### Shell configuration
#
#set -e
set -u
#set -o pipefail



### Messaging functions
#
_echo() {
    MSG="$1"
    echo "AgentFixup: $MSG"
}

_fatalError() {
    MSG="$1"
    echo "AgentFixup ERROR: $MSG"
    exit 1
}



### Messaging functions
#
_manageAgentService() {
    ACTION="$1"
    if   [ "$AGENT_OS_INIT" == "systemd" ]; then
        systemctl $ACTION te-agent

    elif [ "$AGENT_OS_INIT" == "upstart" ]; then

        RES=`status te-agent | grep 'start/running' -c `
        if [ "$RES" -gt "0" ]; then
            AGENT_STATUS="running"
        else
            AGENT_STATUS="stopped"
        fi

        if [ "$ACTION" == "restart" ]; then
            if   [ "$AGENT_STATUS" == "running" ]; then
                restart te-agent
            elif [ "$AGENT_STATUS" == "stopped" ]; then
                start te-agent
            fi
        fi

        if [ "$ACTION" == "stop" ]; then
            if   [ "$AGENT_STATUS" == "running" ]; then
                stop te-agent
            elif [ "$AGENT_STATUS" == "stopped" ]; then
                _echo "Upstart: agent already stopped"
            fi
        fi

        if [ "$ACTION" == "start" ]; then
            if   [ "$AGENT_STATUS" == "running" ]; then
                _echo "Upstart: agent already running"
            elif [ "$AGENT_STATUS" == "stopped" ]; then
                start te-agent
            fi
        fi

    else
        _fatalError "Unsupported AGENT_OS_INIT ($AGENT_OS_INIT)"
    fi
}



### Check if running as root
#
if [ "`id -u`" != "0" ]; then
    _fatalError "This installation must be run as root (hint: 'sudo COMMAND')"
fi



### Determine OS and service management flavour
#
if [ -f /etc/debian_version ]; then
    AGENT_OS_DISTRO="ubuntu"
elif [ -f /etc/redhat-release ]; then
    AGENT_OS_DISTRO="redhat"
else
    _fatalError "Unable to determine OS distribution"
fi

if which systemctl &> /dev/null; then
    AGENT_OS_INIT="systemd"
elif which start &> /dev/null; then
    AGENT_OS_INIT="upstart"
else
    _fatalError "Unable to determine OS service management flavour (not systemd nor upstart?)"
fi



### Check if all packages are installed
#
       REQUIRED_PROGRAMS="dmidecode lspci    lsusb    pstree lsof strace sqlite3 netstat"
REQUIRED_PACKAGES_UBUNTU="dmidecode pciutils usbutils psmisc lsof strace sqlite3 net-tools"
REQUIRED_PACKAGES_REDHAT="dmidecode pciutils usbutils psmisc lsof strace sqlite  net-tools"
if which $REQUIRED_PROGRAMS &> /dev/null; then
    _echo "All required programs found ($REQUIRED_PROGRAMS)"
else
    if [ "$AGENT_OS_DISTRO" == "ubuntu" ]; then
        _echo "Installing packages: $REQUIRED_PACKAGES_UBUNTU"
        # About /dev/null: http://askubuntu.com/questions/372810/how-to-prevent-script-not-to-stop-after-apt-get
        apt-get -y install $REQUIRED_PACKAGES_UBUNTU < "/dev/null"
    elif [ "$AGENT_OS_DISTRO" == "redhat" ]; then
        _echo "Installing packages: $REQUIRED_PACKAGES_REDHAT"
        yum install -y $REQUIRED_PACKAGES_REDHAT
    else
        _fatalError "Internal error"
    fi
fi



### Get agent ID
#
AGENT_ID=`echo "SELECT agent_id FROM tb_agent_id;" | sqlite3 /var/lib/te-agent/te-agent-config.sqlite`
_echo "Agent ID = $AGENT_ID"



### Collect data - system and pre-agent-stop
#
DATETIME_UTC=`date -u "+%Y%m%d-%H%M%SUTC"`
DATADIRNAME="agentdata-id$AGENT_ID-$DATETIME_UTC"
mkdir $DATADIRNAME
_echo "Output directory: $DATADIRNAME"

_echo "Collecting system information..."
_echo "  Hardware and basic host information..."
dmidecode      > $DATADIRNAME/sys-dmidecode.out || true   # Does not work in containers
mount          > $DATADIRNAME/sys-mount.out
df -h          > $DATADIRNAME/sys-df-h.out
df -ih         > $DATADIRNAME/sys-df-ih.out
free           > $DATADIRNAME/sys-free.out
uname -a       > $DATADIRNAME/sys-uname-a

_echo "  /proc information..."
cat /proc/cmdline   > $DATADIRNAME/sys-proc-cmdline.out
cat /proc/diskstats > $DATADIRNAME/sys-proc-diskstats.out
cat /proc/loadavg   > $DATADIRNAME/sys-proc-loadavg.out
cat /proc/meminfo   > $DATADIRNAME/sys-proc-meminfo.out
cat /proc/uptime    > $DATADIRNAME/sys-proc-uptime.out

_echo "  List installed packages..."
if [ "$AGENT_OS_DISTRO" == "ubuntu" ]; then
    dpkg -l   > $DATADIRNAME/sys-dpkg-l.out
elif [ "$AGENT_OS_DISTRO" == "redhat" ]; then
    rpm -qa   > $DATADIRNAME/sys-rpm-qa.out
else
    _fatalError "Internal error"
fi

_echo "  Running processes information (before agent restart)..."
ps auxef       > $DATADIRNAME/pre-ps-auxef.out
ps -eLf        > $DATADIRNAME/pre-ps-eLf.out
netstat -lntup > $DATADIRNAME/pre-netstat-lntup.out
lsof -n        > $DATADIRNAME/pre-lsof-n.out



### Restart the agent
#
_echo "Restarting the agent..."
_manageAgentService "restart"



### Check agent logs, look for err= (DB corruption)
#
_echo "(Waiting for a moment to allow the agent to analyze the database)"
sleep 2
_echo "Checking if agent result cache database is currupted..."
SQLITE_ERROR_COUNT=`tail -n 300 /var/log/te-agent.log | grep "Agent version" -A5 | grep -v 'Vacuuming database' | grep -Ec '(VACUUM|err=)'`
if [ "$SQLITE_ERROR_COUNT" -eq 0 ]; then
    _echo "  No corruption in result cache detected, skipping adding it to the diagnostics package."
else
    _echo "  Corrupted database detected."

    _echo "    Stopping the agent"
    _manageAgentService "stop"

    _echo "    Moving the corrupted DB to diagnostics package"
    mv /var/lib/te-agent/te-agent.sqlite $DATADIRNAME/te-agent.sqlite.CORRUPTED

    _echo "    Starting the agent (it will regenerate empty result cache database)"
    _manageAgentService "start"

fi



### Collect the log files
#
_echo "Collecting agent and system log files..."
mkdir $DATADIRNAME/log
cp /var/log/te-agent*   $DATADIRNAME/log/
if [ "$AGENT_OS_DISTRO" == "ubuntu" ]; then
    cp /var/log/kern.*     $DATADIRNAME/log/
    cp /var/log/syslog.*   $DATADIRNAME/log/
    cp /var/log/dpkg*      $DATADIRNAME/log/
    cp -pR /var/log/apt    $DATADIRNAME/log/
elif [ "$AGENT_OS_DISTRO" == "redhat" ]; then
    cp /var/log/messages   $DATADIRNAME/log/
    cp /var/log/yum.*      $DATADIRNAME/log/
else
    _fatalError "Internal error"
fi



### Compress the diagnostics package
#
DATAFILE="$DATADIRNAME.tar.gz"
_echo "Compressing the collected information..."
tar -c -z -f $DATAFILE $DATADIRNAME
rm -rf $DATADIRNAME
_echo "  Data collection complete."
_echo "Generated diagnostic file: $DATAFILE"
_echo ""
_echo "Uploading the generated file using transfer.sh service."
_echo "Upon successful upload you will see the URL where the data can be retrieved from:"
echo
echo -n "    "
curl \
  --upload-file \
  ./$DATAFILE \
  https://transfer.sh/$DATAFILE

UPLOAD_RESULT="$?"

# Missing newline in the url
echo
echo
if [ "$UPLOAD_RESULT" == "0" ]; then
    _echo "Take the URL above and send it over to support@thousandeyes.com."
else
    _echo "WARNING: Automatic upload failed!"
    _echo "This is probably because proxy usage is required."
    _echo "Please upload the diagnostic package manually using the following command:"
    echo
    echo "https_proxy=\"http://user:pass@proxy-server:port/\"   curl   --upload-file ./$DATAFILE   https://transfer.sh/$DATAFILE"
    echo
    _echo "Once the uplaod is successfull, you will see the URL of the uploaded file."
    _echo "Take that URL and send it over to support@thousandeyes.com."
fi
