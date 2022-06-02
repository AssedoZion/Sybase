use sybsystemprocs
go
IF OBJECT_ID('dbo.sp_killemall') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.sp_killemall
    IF OBJECT_ID('dbo.sp_killemall') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.sp_killemall >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.sp_killemall >>>'
END
go
/********************************************************************* 
 * 
 * FILE NAME		: sp_killemall.sql 
 * 
 * PROCEDURE NAME	: sp_killemall
 * 
 * DESCRIPTION		: kill all sessions 
 *
 * HISTORY			: 
 * 
 * Date			By			Ver			Desc 
 * ----------------------------------------------------------------------------------------- 
 * 22-Jun-2015	Zion A.		
 * 15-Jun-2020  Zion A. - Added return code
 ******************************************************************************************/ 
 CREATE PROCEDURE sp_killemall
	@user_name	varchar(30) = NULL,
	@dbname	varchar(30) = NULL
AS
BEGIN --{
	DECLARE 
		@spid int,
		@rows int,
		@sql_synt varchar(50),
		@retcode int

	SELECT @spid = 0

	SELECT TOP 1 @spid = spid
	FROM
		master..sysprocesses
	WHERE 
		suid > 0 
	AND
		hostprocess  != ""
	AND
		spid != @@SPID
	AND
		spid > @spid
	AND 
		UPPER(substring(cmd,1,4)) not in ("LOAD","ONLI")
	AND
		( suser_name(suid) = @user_name OR @user_name IS NULL )
	AND	
		(db_name(dbid) = @dbname or @dbname is null)
	ORDER BY spid

	SELECT @rows = @@ROWCOUNT

	WHILE @rows > 0
	BEGIN --{

		SELECT @sql_synt = "KILL " + CONVERT(varchar(4),@spid)

		EXEC (@sql_synt)

		SELECT TOP 1 @spid = spid
		FROM
			master..sysprocesses
		WHERE 
			suid > 0 
		AND
			hostprocess  != ""
		AND
			spid != @@SPID
		AND
			spid > @spid
		AND 
			UPPER(substring(cmd,1,4)) not in ("LOAD","ONLI")
		AND
			( suser_name(suid) = @user_name OR @user_name IS NULL )
		AND	
			(db_name(dbid) = @dbname or @dbname is null)
		ORDER BY spid

		SELECT @rows = @@ROWCOUNT

	END --}

	SELECT @rows = @@ROWCOUNT
	FROM
		master..sysprocesses
	WHERE 
		suid > 0 
	AND
		hostprocess  != ""
	AND
		spid != @@SPID
	AND
		spid > @spid
	AND
		( suser_name(suid) = @user_name OR @user_name IS NULL )
	AND	
		(db_name(dbid) = @dbname or @dbname is null)

	IF @rows > 0
	BEGIN
		SELECT @retcode = -1
		Print "Could not kill all sessions ..."
	END
	ELSE
	BEGIN
		SELECT @retcode = 0
		Print "Server is cleared"
	END
	
	RETURN @retcode
END
go

IF OBJECT_ID('dbo.sp_killemall') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.sp_killemall >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.sp_killemall >>>'
go 
