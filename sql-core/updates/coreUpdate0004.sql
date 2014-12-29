
EXEC zsystem.Versions_Start 'CORE', 0004, 'jorundur'
GO



---------------------------------------------------------------------------------------------------------------------------------


REVOKE EXEC ON zutil.DateDay FROM public
REVOKE EXEC ON zutil.DateWeek FROM public
REVOKE EXEC ON zutil.DateMonth FROM public
REVOKE EXEC ON zutil.DateYear FROM public
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.TimeString') IS NOT NULL
  DROP FUNCTION zutil.TimeString
GO
CREATE FUNCTION zutil.TimeString(@seconds int)
RETURNS varchar(20)
BEGIN
  DECLARE @s varchar(20)

  DECLARE @x int

  -- Seconds
  SET @x = @seconds % 60
  SET @s = RIGHT('00' + CONVERT(varchar, @x), 2)
  SET @seconds = @seconds - @x

  -- Minutes
  SET @x = (@seconds % (60 * 60)) / 60
  SET @s = RIGHT('00' + CONVERT(varchar, @x), 2) + ':' + @s
  SET @seconds = @seconds - (@x * 60)

  -- Hours
  SET @x = @seconds / (60 * 60)
  SET @s = CONVERT(varchar, @x) + ':' + @s
  IF LEN(@s) < 8 SET @s = '0' + @s

  RETURN @s
END
GO
GRANT EXEC ON zutil.TimeString TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Code from Itzik Ben-Gan, a very fast inline table function that will return a table of numbers

IF OBJECT_ID('zutil.Numbers') IS NOT NULL
  DROP FUNCTION zutil.Numbers
GO
CREATE FUNCTION zutil.Numbers(@n int)
  RETURNS TABLE
  RETURN WITH L0   AS(SELECT 1 AS c UNION ALL SELECT 1),
              L1   AS(SELECT 1 AS c FROM L0 AS A, L0 AS B),
              L2   AS(SELECT 1 AS c FROM L1 AS A, L1 AS B),
              L3   AS(SELECT 1 AS c FROM L2 AS A, L2 AS B),
              L4   AS(SELECT 1 AS c FROM L3 AS A, L3 AS B),
              L5   AS(SELECT 1 AS c FROM L4 AS A, L4 AS B),
              Nums AS(SELECT ROW_NUMBER() OVER(ORDER BY c) AS n FROM L5)
         SELECT n FROM Nums WHERE n <= @n;
GO
GRANT SELECT ON zutil.Numbers TO zzp_server
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
           firstDuration = zutil.TimeString(firstDuration), lastDuration = zutil.TimeString(lastDuration)
      FROM zsystem.versions
     WHERE developer = @developer AND [version] >= @version


    FETCH NEXT FROM @cursor INTO @developer
  END
  CLOSE @cursor
  DEALLOCATE @cursor
GO
GRANT EXEC ON zsystem.Versions_Check TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Versions_FirstExecution') IS NOT NULL
  DROP FUNCTION zsystem.Versions_FirstExecution
GO
CREATE FUNCTION zsystem.Versions_FirstExecution()
RETURNS bit
BEGIN
  IF EXISTS(SELECT * FROM zsystem.versions WHERE executingSPID = @@SPID AND firstDuration IS NULL)
    RETURN 1
  RETURN 0
END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.PrintNow') IS NOT NULL
  DROP PROCEDURE zsystem.PrintNow
GO
CREATE PROCEDURE zsystem.PrintNow
  @str        nvarchar(4000),
  @printTime  bit = 0
AS
  SET NOCOUNT ON

  IF @printTime = 1
    SET @str = CONVERT(nvarchar, GETUTCDATE(), 120) + ' : ' + @str

  RAISERROR (@str, 0, 1) WITH NOWAIT;
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.PrintFlush') IS NOT NULL
  DROP PROCEDURE zsystem.PrintFlush
GO
CREATE PROCEDURE zsystem.PrintFlush
AS
  SET NOCOUNT ON

  BEGIN TRY
    RAISERROR ('', 11, 1) WITH NOWAIT;
  END TRY
  BEGIN CATCH
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Ben Dill

IF OBJECT_ID('zsystem.PrintMax') IS NOT NULL
  DROP PROCEDURE zsystem.PrintMax
