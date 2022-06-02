sp_helpthreshold

use sybsystemprocs
go
IF OBJECT_ID('dbo.sp_rebuild_thresholds') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.sp_rebuild_thresholds
    IF OBJECT_ID('dbo.sp_rebuild_thresholds') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.sp_rebuild_thresholds >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.sp_rebuild_thresholds >>>'
END
go
/* @FILE_DOC********************************************************************* 
 * 
 * FILE NAME		: sp_rebuild_thresholds.sql 
 * 
 * PROCEDURE NAME	: sp_rebuild_thresholds
 * 
 * DESCRIPTION		: Drop all non last logsegment thresholds and reconfigure them.
 *
 * PARAMTERS		: @p_dbname : a specific database name, if null so all databases
 *					  which are monitored
 *					  @p_percentage : the pourcentage from which the threshold should be fired
 *						if @p_dbname is null, then we take 2% under the value given in the field 
 *						log_limit_prc from ems_official_databases
 *					  @proc_name : The name of the stored procedure to be activated
 *
 *
 *
 *
 * IMPLEMENTATION	:	 
 * 
 * NOTES			:Return values:	 0 = Ok
 *									-1 = Not OK
 * 
 * HISTORY        : 
 * 
 * Name			Date			Modificatiom 
 * ---------------------------------------------------------------------- 
 * Zion A.		9/Feb/2015		First Version 
 * Zion A.		20/Apr/2015		Fix logsegment size computation
 * Zion A.		17/Feb/2016		Fix bug when @p_dbname is not null
 * Zion A.		30/Mar/2016		Added parameter @data_or_log
 ********************************************************************FILE_DOC@**/ 
CREATE PROCEDURE sp_rebuild_thresholds
	@p_dbname 		varchar(30) = NULL,
	@p_percentage	int ,
	@proc_name		VARCHAR(30),
	@data_or_log	char = 'L'
AS
/*
	EXEC sp_rebuild_thresholds 
	@p_dbname = 'bad_1030',
	@p_percentage = 20,
	@proc_name='sp_thresholdaction',
	@data_or_log = 'L'
*/

BEGIN

	DECLARE
		@rows			int,
		@dbid			int,
		@dbname			varchar(30),
		@sql_sentence	varchar(2000),
		@identifier		int,
		@segname		varchar(30),
		@free_space		int,
		@segno			int,
		@status			int,
		@gp_enabled		int,
		@pourcentage	int,
		@default_seg	int,
		@system_seg		int,
		@default_segname varchar(20),
		@system_segname varchar(20),
		@log_segname varchar(20)


	SELECT
		@dbid = 0,
		@identifier = 0,
		@status = 0,
		@default_seg = 1,
		@system_seg = 0,
		@default_segname = 'default',
		@system_segname = 'system',
		@log_segname = 'logsegment'


	set transaction isolation level 1
	set chained off

/*
	Check if the user is allowed to use this sp
*/
	
--	IF substring(@@version,28,2) = "15"
--		execute @status = sp_aux_checkroleperm "dbo", "manage database", @dbname, @gp_enabled output
--	
--	if @status != 0
--	BEGIN
--		Print "The login your logged under is not allowed to do such an operation"
--		return (-1)
--	END


	if @@trancount > 0
	begin
/*
	 17260, "Can't run %1! from within a transaction."
*/
		raiserror 17260, "sp_dropthreshold"
		return (-1)
	end

/*
	Parameters validity control
	1) IF @p_dbname is not null then it should at least exists 
	2) If the name of the database is specified and it dont exists in the table
		ems_official_databases or it is not monitored then the % cannot be null

*/

	IF @p_dbname IS NOT NULL
	AND
		db_id(@p_dbname) IS NULL
	BEGIN
		PRINT "The database %1! dont exists on this server",@p_dbname
		return (-1)
	END

	IF @data_or_log != "L" AND @data_or_log != "D"
	BEGIN
		PRINT "Parameter @data_or_log should be 'D' or 'L'"
		return (-1)
	END

	IF @p_dbname IS NOT NULL
	AND
		(@p_dbname NOT IN ('master', 'model', 'tempdb', 'sybsystemdb', 'sybsystemprocs')) 
	AND
		@p_percentage IS NULL
	BEGIN
		PRINT "If you specify a database name which is not monitored, you must give a value to pourcentage"
		return (-1)
	END

	/*
		1 - if @data_or_log =  'L' (Log) 
			@p_percentage must be greater than last chance 
			@p_percentage must be minimum 10 %
	*/


	EXEC sp_configure "allow updates",1
	
