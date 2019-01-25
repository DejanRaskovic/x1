--	1. Schema AUD tabela AUD.audit_table
-- montira se u MSDB zbog stabilnosti sistema
-- poruke/eventi se uvek upisuju u systemskji queue u MSDB bazi pa ih
-- onda service broker prepisuje u odredisnu bazu servis. Kad odredisna
-- baza nije dostupna dolazi do prepunjavanja systemskog queue-a u MSDB
-- i do enormnog porata MSDB baze koja pojede ceo disk itd ....
use MSDB
go
-- posebna schema!
create schema AUD
go
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
-- TABELA ZA LOGOVANJE ------------------------------
-- drop  TABLE aud.[audit_table]
CREATE TABLE aud.[audit_table](
	[seqId] [bigint] IDENTITY(1,1) NOT NULL,
  PostTime datetime not null, 
  LoginName nvarchar(128),
  EventType varchar(128) not null,
  DatabaseName varchar(128) null,			-- MV 28.5.2010 -- v 3
  SrvEvent xml not null,
  constraint pk_audit_table
     primary key clustered(seqId desc) 
)
go


--	2. PROCEDURA AUD.AUDIT_SERVER_QUEUE_PROC

/*    ==Scripting Parameters==

    Source Server Version : SQL Server 2008 R2 (10.50.6560)
    Source Database Engine Edition : Microsoft SQL Server Standard Edition
    Source Database Engine Type : Standalone SQL Server

    Target Server Version : SQL Server 2008 R2
    Target Database Engine Edition : Microsoft SQL Server Standard Edition
    Target Database Engine Type : Standalone SQL Server
*/

USE [msdb]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-- PROCEDURA ZA PRIHVAT PORUKA IZ QUEUE. ------------
alter procedure [AUD].[AUDIT_SERVER_QUEUE_PROC]
as
set nocount on;
declare @msgBody XML, @message_type_name NVARCHAR(256), @dialog UNIQUEIDENTIFIER ;
declare @lastId int;
declare @EventType nvarchar(4000), @LoginName nvarchar(128);
WHILE (1 = 1)
BEGIN
  BEGIN TRANSACTION ;
  waitfor (
    receive top(1) 
      @message_type_name=message_type_name, 
      @msgBody=message_body, 
      @dialog = conversation_handle
      from aud.AUDIT_SERVER_QUEUE
  ), timeout 2000 ;

  if (@@rowcount = 0)
    begin
      ROLLBACK TRANSACTION ;
      break ;
    end;

  if (@message_type_name = 'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog')
    begin
      end conversation @dialog ;
    end ;
  else
    BEGIN
      set @EventType=isnull(@msgBody.value('(/EVENT_INSTANCE/EventType)[1]', 'varchar(128)'),'');
      set @LoginName=@msgBody.value('(/EVENT_INSTANCE/LoginName)[1]', 'varchar(128)');
      if @EventType not in ('UPDATE_STATISTICS') begin
            insert into aud.audit_table( PostTime, LoginName, EventType, DatabaseName, SrvEvent) 
            values (
              @msgBody.value('(/EVENT_INSTANCE/PostTime)[1]', 'datetime'),
              @LoginName, 
              @EventType,
              @msgBody.value('(/EVENT_INSTANCE/DatabaseName)[1]', 'varchar(128)'),				 
              @msgBody
            )
       end
    END;
    COMMIT TRANSACTION;

    -- svaki stoti upis, inicira brisanje starih zapisa
    -- predvidjeno je cuvanje 30,000 zapisa.
    set @lastId= scope_identity()
    if @lastId%100=0 
      delete aud.audit_table
        where [seqId]<@lastId-10000

END ;
GO

ALTER AUTHORIZATION ON [AUD].[AUDIT_SERVER_QUEUE_PROC] TO  SCHEMA OWNER 
GO



go

--	3. QUEUE aud.[AUDIT_SERVER_QUEUE]

-- CREIRANJE QUEUE ZA PRIHVAT PORUKA -------------------------------------------
create QUEUE aud.[AUDIT_SERVER_QUEUE] 
WITH STATUS = ON 
   , RETENTION = OFF 
   , ACTIVATION (  
       STATUS = ON , 
       PROCEDURE_NAME = aud.[AUDIT_SERVER_QUEUE_PROC] ,
       MAX_QUEUE_READERS = 1 ,
       EXECUTE AS N'dbo'  
   )  

