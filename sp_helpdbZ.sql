use sybsystemprocs
go
IF OBJECT_ID('dbo.sp_helpdbZ') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.sp_helpdbZ
    IF OBJECT_ID('dbo.sp_helpdbZ') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.sp_helpdbZ >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.sp_helpdbZ >>>'
END
go

/* Sccsid = "%Z% generic/sproc/%M% %I% %G%" */
/*	4.8	1.1	06/14/90	sproc/src/help */
/*
** Messages for "sp_helpdbZ"             17590
**
** 17111, "log only"
** 17590, "The specified database does not exist."
** 17591, "no options set"
** 17592, " -- unused by any segments --"
** 17714, "not applicable"
** 17600, "sp_helpdbZ: order value '%1!' is not valid. Valid values are 
**	'lstart' and 'device_name'. Using default value 'lstart'."
** 17609, "Device allocation is not displayed for local temporary 
**	   database '%1!'. To display this information, execute the 
**	   procedure on the owner instance '%2!'."
** 17909, "log only unavailable". 
*/
create procedure sp_helpdbZ
@dbname varchar(255) = NULL,			/* database name to change */
@order	varchar(20) = 'lstart'			/* Use 'device_name' to order
						** by device name
						*/
as

declare	@showdev	int,
	@showinstance	int,
	@allopts	int,
	@all2opts	int,
	@all3opts	int,
	@all4opts	int,
	@dbstatus4	int,
	@thisopt	int,
	@optmask	int,
	@optmax		int,
	@template_mask	int,
	@imdb_mask	int,
	@pgcomp_mask	int,
	@rowcomp_mask	int,
	@has_template_mask	int,
	@local_tempdb_mask	int,
	@pagekb		unsigned int,
	@msg 		varchar(1024),
	@sptlang	int,
	@na_phrase	varchar(30),	/* length of German */
	@sqlbuf		varchar(1024),
	@len1 int, @len2 int, @len3 int,
	@q		char(1),	/* quote sign */
	@instancename	varchar(255),
	@flmode_class	int,
	@flmode		int,
	@flmode_all	int,
	@flmode_desc	varchar(100),
        @holesize 	numeric(20,0),
	@location	int,
	@select_list    varchar(255),
        @str1           varchar(30),
        @str2           varchar(30)
if @@trancount = 0
begin
	set chained off
end

set transaction isolation level 1

select @sptlang = @@langid

if @@langid != 0
begin
	if not exists (
		select * from master.dbo.sysmessages where error
		between 17050 and 17069
		and langid = @@langid)
	    select @sptlang = 0
	else
	if not exists (
		select * from master.dbo.sysmessages where error
		between 17110 and 17119
		and langid = @@langid)
	    select @sptlang = 0
end

set nocount on

/*
**  If no database name given, get 'em all.  Otherwise, count how many
**  databases match the specified name.
*/
if @dbname is null
	select @dbname = "%",
	       @showdev = count(*) from master.dbo.sysdatabases
else
	select @showdev = count(*)
			   from master.dbo.sysdatabases
			   where name like @dbname

/*
**  Sure the database exists
*/
if @showdev = 0
begin
	/* 17590, "The specified database does not exist." */
	raiserror 17590
	return (1)
end

/*
**  Set allopts to be the sum of all possible user-settable database status
**  bits.  (Note that there are 2 groups of such bits.)  If we can't get
**  the option mask from spt_values, guess at the correct value.
*/
select @allopts = number
from master.dbo.spt_values
where	type = "D"
  and	name = "ALL SETTABLE OPTIONS"
if (@allopts is NULL)
	select @allopts = 4 | 8 | 16 | 512 | 1024 | 2048 | 4096 | 8192

select @all2opts = number
from master.dbo.spt_values
where	type = "D2"
  and	name = "ALL SETTABLE OPTIONS"
if (@all2opts is NULL)
	select @all2opts = 1 | 2 | 4 | 8 | 64

select @all3opts = number
from master.dbo.spt_values
where	type = "D3"
  and	name = "ALL SETTABLE OPTIONS"
if (@all3opts is NULL)
	select @all3opts = 0

