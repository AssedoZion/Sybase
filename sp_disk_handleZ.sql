use master
go
IF OBJECT_ID('sp_disk_handleZ') IS NOT NULL
BEGIN
    DROP PROCEDURE sp_disk_handleZ
    IF OBJECT_ID('sp_disk_handleZ') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE sp_disk_handleZ >>>'
    ELSE
        PRINT '<<< PROCEDURE PROCEDURE sp_disk_handleZ >>>'
END
go

/********************************************************************* 
 * 
 * FILE NAME		: sp_disk_handleZ.sql 
 * 
 * PROCEDURE NAME	: sp_disk_handleZ
 * 
 * DESCRIPTION		: Extend a device if exists or create it
 *
 * HISTORY			: 
 * 
 * Date			By			Ver			Desc 
 * ----------------------------------------------------------------------------------------- 
 * 15-May-2016	Zion A.		1.0	Creation
 ******************************************************************************************/ 

CREATE PROCEDURE sp_disk_handleZ
	@device_name varchar(30),
	@physical_name varchar(127) = null,
	@sizeMB int,
	@dsync varchar(5) = 'true',
	@directio varchar(5) = 'false'
AS
/*
	Example of use :
	exec master..sp_disk_handleZ
		'toto_data',
		'd:\toto_data.dat',
		10
	
*/
BEGIN
	DECLARE
		@sql_sentence varchar(1000)

	IF EXISTS (SELECT "DEVICE_ALREADY_EXISTS" FROM master..sysdevices WHERE name = @device_name)
	BEGIN
		PRINT "Extending size of device %1! by %2! MB",@device_name,@sizeMB
		SELECT @sql_sentence = "disk resize name=@device_name, size='" + CONVERT(varchar(10),@sizeMB) + "m' "
	END
	ELSE
	BEGIN
		IF @dsync NOT IN ('true','false')
		BEGIN
			PRINT "Parameter @dsync should be 'true' or 'false' - Operation aborted"
			return -1
		END

		IF @directio NOT IN ('true','false')
		BEGIN
			PRINT "Parameter @directio should be 'true' or 'false' - Operation aborted"
			return -1
		END

		IF @physical_name IS NOT NULL
		BEGIN
			PRINT "Creating a new device %1! (%3!) with a size of %2!",@device_name,@sizeMB,@physical_name
			SELECT @sql_sentence = "disk init name=@device_name, physname = '" + @physical_name + "', size='" + CONVERT(varchar(10),@sizeMB) + "m'" +
			",dsync = " + @dsync + ",directio = " + @directio
		END
		ELSE
		BEGIN
			PRINT "Physical name not supplied, operation aborted"
			return -1
		END
	END

	EXEC (@sql_sentence)
	
END
go
IF OBJECT_ID('dbo.sp_disk_handleZ') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.sp_disk_handleZ >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.sp_disk_handleZ >>>'
go