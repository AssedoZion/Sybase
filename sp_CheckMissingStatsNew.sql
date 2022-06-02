/*
	EXECUTE sp_CheckMissingStats 
	@db_name="emshist",
	@ptable_name = "ems_event_log",
	@days_number=0,
	@max_rows=1
	
	
sp_CheckMissingStats
@db_name		='ems',
@ptable_name	=null,
@days_number	= 1 ,
@max_rows		= 1000,
@prct_chg		 = 1,
@sampling		= 10


*/
--sp_fastrows ems



use sybsystemprocs
go
IF OBJECT_ID('dbo.sp_CheckMissingStats') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.sp_CheckMissingStats
    IF OBJECT_ID('dbo.sp_CheckMissingStats') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.sp_CheckMissingStats >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.sp_CheckMissingStats >>>'
END
go
--
--

/* @FILE_DOC*********************************************************************
 *
 * FILE NAME		:sp_CheckMissingStats.sql
 *
 * PROCEDURE NAME	:sp_CheckMissingStats 
 *
 * DESCRIPTION		:This Procedure will show the fields that are used to be updated but warent updated since n days
 *
 * IMPLEMENTATION	:	
 *
 *
 * HISTORY        :
 *
 * Date         Name			  		Modificatiom
 * ----------------------------------------------------------------------
 * 01-Jun-2015 Zion A:				1rst version
*********************************************************************FILE_DOC@**/ 
 
 /*
	Example:
		
update ems..sysstatistics set moddate = dateadd(dd,-1,moddate)
where id=object_id("ems_event_log")

sp_fastrows ems


	EXECUTE sp_CheckMissingStats 
	@db_name="ems",
--	@ptable_name = "ems_event_log",
	@days_number=0,
	@max_rows=1000000


	EXECUTE sp_CheckMissingStats 
	@db_name="ProtechE",
	@days_number=7

	EXECUTE sp_CheckMissingStats 
	@db_name="emshist",
	@days_number=7

 */

 CREATE PROCEDURE sp_CheckMissingStats
@db_name		varchar(30),
@ptable_name	varchar(30) = null,
@days_number	int = 0 ,
@max_rows		bigint = 100000,
@prct_chg		int = 0,
@sampling		int = 10
AS

BEGIN
	DECLARE 
		@rows 					int,
		@retcode				int,
		@identifier				int,
		@sql_sentence 			varchar(3000),
		@sql_sentence_result	varchar(200),
		@name 					longsysname,
		@id						int,
		@colidarray 			varbinary(100),
		@colid          		varbinary(2),
        @colnum         		smallint,
        @colstring      		varchar(1024),
		@field_name				varchar(30),
        @nb_fields				tinyint,
        @table_id       		int,
        @table_name     		varchar(255),
        @full_table_name     	varchar(255),
        @table_name_prev		varchar(255),
        @user_table_nm			varchar(300),
		@list_fields_keys		varchar(300),
		@list_fields_keys2		varchar(300),
		@pos1					int,
		@pos2					int,
		@index_name				varchar(30),
		@indid					int,
		@max_rowsS				varchar(10),
		@authorized_chg			bigint,
		@len					int,
		@index					int


	SELECT
		@table_name_prev = "",
		@ptable_name = ISNULL(@ptable_name,"ALL"),
		@max_rowsS = CONVERT(VARCHAR(10),@max_rows)

	CREATE TABLE #needees_for_stats
	(
		identifier	int identity not null,
		name		longsysname  not null,
		id			int  not null,
		colidarray	varbinary(100)  null
	)

	CREATE TABLE #tables_rows
	(
		id_key				int identity,
		tale_id				int null,
		table_name			varchar(30) null,
		full_table_name		varchar(62) null,
		rows_number 		bigint null
	)

	create unique clustered index idx_key on #tables_rows(id_key)

	CREATE TABLE #indexes
	(
		identifier		int identity,
		full_table_name	varchar(62) null,
		table_name		varchar(30) null,
		index_name		varchar(30) null,
		index_fields	varchar(500) null,
		nb_fields		int default 0,
		indid			smallint default 0,
		authorized_chg 	bigint null
	)
	CREATE UNIQUE CLUSTERED index idx_indexes on   #indexes (table_name,index_name)

	CREATE TABLE #results
	(
		full_table_name varchar(62) null,
		fields_list	varchar(255) null
	)
	
	create clustered index idx_results on #results (full_table_name,fields_list) with ignore_dup_row
	
