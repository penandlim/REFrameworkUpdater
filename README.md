# REFrameworkUpdater
PowerShell script for updating DLLs from [@praydog's REFramework](https://github.com/praydog/REFramework) nightly builds


* First run

![Preview](https://user-images.githubusercontent.com/4276174/227882218-18a3e9ed-c030-4196-8bd6-1eb64bced91d.gif)
* Updating

![Animation3](https://user-images.githubusercontent.com/4276174/228385076-c38d3243-62c3-47a5-9807-73e80bef0ee5.gif)


## Pre-requisites
Generate a personal github token for public repo artifacts API access
https://github.com/settings/tokens
Then change the `$personalAccessToken` to your own API key.

## Installation
Place the .ps1 file in the same folder as where your game .exe resides (same folder as dinput8.dll).

## How to use
Right click the .ps1 file and run with PowerShell.
Choose your game and the branch to download the files from.

At the time of the writing (2023/03/27), [pd-upscaler](https://github.com/praydog/REFramework/tree/pd-upscaler) is used for the beta feature of custom upscalar such as DLSS.

Then choose which files to copy over. Most of desktop PC users probably want only dinput8.dll.

## Related files & Resetting
Runing the script will create `reframework_updater.config` file. Stores which game this is for and the branch name.

The downloaded artifact zip file is kept in the root folder for checking for updates next time.

You can remove these files to reset the script settings.
