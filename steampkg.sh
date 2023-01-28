#!/bin/bash

# ain't no one got time for functional error handling
set -e

# Path variables to 1) make SteamCMD portable 2) make parts of the script more bearable to read
HOME="$PWD"
MAINDIR="$PWD"
STEAMROOT="$PWD/Steam"

## Regex variables
# Check if appid consists only of numbers
appidRegex='^[0-9]*$'
# Clean up SteamCMD output (might be excessive)
steamRegex='update|success|install|clean|ok|check|package|extract|workshop|version|='
# Allow only these platforms to be used
platformRegex='^(windows|linux|macos)$'
# Allow only these bits to be used
bitnessRegex='^(32|64)$'
# Allow only 0-9 to be used
compressRegex='^[0-9]$'

function usage {
  echo "steampkg, a SteamCMD wrapper for downloading & packaging games
Usage: $0 [optional args...] -u <username> appid [appid...]

Options:
         -h     |  Displays this message
         -b     |  Set branch
         -c     |  Set branch password
         -m     |  Set steamapps location to music for music appids
         -p     |  [default: windows] Set install platform [windows/macos/linux]
         -x     |  [default: 64] Set bitness [32/64]
         -l N   |  [default: 9] Sets 7z archive compression level
         -n     |  Nuke depotcache and steamapps before downloading
         -u     |  Username to login to Steam*
         -f     |  internal: get info and output to file

Refer to the README for information about account management.
If -b/-c is passed, the script will only download the *first* appid specified."
  exit
}

function main {
  # Skip nuke if not called
  [[ "${NUKE}" ]] && nukecheck || :
  download
  clean
  getacfinfo
  compress
  # See function for more info
  [[ "${f}" ]] && checksumforum || :
}

function checkappid {
  if [[ ! "${i}" =~ $appidRegex ]]; then
    echo >&2 "Error: Appid \"${i}\" is invalid!"
    exit 1
  fi
}

function checkprereqs {
  # check if required files and commands exist
  # 7z is the main archive tool
  if [[ ! $(command -v 7z) ]]; then
    echo >&2 '7z not found! Closing.'
    exit 1
  fi
  # jq is a JSON parser, used with vdf2json to parse appmanifest
  if [[ ! $(command -v jq) ]]; then
    echo >&2 'jq not found! Closing.'
    exit 1
  fi
  # self-explanatory, unbuffers steamcmd's output so it can be piped without issues
  if [[ ! $(command -v unbuffer) ]]; then
    echo >&2 'unbuffer not found! Closing.'
    exit 1
  fi
  # if steamcmd is not found in PATH, then check if script exists
  # if script doesn't exist, download steamcmd
  if [[ ! $(command -v steamcmd) ]]; then
    if [[ ! -f "${STEAMROOT}/steamcmd.sh" ]]; then
      echo 'steamcmd.sh not found! Downloading...'
      mkdir -p "${STEAMROOT}"
      curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C "${STEAMROOT}"
      echo 'Done!'
    fi
  fi
  if [[ ! -f vdf2json.py ]]; then
    echo >&2 'vdf2json.py not found! Download it here: https://gist.githubusercontent.com/ynsta/7221512c583fbfbafe6d/raw/vdf2json.py'
    exit 1
  fi
  if [[ "${f}" ]]; then
    if [[ ! $(command -v b3sum) ]]; then
      echo >&2 'b3sum not found! Closing.'
      exit 1
    fi
  fi
}

function nukecheck {
  # When -n (nuke) is called, NUKE is set to 1. That allows the if statement
  # in the main function to call this function. This function gives a y/n
  # prompt asking if steamapps&depotcache should be wiped. If yes is input,
  # NUKE is set to two, so if the script is called with multiple appids and -n,
  # then it will automatically wipe steamapps&depotcache without asking again. 
  if [[ "${NUKE}" == 2 ]]; then
    nuke
    return
  fi

  echo >&2 'WARNING: Running the nuke command will delete your depotcache and steamapps folder!'
  echo >&2 "This shouldn't be a problem, since steamcmd is isolated, but we ask anyways."
  echo >&2 "Tip: Pipe steampkg through yes or call NUKE=2 to skip this prompt"

  while true; do
    read -p 'Are you sure you want to continue? (y/n) ' yn
    case $yn in
      [yY])
        nuke
        return
        ;;
      [nN])
        echo Closing...
        exit
        ;;
      *)
        echo Invalid response
        ;;
    esac
  done
}