GO
CREATE PROCEDURE zsystem.PrintMax
  @str  nvarchar(max)
AS
  SET NOCOUNT ON

  IF @str IS NULL
    RETURN

  DECLARE @reversed nvarchar(max), @break int

  WHILE (LEN(@str) > 4000)
  BEGIN
    SET @reversed = REVERSE(LEFT(@str, 4000))

    SET @break = CHARINDEX(CHAR(10) + CHAR(13), @reversed)

    IF @break = 0
    BEGIN
      PRINT LEFT(@str, 4000)
      SET @str = RIGHT(@str, LEN(@str) - 4000)
    END
    ELSE
    BEGIN
      PRINT LEFT(@str, 4000 - @break + 1)
      SET @str = RIGHT(@str, LEN(@str) - 4000 + @break - 1)
    END
  END

  IF LEN(@str) > 0
    PRINT @str
GO


---------------------------------------------------------------------------------------------------------------------------------


IF SCHEMA_ID('zdm') IS NULL
  EXEC sp_executesql N'CREATE SCHEMA zdm'
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.describe') IS NOT NULL
  DROP PROCEDURE zdm.describe
GO
CREATE PROCEDURE zdm.describe
  @objectName  nvarchar(256)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @schemaID int, @schemaName nvarchar(128), @objectID int,
          @type char(2), @typeDesc nvarchar(60),
          @createDate datetime2(0), @modifyDate datetime2(0), @isMsShipped bit,
          @i int, @text nvarchar(max), @parentID int

  SET @i = CHARINDEX('.', @objectName)
  IF @i > 0
  BEGIN
    SET @schemaName = SUBSTRING(@objectName, 1, @i - 1)
    SET @objectName = SUBSTRING(@objectName, @i + 1, 256)
    IF CHARINDEX('.', @objectName) > 0
    BEGIN
      RAISERROR ('Object name invalid', 16, 1)
      RETURN -1
    END

    SELECT @schemaID = [schema_id] FROM sys.schemas WHERE LOWER(name) = LOWER(@schemaName)
    IF @schemaID IS NULL
    BEGIN
      RAISERROR ('Schema not found', 16, 1)
      RETURN -1
    END
  END

  IF @schemaID IS NULL
  BEGIN
    SELECT TOP 2 @objectID = [object_id], @type = [type], @typeDesc = type_desc,
                 @createDate = create_date, @modifyDate = modify_date, @isMsShipped = is_ms_shipped
      FROM sys.objects
     WHERE LOWER(name) = LOWER(@objectName)
  END
  ELSE
  BEGIN
    SELECT TOP 2 @objectID = [object_id], @type = [type], @typeDesc = type_desc,
                 @createDate = create_date, @modifyDate = modify_date, @isMsShipped = is_ms_shipped
      FROM sys.objects
     WHERE [schema_id] = @schemaID AND LOWER(name) = LOWER(@objectName)
  END
  IF @@ROWCOUNT = 1
  BEGIN
    IF @schemaID IS NULL
      SELECT @schemaID = [schema_id] FROM sys.objects WHERE [object_id] = @objectID
    IF @schemaName IS NULL
      SELECT @schemaName = name FROM sys.schemas WHERE [schema_id] = @schemaID

    IF @type IN ('V', 'P', 'FN', 'IF') -- View, Procedure, Scalar Function, Table Function
    BEGIN
      PRINT ''
      SET @text = OBJECT_DEFINITION(OBJECT_ID(@schemaName + '.' + @objectName))
      EXEC zsystem.PrintMax @text
    END
    ELSE IF @type = 'C' -- Check Constraint
    BEGIN
      PRINT ''
      SELECT @text = [definition], @parentID = parent_object_id
        FROM sys.check_constraints
       WHERE [object_id] = @objectID
      EXEC zsystem.PrintMax @text
    END
    ELSE IF @type = 'D' -- Default Constraint
    BEGIN
      PRINT ''
      SELECT @text = C.name + ' = ' + DC.[definition], @parentID = DC.parent_object_id
        FROM sys.default_constraints DC
          INNER JOIN sys.columns C ON C.[object_id] = DC.parent_object_id AND C.column_id = DC.parent_column_id
       WHERE DC.[object_id] = @objectID
      EXEC zsystem.PrintMax @text
    END
    ELSE IF @type IN ('U', 'IT', 'S', 'PK') -- User Table, Internal Table, System Table, Primary Key
    BEGIN
      DECLARE @tableID int, @rows bigint
      IF @type = 'PK' -- Primary Key
      BEGIN
        SELECT [object_id], [object_name] = @schemaName + '.' + @objectName, [type], type_desc, create_date, modify_date, is_ms_shipped, parent_object_id
          FROM sys.objects
         WHERE [object_id] = @objectID

        SELECT @parentID = parent_object_id FROM sys.objects  WHERE [object_id] = @objectID
        SET @tableID = @parentID
      END
      ELSE
        SET @tableID = @objectID

      SELECT @rows = SUM(P.row_count)
        FROM sys.indexes I
          INNER JOIN sys.dm_db_partition_stats P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
       WHERE I.[object_id] = @tableID AND I.index_id IN (0, 1)

      SELECT [object_id], [object_name] = @schemaName + '.' + @objectName, [type], type_desc, [rows] = @rows, create_date, modify_date, is_ms_shipped
        FROM sys.objects
       WHERE [object_id] = @tableID

      SELECT C.column_id, column_name = C.name, [type_name] = TYPE_NAME(C.system_type_id), C.max_length, C.[precision], C.scale,
             C.collation_name, C.is_nullable, C.is_identity, [default] = D.[definition]
        FROM sys.columns C
          LEFT JOIN sys.default_constraints D ON D.parent_object_id = C.[object_id] AND D.parent_column_id = C.column_id
       WHERE C.[object_id] = @tableID
       ORDER BY C.column_id

      SELECT index_id, index_name = name, [type], type_desc, is_unique, is_primary_key, is_unique_constraint, has_filter, fill_factor, has_filter, filter_definition
        FROM sys.indexes
       WHERE [object_id] = @tableID
       ORDER BY index_id

      SELECT index_name = I.name, IC.key_ordinal, column_name = C.name, IC.is_included_column
        FROM sys.indexes I
          INNER JOIN sys.index_columns IC ON IC.[object_id] = I.[object_id] AND IC.index_id = I.index_id
            INNER JOIN sys.columns C ON C.[object_id] = IC.[object_id] AND C.column_id = IC.column_id
       WHERE I.[object_id] = @tableID
       ORDER BY I.index_id, IC.key_ordinal
    END
    ELSE
    BEGIN
      PRINT ''
      PRINT 'EXTRA INFORMATION NOT AVAILABLE FOR THIS TYPE OF OBJECT!'
    END

    IF @type NOT IN ('U', 'IT', 'S', 'PK')
    BEGIN
      PRINT REPLICATE('_', 100)
      IF @isMsShipped = 1
        PRINT 'THIS IS A MICROSOFT OBJECT'

      IF @parentID IS NOT NULL
        PRINT '  PARENT: ' + OBJECT_SCHEMA_NAME(@parentID) + '.' + OBJECT_NAME(@parentID)

      PRINT '    Name: ' + @schemaName + '.' + @objectName
      PRINT '    Type: ' + @typeDesc
      PRINT ' Created: ' + CONVERT(varchar, @createDate, 120)
      PRINT 'Modified: ' + CONVERT(varchar, @modifyDate, 120)
    END
  END
  ELSE
  BEGIN
    IF @schemaID IS NULL
    BEGIN
      SELECT O.[object_id], [object_name] = S.name + '.' + O.name, O.[type], O.type_desc, O.parent_object_id,
             O.create_date, O.modify_date, O.is_ms_shipped
        FROM sys.objects O
          INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
       WHERE LOWER(O.name) LIKE '%' + LOWER(@objectName) + '%'
       ORDER BY CASE O.[type] WHEN 'U' THEN '_A' WHEN 'V' THEN '_B' WHEN 'P' THEN '_C' WHEN 'FN' THEN '_D' WHEN 'IF' THEN '_E' WHEN 'PK' THEN '_F' ELSE O.[type] END,
                LOWER(S.name), LOWER(O.name)
    END
    ELSE
    BEGIN
      SELECT [object_id], [object_name] = @schemaName + '.' + name, [type], type_desc, parent_object_id,
             create_date, modify_date, is_ms_shipped
        FROM sys.objects
       WHERE [schema_id] = @schemaID AND LOWER(name) LIKE '%' + LOWER(@objectName) + '%'
       ORDER BY CASE [type] WHEN 'U' THEN '_A' WHEN 'V' THEN '_B' WHEN 'P' THEN '_C' WHEN 'FN' THEN '_D' WHEN 'IF' THEN '_E' WHEN 'PK' THEN '_F' ELSE [type] END,
                LOWER(name)
    END
  END
