# linuxscripts
Collection of useful scripts

## ssh_jail.sh
Creates a full ssh jail with basic commands like cp, mv, etc

## ddsplit.sh (quick and dirty dd backup)
Performs disk backups via dd, compresses and splits into file chunks.
Restores the splitted files to disk.

Usage:
ddsplit --backup /dev/sdX /mnt/myFile 1G
ddsplit --restore /mnt/ddsplit.1G.main.myFile.gz /dev/sdY

