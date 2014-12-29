
---------------------------------------------------------------------------------------------------------------------------------


--IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'zzp_service')
--  CREATE ROLE zzp_service
--GO


---------------------------------------------------------------------------------------------------------------------------------


IF SCHEMA_ID('zsystem') IS NULL
  EXEC sp_executesql N'CREATE SCHEMA zsystem'
GO



---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.settings') IS NULL
BEGIN
  CREATE TABLE zsystem.settings
  (
    [group]        varchar(200)   NOT NULL,
    [key]          varchar(200)   NOT NULL,
    [value]        nvarchar(max)  NOT NULL,
    [description]  nvarchar(max)  NOT NULL,
    defaultValue   nvarchar(max)  NULL,
    critical       bit            NOT NULL  DEFAULT 0,
    allowUpdate    bit            NOT NULL  DEFAULT 0,
    orderID        int            NOT NULL  DEFAULT 0,
    --
    CONSTRAINT settings_PK PRIMARY KEY CLUSTERED ([group], [key])
  )
END
--GRANT SELECT ON zsystem.settings TO zzp_service
GO


IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zsystem' AND [key] = 'Product')
  INSERT INTO zsystem.settings ([group], [key], [value], [description], defaultValue, critical)
       VALUES ('zsystem', 'Product', 'CORE', 'The product being developed (CORE, EVE, WOD, ...)', 'CORE', 1)
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zsystem' AND [key] = 'Recipients-Updates')
  INSERT INTO zsystem.settings ([group], [key], [value], [description])
       VALUES ('zsystem', 'Recipients-Updates', '', 'Mail recipients for DB update notifications')
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zsystem' AND [key] = 'Database')
  INSERT INTO zsystem.settings ([group], [key], [value], [description])
       VALUES ('zsystem', 'Database', '', 'The database being used.  Often useful to know when working on a restored database with a different name.)')
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Settings_Value') IS NOT NULL
  DROP FUNCTION zsystem.Settings_Value
GO
CREATE FUNCTION zsystem.Settings_Value(@group varchar(200), @key varchar(200))
RETURNS nvarchar(max)
BEGIN
  DECLARE @value nvarchar(max)
  SELECT @value = LTRIM(RTRIM([value])) FROM zsystem.settings WHERE [group] = @group AND [key] = @key
  RETURN ISNULL(@value, '')
END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.versions') IS NULL
BEGIN
  CREATE TABLE zsystem.versions
  (
    developer       varchar(20)    NOT NULL,
    [version]       int            NOT NULL,
    versionDate     datetime2(2)   NOT NULL,
    userName        nvarchar(100)  NOT NULL,
    loginName       nvarchar(256)  NOT NULL,
    executionCount  int            NOT NULL,
    lastDate        datetime2(2)   NULL,
    lastLoginName   nvarchar(256)  NULL,
    coreVersion     int            NULL,
    firstDuration   int            NULL,
    lastDuration    int            NULL,
    executingSPID   int            NULL
    --
    CONSTRAINT versions_PK PRIMARY KEY CLUSTERED (developer, [version])
  )
END
--GRANT SELECT ON zsystem.versions TO zzp_service
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Versions_Start') IS NOT NULL
  DROP PROCEDURE zsystem.Versions_Start
GO
CREATE PROCEDURE zsystem.Versions_Start
  @developer  nvarchar(20),
  @version    int,
  @userName   nvarchar(100)
AS
  SET NOCOUNT ON

  DECLARE @currentVersion int
  SELECT @currentVersion = MAX([version]) FROM zsystem.versions WHERE developer = @developer
  IF @currentVersion != @version - 1
  BEGIN
    PRINT '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
    PRINT '!!! DATABASE NOT OF CORRECT VERSION !!!'
    PRINT '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
  END

  IF NOT EXISTS(SELECT * FROM zsystem.versions WHERE developer = @developer AND [version] = @version)
  BEGIN
    INSERT INTO zsystem.versions (developer, [version], versionDate, userName, loginName, executionCount, executingSPID)
         VALUES (@developer, @version, GETUTCDATE(), @userName, SUSER_SNAME(), 0, @@SPID)
  END
  ELSE
  BEGIN
    UPDATE zsystem.versions
       SET lastDate = GETUTCDATE(), executingSPID = @@SPID
     WHERE developer = @developer AND [version] = @version
  END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.SendMail') IS NOT NULL
  DROP PROCEDURE zsystem.SendMail
