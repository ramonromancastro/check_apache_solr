# check_apache_solr
Apache Solr Nagios plugin

## Usage
```
check_apache_solr.sh

This plugin is not developped by the Nagios Plugin group.
Please do not e-mail them for support on this plugin.

For contact info, please read the plugin script file.

Usage: ./check_apache_solr.sh -H <hostname> [-h] [-V]
------------------------------------------------------------------------------------
Usable Options:

   -H <hostname>   ... Name or IP address of host to check
   -p <port>       ... Name or IP address of host to check (default: 8983)
   -u <username>   ... Basic authentication user
   -P <password>   ... Basic authentication password
   -C <core>       ... Solr core (default: *)
   -S              ... Enable TLS/SSL (default: no)
   -T              ... Test selection. Available options:
                       - cores
                       - jvm
   -w              ... Warning threshold (default: 80)
   -c              ... Critical threshold (default: 90)
   -f              ... Perfparse compatible output (default: no)
   -h              ... Show this help screen
   -V              ... Show the current version of the plugin

Examples:
    check_apache_solr.sh -h 127.0.0.1 -u nagios -P P@$$w0rd -T cores
    check_apache_solr.sh -V

------------------------------------------------------------------------------------
```
