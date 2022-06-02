use sybsystemprocs
go

if exists (select *
   from sysobjects where type = 'P' and name = 'sp_dba_reorg_rebuild')
begin
   drop procedure sp_dba_reorg_rebuild
end
go

CREATE PROC sp_dba_reorg_rebuild
	@p_db_name	sysname = NULL,
	@p_table_name sysname = NULL
AS
/*
  -  Usage examples :
	  Exec sp_dba_reorg_rebuild
  	  Exec sp_dba_reorg_rebuild 'svk_cm'
	  Exec sp_dba_reorg_rebuild 'svk_cm','lak_edi_dwh'
	  Exec sp_dba_reorg_rebuild 'svk_cm','mzr_mlai'
*/
BEGIN
	DECLARE 
		@user_name      varchar(30),
		@table_name     varchar(255),
		@reserved_pages int,
		@free_space     int,
		@cmd            varchar(2000),
		@db_name        varchar(30),
		@message		nvarchar(254),
		@db_id			int,
		@table_id		int,
		@obj_type		nchar(2),
		@sort_key		int,
		@rows			int

	SET flushmessage ON

	SELECT @db_name = ISNULL(@p_db_name,db_name())
	SELECT @db_id = db_id(@db_name)
	
	IF @db_id IS NULL
	BEGIN
		Print "Database %1! do not exists !",@db_name
		return -1
	END

	IF @p_table_name IS NOT NULL
	BEGIN
		SELECT @cmd =
					"Declare @table_id int, "	+
					"@object_type nchar(2),	"	+
					"@ret_code int			"	+
					"SELECT	@table_id = id, "	+
					"@object_type = type "		+
					"FROM "						+
					@db_name + "..sysobjects "	+
					"WHERE "					+
					"name = '" + @p_table_name +"'"	+ char(10) + 
					"SELECT @ret_code = rm_appcontext('sp_dba_reorg_rebuild', 'table_id')" + char(10) +
					"SELECT @ret_code = rm_appcontext('sp_dba_reorg_rebuild', 'object_type')" + char(10) +
					"SELECT @ret_code = set_appcontext('sp_dba_reorg_rebuild', 'table_id', convert(VARCHAR(13),@table_id))"	+ char(10) +
					"SELECT @ret_code = set_appcontext('sp_dba_reorg_rebuild', 'object_type', @object_type)"
					
		EXECUTE (@cmd)

	/*
		Now get the information back from the context variable
	*/

		SELECT @table_id = CONVERT(INT,get_appcontext('sp_dba_reorg_rebuild', 'table_id'))
		SELECT @obj_type = get_appcontext('sp_dba_reorg_rebuild', 'object_type')

		IF @table_id IS NULL OR @obj_type != 'U'
		BEGIN
			Print "Table specified is not a user table or do not exists - Aborting process"
			Return -1
		END
	END
	ELSE
		SELECT @p_table_name = 'ALL'
	

--
-- First of all : Compute remaining space on the database
--
	SELECT @cmd =
			"DECLARE @free_space int, " + char(10)		+
			"@ret_code int " + char(10) 				+
			"SELECT @free_space = sum(curunreservedpgs(db_id('" + @db_name + "'), lstart, unreservedpgs)) " + char(10) +
			"from  master..sysusages " + char(10)		+
			"where dbid = db_id('" + @db_name + "')" + char(10)	+
			"and   ( segmap = 3 OR  segmap  = 7) " + char(10)	+
			"SELECT @ret_code = rm_appcontext('sp_dba_reorg_rebuild', 'free_space')" + char(10) +
			"SELECT @ret_code = set_appcontext('sp_dba_reorg_rebuild', 'free_space', convert(VARCHAR(13),@free_space))"


	EXECUTE (@cmd)
	
	SELECT @free_space = CONVERT(INT,get_appcontext('sp_dba_reorg_rebuild', 'free_space'))

	

--
-- Create a temp table to run along
--
	CREATE TABLE #tables2rebuild (
		sort_key 	int identity,
		user_name	sysname,
		table_name	sysname,
		table_id	int,
		rsrv_pages	bigint null)
	
	CREATE UNIQUE CLUSTERED INDEX idx_CU_tables2rebuild on #tables2rebuild(table_name)
	
	SELECT @cmd =
		"DECLARE @free_space int"	+ CHAR(10) +
		"SELECT @free_space = CONVERT(INT,get_appcontext('sp_dba_reorg_rebuild', 'free_space'))" + char(10) + 
		"INSERT #tables2rebuild (user_name,table_name,table_id,rsrv_pages) " + char(10) +
		"SELECT user_name(uid),"	+ char(10) + 
				"name,"				+ char(10) +
				"id,"				+ char(10) +
				"0 " +
