dsps
=======

NPR Digital Services Paging System (dsps)

DSPS is a text message-based paging system that provides functionality somewhat
similar to PagerDuty.  It allows you to define users, teams and aliases, any
of which can be used to contact someone.  It supports rotating call schedules,
vacation days and advanced filtering.  To get familiar quickly here are some
good places to start:
 - Main documentation: docs/DSPS Documentation.pdf
 - Sample config file: config.dsps
 - Main code: dsps (see "OVERVIEW")


Debian Prerequisites (possibly incomplete)
====================

apt-get install libproc-daemon-perl libstring-random-perl libfreezethaw-perl libhash-case-perl libhttp-daemon-ssl-perl liblwp-useragent-determined-perl libjson-perl libdate-calc-perl