GO


IF OBJECT_ID('zdm.d') IS NOT NULL
  DROP SYNONYM zdm.d
GO
CREATE SYNONYM zdm.d FOR zdm.describe
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.findusage') IS NOT NULL
  DROP PROCEDURE zdm.findusage
GO
CREATE PROCEDURE zdm.findusage
  @usageText  nvarchar(256),
  @describe   bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @objectID int, @objectName nvarchar(256), @text nvarchar(max), @somethingFound bit = 0

  DECLARE @cursor CURSOR
  SET @cursor = CURSOR LOCAL FAST_FORWARD
    FOR SELECT O.[object_id], S.name + '.' + O.name
          FROM sys.objects O
            INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
         WHERE O.is_ms_shipped = 0 AND O.type IN ('V', 'P', 'FN', 'IF') -- View, Procedure, Scalar Function, Table Function
         ORDER BY O.type_desc, S.name, O.name
  OPEN @cursor
  FETCH NEXT FROM @cursor INTO @objectID, @objectName
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SET @text = OBJECT_DEFINITION(@objectID)
    IF CHARINDEX(@usageText, @text) > 0
    BEGIN
      SET @somethingFound = 1

      IF @describe = 0
        PRINT @objectName
      ELSE
      BEGIN
        EXEC zdm.describe @objectName
        PRINT ''
        PRINT REPLICATE('#', 100)
      END
    END

    FETCH NEXT FROM @cursor INTO @objectID, @objectName
  END
  CLOSE @cursor
  DEALLOCATE @cursor

  IF @somethingFound = 0
    PRINT 'No usage found!'
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.info') IS NOT NULL
  DROP PROCEDURE zdm.info