function nuke {
  # Sets nuke variable so check won't run if multiple appids are specified
  # TODO, maybe check if folders exist or not? don't know if it's needed..
  NUKE=2
  echo 'Deleting depotcache and steamapps...'
  rm -rf "${STEAMROOT}/depotcache" "${STEAMROOT}/steamapps"
  echo 'Done! Continuing.'
}

function download {
  # Delete appinfo.vdf because caches are evil
  if [[ -f "${STEAMROOT}/appcache/appinfo.vdf" ]]; then
    rm "${STEAMROOT}/appcache/appinfo.vdf"
  fi
  # If no platform is set, default to Windows
  [[ "${p}" ]] && : || p="windows"
  # If no bitness is set, default to 64bit
  [[ "${x}" ]] && : || x="64"
  # SteamCMD handles beta branches weirdly. If a branch is set, it will
  # download said branch. If you run the script again, but with no branch
  # set (assuming NUKE is off), it will think that branch is still set and
  # it will download that branch. However, if you call -beta with a space
  # as its flag, it will unset the configured branch and download the default
  # branch available. That is what this if statement does.
  [[ "${b}" ]] && : || b=" "
  # If branch password is set, run with -betapassword called
  if [[ "${c}" ]]; then
    unbuffer "${STEAMROOT}/steamcmd.sh" +login "${u}" +@sSteamCmdForcePlatformType "${p}" +@sSteamCmdForcePlatformBitness "${x}" +app_update "${i}" -validate -beta "${b}" -betapassword "${c}" +quit | grep -iE ${steamRegex}
    errorcheck
  else
    unbuffer "${STEAMROOT}/steamcmd.sh" +login "${u}" +@sSteamCmdForcePlatformType "${p}" +@sSteamCmdForcePlatformBitness "${x}" +app_update "${i}" -validate -beta "${b}" +quit | grep -iE ${steamRegex}
    errorcheck
  fi
}

function errorcheck {
  if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
    if [[ "${ohno}" -eq 2 ]]; then
      echo >&2 'Error: SteamCMD failed after retry, halting.'
      exit 1
    fi
    ((ohno=ohno+1))
    echo >&2 'Warning: SteamCMD failed with error 8. Retrying!'
    download
  fi
}

function clean {
  # Clears LastOwner value in manifest
  echo Cleaning appmanifest_"${i}".acf
  sed -i '/LastOwner/c\\t"LastOwner"\t\t"0"' "${STEAMROOT}/steamapps/appmanifest_${i}.acf"
}

function getacfinfo {
  # Parse manifest into JSON and load into variable
  # https://gist.github.com/ynsta/7221512c583fbfbafe6d
  ACF=$(python3 vdf2json.py -i "${STEAMROOT}/steamapps/appmanifest_${i}.acf")
  # Get archive filename (You may need to rename afterwords, as it uses the install directory)
  FILENAME=$(echo "${ACF}" | jq -r '.AppState.installdir+" ("+.AppState.appid+")" + (if (.AppState.UserConfig.BetaKey) then " [Branch "+.AppState.UserConfig.BetaKey+"]" else "" end) + " [Depot "+(.AppState.InstalledDepots | keys | join(","))+"] [Build "+.AppState.buildid+"].7z"')
  # Get install directory to add to archive
  INSTALLDIR=$(echo "${ACF}" | jq -r '.AppState.installdir')
  # Get depots and turn into array
  DEPOTS=($(echo "${ACF}" | jq -r '.AppState.InstalledDepots | to_entries[] |(.key)+"_"+(.value.manifest)+".manifest"'))
}

