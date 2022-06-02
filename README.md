# Sybase
Small tools for Sybase ASE - All these small tools can be compiled in sybsystemprocs so you can use them anywhere

sp_helpdbZ is a enhanced version of original sp_helpdb with more details

sp_rebuild_thresholds is threshold rebuilder, it is usefull when you want to use the thresholds, it can be run in a schedule so, after increasing the size of your db,
the sp will modify the thresholds definitions according to the new size (data or log)

sp_fastrows will return the number of rows of all the tables of the specifiled db 

sp_killemall will kill every connection for a fast shutdown


