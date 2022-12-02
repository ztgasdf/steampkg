# steampkg

steamcmd wrapper to download and compress games

rec'd usage: `./steampkg.sh -u <username> <appid>`

just check `./steampkg.sh -h` for everything this baby can handle

requires: python3, jq, 7z

todo:

 - allow selection for language (needs a fat regex)
 - clean up if conditions, and organise code
 - maybe make it so i don't need a secondary python script?

---

scripts used:

 - vdf2json [https://gist.github.com/ynsta/7221512c583fbfbafe6d]
