# wocli

## Intro

A small tool to install or update World of Warcraft addons from Curse.com (main target is Linux but you never know, it can work on other OS). Unlike other implementation it doesn't relly on parsing Curse.com website and is way faster than other programs.

The goal is to provide a command line tool as well as a nice UI.

So far it's a Perl script but things will change (or not). 

Please note it's work in progress. Feel free to help.

## Status

It is still under heavy development, some things works:
* search
* install
* update
* add

However, I can promise one thing: this Perl script is going to work and do the job. So if I get tired of this or loose my purpose (stop playing WoW ^^). You still have a working tool.

## Help

Here is a basic help for this little program.

### Install

No need too, just run the script from the Github repo.
The following Perl modules are used, they should be part of the Perl distribution on your Linux box:
* LWP::UserAgent
* Data::Dumper
* Getopt::Long
* File::Path 
* Time::HiRes
* XML::Simple
* Term::ANSIColor


However, if you want to install system wide, you can do:
```bash
[adupuis@localhost wocli] $ sudo "make"
[sudo] password for adupuis: 
install -m 0755 wocli.pl /usr/local/bin
ln -s /usr/local/bin/wocli.pl /usr/local/bin/wocli
```

you can then call wocli system wide (even without the .pl!):
```bash
[adupuis@localhost ~] $ wocli search aki
speakinspell: Says random things in chat when casting any spell or ability. Type "/ss help" for the user's manual.

Found 1 partial name results.


```

## Uninstall

If you did install wocli you can uninstall it:
```bash
[adupuis@localhost wocli] $ sudo make uninstall
rm -f /usr/local/bin/wocli.pl
rm -f /usr/local/bin/wocli

```

### Quick first run

First, tell wocli where your Wordl of Warcraft install is (and build the cache at the same time):
```bash
wocli.pl --wow-dir /your/path/to\ your/wow\ install --save buildcache
```

Then you shoudl be able to install/update/add/search easily:
```bash
wocli.pl install bagnon titan-panel gatherer
```

Please note that for install we need what we call "shortnames", wich is the X-Curse-Project-ID. When you search for an addon, the shortname is displayed first in green in the results list (here there is no formatting).
```bash
[adupuis@localhost wocli] $ ./wocli.pl search gath
gathernow: Give logical progression of Mining, Herbalism & Skinning. Will not be updated with WoD zones
gathermate2: Collects Herbs, Mines, Gas Clouds, Archaeology, Treasure and Fishing locations and adds them to the worldmap and minimap
titan-gathered: This simple WoW addon track all useful tradeitems and materials in your bag and show result in Titan Bar. Over right click is...
gathermate2_data-carbonite: GatherMate2 Data - Carbonite Edition
ygather: English yGather - Gatherers Map is a resource stack mapper. It records resource stack locations as you walk by and shows them...
gatherer: Helps track the closest plants, deposits and treasure locations on your minimap.
gathermate2_data: Wowhead Data dump for GatherMate2
gathertip: Show useful Tooltip for gather information!
gathermate_sharing: Database sharing module for GatherMate2

Found 9 partial name results.
[adupuis@localhost wocli] $ ./wocli.pl install gathermate2 gathermate2_data
Install:        gathermate2                                       :     installed (GatherMate2 1.35.5).
Install:        gathermate2_data                                  :     installed (GatherMate2_Data v29.4).

```

### Run

Here is a list of the commands and options you can use.

#### Options

* **--build-cache**: Force wocli to rebuild the addon cache. If this option is not set and the cache is recent enough wocli will start faster by just loading existing cache.
* **--wow-dir**: Set the World of Warcraft directory (on my computer it looks like: $ENV{HOME}/.cxoffice/World\ of\ Warcraft/drive_c/Program\ Files/World\ of\ Warcraft/). It only affect the current session. See --save for permanent changes.
* **--save**: Is going to save your configuration in $ENV{HOME}/.wocli/config.
* **--debug**: Turn debug on, meaning: lots of debug messages and lots of intermediate data saved in your local cache ($ENV{HOME}/.wocli/cache/).
* **--db-ttl**: Takes an integer as parameter. It will set the cache time to live in seconds. Default is set to 7200 (2 hours). Do not set it to high to avoid issue with DB not synced with Curse.com.
* **--show-config**: Display the configuration before processing other tasks.
* **--version**: Display wocli version and exit.

#### Commands

##### install

Install addons, takes a list of addons shortnames in parameters. It's going to install all mandatory dependencies and ask you about the optional dependencies.

##### update

Update your installed addons to the latest version. This finds your previously installed addons , as long as their .toc file contains a X-Curse-Project-ID tag.
Otherwise it's too risky to do anything automatically.
If you want your addon to be added to the tracked list of addon you can either re-install it with wocli (so it's the latest version available):
```bash
wocli.pl install <your addon list>
```

Or you can use the add command:
```bash
wocli.pl add <your addon list>
```

PLEASE REFER TO THE DOCUMENTATION FOR BOTH OF THESE COMMANDS.

##### remove

Remove an installed addon. It is neither removing dependencies nor it is warning or removing addons that depends on the removed one.

You can use the "*" wildcard in the addons names, you can even mix it with shortnames.

```
[adupuis@localhost wocli] $ ./wocli.pl remove *ell* rolecall
Following addons are going to be removed:
rolecall, tell-track
Is that ok? (y/n):y
Remove: rolecall                                          :     removed.
Remove: tell-track                                        :     removed.
[adupuis@localhost wocli] $ 
```

##### clean

Clean the local cache.

##### search

Will search for the addons that matches your query.

##### add

This command add a list of addon to the installed database. This is super useful if some of your addons that were installed without wocli are not automatically found by wocli. Default behaviour is that wocli only updates addons with a .toc file containing a X-Curse-Project-ID tag. 
If it is not the case of your addon (likely to happen), just add it to the list. It's that easy!
You don't need to do it for addon installed with wocli.

WARNING: wocli will NOT verify that the addon is actually installed (only that the addon name is a valid one). It means that next time you update your addons, it will install the addon that were added and not previously installed.
```bash
wocli.pl add titan-panel titan-panel-attributes-multi
```

##### showconfig

Simply display the wocli current configuration. It looks like that:
```
[adupuis@localhost wocli] $ ./wocli.pl showconfig
               -----------------------
               | WOCLI CONFIGURATION |
               -----------------------
config_dir          :  /home/adupuis/.wocli
config_file         :  config
db                  :  /home/adupuis/.wocli/cache/wocli_db.csv
db_ttl              :  900
installed_db        :  /home/adupuis/.wocli/wocli_installed_db.csv
uri_category        :  /addons/wow/category
uri_complete_db     :  http://clientupdate.curse.com/feed/Complete.xml.bz2
uri_home            :  /addons/wow?page=1
url_base            :  http://www.curse.com
wow_dir             :  ./test/

```



