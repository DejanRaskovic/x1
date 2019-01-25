use msdb
go

select * from sysmail_account
go

EXECUTE msdb.dbo.sysmail_update_account_sp
    @account_id = 1
    --,@email_address= replace(@@servername,'\','_')+'@deltabank.co.yu'
	,@email_address = 'ARHPP@deltabank.co.yu'
	
select * from sysmail_account
go
