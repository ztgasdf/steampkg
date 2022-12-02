#!/bin/bash
#TODO clean shitty if statements

function usage {
echo "steampkg, a SteamCMD wrapper for downloading & packaging games
Usage: $0 [optional args...] -u <username> appid [appid...]

Options:
         -h     |  Displays this message
         -p     |  [default: windows] Set install platform [windows/macos/linux]
         -x     |  [default: 64] Set bitness [32/64]
         -l N   |  [default: 9] Sets 7z archive compression level
         -n     |  Nuke depotcache and steamapps before downloading
         -u     |  Username to login to Steam

This script requires your config.vdf file located in config/ to be renamed
to <steam username>.vdf. This allows effcient multi-account management." 1>&2; exit 1
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
if [[ "${i}" =~ $appidRegex ]]; then :; else echo "Error: Appid \"${i}\" is invalid!"; exit 1; fi
}

function checkprereqs {
# check if required files and commands exist
if [[ ! $(command -v 7z) ]]; then echo "7z not found! Closing."; exit 1; fi
if [[ ! $(command -v jq) ]]; then echo "jq not found! Closing."; exit 1; fi
if [[ ! $(command -v unbuffer) ]]; then echo "unbuffer not found! Closing."; exit 1; fi
if [[ -f steamcmd.sh ]]; then :; else echo 'steamcmd.sh not found! Make sure '"$0"' is in the same directory.'; exit 1; fi
if [[ -f vdf2json.py ]]; then :; else echo 'vdf2json.py not found! Download it here: https://gist.githubusercontent.com/ynsta/7221512c583fbfbafe6d/raw/vdf2json.py'; exit 1; fi
}

function nuke {
# deletes depotcache and steamapps
# ten second warning
echo Purging depotcache and steamapps in 10 seconds\!
echo CTRL-C TO STOP
sleep 10
echo Deleting...
rm -rf depotcache steamapps
echo Done\!
}

function download {
[[ "${p}" ]] && : || p="windows"
[[ "${x}" ]] && : || x="64"
unbuffer ./steamcmd.sh +login "${u}" +@sSteamCmdForcePlatformType "${p}" +sSteamCmdForcePlatformBitness "${x}" +app_update "${i}" validate +quit | grep --line-buffered -iE 'update|success|install|clean|ok|check|package|extract'
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
[[ "${l}" ]] && : || l=9
# Run the damn thing!
7z a -mx"${l}" "${FILENAME}" `for i in "${DEPOTS}"; do echo depotcache/"${i}"; done` steamapps/appmanifest_"${i}".acf steamapps/common/"${INSTALLDIR}"
}

# Check for missing commands and files BEFORE anything starts
# TODO: Make it look pretty!
checkprereqs

# Set options for the script
while getopts "hnp:x:u:l:" o; do
    case "${o}" in
        h)
            usage
            ;;
        n)
            nuke=1
            ;;
        l)
            l=${OPTARG}
            compressRegex='^[0-9]$'
	    if [[ "${l}" =~ $compressRegex ]]; then :; else echo "Error: Specified compression level is invalid! [0 none - 9 max]"; exit 1; fi
            ;;
        u)
            u=${OPTARG}
            ;;
	p)
	    p=${OPTARG}
	    platformRegex='^(windows|linux|macos)$'
	    if [[ "${p}" =~ $platformRegex ]]; then :; else echo "Error: Specified platform is invalid! [windows/linux/macos]"; exit 1; fi
	    ;;
	x)
	    x=${OPTARG}
	    bitnessRegex='^(32|64)$'
	    if [[ "${x}" =~ $bitnessRegex ]]; then :; else echo "Error: Specified bitness is invalid! [32/64]"; exit 1; fi
	    ;;
    esac
done
shift "$((OPTIND-1))"

# Error if username was not specified
# If specified, check if vdf exists then replace config.vdf
# TODO: Can steamcmd directly use <username>.vdf?
# TODO?: Backup config.vdf before overwriting?
if [ -z "${u}" ]; then
echo "Error: No username specified. Make sure it's in config dir!"; exit 1
else
if [[ "${u}" == "config" ]]; then echo "Error: You can't use \"config\" as your username!"; exit 1; fi
if [[ -f "config/${u}.vdf" ]]; then :; else echo "Error: ${u}.vdf does not exist! Check \`$0 -h\` for help."; exit 1; fi
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