/*
	Phase 1 : list up all existing non last chance thresholds
*/

	CREATE TABLE #thresholds2del
	(
		identifier	int identity,
		dbname		varchar(30),
		segname		varchar(30),
		segno		int,
		free_space  int,
		pourcentage numeric(4,2)
	)

	IF @p_dbname IS NULL
	BEGIN --{
		SELECT TOP 1
			@dbname = S.name,
			@dbid = S.dbid
		FROM
			master..sysdatabases S
		WHERE
			S.name NOT IN ('master', 'model', 'tempdb', 'sybsystemdb', 'sybsystemprocs')
		AND
			S.dbid > @dbid

		ORDER by S.dbid

		SELECT @rows = @@rowcount

		WHILE @rows > 0
		BEGIN

			SELECT @sql_sentence = "INSERT #thresholds2del (" +
			"dbname, segname, segno, free_space,pourcentage) "	+
			"select	'"	+@dbname + "',"		+
			"s.name, "						+
			"s.segment,"					+
			"t.free_space,0 "				+
			"from	"						+
			@dbname+"..syssegments s,"		+
			@dbname+"..systhresholds t "	+
			"where "						+
			"s.segment = t.segment "		+
			"and  "							+
			"t.status != 1 "				+
			"and "							+
			"(   (t.segment = 2 AND '" + @data_or_log + "' = 'L') "	+
			" OR "							+
			"    (t.segment in (0,1) AND '" + @data_or_log + "' = 'D') " +
			")"
			
			EXEC(@sql_sentence)

			SELECT TOP 1
				@dbname = S.name,
				@dbid = S.dbid
			FROM
				master..sysdatabases S
			WHERE
				S.name NOT IN ('master', 'model', 'tempdb', 'sybsystemdb', 'sybsystemprocs')
			AND
				S.dbid > @dbid


			ORDER by S.dbid
	
			SELECT @rows = @@rowcount

		END --}

	END --}
	ELSE
	BEGIN --{
			SELECT @sql_sentence = "INSERT #thresholds2del (" +
			"dbname, segname, segno, free_space,pourcentage) "	+
			"select	'"	+@p_dbname + "',"		+
			"s.name, "						+
			"s.segment,"					+
			"t.free_space, "				+
			"0 "							+
			"from	"						+
			@p_dbname+"..syssegments s,"	+
			@p_dbname+"..systhresholds t " +
			"where "						+
			"s.segment = t.segment "		+
			"and  "							+
			"t.status != 1 "				+
			"and "							+
			"(   (t.segment = 2 AND '" + @data_or_log + "' = 'L') "	+
			" OR "							+
			"    (t.segment in (0,1) AND '" + @data_or_log + "' = 'D') " +
			")"
	
			EXEC(@sql_sentence)
	END --}
/*
	Phase 2 : Go over each row and drop the threshold
*/
	SELECT TOP 1
		@identifier	= identifier,
		@dbname		= dbname,
		@segname	= segname,
		@segno		= segno,
		@free_space	= free_space
	FROM
		#thresholds2del
	WHERE
		identifier > @identifier
	ORDER BY identifier

	SELECT @rows = @@ROWCOUNT

	WHILE @rows > 0
	BEGIN

		BEGIN TRANSACTION delete_threshold

		SELECT @sql_sentence = "DELETE "	+
			@dbname + "..systhresholds "	+
			"where	segment = " + convert(varchar(3),@segno)	+
			" and free_space = " + convert(varchar(10),@free_space)

		EXEC (@sql_sentence)

		if @@error != 0
		begin
			rollback transaction
			raiserror 17907
			return (-1)
		end
/*
** Last, rebuild the database threshold table
*/
		if @data_or_log = 'L'
		BEGIN --{
			dbcc dbrepair(@dbname, "newthreshold", @log_segname)
		END
		ELSE
		BEGIN --{
			dbcc dbrepair(@dbname, "newthreshold", @default_segname)
			dbcc dbrepair(@dbname, "newthreshold", @system_segname)
		END --}

		if @@error != 0
		begin
			rollback transaction
			raiserror 17878
			return (-1)
		end

		COMMIT TRANSACTION

		SELECT TOP 1
			@identifier	= identifier,
			@dbname		= dbname,
			@segname	= segname,
			@segno		= segno,
			@free_space	= free_space
		FROM
			#thresholds2del
		WHERE
			identifier > @identifier
		ORDER BY identifier

		SELECT @rows = @@ROWCOUNT

	END

/*
	Phase 3 : Redefine thresholds according to pourcentage parameter
*/

	TRUNCATE TABLE #thresholds2del	

	IF @p_dbname IS NULL
	BEGIN --{
		SELECT 
			@identifier = 0,
			@dbid = 0

/*
	We artificially refill the table using the last_chance threshold
*/
		SELECT TOP 1
			@dbname = S.name,
			@dbid = S.dbid
		FROM
			master..sysdatabases S
		WHERE
			S.dbid > @dbid
		ORDER by S.dbid

		SELECT @rows = @@rowcount

		WHILE @rows > 0
		BEGIN

			SELECT @sql_sentence = "INSERT #thresholds2del (" 	+
			"dbname, segname, segno, free_space,pourcentage) "	+
			"select	'"	+@dbname + "',"		+
			"s.name, "						+
			"s.segment,"					+
			"t.free_space, "				+
			CONVERT(VARCHAR(2),@pourcentage)	+ " " +
			"from	"						+
			@dbname+"..syssegments s,"		+
			@dbname+"..systhresholds t "	+
			"where "						+
			"s.segment = t.segment "		+
			"and  "							+
			"t.status = 1 "
	
			EXEC(@sql_sentence)
				
		SELECT TOP 1
			@dbname = S.name,
			@dbid = S.dbid
		FROM
			master..sysdatabases S
		WHERE
			S.dbid > @dbid
		ORDER by S.dbid

	
			SELECT @rows = @@rowcount

		END --}

	END --}
	ELSE
	BEGIN --{
		SELECT @sql_sentence = "INSERT #thresholds2del (" +
		"dbname, segname, segno, free_space,pourcentage) "	+
		"select	'"	+ @p_dbname + "',"		+
		"s.name, "							+
		"s.segment,"						+
		"t.free_space, "					+
		CONVERT(varchar(2),@p_percentage)	+ " " +
		"from	"							+
		@p_dbname + "..syssegments s,"			+
		@p_dbname + "..systhresholds t "		+
		"where "							+
		"s.segment = t.segment "			+
		"and  "								+
		"t.status = 1 "
	
		EXEC(@sql_sentence)

	END --}

	SELECT TOP 1 
		@identifier	= identifier,
		@dbname		= dbname,
		@segname	= segname,
		@segno		= segno,
		@pourcentage = pourcentage
	FROM
		#thresholds2del
	WHERE
		identifier > @identifier
	ORDER BY identifier

	SELECT @rows = @@ROWCOUNT

	WHILE @rows > 0
	BEGIN

