These are my personal burp incexc rules which:

- Exclude already compressed files from compression
- Exclude a lot of temporary / lock / whatever file extensions
- Exclude loads of Windows temp/cache/system files
- Exclude some Linux paths
- Set standard settings

In order to use it, simply write the following in the client config file server side:

- For linux clients
```
. incexc/std_settings
. incexc/linux_settings
```

- For windows clients
```
. incexc/std_settings
. incexc/windows_settings
```

These rules are designed to exclude most unused system files from backup, but keep system programs and setting files (like Program Files & ProgramData or /sbin & /etc).
It's better to backup too much than not enough :)

All improvements are welcome.
