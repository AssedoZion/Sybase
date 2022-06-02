use sybsystemprocs
go
IF OBJECT_ID('dbo.sp_sybase_logcheck') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.sp_sybase_logcheck
    IF OBJECT_ID('dbo.sp_sybase_logcheck') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.sp_sybase_logcheck >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.sp_sybase_logcheck >>>'
END
go
/* @FILE_DOC*********************************************************************
 *
 * FILE NAME		:sp_sybase_logcheck.sql
 *
 * PROCEDURE NAME	:sp_sybase_logcheck 
 *
 * DESCRIPTION		:This Procedure will wait until the log segment of the target db decreases under the given pourcentage
 *					 It can be usefull in cases of mass deletes/updates/inserts
 *					 NB : parameter @ha2_sleep_time is in seconds
 *
 * IMPLEMENTATION	:	
 *
 *
 * HISTORY        :
 *
 * Date         Name			  		Modificatiom
 * ----------------------------------------------------------------------
 * 04-May-2011 Zion A:				1rst version
 * 12-Mar-2012 Moshe Br.	11.2		NO code changes.
 *										Star Team location Moved ----> to be compiled on sybsystemprocs DB only.
 * 16-May-2012 Zion A.				When ha2_sleep_time = -1 return 1 if the log prc is >= to @prc_limit or 0 if not
 *									drop eventual existence of the sp in ems
 * 11-Dec-2013	Zion A.				According to the sybase version we will use data_pgs or data_pages
 * 10-Apr-2014	Zion A.				replaced 8 by @syslogid
*********************************************************************FILE_DOC@**/ 
 
 /*
	Example:
		
	DECLARE @RetCode INT
	
	EXECUTE @RetCode = sp_sybase_logcheck 
			  @db_name="ems",
			  @pct_limit=70, 
			  @ha2_sleep_time=400
 */

CREATE PROCEDURE sp_sybase_logcheck
	@db_name sysname = "ems",
	@pct_limit money = 80,
	@ha2_sleep_time int = 300