/*
	Now compute the number of pages corresponding to 
	the segment pourcentage
*/
		SELECT
			@free_space = (sum(U.size)*@pourcentage) / 100
		FROM
			master..sysusages U
		WHERE
			U.dbid = db_id(@dbname)
		AND
			(
			 ( U.segmap = 4 AND @data_or_log = 'L')
			 OR
			 ( U.segmap = 3 AND @data_or_log = 'D')
			)

		begin transaction insert_threshold

		if @data_or_log = 'L'
		BEGIN --{
			SELECT @sql_sentence = "INSERT "	+
			@dbname+"..systhresholds"			+
			" values("							+
			convert(varchar(3),@segno)+ ", "	+
			convert(varchar(10),@free_space) + ","	+
			" 0, '"								+
			@proc_name + "', "					+
			convert(varchar(10),suser_id()) + ", "	+
			"current_roles())"

			EXEC (@sql_sentence)

			if @@error != 0
			begin
				rollback transaction
				raiserror 17877
				return (1)
			end
		END --}
		ELSE
		BEGIN --{
			SELECT @sql_sentence = "INSERT "	+
			@dbname+"..systhresholds"			+
			" values("							+
			convert(varchar(3),@default_seg)+ ", "	+
			convert(varchar(10),@free_space) + ","	+
			" 0, '"								+
			@proc_name + "', "					+
			convert(varchar(10),suser_id()) + ", "	+
			"current_roles())"

			EXEC (@sql_sentence)

			IF @@error != 0
			BEGIN
				rollback transaction
				raiserror 17877
				return (1)
			END

			SELECT @sql_sentence = "INSERT "	+
			@dbname+"..systhresholds"			+
			" values("							+
			convert(varchar(3),@system_seg)+ ", "	+
			convert(varchar(10),@free_space) + ","	+
			" 0, '"								+
			@proc_name + "', "					+
			convert(varchar(10),suser_id()) + ", "	+
			"current_roles())"

			EXEC (@sql_sentence)

			IF @@error != 0
			BEGIN
				rollback transaction
				raiserror 17877
				return (1)
			END

		END --}
/*
** Last, rebuild the database threshold table
*/
/*
		if $data_or_log = 'L'
		BEGIN
			select @segname='logsegment'
		END
*/
		if @data_or_log = 'L'
		BEGIN --{
			dbcc dbrepair(@dbname, "newthreshold", @log_segname)
		END
		ELSE
		BEGIN --{
			dbcc dbrepair(@dbname, "newthreshold", @default_segname)
			dbcc dbrepair(@dbname, "newthreshold", @system_segname)
		END --}

		if @@error != 0
		begin
			rollback transaction
			raiserror 17878
			return (1)
		end

		commit transaction

		SELECT TOP 1
			@identifier	= identifier,
			@dbname		= dbname,
			@segname	= segname,
			@segno		= segno,
			@pourcentage = pourcentage
		FROM
			#thresholds2del
		WHERE
			identifier > @identifier
		ORDER BY identifier

		SELECT @rows = @@ROWCOUNT
	END	

	EXEC sp_configure "allow updates",0

	RETURN 0

END
go
IF OBJECT_ID('dbo.sp_rebuild_thresholds') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.sp_rebuild_thresholds >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.sp_rebuild_thresholds >>>'
go
