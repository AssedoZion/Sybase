USE sybsystemprocs
go
IF OBJECT_ID('dbo.sp_chkcont') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.sp_chkcont
    IF OBJECT_ID('dbo.sp_chkcont') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.sp_chkcont >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.sp_chkcont >>>'
END
go

CREATE PROCEDURE dbo.sp_chkcont
	@checktime		int = 5,
	@dbname			sysname = NULL
/*
***************************************************************
* Object Name : sp_chkcont
* Purpose : Check Contention over all applicative database
* Input paramter :	@CheckTime (how much time in minutes Default = 5 minutes)
*					@Db_name (or null for all)
*					@Table_Name (or null for all)
* Creator : Zion Assedo
* Modifications
***************************************************************
*    Date    | Author    | Object
* 17-08-2017 | Z. Assedo | Creation
***************************************************************
*/
/*

EXEC sp_chkcont 2

EXEC sp_chkcont
	@checktime = 2,
	@dbname = 'av_baad',
	
EXEC sp_chkcont
	5,
	@dbname = 'av_clv'


sp_chkcont 1

*/
AS
BEGIN

	DECLARE
		@db_name	sysname,
		@db_id		int,
		@table_name	varchar(255),
		@index_name	varchar(255),
		@statement	varchar(1024),
		@rowcnt		int,
		@rows		int,
		@index		int,
		@hours		int,
		@minutes	int,
		@wait_time	varchar(8)

	SELECT 
		@db_id = 0,
		@index = 0,
		@hours = 0,
		@minutes = 0

-- sp_object_stats "00:00:10",@dbname='svk_7280',@rpt_option="rpt_locks"

	SELECT 	@hours = @checktime/60,
			@minutes = @checktime%60
		
	SELECT
		@wait_time = REPLICATE('0',2 - CHAR_LENGTH(CONVERT(VARCHAR(2),@hours))) + CONVERT(VARCHAR(2),@hours) + 
					":" +
					REPLICATE('0',2 - CHAR_LENGTH(CONVERT(VARCHAR(2),@minutes))) + CONVERT(VARCHAR(2),@minutes) + 
					":" + 
					"00"
		
	SELECT top 1
		@db_name  = name,
		@db_id = dbid
	FROM
		master..sysdatabases
	WHERE
		name not in ('master','model','sybsystemprocs','tempdb','sybsystemdb')
	AND
		dbid > @db_id
	ORDER by dbid
	
	SELECT @rows = @@ROWCOUNT
/*
	First we run over all databases (or the given one) to list up all non empty DOL tables
	and store the information into the temp table #dol_tables
*/
	WHILE @rows > 0
	BEGIN
		select @statement='sp_object_stats "' + @wait_time + '",@dbname="' + @db_name + '",@rpt_option="rpt_locks" '

		exec( @statement)
	
		SELECT top 1
			@db_name  = name,
			@db_id = dbid
		FROM
			master..sysdatabases
		WHERE
			name not in ('master','model','sybsystemprocs','tempdb','sybsystemdb')
		AND
			dbid > @db_id
		ORDER by dbid
		
		SELECT @rows = @@ROWCOUNT
	
	END
	
END
go
EXEC sp_procxmode 'dbo.sp_chkcont', 'unchained'
go
IF OBJECT_ID('dbo.sp_chkcont') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.sp_chkcont >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.sp_chkcont >>>'
go