AS
BEGIN --{
	DECLARE 
		@pct money, 
		@mb1 real, 
		@log_size money ,
		@time2wait varchar(8),
		@ret_code int,
		@sql_sentence varchar(2000),
		@sleep_time_minutes int,
		@remain_seconds int,
		@pos1	int,
		@sybase_version int


	SET NOCOUNT ON

	SELECT @pos1 = charindex("/",@@version)

	select @sybase_version = CONVERT(int,substring(@@version,@pos1+1,2))


	if @ha2_sleep_time > 0
	BEGIN --{
/*
	We convert the sleep time from seconds to minutes
*/
		SELECT @sleep_time_minutes = @ha2_sleep_time / 60

		SELECT @remain_seconds = @ha2_sleep_time - (@sleep_time_minutes * 60)
	
		SELECT 
			@time2wait = "00:" + REPLICATE ("0",2 - CHAR_LENGTH(CONVERT(VARCHAR(2),@sleep_time_minutes))) + CONVERT(VARCHAR(2),@sleep_time_minutes)

		SELECT 
			@time2wait = @time2wait + ":" + REPLICATE ("0",2 - CHAR_LENGTH(CONVERT(VARCHAR(2),@remain_seconds))) + CONVERT(VARCHAR(2),@remain_seconds)
	END --}
/*
	To allow us getting to the given database we will use dynamic sql
*/
	SELECT @sql_sentence =
	"DECLARE @page_size int, "	+
	"		 @mb1 real, "		+
	"		 @ret_code int, "	+
	"		 @syslog_id int "	+
	"SELECT @page_size = low FROM master..spt_values WHERE type = 'E' AND number = 1 " + char(10)		+
	"SELECT @syslog_id = id FROM " + @db_name + "..sysobjects WHERE name = 'syslogs' " + char(10)		+
	"SELECT "																							+
	CASE @sybase_version
	WHEN 15 THEN
	"	@mb1 = ((( convert(real,data_pages (db_id('" + @db_name + "'),@syslog_id, 0) )) *  @page_size  ) /1024) / 1024 "
	ELSE
	"	@mb1 = ((( data_pgs (db_id('" + @db_name + "'),@syslog_id, doampg) ) *  @page_size  ) /1024) / 1024 "
	END +
	"FROM "																								+ 
	@db_name + "..sysindexes where id =  @syslog_id "													+
	"	select @ret_code = rm_appcontext('sp_sybase_logcheck', 'log_trans')" 							+
	"	select @ret_code = set_appcontext('sp_sybase_logcheck', 'log_trans', convert(VARCHAR(13),convert(numeric(8,2),round(@mb1,3))))"	

	EXEC (@sql_sentence)
	
/*
	Now get the information back from the context variable
*/
	SELECT @mb1 = CONVERT(real,get_appcontext('sp_sybase_logcheck', 'log_trans'))

/*
	Compute the log segment size
*/
	SELECT 
		@log_size = sum(size)/ 512
	FROM 
		master.dbo.sysusages u 
	WHERE 
		u.dbid = db_id(@db_name) and u.segmap = 4 --> Well, we assume that there is no mix

/*
	compute the pourcentage
*/
	SELECT 
		@pct = (@mb1 / @log_size) * 100 
	
/*
	Now enter the loop and wait until EmsHa2 empties the log segment
*/
	IF @ha2_sleep_time > 0
	BEGIN --{
		WHILE @pct >= @pct_limit
		BEGIN --{

			PRINT "Current log segment of %1! is @pct=%2!, Waiting %3!",@db_name,@pct,@time2wait

			WAITFOR delay @time2wait

			SELECT @sql_sentence =
			"DECLARE @page_size int, "	+
			"		 @mb1 real, "		+
			"		 @ret_code int, "	+
			"		 @syslog_id int "	+
			"SELECT @page_size = low FROM master..spt_values WHERE type = 'E' AND number = 1 " + char(10)		+
			"SELECT @syslog_id = id FROM " + @db_name + "..sysobjects WHERE name = 'syslogs' " + char(10)		+
			"SELECT "																							+
			CASE @sybase_version
			WHEN 15 THEN
			"	@mb1 = ((( convert(real,data_pages (db_id('" + @db_name + "'),@syslog_id, 0) )) *  @page_size  ) /1024) / 1024 "
			ELSE
			"	@mb1 = ((( data_pgs (db_id('" + @db_name + "'),@syslog_id, doampg) ) *  @page_size  ) /1024) / 1024 "
			END +
			"FROM "																								+ 
			@db_name + "..sysindexes where id = @syslog_id "													+
			"	select @ret_code = rm_appcontext('sp_sybase_logcheck', 'log_trans')" 							+
			"	select @ret_code = set_appcontext('sp_sybase_logcheck', 'log_trans', convert(VARCHAR(13),convert(numeric(8,2),round(@mb1,3))))"	
		
			EXEC (@sql_sentence)
		
			SELECT @mb1 = CONVERT(real,get_appcontext('sp_sybase_logcheck', 'log_trans'))

			SELECT
				@pct = (@mb1 / @log_size) * 100 

		END --} 
	END --}

/*
	Clean all context variables
*/
	SELECT @ret_code = rm_appcontext('sp_sybase_logcheck', 'page_size')
	SELECT @ret_code = rm_appcontext('sp_sybase_logcheck', 'log_trans')

	if @pct >= @pct_limit
	BEGIN --{
		RETURN 1
	END
	ELSE
	BEGIN --{
		RETURN 0
	END --}

END --}
go

IF OBJECT_ID('dbo.sp_sybase_logcheck') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.sp_sybase_logcheck >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.sp_sybase_logcheck >>>'
go
grant select on RM_APPCONTEXT to public
go
grant select on SET_APPCONTEXT to public
go
grant select on GET_APPCONTEXT to public
go
