use sybsystemprocs
go

IF OBJECT_ID('dbo.sp_show_locks') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.sp_show_locks
    IF OBJECT_ID('dbo.sp_show_locks') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.sp_show_locks >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.sp_show_locks >>>'
END
go

/* @FILE_DOC*********************************************************************
 *
 * FILE NAME		:sp_show_locks.sql
 *
 * PROCEDURE NAME	:sp_show_locks 
 *
 * DESCRIPTION		:This Procedure returns locked users
 *
 * IMPLEMENTATION	:	
 *
 *
 * HISTORY        :
 *
 * Date         Name			  		Modificatiom
 * ----------------------------------------------------------------------
 * 29-Nov-2018 Zion A:				1rst version
*/
create procedure sp_show_locks
as
begin
	SELECT 
	V.spid, 
	V.status, 
	SUSER_NAME(V.suid) as victim_user_name, 
	CASE V.clienthostname WHEN '' THEN V.hostname WHEN NULL THEN V.hostname ELSE V.clienthostname END as victim_hostname, 
	CASE V.clientapplname WHEN '' THEN V.program_name WHEN NULL THEN V.program_name ELSE V.clientapplname END as victim_prog_name, 
	DB_NAME(G.suid) 'Database', 
	V.cmd, 
	V.tran_name 'Transaction', 
	V.time_blocked 'Time Blocked', 
	V.blocked 'Blocker spid', 
	SUSER_NAME(G.suid) as blocker_user_name, 
	G.status, 
	CASE G.clienthostname WHEN '' THEN G.hostname WHEN NULL THEN G.hostname ELSE G.clienthostname END as blocker_hostname, 
	CASE G.clientapplname WHEN '' THEN G.program_name WHEN NULL THEN G.program_name ELSE G.clientapplname END as blocker_prog_nameG,
	G.memusage, 
	G.cpu, 
	G.physical_io
	FROM 
		master.dbo.sysprocesses V,
		master.dbo.sysprocesses G
	WHERE 
		V.blocked !=0
	AND
		V.blocked=G.spid
	ORDER by 1
end	
go
go
GRANT EXECUTE on sp_show_locks to public
go
IF OBJECT_ID('dbo.sp_show_locks') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.sp_show_locks >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.sp_show_locks >>>'
go

