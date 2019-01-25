--	1. Schema AUD vec postoji
-- tabela AUD.audit_login_failed po uzoru na AUD.audit_table

use MSDB
go

SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
-- TABELA ZA LOGOVANJE ------------------------------
-- drop  TABLE aud.[audit_login_failed]
CREATE TABLE aud.[audit_login_failed](
  [seqId] [bigint] IDENTITY(1,1) NOT NULL ,
  EventType varchar(128) not null,
  PostTime datetime not null, 
  Slanje smallint not null default 0,
  HostName varchar(128) not null,
  LoginName varchar(128) not null,
  --[State] smallint not null,
  TextData varchar(256) not null,
  SrvEvent xml not null,
  constraint pk_audit_login
     primary key clustered(seqId desc) 
)
go

--	2. PROCEDURA AUD.AUDIT_LOGIN_QUEUE_PROC

-- PROCEDURA ZA PRIHVAT PORUKA IZ QUEUE. ------------
create procedure aud.[AUDIT_LOGIN_QUEUE_PROC]
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
      from aud.AUDIT_LOGIN_QUEUE
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
      insert into aud.audit_login_failed( PostTime, EventType, HostName, LoginName, --[State], 
      TextData, SrvEvent) 
      values (
         @msgBody.value('(/EVENT_INSTANCE/PostTime)[1]', 'datetime'),
         @msgBody.value('(/EVENT_INSTANCE/EventType)[1]', 'varchar(128)'),
         @msgBody.value('(/EVENT_INSTANCE/HostName)[1]', 'varchar(128)'),
         @msgBody.value('(/EVENT_INSTANCE/LoginName)[1]', 'varchar(128)'),
         --@msgBody.value('(/EVENT_INSTANCE/State)[1]', 'smallint'),
         @msgBody.value('(/EVENT_INSTANCE/TextData)[1]', 'varchar(256)'),
         @msgBody
      )
    END;
    COMMIT TRANSACTION;

    -- svaki hiljaditi upis, inicira brisanje starih zapisa
    -- predvidjeno je cuvanje 100,000 zapisa.
    set @lastId= scope_identity()
    if @lastId%1000=0 
      delete aud.audit_login_failed
        where [seqId]<@lastId-99000

END ;
go

--	3. QUEUE aud.[AUDIT_LOGIN_QUEUE]

-- CREIRANJE QUEUE ZA PRIHVAT PORUKA -------------------------------------------
create QUEUE aud.[AUDIT_LOGIN_QUEUE] 
WITH STATUS = ON 
   , RETENTION = OFF 
   , ACTIVATION (  
       STATUS = ON , 
       PROCEDURE_NAME = aud.[AUDIT_LOGIN_QUEUE_PROC] ,
       MAX_QUEUE_READERS = 1 ,
       EXECUTE AS N'dbo'  
   )  

go

-- paljenje queue po potrebi .
alter QUEUE aud.[AUDIT_LOGIN_QUEUE] 
with status=ON

--	4. Servis AUDIT_LOGIN_SERVICE i sta sve prati

-- CREIRANJE SERVISA (VIRTUALNI SERVIS BROKER GA NOSI, vise je deklaracija) -----
CREATE SERVICE [AUDIT_LOGIN_SERVICE]  
AUTHORIZATION [dbo]  
ON QUEUE aud.[AUDIT_LOGIN_QUEUE] (
  [http://schemas.microsoft.com/SQL/Notifications/PostEventNotification]
)
go

-- PRETPLACIVANJE NA DOGADJAJ  audit_login_failed --------------------------------------
--
use MSDB
create event notification AUDIT_LOGIN_EVENTS
  on server
  for 
--  10.10.2013
AUDIT_LOGIN_FAILED
  to service 'AUDIT_LOGIN_SERVICE', 'current database'  

go



-- sta od dogadjaja imamo!
select * 
  from sys.event_notification_event_types
  where type_name like '%AUDIT_LOGIN%'

--ako se zeli izmena, dodavanje eventa tad:
--drop event notification AUDIT_LOGIN_EVENTS on server
-- pa recreate, potencijalno enable queue!



-- Sve je kreirano i radi...



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
if exists(select * from sys.services where [name]='AUDIT_LOGIN_SERVICE')
  drop service [AUDIT_LOGIN_SERVICE]

if exists(select * from sys.service_queues where [name]='AUDIT_LOGIN_QUEUE')
  drop queue aud.[AUDIT_LOGIN_QUEUE] 

if object_id('aud.[AUDIT_LOGIN_QUEUE_PROC]') is not null 
  drop procedure aud.[AUDIT_LOGIN_QUEUE_PROC]

if object_id('aud.[audit_login_failed]') is not null 
  drop TABLE aud.[audit_login_failed]

if exists(select * from sys.server_event_notifications where [name]='AUDIT_LOGIN_EVENTS')
 drop event notification AUDIT_LOGIN_EVENTS
 on server

  --drop schema aud

go

*/