go

-- paljenje queue po potrebi .
alter QUEUE aud.[AUDIT_SERVER_QUEUE] 
with status=ON

--	4. Servis AUDIT_SERVER_SERVICE i sta sve prati

-- CREIRANJE SERVISA (VIRTUALNI SERVIS BROKER GA NOSI, vise je deklaracija) -----
CREATE SERVICE [AUDIT_SERVER_SERVICE]  
AUTHORIZATION [dbo]  
ON QUEUE aud.[AUDIT_SERVER_QUEUE] (
  [http://schemas.microsoft.com/SQL/Notifications/PostEventNotification]
)
go

-- PRETPLACIVANJE NA DOGADJAJ  audit_table --------------------------------------
--




WITH DirectReports(name, parent_type, type, level, sort) AS   
(  
    SELECT CONVERT(varchar(255),type_name), parent_type, type, 1, CONVERT(varchar(255),type_name)  
    FROM sys.trigger_event_types   
    WHERE parent_type IS NULL  
    UNION ALL  
    SELECT  CONVERT(varchar(255), REPLICATE ('|   ' , level) + e.type_name),  
        e.parent_type, e.type, level + 1,  
    CONVERT (varchar(255), RTRIM(sort) + '|   ' + e.type_name)  
    FROM sys.trigger_event_types AS e  
        INNER JOIN DirectReports AS d  
        ON e.parent_type = d.type   
)  
SELECT parent_type, type, name  
FROM DirectReports  
ORDER BY sort;  




use MSDB
create event notification AUDIT_SERVER_EVENTS
  on server
  for 
 ALTER_SERVER_CONFIGURATION
,DDL_EVENTS
  to service 'AUDIT_SERVER_SERVICE', 'current database'  
go
-------------------------------------------------



-- sta od dogadjaja imamo!
select * 
  from sys.event_notification_event_types
  where type_name like '%database%'

--ako se zeli izmena, dodavanje eventa tad:
--drop event notification AUDIT_SERVER_EVENTS on server
-- pa recreate, potencijalno enable queue!



-- Sve je kreirano i radi...
--------------------------------------------------------------------------------
-- 5. TEST  -- nije neophodno 
--------------------------------------------------------------------------------


use Adm
use tempdb
create table ttt (rb int)
drop table ttt


--create database db2
--delete msdb.aud.[audit_table]
select * from msdb.aud.[audit_table]

create database xdb
drop database xdb
-- create table #t(rb int)

create login xlogin with password='12b1k34jbtk23t2#"'
drop login xlogin

sp_configure 'xp_cmdshell', 0; reconfigure

----create database db2
--drop database db2

--use db2
--use master
--drop database db1

--create database db1

-- kreiranje tabele
--select a=1 into tt1

-- login failure
--!!sqlcmd -Svsrv5 -Udjura1 -Psa12345. -Q"select @@servername"


go



-- 6. Pregled -- 
------------------------------------
-- PRATI SVE STO PRATI i PROFILER --
------------------------------------

--------------------------------------------------------------------------
-- OBAVEZAN UNINSTAL JER QUEUE NA SERVERU RADI I KAD DROPNEMO BAZU DB1 --
--------------------------------------------------------------------------

-------< pregled sta se radi / monitorise >----------------

-- sta se monitorise
select * from sys.server_event_notifications

-- servis je u bazi!
use MSDB
select * from sys.services

-- queue je u bazi
select * from sys.service_queues
go
---------------------------------------------------------------



---------------------------------------------------------------
-- 9. < ciscenje naseg sistema > odblokirati po potrebi
/*
use msdb
go
if exists(select * from sys.services where [name]='AUDIT_SERVER_SERVICE')
  drop service [AUDIT_SERVER_SERVICE]

if exists(select * from sys.service_queues where [name]='AUDIT_SERVER_QUEUE')
  drop queue aud.[AUDIT_SERVER_QUEUE] 

if object_id('aud.[AUDIT_SERVER_QUEUE_PROC]') is not null 
  drop procedure aud.[AUDIT_SERVER_QUEUE_PROC]

if object_id('aud.[audit_table]') is not null 
  drop TABLE aud.[audit_table]


  drop schema aud

go

*/