GO
CREATE PROCEDURE zdm.info
  @info    varchar(100) = '',
  @filter  nvarchar(300) = ''
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  IF @info = ''
  BEGIN
    PRINT 'AVAILABLE OPTIONS...'
    PRINT '  zdm.info ''tables'''
    PRINT '  zdm.info ''indexes'''
    PRINT '  zdm.info ''views'''
    PRINT '  zdm.info ''functions'''
    PRINT '  zdm.info ''procs'''
    PRINT '  zdm.info ''filegroups'''
    PRINT '  zdm.info ''mountpoints'''
    PRINT '  zdm.info ''partitions'''
    PRINT '  zdm.info ''index stats'''
    PRINT '  zdm.info ''proc stats'''
    PRINT '  zdm.info ''indexes by filegroup'''
    PRINT '  zdm.info ''indexes by allocation type'''
    RETURN
  END

  IF @filter != ''
    SET @filter = '%' + LOWER(@filter) + '%'

  IF @info = 'tables'
  BEGIN
    SELECT I.[object_id], [object_name] = S.name + '.' + O.name,
           [rows] = SUM(CASE WHEN I.index_id IN (0, 1) THEN P.row_count ELSE 0 END),
           total_kb = SUM(P.reserved_page_count * 8), used_kb = SUM(P.used_page_count * 8), data_kb = SUM(P.in_row_data_page_count * 8),
           create_date = MIN(CONVERT(datetime2(0), O.create_date)), modify_date = MIN(CONVERT(datetime2(0), O.modify_date))
      FROM sys.indexes I
        INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
          INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
        INNER JOIN sys.dm_db_partition_stats P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
     WHERE O.type_desc = 'USER_TABLE' AND O.is_ms_shipped = 0
       AND (@filter = '' OR LOWER(S.name + '.' + O.name) LIKE @filter)
     GROUP BY I.[object_id], S.name, O.name
     ORDER BY S.name, O.name
  END

  ELSE IF @info = 'indexes'
  BEGIN
    SELECT I.[object_id], I.index_id, index_type = I.type_desc, [object_name] = S.name + '.' + O.name, index_name = I.name,
           [rows] = SUM(P.row_count),
           total_kb = SUM(P.reserved_page_count * 8), used_kb = SUM(P.used_page_count * 8), data_kb = SUM(P.in_row_data_page_count * 8),
           [partitions] = COUNT(*), I.fill_factor
      FROM sys.indexes I
        INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
          INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
        INNER JOIN sys.dm_db_partition_stats P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
     WHERE O.type_desc = 'USER_TABLE' AND O.is_ms_shipped = 0
       AND (@filter = '' OR (LOWER(S.name + '.' + O.name) LIKE @filter OR LOWER(I.name) LIKE @filter))
     GROUP BY I.[object_id], I.index_id, I.type_desc, I.fill_factor, S.name, O.name, I.name
     ORDER BY S.name, O.name, I.index_id
  END

  ELSE IF @info = 'views'
  BEGIN
    SELECT O.[object_id], [object_name] = S.name + '.' + O.name,
           create_date = CONVERT(datetime2(0), O.create_date), modify_date = CONVERT(datetime2(0), O.modify_date)
      FROM sys.objects O
        INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
     WHERE O.type_desc = 'VIEW'
       AND (@filter = '' OR LOWER(S.name + '.' + O.name) LIKE @filter)
     ORDER BY S.name, O.name
  END

  ELSE IF @info = 'functions'
  BEGIN
    SELECT O.[object_id], [object_name] = S.name + '.' + O.name, function_type = O.type_desc,
           create_date = CONVERT(datetime2(0), O.create_date), modify_date = CONVERT(datetime2(0), O.modify_date)
      FROM sys.objects O
        INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
     WHERE O.type_desc IN ('SQL_SCALAR_FUNCTION', 'SQL_TABLE_VALUED_FUNCTION', 'SQL_INLINE_TABLE_VALUED_FUNCTION')
       AND (@filter = '' OR (LOWER(S.name + '.' + O.name) LIKE @filter OR LOWER(O.type_desc) LIKE @filter))
     ORDER BY S.name, O.name
  END

  ELSE IF @info IN ('procs', 'procedures')
  BEGIN
    SELECT O.[object_id], [object_name] = S.name + '.' + O.name,
           create_date = CONVERT(datetime2(0), O.create_date), modify_date = CONVERT(datetime2(0), O.modify_date)
      FROM sys.objects O
        INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
     WHERE O.type_desc = 'SQL_STORED_PROCEDURE'
       AND (@filter = '' OR LOWER(S.name + '.' + O.name) LIKE @filter)
     ORDER BY S.name, O.name
  END

  ELSE IF @info = 'filegroups'
  BEGIN
    SELECT [filegroup] = F.name, total_kb = SUM(A.total_pages * 8), used_kb = SUM(A.used_pages * 8), data_kb = SUM(A.data_pages * 8)
      FROM sys.indexes I
        INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
        INNER JOIN sys.partitions P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
          INNER JOIN sys.allocation_units A ON A.container_id = P.[partition_id]
            INNER JOIN sys.filegroups F ON F.data_space_id = A.data_space_id
     WHERE O.type_desc = 'USER_TABLE' AND O.is_ms_shipped = 0
       AND (@filter = '' OR LOWER(F.name) LIKE @filter)
     GROUP BY F.name
     ORDER BY F.name
  END

  ELSE IF @info = 'mountpoints'
  BEGIN
    SELECT DISTINCT volume_mount_point = UPPER(V.volume_mount_point), V.file_system_type, V.logical_volume_name,
           total_size_GB = CONVERT(DECIMAL(18,2), V.total_bytes / 1073741824.0),
           available_size_GB = CONVERT(DECIMAL(18,2), V.available_bytes / 1073741824.0),
           [space_free_%] = CONVERT(DECIMAL(18,2), CONVERT(float, V.available_bytes) / CONVERT(float, V.total_bytes)) * 100
      FROM sys.master_files AS F WITH (NOLOCK)
        CROSS APPLY sys.dm_os_volume_stats(F.database_id, F.file_id) AS V
     WHERE @filter = '' OR LOWER(V.volume_mount_point) LIKE @filter OR LOWER(V.logical_volume_name) LIKE @filter
     ORDER BY UPPER(V.volume_mount_point)
    OPTION (RECOMPILE);
  END

  ELSE IF @info = 'partitions'
  BEGIN
    SELECT I.[object_id], [object_name] = S.name + '.' + O.name, index_name = I.name, [filegroup_name] = F.name,
           partition_scheme = PS.name, partition_function = PF.name, P.partition_number, P.[rows], boundary_value = PRV.value,
           PF.boundary_value_on_right, [data_compression] = P.data_compression_desc
       FROM sys.partition_schemes PS
         INNER JOIN sys.indexes I ON I.data_space_id = PS.data_space_id
           INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
             INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
           INNER JOIN sys.partitions P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
             INNER JOIN sys.destination_data_spaces DDS on DDS.partition_scheme_id = PS.data_space_id and DDS.destination_id = P.partition_number
               INNER JOIN sys.filegroups F ON F.data_space_id = DDS.data_space_id
         INNER JOIN sys.partition_functions PF ON PF.function_id = PS.function_id
           INNER JOIN sys.partition_range_values PRV on PRV.function_id = PF.function_id AND PRV.boundary_id = P.partition_number
     WHERE @filter = '' OR LOWER(S.name + '.' + O.name) LIKE @filter
     ORDER BY S.name, O.name, I.index_id, P.partition_number
  END

  ELSE IF @info = 'index stats'
  BEGIN
    SELECT I.[object_id], I.index_id, index_type = I.type_desc, [object_name] = S.name + '.' + O.name, index_name = I.name,
           [rows] = SUM(P.row_count),
           total_kb = SUM(P.reserved_page_count * 8),
           user_seeks = MAX(U.user_seeks), user_scans = MAX(U.user_scans), user_lookups = MAX(U.user_lookups), user_updates = MAX(U.user_updates),
           [partitions] = COUNT(*)
      FROM sys.indexes I
        INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
          INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
        INNER JOIN sys.dm_db_partition_stats P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
        LEFT JOIN sys.dm_db_index_usage_stats U ON U.database_id = DB_ID() AND U.[object_id] = I.[object_id] AND U.index_id = I.index_id
     WHERE O.type_desc = 'USER_TABLE' AND O.is_ms_shipped = 0
       AND (@filter = '' OR (LOWER(S.name + '.' + O.name) LIKE @filter OR LOWER(I.name) LIKE @filter))
     GROUP BY I.[object_id], I.index_id, I.type_desc, S.name, O.name, I.name
     ORDER BY S.name, O.name, I.index_id
  END

  ELSE IF @info IN ('proc stats', 'procedure stats')
  BEGIN
    SELECT O.[object_id], [object_name] = S.name + '.' + O.name,
           P.execution_count, P.total_worker_time, P.total_elapsed_time, P.total_logical_reads, P.total_logical_writes,
           P.max_worker_time, P.max_elapsed_time, P.max_logical_reads, P.max_logical_writes,
           P.last_execution_time, P.cached_time
      FROM sys.objects O
        INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
        LEFT JOIN sys.dm_exec_procedure_stats P ON P.database_id = DB_ID() AND P.[object_id] = O.[object_id]
     WHERE O.type_desc = 'SQL_STORED_PROCEDURE'
       AND (@filter = '' OR LOWER(S.name + '.' + O.name) LIKE @filter)
     ORDER BY S.name, O.name
  END

  ELSE IF @info = 'indexes by filegroup'
  BEGIN
    SELECT [filegroup] = F.name, I.[object_id], I.index_id, index_type = I.type_desc, [object_name] = S.name + '.' + O.name, index_name = I.name,
           [rows] = SUM(CASE WHEN A.type_desc = 'IN_ROW_DATA' THEN P.[rows] ELSE 0 END),
           total_kb = SUM(A.total_pages * 8), used_kb = SUM(A.used_pages * 8), data_kb = SUM(A.data_pages * 8),
           [partitions] = SUM(CASE WHEN A.type_desc = 'IN_ROW_DATA' THEN 1 ELSE 0 END),
           [compression] = CASE WHEN P.data_compression_desc = 'NONE' THEN '' ELSE P.data_compression_desc END
      FROM sys.indexes I
        INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
          INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
        INNER JOIN sys.partitions P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
          INNER JOIN sys.allocation_units A ON A.container_id = P.[partition_id]
            INNER JOIN sys.filegroups F ON F.data_space_id = A.data_space_id
     WHERE O.type_desc = 'USER_TABLE' AND O.is_ms_shipped = 0
       AND (@filter = '' OR (LOWER(S.name + '.' + O.name) LIKE @filter OR LOWER(I.name) LIKE @filter OR LOWER(F.name) LIKE @filter))
     GROUP BY F.name, I.[object_id], I.index_id, I.type_desc, S.name, O.name, I.name, P.data_compression_desc
     ORDER BY F.name, S.name, O.name, I.index_id
  END

  ELSE IF @info = 'indexes by allocation type'
  BEGIN
    SELECT allocation_type = A.type_desc,
           I.[object_id], I.index_id, index_type = I.type_desc, [object_name] = S.name + '.' + O.name, index_name = I.name,
           [rows] = SUM(CASE WHEN A.type_desc = 'IN_ROW_DATA' THEN P.[rows] ELSE 0 END),
           total_kb = SUM(A.total_pages * 8), used_kb = SUM(A.used_pages * 8), data_kb = SUM(A.data_pages * 8),
           [partitions] = COUNT(*),
           [compression] = CASE WHEN P.data_compression_desc = 'NONE' THEN '' ELSE P.data_compression_desc END,
           [filegroup] = F.name
      FROM sys.indexes I
        INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
          INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
        INNER JOIN sys.partitions P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
          INNER JOIN sys.allocation_units A ON A.container_id = P.[partition_id]
            INNER JOIN sys.filegroups F ON F.data_space_id = A.data_space_id
     WHERE O.type_desc = 'USER_TABLE' AND O.is_ms_shipped = 0
       AND (@filter = '' OR (LOWER(S.name + '.' + O.name) LIKE @filter OR LOWER(I.name) LIKE @filter OR LOWER(F.name) LIKE @filter OR LOWER(A.type_desc) LIKE @filter))
     GROUP BY A.type_desc, F.name, I.[object_id], I.index_id, I.type_desc, S.name, O.name, I.name, P.data_compression_desc
     ORDER BY A.type_desc, S.name, O.name, I.index_id
  END

  ELSE
  BEGIN
    PRINT 'OPTION NOT AVAILAIBLE !!!'
  END
