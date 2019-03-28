# linuxscripts
Collection of useful scripts / tools / files for Linux

## Burp incexc rules
A set of regex rules and generic settings for Backup and Restore Program (BURP) from Graham Keeling (http://burp.grke.org)

## emailCheck.sh

Low tech tool to cleanup mailing lists from unwanted emails.
Performs various checks on a list of email adresses:

1. Converts all addresses to lowercase
2. Checks address' compliance against RC822
3. Checks address' domain for known typos and corrects them
4. Checks if email domain has MX records
5. Checks if email user or domain is test / example / spam, rendering them ambiguous

Usage:
```
emailCheck.sh /path/to/email_list
```

Base script reads one email per line from input file. Script header contains instructions to read multicolumn CSV files.
Warning: Using files comming from windows need prior conversion with dos2unix tool. 

## ddsplit.sh

Quick and dirty dd backup, useful to backup unknown file systems on fat32 / vfat devices.
Performs disk backups via dd, compresses and splits into file chunks.
Restores the splitted files to disk.

Usage:
```
ddsplit.sh --backup /dev/sdX /mnt/myFile 1G
ddsplit.sh --restore /mnt/ddsplit.1G.main.myFile.gz /dev/sdY
```
## repairbadblocks.sh

Highly experimental script to force SATA disk firmwares to reallocate a pending sector / bad sector using dd or hdparm.
Use at your very own risk. Might even send your data to an unknown parallel universe where cows rule the world ! You have been warned.

Usage:

```
repairbadblocks.sh /dev/sdX /tmp
```

## ssh_jail.sh
Creates a full ssh jail with basic commands like cp, mv, etc