/*
	Lets get the count of each table, so we can decide which kind of statistics we will produce
	If number of rows (estimation indeed) is lower than the value of @max_rows
		==> Then we perform UPDATE index statistics
	ELSE
		==> We run over the idexes of the table and produce an UPDATE STAT per combinations
		
*/

	EXEC (  "INSERT #tables_rows "	+
	"SELECT DISTINCT "				+
	"	O.id, "						+
	"	O.name, " 					+
	"'" + @db_name + "..' + O.name, "				+  
	"	row_count(db_id('" + @db_name + "'),O.id) " +
	"FROM "				 			+ 
	@db_name + "..sysobjects O, "	+
	@db_name + "..sysindexes I, "	+
	@db_name + "..syssegments S "	+
	"WHERE "						+
	"	O.type = 'U' "				+
	"AND "							+
	"	O.id=I.id "					+
	"AND "							+
	"((I.indid = 1 "				+
	" AND O.sysstat2 & 57344 NOT IN (32768,16384)) " +
	" OR "							+
	" (I.indid = 0 "				+
	" AND O.sysstat2 & 57344 IN (32768,16384))) "  +
	"AND "							+
	"(O.name = '" + @ptable_name + "' OR '" +
	@ptable_name	+ "' = 'ALL')" ) 

/*
	We will store the indexes definitions of each table in the list
*/
	EXEC ( "INSERT #indexes "		+
		"( "						+
		"full_table_name,"			+
		"table_name,"				+
		"index_name"				+
		") "						+
		"SELECT "					+
		"'" + @db_name + "' + " + "'..'" + " + o.name ,"		+
		"o.name,"					+
		"i.name "					+
		"FROM "						+
		@db_name + "..sysindexes i, "	+
		@db_name + "..sysobjects o, "	+
		"#tables_rows T "			+
		"WHERE "					+
		"T.rows_number >"			+
		@max_rowsS					+ " " +
		"AND "						+
		"T.table_name = o.name "	+
		"AND "						+
		"	i.indid >=1 "			+
		"AND "						+
		"o.id = i.id "				+
		"AND "						+
		"o.type = 'U' "				+
		"AND "						+
		"i.keycnt > 0 "				+
		"AND "						+
		"(o.name = '" + @ptable_name 				+ 
		"' OR '" + @ptable_name	+ "' = 'ALL') " 	+	
		"order by o.name,i.name" )

	EXEC("UPDATE #indexes "			+
	"SET "							+
	"	index_fields = "			+
	"index_col( T.full_table_name" + ", i.indid, 1) + ',' +"  +
	"CASE WHEN i.keycnt > 1 THEN index_col( T.full_table_name" + ", i.indid, 2) + ',' ELSE '' END  + "	+
	"CASE WHEN i.keycnt > 2 THEN index_col( T.full_table_name" + ", i.indid, 3) + ',' ELSE '' END  + "	+
	"CASE WHEN i.keycnt > 3 THEN index_col( T.full_table_name" + ", i.indid, 4) + ',' ELSE '' END  + "	+
	"CASE WHEN i.keycnt > 4 THEN index_col( T.full_table_name" + ", i.indid, 5) + ',' ELSE '' END  + "	+
	"CASE WHEN i.keycnt > 5 THEN index_col( T.full_table_name" + ", i.indid, 6) + ',' ELSE '' END  + "	+
	"CASE WHEN i.keycnt > 6 THEN index_col( T.full_table_name" + ", i.indid, 7) + ',' ELSE '' END  + "	+
	"CASE WHEN i.keycnt > 7 THEN index_col( T.full_table_name" + ", i.indid, 8) + ',' ELSE '' END  + "	+
	"CASE WHEN i.keycnt > 8 THEN index_col( T.full_table_name" + ", i.indid, 9) + ',' ELSE '' END  + "	+
	"CASE WHEN i.keycnt > 9 THEN index_col( T.full_table_name" + ", i.indid, 10) + ',' ELSE '' END + "	+
	"CASE WHEN i.keycnt > 10 THEN index_col( T.full_table_name" + ", i.indid, 11) + ',' ELSE '' END + "	+
	"CASE WHEN i.keycnt > 11 THEN index_col( T.full_table_name" + ", i.indid, 12) + ',' ELSE '' END + "	+
	"CASE WHEN i.keycnt > 12 THEN index_col( T.full_table_name" + ", i.indid, 13) + ',' ELSE '' END + "	+
	"CASE WHEN i.keycnt > 13 THEN index_col( T.full_table_name" + ", i.indid, 14) + ',' ELSE '' END + "	+
	"CASE WHEN i.keycnt > 14 THEN index_col( T.full_table_name" + ", i.indid, 15) + ',' ELSE '' END , " +
	"nb_fields = i.keycnt -1, "				+
	"indid = i.indid "						+
	"FROM "	+
	"	#indexes T, "					+
		@db_name + "..sysobjects o, "	+
		@db_name + "..sysindexes i "	+
	"WHERE "			+
	"o.id = i.id "	+
	"AND "				+
	"o.type = 'U' "	+
	"AND "				+
	"	i.indid > 0	"	+
	"AND "				+
	"o.name = T.table_name "	+
	"AND "				+
	"	i.name = T.index_name "  )

	UPDATE #indexes
	SET
		index_fields = left(index_fields,char_length(index_fields)-1)

	UPDATE #indexes
	SET
		index_fields = left(index_fields,char_length(index_fields)-1)
	WHERE 
		RIGHT(index_fields,1)=','
		
	SELECT @identifier = 0

	SELECT TOP 1
		@identifier			= I.identifier,
		@list_fields_keys	= I.index_fields,
		@full_table_name	= I.full_table_name,
		@pos1				= 1,
		@pos2				= 1,
		@authorized_chg		= authorized_chg,
		@nb_fields			= nb_fields,
		@indid				= indid,
		@index				= 1,
		@list_fields_keys2	= ''
	FROM
		#indexes I
	WHERE
		I.identifier > @identifier
	ORDER by identifier
	
	SELECT @pos2=CHAR_LENGTH(@list_fields_keys)
	
	SELECT @rows = @@ROWCOUNT
	
	WHILE @rows > 0
	BEGIN

		IF ISNULL(datachange(@full_table_name,null,index_col(@full_table_name,@indid,@index)),0) >= @prct_chg
		BEGIN
			WHILE @index <= @nb_fields
			BEGIN
				select @list_fields_keys2 = CASE WHEN @list_fields_keys2 != '' 
												THEN @list_fields_keys2 + ',' + index_col(@full_table_name,@indid,@index)
												ELSE index_col(@full_table_name,@indid,@index) END
				INSERT #results SELECT @full_table_name,@list_fields_keys2
				
				select @index = @index + 1
			END
		END

		SELECT TOP 1
			@identifier			= I.identifier,
			@list_fields_keys	= I.index_fields,
			@full_table_name	= I.full_table_name,
			@pos1				= 1,
			@pos2				= 1,
			@authorized_chg		= authorized_chg,
			@nb_fields			= nb_fields,
			@indid				= indid,
			@index				= 1,
			@list_fields_keys2 = ''

		FROM
			#indexes I
		WHERE
			I.identifier > @identifier
		ORDER by identifier
		
		SELECT @rows = @@ROWCOUNT
	END


	SELECT
		'UPDATE INDEX STATISTICS ' + @db_name + '..' + table_name + CHAR(10) + 'go' + CHAR(10)
	FROM
		#tables_rows
	WHERE
		rows_number < @max_rows
	AND
		datachange(full_table_name,null,null) >=@prct_chg
	UNION
	SELECT 
		'UPDATE STATISTICS ' + full_table_name + '(' + fields_list + ') WITH SAMPLING = ' + convert(varchar(3),@sampling) + ' PERCENT' + CHAR(10) + 'go' + CHAR(10)
	FROM 
		#results
	WHERE
		datachange(full_table_name,null,null) >=@prct_chg
END
go
IF OBJECT_ID('dbo.sp_CheckMissingStats') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.sp_CheckMissingStats >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.sp_CheckMissingStats >>>'
go