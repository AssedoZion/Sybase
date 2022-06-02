
use sybsystemprocs
go

IF OBJECT_ID('dbo.sp_fastrows') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.sp_fastrows
    IF OBJECT_ID('dbo.sp_fastrows') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.sp_fastrows >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.sp_fastrows >>>'
END
go

/* @FILE_DOC*********************************************************************
 *
 * FILE NAME		:sp_fastrows.sql
 *
 * PROCEDURE NAME	:sp_fastrows 
 *
 * DESCRIPTION		:This Procedure returns rows number of all tables withing a given database
 *
 * IMPLEMENTATION	:	
 *
 *
 * HISTORY        :
 *
 * Date         Name			  		Modificatiom
 * ----------------------------------------------------------------------
 * 05-Mar-2015 Zion A:				1rst version
 * 05-Aug-2018 Zion A.				Added order by option
*********************************************************************FILE_DOC@**/ 

CREATE PROCEDURE sp_fastrows
@db_name VARCHAR(30),
@table_name sysname = null,
@order_by int = 2,
@asc_desc char(3) = 'Asc'
AS
BEGIN

	DECLARE @order_by_s varchar(30)
	SELECT @order_by_s = "   ORDER BY 2 desc"
	
	if ISNULL(@order_by,2) != 2
		SELECT @order_by_s = "   ORDER BY " + CONVERT(varchar(2),@order_by) + " " + @asc_desc

	select @db_name = ISNULL(@db_name,db_name())

	SELECT @table_name = ISNULL(@table_name,'NULL')
		
	EXEC (  "SELECT "		+
	"	O.name, "		+
	"	row_count(db_id('" + @db_name + "'),O.id) as row_count,"	+
	"   (reserved_pages(db_id('" + @db_name + "'), O.id) * @@pagesize)/1024 as rsrvd_space,"			+
	"	case sysstat2 & 57344 when 32768 then 'datarows' when 16384 then 'datapages' else 'allpages' end as scheme "	+
	"FROM "				+ 
	@db_name + "..sysobjects O, "	+
	@db_name + "..sysindexes I "	+
	"WHERE "						+
	"	O.type = 'U' "				+
	"AND "							+
	"	O.id=I.id "					+
	"AND "							+
	"	I.indid IN (0,1) "			+
	"AND "							+
	"( O.name = '" + @table_name + "' OR '" + @table_name + "'" + " = 'NULL' )"  +
	"   ORDER BY 2 desc")
	
END

go
GRANT EXECUTE on sp_fastrows to public
go
IF OBJECT_ID('dbo.sp_fastrows') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.sp_fastrows >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.sp_fastrows >>>'
go