GO
CREATE PROCEDURE zsystem.SendMail
  @recipients   varchar(max),
  @subject      nvarchar(255),
  @body         nvarchar(max),
  @body_format  varchar(20) = NULL
AS
  SET NOCOUNT ON

  -- Azure does not support msdb.dbo.sp_send_dbmail
  IF CONVERT(varchar(max), SERVERPROPERTY('edition')) NOT LIKE '%Azure%'
  BEGIN
    EXEC sp_executesql N'EXEC msdb.dbo.sp_send_dbmail NULL, @p_recipients, NULL, NULL, @p_subject, @p_body, @p_body_format',
                       N'@p_recipients varchar(max), @p_subject nvarchar(255), @p_body nvarchar(max), @p_body_format  varchar(20)',
                       @p_recipients = @recipients, @p_subject = @subject, @p_body = @body, @p_body_format = @body_format
  END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Versions_Finish') IS NOT NULL
  DROP PROCEDURE zsystem.Versions_Finish
GO
CREATE PROCEDURE zsystem.Versions_Finish
  @developer  varchar(20),
  @version    int,
  @userName   nvarchar(100)
AS
  SET NOCOUNT ON

  IF EXISTS(SELECT *
              FROM zsystem.versions
             WHERE developer = @developer AND [version] = @version AND userName = @userName AND firstDuration IS NOT NULL)
  BEGIN
    PRINT ''
    PRINT '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
    PRINT '!!! DATABASE UPDATE HAS BEEN EXECUTED BEFORE !!!'
    PRINT '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
    UPDATE zsystem.versions
       SET executionCount = executionCount + 1, lastDate = GETUTCDATE(),
           lastLoginName = SUSER_SNAME(), lastDuration = DATEDIFF(second, lastDate, GETUTCDATE()), executingSPID = NULL
     WHERE developer = @developer AND [version] = @version
  END
  ELSE
  BEGIN
    DECLARE @coreVersion int
    IF @developer != 'CORE'
      SELECT @coreVersion = MAX([version]) FROM zsystem.versions WHERE developer = 'CORE'

    UPDATE zsystem.versions
       SET executionCount = executionCount + 1, coreVersion = @coreVersion,
           firstDuration = DATEDIFF(second, versionDate, GETUTCDATE()), executingSPID = NULL
     WHERE developer = @developer AND [version] = @version
  END

  PRINT ''
  PRINT '[EXEC zsystem.Versions_Finish ''' + @developer + ''', ' + CONVERT(varchar, @version) + ', ''' + @userName + '''] has completed'
  PRINT ''

  DECLARE @recipients varchar(max)
  SET @recipients = zsystem.Settings_Value('zsystem', 'Recipients-Updates')
  IF @recipients != '' AND zsystem.Settings_Value('zsystem', 'Database') = DB_NAME()
  BEGIN
    DECLARE @subject nvarchar(255), @body nvarchar(max)
    SET @subject = 'Database update ' + @developer + '-' + CONVERT(varchar, @version) + ' applied on ' + DB_NAME()
    SET @body = NCHAR(13) + @subject + NCHAR(13)
                + NCHAR(13) + '  Developer: ' + @developer
                + NCHAR(13) + '    Version: ' + CONVERT(varchar, @version)
                + NCHAR(13) + '       User: ' + @userName
                + NCHAR(13) + NCHAR(13)
                + NCHAR(13) + '   Database: ' + DB_NAME()
                + NCHAR(13) + '       Host: ' + HOST_NAME()
                + NCHAR(13) + '      Login: ' + SUSER_SNAME()
                + NCHAR(13) + 'Application: ' + APP_NAME()
    EXEC zsystem.SendMail @recipients, @subject, @body
  END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Versions_Check') IS NOT NULL
  DROP PROCEDURE zsystem.Versions_Check
GO
CREATE PROCEDURE zsystem.Versions_Check
  @developer  varchar(20) = NULL
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @developers TABLE (developer varchar(20))

  IF @developer IS NULL
  BEGIN
    INSERT INTO @developers (developer)
         SELECT DISTINCT developer FROM zsystem.versions
  END
  ELSE
    INSERT INTO @developers (developer) VALUES (@developer)

  DECLARE @version int, @firstVersion int

  DECLARE @cursor CURSOR
  SET @cursor = CURSOR LOCAL FAST_FORWARD
    FOR SELECT developer FROM @developers ORDER BY developer
  OPEN @cursor
  FETCH NEXT FROM @cursor INTO @developer
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SELECT @firstVersion = MIN([version]) - 1 FROM zsystem.versions WHERE developer = @developer;

    WITH CTE (rowID, versionID, [version]) AS
    (
      SELECT ROW_NUMBER() OVER(ORDER BY [version]),
             [version] - @firstVersion, [version]
        FROM zsystem.versions
        WHERE developer = @developer
    )
    SELECT @version = MAX([version]) FROM CTE WHERE rowID = versionID

    SELECT developer,
           info = CASE WHEN [version] = @version THEN 'LAST CONTINUOUS VERSION' ELSE 'MISSING PRIOR VERSIONS' END,
           [version], versionDate, userName, executionCount, lastDate, coreVersion,
--           firstDuration = zutil.TimeString(firstDuration), lastDuration = zutil.TimeString(lastDuration)
           firstDuration, lastDuration
      FROM zsystem.versions
     WHERE developer = @developer AND [version] >= @version


    FETCH NEXT FROM @cursor INTO @developer
  END
  CLOSE @cursor
  DEALLOCATE @cursor
GO
--GRANT EXEC ON zsystem.Versions_Check TO zzp_service
--GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.CatchError') IS NOT NULL
  DROP PROCEDURE zsystem.CatchError
GO
CREATE PROCEDURE zsystem.CatchError
  @objectName  nvarchar(256) = NULL,
  @rollback    bit = 1
AS
  SET NOCOUNT ON

  DECLARE @message nvarchar(4000), @number int, @severity int, @state int, @line int, @procedure nvarchar(200)
  SELECT @number = ERROR_NUMBER(), @severity = ERROR_SEVERITY(), @state = ERROR_STATE(),
         @line = ERROR_LINE(), @procedure = ISNULL(ERROR_PROCEDURE(), '?'), @message = ISNULL(ERROR_MESSAGE(), '?')

  IF @rollback = 1
  BEGIN
    IF @@TRANCOUNT > 0
      ROLLBACK TRANSACTION
  END

  IF @procedure = 'CatchError'
    SET @message = ISNULL(@objectName, '?') + ' >> ' + @message
  ELSE
  BEGIN
    IF @number = 50000
      SET @message = ISNULL(@objectName, @procedure) + ' (line ' + ISNULL(CONVERT(nvarchar, @line), '?') + ') >> ' + @message
    ELSE
    BEGIN
      SET @message = ISNULL(@objectName, @procedure) + ' (line ' + ISNULL(CONVERT(nvarchar, @line), '?')
                   + ', error ' + ISNULL(CONVERT(nvarchar, @number), '?') + ') >> ' + @message
    END
  END

  RAISERROR (@message, @severity, @state)
GO


---------------------------------------------------------------------------------------------------------------------------------


EXEC zsystem.Versions_Start 'CORE', 0001, 'jorundur'
GO


---------------------------------------------------------------------------------------------------------------------------------



GO
EXEC zsystem.Versions_Finish 'CORE', 0001, 'jorundur'
GO
