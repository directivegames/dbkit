
EXEC zsystem.Versions_Start 'CORE', 0003, 'jorundur'
GO



---------------------------------------------------------------------------------------------------------------------------------


GRANT SELECT ON zsystem.settings TO zzp_server
GRANT SELECT ON zsystem.versions TO zzp_server
GRANT EXEC ON zsystem.Versions_Check TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


--IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'zzp_service')
--BEGIN
--  REVOKE SELECT ON zsystem.settings FROM zzp_service
--  REVOKE SELECT ON zsystem.versions FROM zzp_service
--  REVOKE EXEC ON zsystem.Versions_Check FROM zzp_service
--END
--GO


---------------------------------------------------------------------------------------------------------------------------------


--IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'zzp_service') AND NOT EXISTS(SELECT * FROM zsystem.versions WHERE developer = 'CORE' AND [version] = 4)
--BEGIN
--  DECLARE @RoleMemberName sysname, @SQL NVARCHAR(4000)
--  DECLARE Member_Cursor CURSOR FOR
--    select [name]
--      from sys.database_principals
--     where principal_id in (select member_principal_id
--                              from sys.database_role_members
--                             where role_principal_id in (select principal_id FROM sys.database_principals where [name] = 'zzp_service' AND [type] = 'R'))
--  OPEN Member_Cursor;
--  FETCH NEXT FROM Member_Cursor into @RoleMemberName
--  WHILE @@FETCH_STATUS = 0
--  BEGIN
--    SET @SQL = 'ALTER ROLE '+ QUOTENAME('zzp_service', '[') +' DROP MEMBER '+ QUOTENAME(@RoleMemberName, '[')
--    EXEC(@SQL)
--
--    FETCH NEXT FROM Member_Cursor into @RoleMemberName
--  END;
--
--  CLOSE Member_Cursor;
--  DEALLOCATE Member_Cursor;
--
--  DROP ROLE zzp_service
--END
--GO


---------------------------------------------------------------------------------------------------------------------------------



GO
EXEC zsystem.Versions_Finish 'CORE', 0003, 'jorundur'
GO