select @all4opts = number
from master.dbo.spt_values
where	type = "D4"
  and	name = "ALL SETTABLE OPTIONS"
if (@all4opts is NULL)
	select @all4opts = 0

/*
** @allopts (sysdatabases.status options) should also contain some
** NON-settable options that we want to check for:
**	 32 = "don't recover"
**	256 = "not recovered"
*/
select @allopts = @allopts | 32 | 256

/*
** @all2opts (sysdatabases.status2 options) should also contain a
** NON-settable option that we want to check for:
**	 16 = "offline"
**	128 = "has suspect objects"
**     1024 = "online for standby access"
**    32768 = "mixed log and data" 
*/
select @all2opts = @all2opts | 16 | 128 | 1024 | 32768

/*
** @all3opts (sysdatabases.status3 options) should also contain 
** NON-settable options that we want to check for:
**
**	0128 = "quiesce database"
**	
**	if SMP
**		256 = "user created temp db"
**	if SDC
**	        256 = "local user temp db"
**		536870912 = "local system temp db"
**		1073741824 = "global user temp db"
**
**	1024 = "async log service"
**	2048 = "delayed commit"
**   4194304 = "archive database"
**   8388608 = "compressed data"
** 134217728 = "compressed log"
*/
select @all3opts = @all3opts | 128 | 256 | 1024 | 2048 | 4194304 | 8388608 | 134217728
if @@clustermode = "shared disk cluster"
begin
	select @all3opts = 
		@all3opts | 536870912 | 1073741824
	select @local_tempdb_mask = number
		from master.dbo.spt_values
		where   type = "D3" and name = "LOCAL TEMPDB STATUS MASK"
end
else
begin
	select @local_tempdb_mask = 0 
end

/*
** @all4opts (sysdatabases.status4 options) should also contain 
** NON-settable options that we want to check for:
**
**	4096 = "in-memory database"
**	512  = "has template"
**	1024 = "is template database"
**      8192 = "user-created" "enhanced performance temp db"
*/
select 	@all4opts = @all4opts | 256 | 1024 | 4096 | 16777216 | 33554432,
	@has_template_mask = 512,
	@template_mask = 1024,
	@imdb_mask = 4096,
	@pgcomp_mask = 16777216,
	@rowcomp_mask = 33554432

/*
**  Since we examine the status bits in sysdatabase and turn them
**  into english, we need a temporary table to build the descriptions.
*/
create table #spdbdesc
(
	dbid	smallint null,
	dbdesc	varchar(777) null
)

/*
**  Initialize #spdbdesc from sysdatabases
*/
insert into #spdbdesc (dbid)
		select dbid 
			from master.dbo.sysdatabases
				where name like @dbname
/*
**  Now for each dbid in #spdbdesc, build the database status
**  description.
*/
declare @curdbid smallint		/* the one we're currently working on */
declare @dbdesc varchar(777)		/* the total description for the db */
declare @bitdesc varchar(50)		/* the bit description for the db */

/* For regular databases, we don't need to show the owner instances. */
select @showinstance = 0

/*
** Get full logging option mask for all
*/
select @flmode_class = 38
select @flmode_all = object_info1 
from master..sysattributes
where class = @flmode_class and object = 1 and attribute = 0

select @optmax = max(object_info1)
from master..sysattributes
where class = @flmode_class and object = 1 and attribute != 0

/*
**  Set @curdbid to the first dbid.
*/
select @curdbid = min(dbid)
	from #spdbdesc

