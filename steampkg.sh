#!/bin/bash
#TODO ^(windows|macos|linux)$
#TODO bitness
#TODO clean shitty if statements

function usage {
echo "steampkg, a SteamCMD wrapper for downloading & packaging games
Usage: $0 [-x 0-9] [-n] -u <username> <appid [appid...]>

Options:
         -h     |  Displays this message
         -x N   |  [default: 9] Sets 7z archive compression level
         -n     |  Nuke depotcache and steamapps before downloading" 1>&2; exit 1
         -u     |  Username to login to Steam
}

function main {
checkappid
[[ "${nuke}" ]] && nuke || :
download
clean
getacfinfo
compress
}

function checkappid {
# check if appid is valid (numbers only)
appidRegex='^[0-9]*$'
if [[ "${i}" =~ $appidRegex ]]; then :; else echo "Error: Invalid appid!"; exit 1; fi
}

function checkprereqs {
# check if required files and commands exist
if [[ ! $(command -v 7z) ]]; then echo "7z not found! Closing."; exit 1; fi
if [[ ! $(command -v unbuffer) ]]; then echo "unbuffer not found! Closing."; exit 1; fi
if [[ -f steamcmd.sh ]]; then :; else echo 'steamcmd.sh not found! Make sure '"$0"' is in the same directory.'; exit 1; fi
if [[ -f vdf2json.py ]]; then :; else echo 'vdf2json.py not found! Download it here: https://gist.githubusercontent.com/ynsta/7221512c583fbfbafe6d/raw/vdf2json.py'; exit 1; fi
}

function nuke {
# deletes depotcache and steamapps
# TODO: maybe not needed? though i use it so meh
echo DELETING depotcache AND steamapps IN 10 SECONDS
echo CTRL-C TO STOP
sleep 10
rm -rf depotcache steamapps
}

function download {
#TODO add arg for windows/macos/linux
#TODO add arg for 32bit/64bit config
unbuffer ./steamcmd.sh +login "${u}" +@sSteamCmdForcePlatformType windows +app_update "${i}" +quit | grep -iE 'update|success|install|clean|ok|check|package|extract'
}

function clean {
echo Cleaning appmanifest_"${i}".acf
sed -i '/LastOwner/c\\t"LastOwner"\t\t"0"' steamapps/appmanifest_"${i}".acf
}

function getacfinfo {
# Parse ACF info into JSON and load into variable
# https://gist.github.com/ynsta/7221512c583fbfbafe6d
ACF=$(python vdf2json.py -i steamapps/appmanifest_"${i}".acf)
# Get archive filename (You may need to rename the first part)
FILENAME=$(echo "${ACF}" | jq -r '.AppState.installdir+" ("+.AppState.appid+") [Depot "+(.AppState.InstalledDepots | keys | join(","))+"] [Build "+.AppState.buildid+"].7z"')
# Get install directory to add to archive
INSTALLDIR=$(echo "${ACF}" | jq -r '.AppState.installdir')
# Get depots and slap a wildcard to add to archive
DEPOTS=$(echo "${ACF}" | jq -r '.AppState.InstalledDepots | keys[] + "*"')
}

# Compress game using 7z
function compress {
# If compression level set, set variable; if not, max compression
[[ "${x}" ]] && : || x=9
# Run the damn thing!
7z a -mx"${x}" "${FILENAME}" `for i in "${DEPOTS}"; do echo depotcache/"${i}"; done` steamapps/appmanifest_"${i}".acf steamapps/common/"${INSTALLDIR}"
}

# Check for missing commands and files BEFORE anything starts
# TODO: Make it look pretty!
checkprereqs

# Set options for the script
while getopts "hnu:x:" o; do
    case "${o}" in
        h)
            usage
            ;;
        n)
            nuke=1
            ;;
        x)
            x=${OPTARG}
            compressRegex='^[0-9]$'
	    if [[ "${x}" =~ $compressRegex ]]; then :; else echo "Error: Compression level is invalid! [0 none - 9 max]"; exit 1; fi
            ;;
        u)
            u=${OPTARG}
            ;;
    esac
done
shift "$((OPTIND-1))"

# Check if username was specified, and check if config exists
# TODO: add documentation about this
if [ -z "${u}" ]; then
echo "Error: No username specified. Make sure it's in config dir!"; exit 1
else
if [[ -f "config/${u}.vdf" ]]; then :; else echo "Error: ${u}.vdf does not exist! Did you copy config.vdf to ${u}.vdf?"; exit 1; fi
cp config/$u.vdf config/config.vdf
fi

# see shift "$((OPTIND-1))"
# errors out when nothing is specified
if [[ "$#" == 0 ]]; then
echo "Error: No appid specified"
exit 1
fi

# main loop, make sure functions are set properly so nothing breaks
for i in $@; do
main
done
