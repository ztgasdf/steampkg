# steampkg

steampkg is a wrapper script for steamcmd that downloads and compresses games for easy archival.

run `./steampkg.sh -h` for full usage options

requirements: **steamcmd.sh** (not package), python3, jq, 7z, unbuffer (expect package)- 

## Account management

*Warning: If the script detects an existing config, it will make a backup located in `<script dir>/backups/`. Regardless, it is highly recommended that this script is run as a different user that does NOT have Steam installed.*

As you might have noticed, steampkg will refuse to run unless a username is specified *and* found in `<script dir>/config/`. steampkg utilises cached credentials that can be found in your `config/config.vdf` file in your local Steam insallation. Only three keys are actually required, however: Accounts, MTBF, ConnectCache. These values would be made into a new file labeled `<your username>.vdf` in `config/`, located in the same directory as the script.

Example (this would be tab-separated, no spaces [is this actually required? not sure]):

```
"InstallConfigStore"
{
  "Software"
  {
    "Valve"
    {
      "Steam"
      {
        "Accounts"
        {
          "username"
          {
            "SteamID"    "xxxxx"
          }
        }
        "MTBF"    "xxxxx"
        "ConnectCache"
        {
          "CRC32 hash of username with 1 added AFTER (username = f85e06771)"    "verylonghash, ~1000 characters"
        }
      }
    }
  }
}
```

```
$ ls config
username.vdf username2.vdf username3.vdf
$ ./steampkg.sh -u username 4000   #Downloads Garry's Mod (assuming you own it) for Windows
```


---

todo:

 - add if statement for goldsrc games, ref. linuxgsm [here](https://github.com/GameServerManagers/LinuxGSM/blob/master/lgsm/functions/core_dl.sh)
 - allow selection for language (needs a fat regex)

scripts used:

 - vdf2json [https://gist.github.com/ynsta/7221512c583fbfbafe6d]