while @curdbid is not NULL
begin
	/*
	**  Initialize @dbdesc.
	*/
	select @dbdesc = ""

	/*
	**  Check status options (spt_values.type = "D")
	*/
	select @thisopt = 1
	select @optmask = @allopts	/* status options */
	while (@optmask != 0)		/* until all set options noted ... */
	begin
		/*
		** If this option is user-settable, check for it
		*/
		if (@optmask & @thisopt = @thisopt)
		begin
			select @bitdesc = null

			select @bitdesc = m.description
			from master.dbo.spt_values v,
			     master.dbo.sysdatabases d,
			     master.dbo.sysmessages m
			where d.dbid = @curdbid
				and v.type = "D"
				and d.status & v.number = @thisopt
				and v.number = @thisopt
				and v.msgnum = m.error
				and isnull(m.langid, 0) = @sptlang
			if @bitdesc is not null
			begin
				if @dbdesc != ""
					select @dbdesc = @dbdesc + ", " +  @bitdesc
				else select @dbdesc = @bitdesc
			end

			/* Turn off this status bit in the options mask */
			select @optmask = @optmask & ~(@thisopt)
		end

		/*
		** Get the next option bit.  Check for integer overflow for
		** bit 31 (0x80000000).
		*/
		if (@thisopt < 1073741824)
			select @thisopt = @thisopt * 2
		else
			select @thisopt = -2147483648
	end

	/*
	**  Check status2 options (spt_values.type = "D2")
	*/
	select @thisopt = 1
	select @optmask = @all2opts	/* status2 options */
	while (@optmask != 0)		/* until all set options noted ... */
	begin
		/*
		** If this option is user-settable, check for it
		*/
		if (@optmask & @thisopt = @thisopt)
		begin
			select @bitdesc = null

			select @bitdesc = m.description
			from master.dbo.spt_values v,
			     master.dbo.sysdatabases d,
			     master.dbo.sysmessages m
			where d.dbid = @curdbid
				and v.type = "D2"
				and d.status2 & v.number = @thisopt
				and v.number = @thisopt
				and v.msgnum = m.error
				and isnull(m.langid, 0) = @sptlang
			if @bitdesc is not null
			begin
				if @dbdesc != ""
					select @dbdesc = @dbdesc + ", " +  @bitdesc
				else select @dbdesc = @bitdesc
			end

			/* Turn off this status bit in the options mask */
			select @optmask = @optmask & ~(@thisopt)
		end

		/*
		** Get the next option bit.  Check for integer overflow for
		** bit 31 (0x80000000).
		*/
		if (@thisopt < 1073741824)
			select @thisopt = @thisopt * 2
		else
			select @thisopt = -2147483648
	end

	/*
	**  Check status3 options (spt_values.type = "D3")
	*/
	select @thisopt = 1
	select @optmask = @all3opts	/* status3 options */
	while (@optmask != 0)		/* until all set options noted ... */
	begin	-- {
		/*
		** If this option is user-settable, check for it
		*/
		if (@optmask & @thisopt = @thisopt)
		begin
			select @bitdesc = null

			select @bitdesc = m.description
			from master.dbo.spt_values v,
			     master.dbo.sysdatabases d,
			     master.dbo.sysmessages m
			where d.dbid = @curdbid
				and v.type = "D3"
				and d.status3 & v.number = @thisopt
				and v.number = @thisopt
				and v.msgnum = m.error
				and isnull(m.langid, 0) = @sptlang

			if (	(@bitdesc is not null)
			    and (@thisopt = 256) )
			begin	-- {
				/*
				** Check if it's an Implicit or
				** Explicit tempdb.
				*/
				select @dbstatus4 = status4 
				from master.dbo.sysdatabases
				where dbid = @curdbid
 
				/*
				** Check if its explicit tempdb with
				** "no_recovery" by comparing it with
				** the decimal value of
				** DBT4_EXPLICIT_NO_REC_TEMPDB.
				** If explicit, output "user-created
				** enhanced performance temp db".
				**
				** If implicit (normal or IMDB) tempdb
				** then output "user created temp db".
				*/
				if (@dbstatus4 & 8192 = 8192)
				begin
					select @str1 = m.description
					from master.dbo.spt_values v
					   , master.dbo.sysmessages m
					where v.type = "D4"
					  and v.number = 8192
					  and v.msgnum = 17164
					  and m.error = v.msgnum

					select @str2 = m.description
					from master.dbo.spt_values v
					   , master.dbo.sysmessages m
					where v.type = "D4"
					  and v.number = 8192
					  and v.msgnum = 17165
					  and m.error = v.msgnum

					/*
					** In case of a rare error that we
					** could not retrieve one or both of
					** the messages, return the final
					** message as NULL so as to signal some
					** unforeseen error.
					*/
					if (    (@str1 IS NOT NULL)
					    and (@str2 IS NOT NULL))

						select @bitdesc = @str1
							   	+ " "
								+ @str2

					else
						select @bitdesc = NULL
				end
			end	-- }

			if @bitdesc is not null
			begin 
				if @dbdesc != ""
					select @dbdesc = @dbdesc + ", " + @bitdesc
				else 
					select @dbdesc = @bitdesc

				if (@thisopt & @local_tempdb_mask = @thisopt)
					select @showinstance = 1
			end

			/* Turn off this status bit in the options mask */
			select @optmask = @optmask & ~(@thisopt)
		end	-- }

		/*
		** Get the next option bit.  Check for integer overflow for
		** bit 31 (0x80000000).
		*/
		if (@thisopt < 1073741824)
			select @thisopt = @thisopt * 2
		else
			select @thisopt = -2147483648
	end	-- }

	/*
	**  Check status4 options (spt_values.type = "D4")
	*/
	select @thisopt = 1
	select @optmask = @all4opts	/* status4 options */
	while (@optmask != 0)		/* until all set options noted ... */
	begin	-- {
		/*
		** If this option is user-settable, check for it
		*/
		if (@optmask & @thisopt = @thisopt)
		begin
			select @bitdesc = null

			select @bitdesc = m.description
			from master.dbo.spt_values v,
			     master.dbo.sysdatabases d,
			     master.dbo.sysmessages m
			where d.dbid = @curdbid
				and v.type = "D4"
				and d.status4 & v.number = @thisopt
				and v.number = @thisopt
				and v.msgnum = m.error
				and isnull(m.langid, 0) = @sptlang
			if @bitdesc is not null
			begin
				if @dbdesc != ""
					select @dbdesc = @dbdesc + ", " +  @bitdesc
				else select @dbdesc = @bitdesc
			end

			/* Turn off this status bit in the options mask */
			select @optmask = @optmask & ~(@thisopt)
		end

		/*
		** Get the next option bit. Now bit 31 (0x80000000) is 
		** used for "deallocate first text page", handle it
		** here.
		** 
		**	-2147483648 = "deallocate first text page"
		*/
		if (@thisopt = -2147483648)
			break
		else if (@thisopt < 1073741824)
			select @thisopt = @thisopt * 2
		else
			select @thisopt = -2147483648
	end	-- }

	/* 
	** Master uses @flmode_class only to store bit names/values
	** but they are not applicable to master itself.
	*/
	if @curdbid = 1
		goto skip_flmode

	/*
	** Get full logging modes for this database
	*/
	select @flmode = 0, @flmode_desc = ""

	select @flmode = object_info1 
	from master..sysattributes
	where class = @flmode_class and object = @curdbid and attribute = 0

	if (@flmode = @flmode_all)
	begin
		select @flmode_desc = "full logging for all"
		select @flmode = 0
	end

	select @thisopt = 1
        select @optmask = @flmode  
        while ((@optmask != 0) and (@thisopt <= @optmax))
        begin
               	if (@optmask & @thisopt != 0)
               	begin
                       	select @bitdesc=char_value
                       	from master..sysattributes
                       	where class = @flmode_class 
                       	and object = 1 
			and object_info1 = @thisopt
 
			if @bitdesc is not null
                       	begin
				if (@flmode_desc = "")
					select @flmode_desc = "full logging for "
						+ @bitdesc
				else
					select @flmode_desc = @flmode_desc + "/"
						+ @bitdesc
                       	end
			select @optmask = @optmask & ~(@thisopt)
		end
			
               	if (@thisopt < 1073741824)
			select @thisopt = @thisopt * 2
               	else
                       	select @thisopt = -2147483648
       	end

	if (@flmode_desc != "")
	begin
		if (@dbdesc != "")
			select @dbdesc = @dbdesc + "," +  @flmode_desc
       		else 
			select @dbdesc = @flmode_desc
	end
	
