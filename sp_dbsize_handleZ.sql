	use master
	go
	IF OBJECT_ID('sp_dbsize_handleZ') IS NOT NULL
	BEGIN
		DROP PROCEDURE sp_dbsize_handleZ
		IF OBJECT_ID('sp_dbsize_handleZ') IS NOT NULL
			PRINT '<<< FAILED DROPPING PROCEDURE sp_dbsize_handleZ >>>'
		ELSE
			PRINT '<<< PROCEDURE PROCEDURE sp_dbsize_handleZ >>>'
	END
	go

	/********************************************************************* 
	 * 
	 * FILE NAME		: sp_dbsize_handleZ.sql 
	 * 
	 * PROCEDURE NAME	: sp_dbsize_handleZ
	 * 
	 * DESCRIPTION		: Extend a database on the specifide device
	 *
	 * HISTORY			: 
	 * 
	 * Date			By			Ver			Desc 
	 * ----------------------------------------------------------------------------------------- 
	 * 15-May-2016	Zion A.		1.0	Creation
	 * 26-Jun-2016	Zion A.		1.1 Added optionnal log threshold
	 * 10-Jul-2016	Zion A.		1.2	Added optionnal "for load" option
	 ******************************************************************************************/ 

	CREATE PROCEDURE sp_dbsize_handleZ
		@db_name		sysname,
		@device_name 	varchar(30),
		@data_or_log 	char,
		@sizeMB 		int,
		@for_load		char = null,
		@log_threshold_prc tinyint = null
	AS
	/*

		Sample of use :
		exec master..sp_dbsize_handleZ
			'ems',
			'ems_data',
			'D',
			10
		
	*/
	BEGIN
		DECLARE
			@err int,
			@sql_sentence varchar(1000),
			@device_size numeric(13,2),
			@device_use numeric(13,2),
			@remain_size numeric(13,2),
			@segmap int,
			@vdevno int,
			@ret_code int

	/*
		Parameters control
	*/
		IF NOT EXISTS (SELECT "DB_EXISTS" FROM master..sysdatabases WHERE name = @db_name)
		BEGIN
			PRINT "Database %1! doesnt exist, operation aborted",@db_name
			return -1
		END

		IF NOT EXISTS (SELECT "DEVICE_EXISTS" FROM master..sysdevices WHERE name = @device_name)
		BEGIN
			PRINT "Device %1! doesnt exist, operation aborted",@device_name
			return -1
		END

		IF @data_or_log NOT IN ("D","L")
		BEGIN
			PRINT "Parameter @data_or_log is invalid, should be 'L' (log) or 'D' (data), operation aborted"
			return -1
		END
		ELSE
			SELECT @segmap = CASE WHEN @data_or_log = 'D' THEN 3 ELSE 4 END

		SELECT
			 @device_size = CONVERT(NUMERIC(13,2),(((high + 1) - low) *  (@@maxpagesize / 1024)) / 1024),
			 @vdevno = vdevno
		FROM
			master..sysdevices
		WHERE
			name = @device_name
		
		IF EXISTS (SELECT "IN_USE_BY_ANOTHER_DB" FROM master..sysusages WHERE vdevno = @vdevno and dbid != db_id(@db_name))
		BEGIN
			PRINT "This device is already used by another database, operation aborted"
			return -1
		END

		IF EXISTS (SELECT "IN_USE_BY_ANOTHER_DB" FROM master..sysusages WHERE vdevno = @vdevno and segmap != @segmap)
		BEGIN
			PRINT "This device is already used for another purpose (data/log), operation aborted"
			return -1
		END

		SELECT
			@device_use = CONVERT(NUMERIC(13,2),SUM(size *  (@@maxpagesize / 1024)) / 1024)
		FROM
			master..sysusages
		WHERE
			vdevno = @vdevno

		SELECT @remain_size = @device_size - @device_use
		
		IF  @remain_size < @sizeMB
		BEGIN
			PRINT "The given size  for the allocation is greater than the remaining space (%1!MB) on the device, operation aborted",@remain_size
			return -1
		END
		
		PRINT "Extending size of database %1! by %2!MB on device %3!",@db_name,@sizeMB,@device_name
		SELECT @sql_sentence = "ALTER DATABASE " + 
							@db_name + 
							CASE WHEN @data_or_log = "D" THEN " ON " ELSE " LOG ON " END + 
							@device_name + "= '" +
							CONVERT(varchar(10),@sizeMB) + "m'"

--		SELECT @sql_sentence
		
/*
	Z.A 1.1 added for load option
*/
		SELECT @sql_sentence = @sql_sentence + " for load" where @for_load = 'Y'

		EXEC (@sql_sentence)
		SELECT @err = @@ERROR
		if @err = 0
			PRINT "Database %1! has been successfully altered",@db_name
		else
			PRINT "Failure during alter of database %1!",@db_name

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
	IF OBJECT_ID('dbo.sp_dbsize_handleZ') IS NOT NULL
		PRINT '<<< CREATED PROCEDURE dbo.sp_dbsize_handleZ >>>'
	ELSE
		PRINT '<<< FAILED CREATING PROCEDURE dbo.sp_dbsize_handleZ >>>'
	go