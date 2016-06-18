/*This script is used to convert the action_ids to a readable format to be used in audit filtering.
Please change the values in line 38, 43 and 48 if the name of the audit should be any other than S056_Config_Audit*/

USE [master]
GO

IF OBJECT_ID('dbo.GetInt_action_id') IS NOT NULL
DROP FUNCTION dbo.GetInt_action_id
GO

CREATE FUNCTION dbo.GetInt_action_id (@action_id varchar(4)) returns int
BEGIN
DECLARE @x int
SET @x = convert(int, convert(varbinary(1), upper(substring(@action_id, 1, 1))))

if LEN(@action_id)>=2
SET @x = convert(int, convert(varbinary(1), upper(substring(@action_id, 2, 1)))) * power(2,8) + @x
else
SET @x = convert(int, convert(varbinary(1), ' ')) * power(2,8) + @x

if LEN(@action_id)>=3
SET @x = convert(int, convert(varbinary(1), upper(substring(@action_id, 3, 1)))) * power(2,16) + @x
else
SET @x = convert(int, convert(varbinary(1), ' ')) * power(2,16) + @x

if LEN(@action_id)>=4
SET @x = convert(int, convert(varbinary(1), upper(substring(@action_id, 4, 1)))) * power(2,24) + @x
else
SET @x = convert(int, convert(varbinary(1), ' ')) * power(2,24) + @x

return @x

end

GO

--disable audit in order to set the filter
ALTER SERVER AUDIT Config_Audit --change to correct name
WITH (STATE = OFF);
GO

--set the filter
ALTER SERVER AUDIT Config_Audit --change to correct name
WHERE ACTION_ID<>1464158550
GO

--enable the audit
ALTER SERVER AUDIT Config_Audit --change to correct name
WITH (STATE = ON);
GO