skip_flmode:

	/*
	**  If no flags are set, say so.
	*/
	if (@dbdesc = "")
	begin
		/* 17591, "no options set" */
		exec sp_getmessage 17591, @dbdesc out
	end

	/*
	**  Save the description.
	*/
	update #spdbdesc
		set dbdesc = @dbdesc
			from #spdbdesc
				where dbid = @curdbid

	/*
	**  Now get the next, if any dbid.
	*/
	select @curdbid = min(dbid)
		from #spdbdesc
			where dbid > @curdbid
end 
	
/* 
** Get the rows of interest from sysusages into a temp table.  This is to
** avoid deadlocking with create table, which could happen if we directly
** join sysdatabases and sysusages.
** Mark as log only those fragments that have segmap = 0 but location
** set as read only log. They are an intermediate step in the
** log shrink process.
*/
select  u.dbid, segmap = u.segmap,
	u.lstart, u.size, u.vdevno,
	u.unreservedpgs, u.crdate
	into #spdbusages
	from #spdbdesc, master.dbo.sysusages u
	where #spdbdesc.dbid = u.dbid
	and u.vdevno >= 0

/*
	Zion Fix : 0 for segmap IS NOT ACCEPTABLE !!!!
*/

	SELECT
		b.number,
		CASE WHEN b.number in (3,4,7)
			then left(m.description,20)
		ELSE
			"Balagan - " + convert(varchar,b.number)
		END as descriptipn,
		b.msgnum,
		b.type
	INTO
		#spt_values
	FROM
		master.dbo.spt_values b, 
		master.dbo.sysmessages m
	WHERE
		b.type = "S"
	AND
		b.msgnum = m.error

