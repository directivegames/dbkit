
--
-- SCHEMA
--

IF SCHEMA_ID('zutil') IS NULL
  EXEC sp_executesql N'CREATE SCHEMA zutil'
GO