GO


IF OBJECT_ID('zdm.i') IS NOT NULL
  DROP SYNONYM zdm.i
GO
CREATE SYNONYM zdm.i FOR zdm.info
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.topsql') IS NOT NULL
  DROP PROCEDURE zdm.topsql
GO
CREATE PROCEDURE zdm.topsql
  @rows  smallint = 30
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @now datetime2(0) = GETDATE()

  IF NOT EXISTS(SELECT 1 FROM sys.dm_exec_requests WHERE blocking_session_id != 0)
  BEGIN
    -- No blocking, light version
    SELECT TOP (@rows) start_time = CONVERT(datetime2(0), R.start_time), run_time = zutil.TimeString(ABS(DATEDIFF(second, R.start_time, @now))),
           R.session_id, blocking_id = R.blocking_session_id, R.logical_reads,
           S.[host_name], S.[program_name], S.login_name, database_name = DB_NAME(R.database_id),
           [object_name] = OBJECT_SCHEMA_NAME(T.objectid, R.database_id) + '.' + OBJECT_NAME(T.objectid, R.database_id),
           T.[text], R.command, R.[status], estimated_completion_time = zutil.TimeString(R.estimated_completion_time / 1000),
           wait_time = zutil.TimeString(R.wait_time / 1000), R.last_wait_type, cpu_time = zutil.TimeString(R.cpu_time / 1000),
           total_elapsed_time = zutil.TimeString(R.total_elapsed_time / 1000), R.reads, R.writes,
           R.open_transaction_count, R.open_resultset_count, R.percent_complete, R.database_id,
           [object_id] = T.objectid, S.host_process_id, S.client_interface_name, R.[sql_handle], R.plan_handle
      FROM sys.dm_exec_requests R
        CROSS APPLY sys.dm_exec_sql_text(R.[sql_handle]) T
        LEFT JOIN sys.dm_exec_sessions S ON S.session_id = R.session_id
     ORDER BY R.start_time
  END
  ELSE
  BEGIN
    -- Blocking, add blocking info rowset
    DECLARE @topsql TABLE
    (
      start_time                 datetime2(0),
      run_time                   varchar(20),
      session_id                 smallint,
      blocking_id                smallint,
      logical_reads              bigint,
      [host_name]                nvarchar(128),
      [program_name]             nvarchar(128),
      login_name                 nvarchar(128),
      database_name              nvarchar(128),
      [object_name]              nvarchar(256),
      [text]                     nvarchar(max),
      command                    nvarchar(32),
      [status]                   nvarchar(30),
      estimated_completion_time  varchar(20),
      wait_time                  varchar(20),
      last_wait_type             nvarchar(60),
      cpu_time                   varchar(20),
      total_elapsed_time         varchar(20),
      reads                      bigint,
      writes                     bigint,
      open_transaction_count     int,
      open_resultset_count       int,
      percent_complete           real,
      database_id                smallint,
      [object_id]                int,
      host_process_id            int,
      client_interface_name      nvarchar(32),
      [sql_handle]               varbinary(64),
      plan_handle                varbinary(64)
    )

    INSERT INTO @topsql
         SELECT TOP (@rows) start_time = CONVERT(datetime2(0), R.start_time), run_time = zutil.TimeString(ABS(DATEDIFF(second, R.start_time, @now))),
                R.session_id, blocking_id = R.blocking_session_id, R.logical_reads,
                S.[host_name], S.[program_name], S.login_name, database_name = DB_NAME(R.database_id),
                [object_name] = OBJECT_SCHEMA_NAME(T.objectid, R.database_id) + '.' + OBJECT_NAME(T.objectid, R.database_id),
                T.[text], R.command, R.[status], estimated_completion_time = zutil.TimeString(R.estimated_completion_time / 1000),
                wait_time = zutil.TimeString(R.wait_time / 1000), R.last_wait_type, cpu_time = zutil.TimeString(R.cpu_time / 1000),
                total_elapsed_time = zutil.TimeString(R.total_elapsed_time / 1000), R.reads, R.writes,
                R.open_transaction_count, R.open_resultset_count, R.percent_complete, R.database_id,
                [object_id] = T.objectid, S.host_process_id, S.client_interface_name, R.[sql_handle], R.plan_handle
           FROM sys.dm_exec_requests R
             CROSS APPLY sys.dm_exec_sql_text(R.[sql_handle]) T
             LEFT JOIN sys.dm_exec_sessions S ON S.session_id = R.session_id

    SELECT 'Blocking info' AS Info, start_time, run_time, session_id, blocking_id, logical_reads,
            [host_name], [program_name], login_name, database_name, [object_name],
            [text], command, [status], estimated_completion_time, wait_time, last_wait_type, cpu_time,
            total_elapsed_time, reads, writes,
            open_transaction_count, open_resultset_count, percent_complete, database_id,
            [object_id], host_process_id, client_interface_name, [sql_handle], plan_handle
      FROM @topsql
      WHERE blocking_id IN (select session_id FROM @topsql) OR session_id IN (select blocking_id FROM @topsql)
      ORDER BY blocking_id, session_id

    SELECT start_time, run_time, session_id, blocking_id, logical_reads,
           [host_name], [program_name], login_name, database_name, [object_name],
           [text], command, [status], estimated_completion_time, wait_time, last_wait_type, cpu_time,
           total_elapsed_time, reads, writes,
           open_transaction_count, open_resultset_count, percent_complete, database_id,
           [object_id], host_process_id, client_interface_name, [sql_handle], plan_handle
      FROM @topsql
     ORDER BY start_time
  END
GO


IF OBJECT_ID('zdm.t') IS NOT NULL
  DROP SYNONYM zdm.t
GO
CREATE SYNONYM zdm.t FOR zdm.topsql
GO


---------------------------------------------------------------------------------------------------------------------------------



GO
EXEC zsystem.Versions_Finish 'CORE', 0004, 'jorundur'
GO