/*	
** Compute number of Pages in a Megabyte.
*/
declare @numpgsmb 	float		/* Number of Pages per Megabyte */

select @numpgsmb = (1048576. / v.low)
	from master.dbo.spt_values v
		 where v.number = 1
		 and v.type = "E"	

/*
**  Now #spdbdesc is complete so we can print out the db info
*/

	select distinct name = d.name,
		db_size = str(sum(u.size) / @numpgsmb, 10, 1)
			+ " MB",
		owner = suser_name(d.suid), 
		dbid = d.dbid,
		created = convert(char(18), d.crdate, 107),
		durability = ' ',
		status = #spdbdesc.dbdesc

	into #sphelpdb1rs
			from master.dbo.sysdatabases d, 
				 #spdbusages u, #spdbdesc
		where d.dbid = #spdbdesc.dbid
			and #spdbdesc.dbid = u.dbid
		group by #spdbdesc.dbid
		having d.dbid = #spdbdesc.dbid
			and #spdbdesc.dbid = u.dbid


/*
** Print the owner instance name only if the database name is specified
** and the database is a local tempdb (@showinstance = 1)
*/
select @select_list = "name, db_size, owner, dbid, created, durability,   status"

	exec sp_autoformat @fulltabname = #sphelpdb1rs
			 , @selectlist = @select_list
			 , @orderby = "order by 1"


/*  
** Print sysattributes data if there is any.  The join with multiple
** instances of sysattributes is to get the string descriptions for
** the class (master..sysattributes cn) and the attribute
** (master..sysattributes an). These should never be longer than
** 30 characters, so it's okay to truncate them.
*/

select name = db.name, attribute_class = 
				convert(varchar(512), cn.char_value), 
	attribute = convert(varchar(512), an.char_value), a.int_value, 
	char_value = convert(varchar(512), a.char_value), a.comments, 
	class = a.class, 
	attribute_id = a.attribute
into #spdbattr
from master.dbo.sysdatabases db, #spdbdesc d,
	master.dbo.sysattributes a, master.dbo.sysattributes an,
	master.dbo.sysattributes cn
where db.dbid = d.dbid
and a.class != @flmode_class
and a.class = cn.object
and a.attribute = an.object_info1
and a.class = an.object
and a.object_type = "D"
and a.object = d.dbid
and cn.class = 0
and cn.attribute = 0
and an.class = 0
and an.attribute = 1
and a.object = db.dbid

