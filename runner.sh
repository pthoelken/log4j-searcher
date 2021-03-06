#!/bin/bash -e

# Original from @becker-rzht
# Edited from @pthoelken

strTempDir=$(mktemp -d)
strDate=$(date '+%d-%m-%Y_%H-%M-%S')
strLogDirectory=~/log4j-log
strLogUnparsed=$strLogDirectory/log4j-$strDate-$HOSTNAME-$USER-unparsed.log
strLogParsed=$strLogDirectory/log4j-$strDate-$HOSTNAME-$USER-parsed.log

objDetector="https://github.com/pthoelken/log4j-detector/blob/master/log4j-detector-2021.12.29.jar"
objDetectorBinary=log4j-detector-2021.12.29.jar

function CopyLatestDetector() {
    echo -n "* Copy: log4j-detector latest version ... "
    cp $objDetectorBinary $strTempDir && echo OK
}

cd "$strTempDir"

cleaner() {
    echo -e "* Removing: $strTempDir ... "
    rm -rf "${strTempDir:-does-not-exist}"
}
trap cleaner INT TERM EXIT

function CheckApplication() {
    if ! hash $1 2>/dev/null; then
        echo "* Error: Software $1 is not installed. Please be sure, that $1 is installed before running this script! Abort."
        exit 1
    fi
}

function initApplication() {
    if [ ! -d $strLogDirectory ]; then
        mkdir -p $strLogDirectory
    fi

    rm -rf $strLogDirectory/* 2>/dev/null
}

function DownloadJava() {
    m="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    case "$m" in
        armsf) jre="https://cdn.azul.com/zulu-embedded/bin/zulu11.52.13-ca-jdk11.0.13-linux_aarch32sf.tar.gz" ;; # RPI
        armhf) jre="https://cdn.azul.com/zulu-embedded/bin/zulu11.52.13-ca-jdk11.0.13-linux_aarch32hf.tar.gz" ;; # RPI
        *64)   jre="https://cdn.azul.com/zulu/bin/zulu11.52.13-ca-jre11.0.13-linux_x64.tar.gz" ;; # 64 Bit
        i?86)  jre="https://cdn.azul.com/zulu/bin/zulu11.52.13-ca-jre11.0.13-linux_i686.tar.gz" ;; # 32 Bit
        *)     echo "* ERROR: No Java binary tarball found for $m" 2>&1; exit 1
    esac

    echo -n "* Downloading: jre ... "
    wget -qO - "$jre" | tar xzf - && echo OK

    objJava=$(sudo find . -name java -type f -executable| head -1)
}

function ExtractMacJava() {

    if [[ `uname -m` == 'arm64' ]]; then
        jre="https://cdn.azul.com/zulu/bin/zulu11.52.13-ca-jdk11.0.13-macosx_aarch64.tar.gz"
    else
        jre="https://cdn.azul.com/zulu/bin/zulu11.52.13-ca-jdk11.0.13-macosx_x64.tar.gz"
    fi

    echo -n "* Extracting: jre ... "
    tar xzf $jre && echo OK

    objJava=$(sudo find . -name java -type f -executable| head -1)
}

function DownloadLatestDetector() {
    echo -n "* Downloading: log4j-detector latest version ... "
    wget -q "$objDetector" && echo OK
}

function Scanning() {
    find_opt=(
    /
    \( -type d \( -fstype autofs -o -fstype fuse.sshfs -o -fstype nfs -o -fstype proc -o -fstype sshfs -o -fstype sysfs -o -fstype tmpfs \) -prune -o -type f \)  
    -not -path  \*/.snapshots/\*
    -not -path  \*/.m2/repo/\*
    -type f -print
    )

    warn=()
    while read line; do

        case "$line" in
            "-- Problem"*" encrypted "*) ;;         # HIDE
            "-- Problem"*".zip.ZipException"*) ;;   # HIDE
            "-- Problem"*".io.EOFException"*) ;;    # HIDE
            "-- Problem"*"no magic number"*) ;;     # HIDE
            "-- Problem"*"not find ZIP magic"*);;   # HIDE
            "-- Problem"*"malformed") ;;            # HIDE
            "-- Problem"*"invalid distance"*) ;;    # HIDE
            "-- Problem"*) echo "  ${line#-}";;     # SHOW (unknown problems)
            "-- "*);;                               # HIDE
            *" _POTENTIALLY_SAFE_"*);;              # HIDE
            *" _OLD_");;                            # HIDE (for the moment)
            *) echo "  - $line" ;;                  # SHOW (the rest)
        esac

    done < <(sudo find "${find_opt[@]}" | sudo "$objJava" -jar ${objDetector##*/} --stdin | tee -a $strLogUnparsed || true) > /dev/null 2>&1

    printf "\n"
}

function ParseLogs() {
    echo "* Processing: Parse log for $1 output ..."
    cat $strLogUnparsed | grep -i $1 | tee -a $strLogParsed > /dev/null 2>&1
}

function ParseLogsCall() {
    if (grep -i "_VULNERABLE_" $strLogUnparsed || grep -i "_OLD_" $strLogUnparsed || grep -i "_POTENTIALLY_SAFE_" $strLogUnparsed ); then
        printf "\n=== LOG4J DETECTOR PARSED LOG WITH VULNERABILITIES AND UNSAFES AND OLDS ONLY ===\n\nScan Date: $strDate\nHostname: $HOSTNAME\nUsername: $USER\n\n=== LOG4J DETECTOR PARSED LOG RESULTS BELOW ===\n\n" >> $strLogParsed
        ParseLogs "_VULNERABLE_"
        ParseLogs "_OLD_"
        ParseLogs "_POTENTIALLY_SAFE_"
        printf "\n=== LOG4J DETECTOR PARSED LOG ENDING ===\n\n" >> $strLogParsed
        printf "* Result: Warning! You can find the final log file here: $strLogParsed\n"
    else
        echo "* Result: No vulnerabilities are found in $strLogUnparsed. Nothing to parse, nothing to do at your side! :)"
    fi
}

function ApplicationCheck() {
    CheckApplication "sudo"
    CheckApplication "tee"
    CheckApplication "grep"
    CheckApplication "wget"
    CheckApplication "cat"
}

function Dispose() {
    echo -n "* Removing: Unparsed log files and log folders ... "
    sudo chown $USER:$USER -R $strLogDirectory && echo OK

    if [ -f $strLogUnparsed ]; then
        rm -rf $strLogUnparsed
    fi

}

initApplication
ApplicationCheck

case "$1" in 
    "--offline")
        ExtractMacJava
        CopyLatestDetector
        ;;
    "--online")
        DownloadJava
        DownloadLatestDetector
        ;;
    *)
        echo -e "Unkown Command - $0 { --online | --offline } - Online: download online the correct version. Offline: extract the macOS versions of jre. "
        exit 1
        ;;
esac

printf "\n+++ Scanning is starting with ...\n* Binary: $objJava\n* Detector: ${objDetector##*/}\n* Log File: $strLogUnparsed\n* State: in progress ...\n\n"
Scanning
ParseLogsCall
Dispose

exit 0