function compress {
  # Compress game using 7z
  # If compression level is not set, default to 9
  [[ "${l}" ]] && : || l=9
  # If -m flag is set, set folder to music
  [[ "${music}" ]] && folder="music" || folder="common"
  # Run the damn thing!
  cd "${STEAMROOT}"
  7z a -mx"${l}" "${MAINDIR}/archives/${FILENAME}" $(for i in "${DEPOTS[@]}"; do echo "depotcache/${i}"; done) steamapps/appmanifest_"${i}".acf steamapps/"${folder}"/"${INSTALLDIR}"
  cd "${MAINDIR}"
}

function checksumforum {
  # This is for internal use only!
  # This function does two things:
  #  1. Get BLAKE3 checksum and size; outputs to list
  #  2. Create forum code for cs.rin.ru posting (Requires direct file host/redirector)
  echo 'Getting checksum...'
  CHECKSUM=$(b3sum "${MAINDIR}/archives/${FILENAME}" | cut -f1 -d' ')
  SIZE=$(stat -c %s "${MAINDIR}/archives/${FILENAME}")
  FMTSIZE=$(stat -c %s "${MAINDIR}/archives/${FILENAME}" | numfmt --to=iec-i --suffix=B --format="%.3f")
  echo "${CHECKSUM} | ${FILENAME} | ${SIZE}" >> publicinfos
  echo "[url=https://z.tess.eu.org/rin/${CHECKSUM}][b][color=#FFFFFF]${FILENAME}[/color][/b][/url] [size=85][color=#FFFFFF]${FMTSIZE}[/color][/size]" >> publicinfos
  echo 'Done!'
}

# archives: finished game archives
# TODO: maybe set variable and or move this somewhere else?
mkdir -p archives

# Set options for the script
# TODO: Organise/order it properly
while getopts "hmnfb:c:p:x:u:l:" o; do
  case "${o}" in
  h)
    usage
    ;;
  m)
    music=1
    ;;
  n)
    if [[ ! "${NUKE}" == 2 ]]; then
      NUKE=1
    fi
    ;;
  f)
    f=1
    ;;
  l)
    l=${OPTARG}
    if [[ "${l}" =~ $compressRegex ]]; then :; else
      echo >&2 "Error: Specified compression level is invalid! [0 none - 9 max]"
      exit 1
    fi
    ;;
  u)
    u=${OPTARG}
    ;;
  b)
    b=${OPTARG}
    ;;
  c)
    c=${OPTARG}
    if [[ -z "${b}" ]]; then
      echo >&2 "Error: -b must be called before -c!"
      exit 1
    fi
    ;;
  p)
    p=${OPTARG}
    if [[ "${p}" =~ $platformRegex ]]; then :; else
      echo >&2 "Error: Specified platform is invalid! [windows/linux/macos]"
      exit 1
    fi
    ;;
  x)
    x=${OPTARG}
    if [[ "${x}" =~ $bitnessRegex ]]; then :; else
      echo >&2 "Error: Specified bitness is invalid! [32/64]"
      exit 1
    fi
    ;;
  esac
done
shift "$((OPTIND - 1))"

# Check for missing commands and files BEFORE anything starts
checkprereqs

# Self-explanatory, error out when nothing is specified
if [[ "$#" == 0 ]]; then
  echo >&2 "Error: No appid specified"
  exit 1
else
  # Error if branch is set and two or more appids are passed
  if [[ "$#" -ge 2 ]]; then
    if [[ "${b}" ]]; then
      echo >&2 "Error: You can only specify one appid if branch is set!"
      exit 1
    fi
  fi
fi

# Error if username was not specified
# If specified, check if vdf exists then replace config.vdf
if [[ -z "${u}" ]]; then
  echo >&2 "Error: No username specified!"
  exit 1
else
  if [[ "${u}" == "config" ]]; then
    echo >&2 "Error: You can't use \"config\" as your username!"
    exit 1
  fi
  if [[ ! -f "accounts/${u}.vdf" ]]; then
    echo >&2 "Error: ${u}.vdf does not exist! Make sure it's in config dir!"
    exit 1
  fi
    mkdir -p "${STEAMROOT}/config"
    echo "Copying account to config..."
    cp "accounts/${u}.vdf" "${STEAMROOT}/config/config.vdf"
fi

# Check appids before actually executing
for i; do
  checkappid
done

# main loop, make sure functions are set properly so nothing breaks
for i; do
  main
done