/*
** It's possible a cache is deleted without doing an unbind first. After
** a server reboot the binding is marked 'invalid' (int_value = 0).
** If we have such an invalid binding, don't show it in the output.
*/
delete from #spdbattr
where class = 3
and attribute_id = 0
and int_value = 0

if exists (select * from #spdbattr)
begin
	exec sp_autoformat  @fulltabname = #spdbattr,
		@selectlist = "name, attribute_class, attribute, int_value,char_value,comments"
end



if @showdev = 1 
begin	-- {
	select @curdbid = dbid			/* database ID */
		from master.dbo.sysdatabases
		where name like @dbname
	select @pagekb = (low / 1024)		/* kbytes per page */
		from master.dbo.spt_values
		where number = 1
		  and type = 'E'

	/* 17714, "not applicable" */
	select @na_phrase = description
		from master.dbo.sysmessages 
		where error = 17714
		  and isnull(langid, 0) = @sptlang

	/* Check the length of the usage column */
	select distinct @len3 = max(datalength(m.description))
	    from master.dbo.sysdatabases d, #spdbusages u, master.dbo.sysdevices v, 
			master.dbo.spt_values b, master.dbo.sysmessages m
		where d.dbid = u.dbid
			and u.vdevno = v.vdevno
			and ((v.status & 2 = 2)  or (v.status2 & 8 = 8))
			and d.name like @dbname
			and b.type = "S"
			and u.segmap & 7 = b.number
			and b.msgnum = m.error
			and isnull(m.langid, 0) = @sptlang

	/*
	** Order the device fragments output by sysusages.lstart unless
	** the 2nd parameter of sp_helpdbZ is "device_name"
	*/
	if (@order = "device_name")
	begin
		select @order = "v.name"
	end
	else
	begin
		if (@order != "lstart")
		begin
			/*
			** 17600, "sp_helpdbZ: order value '%1!' is not valid. 
			** Valid values are 'lstart' and 'device_name'. 
			** Using default value 'lstart'."
			*/
			raiserror 17600, @order
		end

		/* Fragment order same as order in create/alter database */
		select @order = "u.lstart"

	end

	if (@len3 < 20)
		select @len3 = 20

	select  @q = substring('''',1,1)

	select @sqlbuf = 
	    'select device_fragments = v.name, size =
			str(size / ' + str(@numpgsmb,10,1) + ', 10, 1) + '
			+ @q + ' MB' + @q + ',
		usage = convert(char('
			+ convert(varchar, @len3) + '), m.description),
		created = convert(char(25), u.crdate, 100),
		case
			when u.segmap = 4 then ' + @q + @na_phrase + @q
			+ ' else 
			str((convert(bigint, (curunreservedpgs(d.dbid, u.lstart,
				u.unreservedpgs)) * ' 
				+ convert(varchar, @pagekb) + ')/1024), 16)
		end "free Mbytes","%"=convert(numeric(10,2), (((curunreservedpgs(d.dbid, u.lstart,
				u.unreservedpgs)) *@pagekb)/1024)/(size/@numpgsmb))*100 
	    from master.dbo.sysdatabases d,
		 #spdbusages u,
		 master.dbo.sysdevices v,
		 master.dbo.spt_values b,
		 master.dbo.sysmessages m
		where d.dbid = u.dbid
			and u.vdevno = v.vdevno
			and ((v.status & 2 = 2)  or (v.status2 & 8 = 8))
			and d.name = '  +@q + @dbname + @q + '
			and b.type = ' + @q + 'S' + @q + '
			and u.segmap & 7 = b.number
			and b.msgnum = m.error
			and isnull(m.langid, 0) = ' 
				+ convert(varchar,@sptlang) +
	    ' order by ' + @order 

	exec (@sqlbuf)

--start Zion addition

	select @sqlbuf = 
	    'select device = v.name, Total_size =
			str(sum(size / ' + str(@numpgsmb,10,1) + '), 10, 1) + '
			+ @q + ' MB' + @q + '
	    from master.dbo.sysdatabases d,
		 #spdbusages u,
		 master.dbo.sysdevices v,
		 master.dbo.spt_values b,
		 master.dbo.sysmessages m
		where d.dbid = u.dbid
			and u.vdevno = v.vdevno 
			and ((v.status & 2 = 2)  or (v.status2 & 8 = 8))
			and d.name = '  +@q + @dbname + @q + '
			and b.type = ' + @q + 'S' + @q + '
			and u.segmap & 7 = b.number
			and b.msgnum = m.error
			and isnull(m.langid, 0) = ' 
				+ convert(varchar,@sptlang) +
	    ' group by v.name'

	exec (@sqlbuf)


	select @sqlbuf = 
	    'SELECT Usage = m.description, Total_Allocation =
			str(sum(size / ' + str(@numpgsmb,10,1) + '), 10, 1) + '
			+ @q + ' MB' + @q 
			+
	', Free_Mb = str(sum((convert(bigint, (curunreservedpgs(d.dbid, u.lstart,
				u.unreservedpgs)) * ' 
				+ convert(varchar, @pagekb) + '.)/1024.)), 10,2) ' + 
	', Free_prc = convert(numeric(5,2),(convert(real,sum((((curunreservedpgs(d.dbid, u.lstart,
				u.unreservedpgs)) * 2.)/1024.)))/sum(size /' +  str(@numpgsmb,10,1) + ')) * 100 )
  	    from master.dbo.sysdatabases d,
		 #spdbusages u,
		 master.dbo.sysdevices v,
		 master.dbo.spt_values b,
		 master.dbo.sysmessages m
		where d.dbid = u.dbid
			and u.vdevno = v.vdevno 
			and ((v.status & 2 = 2)  or (v.status2 & 8 = 8))
			and d.name = '  +@q + @dbname + @q + '
			and b.type = ' + @q + 'S' + @q + '
			and u.segmap & 7 = b.number
			and b.msgnum = m.error
			and isnull(m.langid, 0) = ' 
				+ convert(varchar,@sptlang) +
	    ' group by m.description'

	exec (@sqlbuf)
--select @sqlbuf



-- End Zion addition


	/* 
	** If log segment free space wasn't selected above, select it now.
	** Skip this step if the database is in load (32), not recovered (64)
	** in bypass recovery (128), suspect (256), offline (64)
	*/
	select @sqlbuf=""
	if exists (select *
	    from master.dbo.sysdatabases d, master.dbo.sysusages u
		where d.name like @dbname
			and d.dbid = u.dbid
			and u.segmap = 4
			and (d.status & ( 32 + 64 + 128 + 256) = 0)
			and (d.status2 & 64) = 0)

	begin
		/* 17111, "log only".  Length 17 is for French, the longest */
		select @sqlbuf = substring((select description
		    from master.dbo.sysmessages 
			where error = 17111
			   and isnull(langid, 0) = @sptlang), 1, 17)
		+ " " + "free Mbytes" + " = "
		+ convert (char, convert(numeric(15,2),((lct_admin("logsegment_freepages", @curdbid)
				- lct_admin("reserved_for_rollbacks", @curdbid))
				* @pagekb)/1024.))
	end

	/* 
	** If there are holes in the database, show the size. 
	** - LOG holes have sysusages.location == 9
	** - DATA holes have sysusages.location == 10
	*/
--	select @location = 9
--
--	while (@location > 0)
--	begin
--		select @holesize = sum(size)
--	    	from master.dbo.sysusages
--			where dbid = @curdbid 
--			and vdevno = -@curdbid
--			and location = @location
--
--		if (@holesize > 0)
--		begin
--			if ( @sqlbuf != "" )
--				select @sqlbuf=rtrim(@sqlbuf) + ", "
--
--			/* 17909, "only unavailable" */
--			select @sqlbuf = @sqlbuf 
--			+ case @location when 9 then "log " else "data " end
--			+ substring((select description
--		    	from master.dbo.sysmessages 
--			where error = 17909
--			   and isnull(langid, 0) = @sptlang), 1, 20)
--			+ " kbytes = " + convert(char, @holesize * @pagekb)
--		end
--
--		if (@location = 9)
--			select @location = 10
--		else
--			select @location = 0
--	end

	if ( @sqlbuf != "" )
		select substring(@sqlbuf, 1, 110)

	/*
	**  If there is only one database and we are in it, show the
	**  segments.
	*/
	if exists (select *
			from #spdbdesc
				where db_id() = dbid)
	begin	-- {
		declare @curdevice	varchar(255),
			@curseg		smallint,
			@segbit		int

		delete #spdbdesc

		select @curdevice = min(d.name)
			from  #spdbusages u, master.dbo.sysdevices d
				where u.dbid = db_id()
					and u.vdevno = d.vdevno
					and ((d.status & 2 = 2)  or (d.status2 & 8 = 8))
		while (@curdevice is not null)
		begin	-- {
			/*
			** We need an inner loop here to go through
			**  all the possible segment.
			*/
			select @curseg = min(segment)
					from syssegments
			while (@curseg is not null)
			begin
				if (@curseg < 31)
					select @segbit = power(2, @curseg)
				else select @segbit = low
					from master.dbo.spt_values
						where type = "E"
							and number = 2
				insert into #spdbdesc
					select @curseg, @curdevice
						from #spdbusages u,
							master.dbo.sysdevices d,
							master.dbo.spt_values v
					where u.segmap & @segbit = @segbit
						and u.vdevno = d.vdevno
						and u.dbid = db_id()
						and ((d.status & 2 = 2)  or (d.status2 & 8 = 8))
						and v.number = 1
						and v.type = "E"
						and d.name = @curdevice
				select @curseg = min(segment)
						from syssegments
							where segment > @curseg
			end

			select @curdevice = min(d.name)
				from  #spdbusages u,
					master.dbo.sysdevices d
				where u.dbid = db_id()
					and u.vdevno = d.vdevno
					and ((d.status & 2 = 2)  or (d.status2 & 8 = 8))
					and d.name > @curdevice
		end	-- }

		/*
		**  One last check for any devices that have no segments.
		*/
		insert into #spdbdesc
			select null, d.name
				from #spdbusages u,
					master.dbo.sysdevices d
			where u.segmap = 0
				and u.vdevno = d.vdevno
				and u.dbid = db_id()
				and ((d.status & 2 = 2)  or (d.status2 & 8 = 8))

		/* 17592, " -- unused by any segments --" */
		exec sp_getmessage 17592, @msg out

			select distinct device = dbdesc,
				segment = isnull(name, @msg)
			into #sphelpdb2rs
			from #spdbdesc, syssegments
				where dbid *= segment
			exec sp_autoformat @fulltabname = #sphelpdb2rs,
				@orderby = "order by 1, 2"
			drop table #sphelpdb2rs
	end	-- }

	/*
	** If the given database is a template database then
	** print all the database created from it.
	*/
	select @dbstatus4 = d.status4
		from master.dbo.sysdatabases d
		where name like @dbname

	/*
	** OMNI: Display the default location for remote tables
	**       if one exists.
	**
	** IMDB: In case of in-memory database def_remote_loc is
	** used to store the template database associated with the
	** in-memory database.
	*/
	if exists (select *
			from master.dbo.sysdatabases
				where name like @dbname 
				and def_remote_loc is not null)
	begin --{
		if ((@dbstatus4 & @has_template_mask) != 0)
		begin --{
			select "template_database" 
					= substring(def_remote_loc, 1, 30)
				from master.dbo.sysdatabases
					where name like @dbname
		end --}
		else
		begin --{
			select "remote location" = 
					substring(def_remote_loc, 1, 77)
				from master.dbo.sysdatabases
					where name like @dbname
		end --}
	end --}

	if ((@dbstatus4 & @template_mask) = @template_mask)
	begin --{
		select template_for = name 
		into #templateddbs
		from master.dbo.sysdatabases
		where def_remote_loc like @dbname
		
		exec sp_autoformat @fulltabname = #templateddbs
	end --}
end	-- }

drop table #spdbdesc
drop table #spdbattr
return (0)
go
IF OBJECT_ID('dbo.sp_helpdbZ') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.sp_helpdbZ >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.sp_helpdbZ >>>'
go
