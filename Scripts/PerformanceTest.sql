-- Performance test script, focussing on Latency.

-- This script will perform the following:
-- - Use the Test database
-- - (Optional: Drop performance_test table, if already existing)
-- - Create a performance_test table
-- - Create indexes
-- - Insert 1,000,000 rows, sequentially
-- - Update 1,000,000 rows, sequentially
-- - Delete 1,000,000 rows, sequentially

-- Use the appropriate database
use test
go

-- do not display rows affected messages
set nocount on

-- drop test table if it exists
if exists ( select * from sysobjects where name='performance_test' and type='U')
	drop table performance_test
go

-- create test table
create table performance_test
(
	nvarcol1 nvarchar(12),
	nvarcol2 nvarchar(12),
	nvarcol3 nvarchar(12),
	intcol1 int,
	intcol2 int,
	intcol3 int
)

-- create indexes on test table
create unique clustered index performance_test_uind on performance_test
(
	intcol2,
	intcol1,
	nvarcol1,
	nvarcol2
)

create index performance_test_ind on performance_test
(
	intcol1,
	intcol3,
	nvarcol2,
	nvarcol3
)

-- declare variables
declare @startTime DATETIME
declare @endTime DATETIME
declare @loop int = 1

-- change initial values below as appropriate
declare @inserts int = 1000000
declare @updates int = 1000000
declare @reads int = 5
declare @deletes int = 1000000
declare @actual_deletes int = 1000000

if @actual_deletes > @inserts
	BEGIN
		Select 'Cannot delete more rows than inserted' as 'Error'
	END

-- CAPTURE SCRIPT START TIME
SELECT GETDATE() test_start_time

-- INSERT RECORDS
SET @startTime = GETDATE();

while (@loop <= @inserts)
begin
	insert into performance_test values
	(
		'a',
		'b',
		'c',
		@loop,
		0,
		3
	)
	set @loop = @loop + 1
end

SET @endTime = GETDATE();
select cast((@endTime-@startTime) AS TIME) insert_time

-- UPDATE RECORDS
set @loop = 1

SET @startTime = GETDATE();

while (@loop <= @updates)
begin
	update unit4_test set intcol2 = @loop, nvarcol2 = 'abcdefghijkl', nvarcol3 = 'mnopqrstuvwx' where
		nvarcol1 = 'a' and 
		nvarcol2 = 'b' and
		intcol1 = @loop and
		intcol2 = 0
	set @loop = @loop + 1
end

SET @endTime = GETDATE();
select cast((@endTime-@startTime) AS TIME) update_time

-- DELETE RECORDS
set @loop = 1

SET @startTime = GETDATE();

while (@loop <= @actual_deletes)
begin
	delete unit4_test where
		nvarcol1 = 'a' and 
		nvarcol2 = 'abcdefghijkl' and
		nvarcol3 = 'mnopqrstuvwx' and
		intcol1 = @loop and
		intcol2 = @loop and
		intcol3 = 3
	set @loop = @loop + 1
end

SET @endTime = GETDATE();
select cast((@endTime-@startTime) AS TIME) actual_delete_time

-- Clean environment / remove test table
if exists ( select * from sysobjects where name='performance_test' and type='U')
	drop table performance_test
go


SELECT GETDATE() test_end_time
go
