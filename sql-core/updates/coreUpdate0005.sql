
EXEC zsystem.Versions_Start 'CORE', 0005, 'jorundur'
GO



---------------------------------------------------------------------------------------------------------------------------------


 -- *** Empty DB update to hack Perforce/makedbupdate.py which looks for the latest add in the updates folder ***


---------------------------------------------------------------------------------------------------------------------------------



GO
EXEC zsystem.Versions_Finish 'CORE', 0005, 'jorundur'
GO
