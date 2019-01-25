USE [msdb]
GO

/****** Object:  Job [_Login_failed_report]    Script Date: 10/11/2013 10:05:58 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 10/11/2013 10:05:58 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'DBA'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'_Login_failed_report', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Djole, Maki

Na svim serverima baza podataka (oarcle+sql) potrebno je konfigurisati javljanje ukoliko se pojavi neuspešno logovanje na server (nalog disabled, nema usera, loš password, deny logon, …)

Kontrolu implementirati kroz job koji radi na 1h. (Maximalno 1 mail na sat po serveru)
Mail slati na sql.admin grupu.
Ako nije bilo neuspešnih logovanja, ne slati nikakav mail.

Ovo bi trebalo da bude završeno do petka 11.10.2013.

Dejan Raskovic', 
		@category_name=N'DBA', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Poslednjih 100]    Script Date: 10/11/2013 10:05:59 ******/
declare @driveLetter nChar(1), @outPath nvarchar(1000)
select @outPath=left(filename,1) +':\SqlPlus\Logs\_LoginFailedReport.txt'
from master..sysaltfiles where db_name(dbid) = 'master' and filename like '%master.mdf'
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Poslednjih 100', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'----------------------------------
--  mail u XML formatu
----------------------------------
DECLARE @tableHTML  NVARCHAR(MAX) ;
DECLARE @maxID int
SELECT @maxID = max(seqID) from msdb.aud.[audit_login_failed]

SET @tableHTML =
''<H1>Login failed [''+@@servername +''] Report</H1>
<table border="1">
<tr>
  <th>PostTime</th>
  <th>HostName</th>
  <th>LoginName</th>
  <th>TextData</th>
</tr>'' +
cast((
select top 100
       td=PostTime,'''',
       td=HostName, '''',
       td=LoginName, '''',
       td=TextData
from msdb.aud.[audit_login_failed]
--where PostTime > DATEADD(hh,-1,getdate())
where slanje = 0 and LoginName not in (''alfa155'',''delta'',''DELTABANK\quser'')
--where slanje = 0
order by PostTime desc
for xml path(''tr''), type
) as nvarchar(max))
+ N''</table>'' ;
--       
update msdb.aud.[audit_login_failed]
set slanje = 1
where slanje = 0 and seqID <= @maxID and LoginName not in (''alfa155'',''delta'',''DELTABANK\quser'');

if @@rowcount > 0   
EXEC msdb.dbo.sp_send_dbmail @recipients=''SQLAdmin@bancaintesa.rs'',
    @subject = ''Login failed'',
    @body = @tableHTML,
    @body_format = ''HTML'',
    @profile_name=''default'' ;



', 
		@database_name=N'master', 
		@output_file_name=@outPath, 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Na sat tokom dana', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=126, 
		@freq_subday_type=8, 
		@freq_subday_interval=1, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20131011, 
		@active_end_date=99991231, 
		@active_start_time=75500, 
		@active_end_time=195900
		
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


