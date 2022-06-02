# Sybase
Small tools for Sybase ASE - All these small tools can be compiled in sybsystemprocs so you can use them anywhere

sp_helpdbZ is a enhanced version of original sp_helpdb with more details

sp_rebuild_thresholds is threshold rebuilder, it is usefull when you want to use the thresholds, it can be run in a schedule so, after increasing the size of your db,
the sp will modify the thresholds definitions according to the new size (data or log)

sp_fastrows will return the number of rows of all the tables of the specifiled db 

sp_killemall will kill every connection for a fast shutdown

sp_sybase_logcheck : Can be call from within a massive insert/update loop to keep after the log segment

sp_dbcreateZ : Will create the database according to given parameters

sp_dbsize_handleZ : Extends a database on the specifide device

sp_disk_handleZ : Extend a device if exists or create it

sp_chkcont : Check Contention over an applicative database

sp_CheckMissingStats : will show the fields statistics that are used to be updated but warent updated since n days

sp_dba_reorg_rebuild : This Procedure will reorg / rebuild tables/indexes if needed

sp_show_locks : This Procedure returns locked users

