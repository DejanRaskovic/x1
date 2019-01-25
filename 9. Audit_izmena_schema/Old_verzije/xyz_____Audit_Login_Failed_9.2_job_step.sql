-----------------------------
-- proba : mail u XML formatu
-----------------------------
DECLARE @tableHTML  NVARCHAR(MAX) ;
DECLARE @maxID int
SELECT @maxID = max(seqID) from msdb.aud.[audit_login_failed]

SET @tableHTML =
'<H1>Login failed ['+@@servername +'] Report</H1>
<table border="1">
<tr>
  <th>PostTime</th>
  <th>HostName</th>
  <th>LoginName</th>
  <th>TextData</th>
</tr>' +
cast((
select top 100
       td=PostTime,'',
       td=HostName, '',
       td=LoginName, '',
       td=TextData
from msdb.aud.[audit_login_failed]
--where PostTime > DATEADD(hh,-1,getdate())
where slanje = 0
order by PostTime desc
for xml path('tr'), type
) as nvarchar(max))
+ N'</table>' ;
--       
update msdb.aud.[audit_login_failed]
set slanje = 1
where slanje = 0 and seqID <= @maxID;

if @@rowcount > 0   
EXEC msdb.dbo.sp_send_dbmail @recipients='SQLAdmin@bancaintesa.rs',
    @subject = 'Login failed',
    @body = @tableHTML,
    @body_format = 'HTML',
    @profile_name='default' ;



