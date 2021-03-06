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
	[seqId] [bigint] IDENTITY(1,1) NOT NULL ,
  PostTime datetime not null, 
  EventType varchar(128) not null,
  DatabaseName varchar(128) not null,			-- MV 28.5.2010 -- v 3
  SrvEvent xml not null,
  constraint pk_audit_table
     primary key clustered(seqId desc) 
)
go

--	2. PROCEDURA AUD.AUDIT_SERVER_QUEUE_PROC

-- PROCEDURA ZA PRIHVAT PORUKA IZ QUEUE. ------------
create procedure aud.[AUDIT_SERVER_QUEUE_PROC]
as
set nocount on;
declare @msgBody XML, @message_type_name NVARCHAR(256), @dialog UNIQUEIDENTIFIER ;
declare @lastId int
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
      insert into aud.audit_table( PostTime, EventType, DatabaseName, SrvEvent) 
      values (
         @msgBody.value('(/EVENT_INSTANCE/PostTime)[1]', 'datetime'),
         @msgBody.value('(/EVENT_INSTANCE/EventType)[1]', 'varchar(128)'),
         @msgBody.value('(/EVENT_INSTANCE/DatabaseName)[1]', 'varchar(128)'),				-- MV 28.5.2010 -- v 3
         @msgBody
      )
    END;
    COMMIT TRANSACTION;

    -- svaki stoti upis, inicira brisanje starih zapisa
    -- predvidjeno je cuvanje 30,000 zapisa.
    set @lastId= scope_identity()
    if @lastId%100=0 
      delete aud.audit_table
        where [seqId]<@lastId-99000

END ;
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
use MSDB
create event notification AUDIT_SERVER_EVENTS
  on server
  for 
 CREATE_TABLE
,ALTER_TABLE
,DROP_TABLE
,CREATE_INDEX
-- ,ALTER_INDEX		-	ne pratimo zbog ALTER INDEX blabla ON tblbla REBUILD WITH (FILLFACTOR = 80, ONLINE = ON)
,DROP_INDEX
,CREATE_SYNONYM
,DROP_SYNONYM
,CREATE_VIEW
,ALTER_VIEW
,DROP_VIEW
,CREATE_PROCEDURE
,ALTER_PROCEDURE
,DROP_PROCEDURE
,CREATE_FUNCTION
,ALTER_FUNCTION
,DROP_FUNCTION
,CREATE_TRIGGER
,ALTER_TRIGGER
,DROP_TRIGGER
,CREATE_USER
,ALTER_USER
,DROP_USER
,CREATE_ROLE
,ALTER_ROLE
,DROP_ROLE
,CREATE_APPLICATION_ROLE
,ALTER_APPLICATION_ROLE
,DROP_APPLICATION_ROLE
,GRANT_SERVER
,DENY_SERVER
,GRANT_DATABASE
,DENY_DATABASE
,CREATE_PARTITION_FUNCTION
,ALTER_PARTITION_FUNCTION
,DROP_PARTITION_FUNCTION
,CREATE_XML_INDEX
,ADD_ROLE_MEMBER
,DROP_ROLE_MEMBER
,ADD_SERVER_ROLE_MEMBER
,DROP_SERVER_ROLE_MEMBER
,CREATE_DATABASE
,ALTER_DATABASE
,DROP_DATABASE
-- dodato 22.11.2011
,CREATE_LOGIN
,ALTER_LOGIN
,DROP_LOGIN
  to service 'AUDIT_SERVER_SERVICE', 'current database'  

go



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

-- create table #t(rb int)

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