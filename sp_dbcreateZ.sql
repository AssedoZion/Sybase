use master
go
IF OBJECT_ID('sp_dbcreateZ') IS NOT NULL
BEGIN
    DROP PROCEDURE sp_dbcreateZ
    IF OBJECT_ID('sp_dbcreateZ') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE sp_dbcreateZ >>>'
    ELSE
        PRINT '<<< PROCEDURE PROCEDURE sp_dbcreateZ >>>'
END
go

/********************************************************************* 
 * 
 * FILE NAME		: sp_dbcreateZ.sql 
 * 
 * PROCEDURE NAME	: sp_dbcreateZ
 * 
 * DESCRIPTION		: Create a database on the specified devices
 *
 * HISTORY			: 
 * 
 * Date			By			Ver			Desc 
 * ----------------------------------------------------------------------------------------- 
 * 15-May-2016	Zion A.		1.0	Creation
 * 21-Jun-2016	Zion A.		1.1 Added 3 parameters for basic options
 * 26-Jun-2016	Zion A.		1.1 Added optionnal log threshold
 ******************************************************************************************/ 

CREATE PROCEDURE sp_dbcreateZ
	@db_name			sysname,
	@data_device_name 	varchar(30),
	@data_sizeMB 		int,
	@log_device_name 	varchar(30),
	@log_sizeMB 		int,
	@for_load			char = null,
	@abrt_trn_log_full 	char  = null,
	@trn_log_chkpt		char = null,
	@sel_into_blk		char = null,
	@log_threshold_prc 	tinyint = null

AS
/*
drop database titi
	Sample of use :
	exec master..sp_dbcreateZ
		@db_name='titi',
		@data_device_name='titi_data',
		@data_sizeMB=10,
		@log_device_name='titi_log',
		@log_sizeMB=2,
		@for_load = 'N',
		@abrt_trn_log_full = 'Y',
		@trn_log_chkpt = 'Y',
		@sel_into_blk = 'Y'
sp_helpdb titi
online database titi

*/
BEGIN

	DECLARE
		@err	int,
		@sql_sentence varchar(1000),
		@device_size numeric(13,2),
		@device_use numeric(13,2),
		@remain_size numeric(13,2),
		@segmap int,
		@vdevno int,
		@TRUE_FALSE varchar(5),
		@ret_code int
/*
	Parameters control
*/
	IF EXISTS (SELECT "DB_EXISTS" FROM master..sysdatabases WHERE name = @db_name)
	BEGIN
		PRINT "Database %1! allreasdy exists, operation aborted",@db_name
		return -1
	END

	IF NOT EXISTS (SELECT "DEVICE_EXISTS" FROM master..sysdevices WHERE name = @data_device_name)
	BEGIN
		PRINT "Device %1! doesnt exist, operation aborted",@data_device_name
		return -1
	END

	IF NOT EXISTS (SELECT "DEVICE_EXISTS" FROM master..sysdevices WHERE name = @log_device_name)
	BEGIN
		PRINT "Device %1! doesnt exist, operation aborted",@log_device_name
		return -1
	END
/*
	Check out data device availability
*/
	SELECT
		 @device_size = CONVERT(NUMERIC(13,2),(((high + 1) - low) *  (@@maxpagesize / 1024)) / 1024),
		 @vdevno = vdevno
	FROM
		master..sysdevices
	WHERE
		name = @data_device_name
	
	IF EXISTS (SELECT "IN_USE_BY_ANOTHER_DB" FROM master..sysusages WHERE vdevno = @vdevno)
	BEGIN
		PRINT "The device %1! is already used by another database, operation aborted",@data_device_name
		return -1
	END
	
	IF  @device_size < @data_sizeMB
	BEGIN
		PRINT "The given size for the allocation is greater than the remaining space on the data device, operation aborted"
		return -1
	END

/*
	Check out log device availability
*/
	SELECT
		 @device_size = CONVERT(NUMERIC(13,2),(((high + 1) - low) *  (@@maxpagesize / 1024)) / 1024),
		 @vdevno = vdevno
	FROM
		master..sysdevices
	WHERE
		name = @log_device_name
	
	IF EXISTS (SELECT "IN_USE_BY_ANOTHER_DB" FROM master..sysusages WHERE vdevno = @vdevno)
	BEGIN
		PRINT "The device %1! is already used by another database, operation aborted",@log_device_name
		return -1
	END

	IF  @device_size < @log_sizeMB
	BEGIN
		PRINT "The given size for the allocation is greater than the remaining space on the log device, operation aborted"
		return -1
	END
	
	SELECT @sql_sentence = "CREATE DATABASE " + 
						@db_name 	+ 
						" ON "		+ 
						@data_device_name + "= '" +
						CONVERT(varchar(10),@data_sizeMB) + "m' " +
						"LOG ON "	+
						@log_device_name  + "= '" +
						CONVERT(varchar(10),@log_sizeMB) + "m' "
						
	SELECT @sql_sentence = @sql_sentence + " for load" where @for_load = 'Y'
--	SELECT @sql_sentence
	
	EXEC (@sql_sentence)
	
	SELECT @err = @@error
	IF @@error != 0 OR (SELECT "CREATED" FROM master..sysdatabases where name = @db_name) IS NULL
	BEGIN
		PRINT "Database %1! was not successfully created with error %2!",@db_name,@err
	END
	
	if @abrt_trn_log_full IS NOT NULL
	BEGIN
		SELECT @TRUE_FALSE = CASE WHEN @abrt_trn_log_full = "Y"
				THEN "True"
				ELSE "False"
				END
		SELECT @sql_sentence = "EXEC master..sp_dboption " + @db_name + ",'abort tran on log full'," + @TRUE_FALSE
		EXEC (@sql_sentence)
	END

	if @trn_log_chkpt IS NOT NULL
	BEGIN
		SELECT @TRUE_FALSE = CASE WHEN @trn_log_chkpt = "Y"
				THEN "True"
				ELSE "False"
				END
		SELECT @sql_sentence = "EXEC master..sp_dboption " + @db_name + ",'trunc log on chkpt'," + @TRUE_FALSE
		EXEC (@sql_sentence)
	END

	if @sel_into_blk IS NOT NULL
	BEGIN
		SELECT @TRUE_FALSE = CASE WHEN @sel_into_blk = "Y"
				THEN "True"
				ELSE "False"
				END
		SELECT @sql_sentence = "EXEC master..sp_dboption " + @db_name + ",'select into/bulkcopy/pllsort'," + @TRUE_FALSE
		EXEC (@sql_sentence)
	END

	if @abrt_trn_log_full IS NOT NULL
	OR @trn_log_chkpt  IS NOT NULL
	OR @sel_into_blk IS NOT NULL
	BEGIN
		SELECT @sql_sentence = "checkpoint " + @db_name
		EXEC (@sql_sentence)
	END
	
	if @log_threshold_prc IS NOT NULL
	BEGIN
		EXECUTE @ret_code = sp_rebuild_thresholds
			@p_dbname		= @db_name,
			@p_pourcentage	= @log_threshold_prc,
			@proc_name		= "sp_thresholdaction",
			@data_or_log	= 'L'
		
		if @ret_code = 0
			PRINT "Threshold action sp_thresholdaction have beed successfully set on %1!",@db_name
		else
			PRINT "Failure setting threshold action on %1!",@db_name
	END
	
END
go
IF OBJECT_ID('dbo.sp_dbcreateZ') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.sp_dbcreateZ >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.sp_dbcreateZ >>>'
go