--				"reserved_pages(db_id('" + @db_name + "'),id)" + char(10) + 
				"from "				+ char(10) +
				@db_name + "..sysobjects "	+ char(10)							+
				"where   type    = 'U' "	+ char(10)							+
				"and     not (sysstat2 & 1024 = 1024 or  -- Remote " + char(10)	+
				"sysstat2 & 2048 = 2048)         -- Proxy "	+ char(10)			+
				"and (name = '" + @p_table_name + "' OR '" + @p_table_name + "' = 'ALL')" + char(10) +
				" ORDER BY name"

	EXECUTE (@cmd)

--
-- Refresh stats (sp_flushstats cannot be executed outside the database)
--

	SELECT @sort_key = 0
	
	SELECT TOP 1 
		@sort_key	= sort_key,
		@table_id	= table_id
	FROM
		#tables2rebuild
	WHERE
		sort_key > @sort_key
	AND
		round(rsrv_pages * 2.0,0) < @free_space
	ORDER by table_id
	
	SELECT @rows = @@ROWCOUNT
	
	WHILE @rows > 0
	BEGIN
/*
	Issue the dbcc operation for each table
*/
		
		dbcc flushstats(@db_id, @table_id)
	
		SELECT TOP 1 
			@sort_key	= sort_key,
			@table_id	= table_id
		FROM
			#tables2rebuild
		WHERE
			sort_key > @sort_key
		AND
			round(rsrv_pages * 2.0,0) < @free_space
		ORDER by table_id
		
		SELECT @rows = @@ROWCOUNT
	
	END

/*
	Now we can get the very last values from the OAM tables
*/

	UPDATE 
		#tables2rebuild
	SET
		rsrv_pages = reserved_pages(@db_id,table_id)

	
/*
	Here comes the real work
*/
	
	SELECT @sort_key = 0
	
	SELECT TOP 1 
		@sort_key	= sort_key,
		@table_name	= table_name
	FROM
		#tables2rebuild
	WHERE
		sort_key > @sort_key
	ORDER by table_name
	
	SELECT @rows = @@ROWCOUNT
	
	WHILE @rows > 0
	BEGIN
/*
	Lets try to analyze the state of the table and see if
	there is a need to do something
*/
	
/*
	Can we full rebuild ?
*/	
		IF rsrv_pages < @free_space ......
/*
		Is there a big fragmentation ?
*/
	"Data Page Cluster Ratio"
	
		SELECT TOP 1 
			@sort_key	= sort_key,
			@table_name	= table_name
		FROM
			#tables2rebuild
		WHERE
			sort_key > @sort_key
		AND
			rsrv_pages < @free_space
		ORDER by table_name
		
		SELECT @rows = @@ROWCOUNT
	
	END
		
	

--
--declare c2 cursor for
--        select user_name(uid),
--               name,
--               reserved_pages(db_id(@db_name),id)
--               from    sysobjects
--               where   type    = "U"   -- User tables
--               and     not (sysstat2 & 1024 = 1024 or  -- Remote
--                       sysstat2 & 2048 = 2048)         -- Proxy
--               order   by 3


SELECT @message = "reorg rebuild started for database : " +  @db_name
print "reorg rebuild started for database %1!", @db_name

exec sp_flushstats

open c2

fetch c2 into @user_name, @table_name, @reserved_pages

while @@sqlstatus = 0
begin


   if @free_space < round(@reserved_pages * 2.0,0)
      print   "Skipping table %1!.%2! not enough space in database", @user_name, @table_name
   else
   begin
      print "Table %1!.%2!", @user_name, @table_name

      select @cmd = "reorg rebuild " + @user_name + "." + @table_name

      exec (@cmd)

      if @@error != 0
         break

      select @cmd = rtrim(@user_name) + "." + @table_name

      exec sp_recompile @cmd

      if @@error != 0
         break
   end

   fetch c2 into @user_name, @table_name, @reserved_pages
end

close c2

deallocate cursor c2

return 0
go