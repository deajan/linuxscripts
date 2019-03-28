These are my personal burp incexc rules which:

- Exclude already compressed files from burp zlib compression
- Exclude a lot of temporary / lock / unuseful file extensions
- Exclude loads of Windows temp/cache/system files
- Exclude unnecessary Linux paths
- Set standard settings (which you may have to modify to fit your needs)

The regex are PCRE and validated by https://regexr.com

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
There may also exist multiple backup exclusion profiles like, whatever your needs are, eg:

- windows_settings = Generic temp/cache/system path exclusions
- windows_programs = Exclude most system paths (eg Windows / ProgramFiles / ProgramData)
- linux_settings = Genreic path exclusions
- linux_programs = Exclude /bin /sbin /usr/local/bin...

Missing a MacOS guru that may write specific Mac settings file.
