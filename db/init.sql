/*
--將既有 eTicketShop 資料庫移除的指令碼
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'eTicketShop'
GO

USE [master]
GO

ALTER DATABASE [eTicketShop]
	SET SINGLE_USER WITH ROLLBACK IMMEDIATE
GO

USE [master]
GO

DROP DATABASE [eTicketShop]
GO
*/

/*
    建立 eTicketShop 範例資料庫需要的資料表與預設資料內容
*/
CREATE DATABASE [eTicketShop]
GO

/*
	此設定與 Azure SQL Database 相同
	https://blogs.msdn.microsoft.com/sqlcat/2013/12/26/be-aware-of-the-difference-in-isolation-levels-if-porting-an-application-from-windows-azure-sql-db-to-sql-server-in-windows-azure-virtual-machine/
*/

--啟用 SNAPSHOT_ISOLATION
ALTER DATABASE [eTicketShop]
	SET ALLOW_SNAPSHOT_ISOLATION ON
GO

--啟用 READ_COMMITTED_SNAPSHOT
ALTER DATABASE [eTicketShop]
	SET READ_COMMITTED_SNAPSHOT ON
	WITH ROLLBACK IMMEDIATE
GO

USE [eTicketShop]
GO

CREATE SCHEMA [Places]
GO

CREATE SCHEMA [Tickets]
GO

CREATE SCHEMA [Logs]
GO

CREATE TABLE [Places].[PlaceMains]
(
	[No]			INT,
	[Name]			NVARCHAR(150),
	
	[whenCreate]	SMALLDATETIME DEFAULT (GETDATE()),
	
	CONSTRAINT [pk_PlaceMains] PRIMARY KEY ([No])
)
GO

CREATE TABLE [Tickets].[TicketEvents]
(
	[No]			INT,
	[PlaceMainNo]	INT,
	[Name]			NVARCHAR(150),
	[EventTime]		SMALLDATETIME,
	
	CONSTRAINT [pk_TicketEvents] PRIMARY KEY ([No]),
	
	CONSTRAINT [fk_TicketEvents_PlaceMainNo] FOREIGN KEY([PlaceMainNo])
		REFERENCES [Places].[PlaceMains]([No])
			ON DELETE NO ACTION
)
GO

CREATE TABLE [Tickets].[TicketGates]
(
	[No]			INT,
	[TicketEventNo]	INT,
	
	[Gate]			NVARCHAR(10),
	[Section]		NVARCHAR(10),
	
	[ListPrice]		SMALLMONEY,
	[Sort]			SMALLINT,
	
	CONSTRAINT [pk_TicketGates] PRIMARY KEY ([No]),
	
	CONSTRAINT [fk_TicketGates_TicketEventNo] FOREIGN KEY ([TicketEventNo])
		REFERENCES [Tickets].[TicketEvents]([No]),
		
	CONSTRAINT [un_TicketGates] UNIQUE (
		[TicketEventNo]
		,[Gate]
		,[Section]
		,[ListPrice]
	)
)
GO

CREATE TABLE [Tickets].[TicketSeats]
(
	[No]			INT,
	[TicketGateNo]	INT,
	
	[Row]			NVARCHAR(10),
	[Seat]			NVARCHAR(10),
	[Sort]			SMALLINT,
	
	CONSTRAINT [pk_TicketSeats] PRIMARY KEY ([No]),	
	
	CONSTRAINT [fk_TicketSeats_TicketGateNo] FOREIGN KEY ([TicketGateNo])
		REFERENCES [Tickets].[TicketGates]([No]),
		
	CONSTRAINT [un_TicketSeats_Row_Seat_TicketGateNo] UNIQUE (
		[TicketGateNo]
		,[Row]
		,[Seat]
	)
)
GO


CREATE TABLE [Tickets].[TicketPositions]
(
	[No]				INT IDENTITY(1,1),
	
	[TicketEventNo]		INT,
	[Gate]				NVARCHAR(50),
	[Section]			NVARCHAR(50),
	[Row]				NVARCHAR(10),
	[Seat]				NVARCHAR(10),
	[ListPrice]			SMALLMONEY,
	
	[memberCreate]		NVARCHAR(50),
	[memberLastChange]	NVARCHAR(50),
	[whenCreate]		SMALLDATETIME DEFAULT (GETDATE()),
	[whenLastChange]	SMALLDATETIME,

	CONSTRAINT [pk_TicketPositions] PRIMARY KEY ([No]),
	
	CONSTRAINT [fk_TicketPositions_TicketEventNo] FOREIGN KEY ([TicketEventNo])
		REFERENCES [Tickets].[TicketEvents]([No]) ON DELETE NO ACTION
)
GO

CREATE TABLE [Tickets].[TicketOrders]
(
	[No]				INT IDENTITY(1,1),
	[TicketEventNo]		INT,
	[TicketGateNo]		INT,
	[TicketSeatNo]		INT,
	
	[Gate]				NVARCHAR(50),
	[Section]			NVARCHAR(50),
	[Row]				NVARCHAR(10),
	[Seat]				NVARCHAR(10),
	[ListPrice]			SMALLMONEY,
	
	[memberGUID]		UNIQUEIDENTIFIER,
	
	[memberCreate]		NVARCHAR(50),
	[memberLastChange]	NVARCHAR(50),
	[whenCreate]		SMALLDATETIME DEFAULT (GETDATE()),
	[whenLastChange]	SMALLDATETIME,
	
	CONSTRAINT [pk_TicketOrders] PRIMARY KEY ([No]),
	
	CONSTRAINT [fk_TicketOrders_TicketEventNo] FOREIGN KEY ([TicketEventNo])
		REFERENCES [Tickets].[TicketEvents]([No]),
		
	CONSTRAINT [fk_TicketOrders_TicketGateNo] FOREIGN KEY ([TicketGateNo])
		REFERENCES [Tickets].[TicketGates]([No]),
		
	CONSTRAINT [fk_TicketOrders_TicketSeatNo] FOREIGN KEY ([TicketSeatNo])
		REFERENCES [Tickets].[TicketSeats]([No])
)
GO

CREATE NONCLUSTERED INDEX [ix_TicketOrders_memberGUID]
	ON [Tickets].[TicketOrders] ([memberGUID])
GO




CREATE TABLE [Logs].[Logs]
(
	[No]				INT IDENTITY(1,1),
	[EventDateTime]		DATETIME DEFAULT (GETDATE()),
	
	[memberGUID]		UNIQUEIDENTIFIER,
	[TicketNumber]		INT,
	
	[Elapsed]			INT,
	[IsSuccess]			BIT,
	
	[Exception]			NVARCHAR(250),
	[Retry]				INT,
	
	CONSTRAINT [pk_Logs] PRIMARY KEY ([No]),
)
GO

CREATE PROCEDURE [Logs].[AddLog]
	@memberGUID			UNIQUEIDENTIFIER,
	@TicketNumber		INT,
	
	@Elapsed			INT,
	@IsSuccess			BIT,
	
	@Exception			NVARCHAR(250),
	@Retry				INT
AS

	INSERT INTO [Logs].[Logs] (
		[memberGUID]
		,[TicketNumber]
		,[Elapsed]
		,[IsSuccess]
		,[Exception]
		,[Retry]
	) VALUES (
		@memberGUID
		,@TicketNumber
		,@Elapsed
		,@IsSuccess
		,@Exception
		,@Retry
	)
	
GO


--初始化購票訂單預存程序 StoredProcedure
CREATE PROCEDURE [Tickets].[CreateTicketOrderByEventNo]
	@TicketEventNo	INT,
	@memberCreate	NVARCHAR(50)
AS
	INSERT INTO [Tickets].[TicketOrders] (
		[TicketEventNo]
		,[TicketGateNo]
		,[TicketSeatNo]
		,[Gate]
		,[Section]
		,[Row]
		,[Seat]
		,[ListPrice]
		,[memberCreate]
	) SELECT 
		@TicketEventNo
		,a.[No] [TicketGateNo]
		,b.[No] [TicketSeatNo]
		,a.[Gate]
		,a.[Section]
		,b.[Row]
		,b.[Seat]
		,a.[ListPrice]
		,@memberCreate
	FROM [Tickets].[TicketGates] a
		INNER JOIN [Tickets].[TicketSeats] b ON a.[No] = b.[TicketGateNo]
	WHERE a.[TicketEventNo] = @TicketEventNo
	ORDER BY a.[No] ASC
		,b.[No] ASC
GO


--依照活動、區域與張數進行訂票作業 - 自動劃位
CREATE PROCEDURE [Tickets].[BuyTicketAuto]
	@TicketEventNo		INT,
	@GateNo				INT,
	@memberGUID			UNIQUEIDENTIFIER,
	@TicketCount		TINYINT,
	@IsSuccess			BIT OUT
AS

DECLARE @memberOut		TABLE
(
	[memberGUID]		UNIQUEIDENTIFIER
)
SET @IsSuccess = 0

BEGIN TRY

	BEGIN TRANSACTION

	UPDATE TOP(@TicketCount) [Tickets].[TicketOrders]
		SET [memberGUID] = @memberGUID
	OUTPUT INSERTED.[memberGUID]
		INTO @memberOut
	WHERE [TicketGateNo] = @GateNo
		AND [memberGUID] IS NULL

	IF @TicketCount = (SELECT COUNT(*) FROM @memberOut)
		BEGIN
			SET @IsSuccess = 1
			COMMIT
		END
	ELSE
		BEGIN
			ROLLBACK
		END

END TRY

BEGIN CATCH
	ROLLBACK
END CATCH
GO

--取得指定售票活動的狀態
CREATE FUNCTION [Tickets].[GetTicketEventStatus]
(
	@TicketEventNo		INT
)
RETURNS TABLE
AS
	RETURN (
		SELECT [TicketGateNo]
			,[Gate]
			,[Section]
			,[ListPrice]
			,COUNT([MemberGUID]) [TicketSell]
			,COUNT(*) [TicketTotal]
		FROM [Tickets].[TicketOrders]
		WHERE [TicketEventNo] = @TicketEventNo
		GROUP BY [TicketGateNo]
			,[Gate]
			,[Section]
			,[ListPrice]
	)
GO



--初始化範例資料表內容
INSERT INTO [Places].[PlaceMains] ([No],[Name])
	VALUES (1,N'台北小巨蛋')
GO

INSERT INTO [Tickets].[TicketEvents] ([No],[Name],[PlaceMainNo],[EventTime])
	VALUES (1,N'五月天 諾亞方舟 巡迴最終站',1,'2018-12-25 20:00')
GO


INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (1, 1, N'搖滾', N'A區', 6000.0000, 1)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (2, 1, N'搖滾', N'B區', 6000.0000, 2)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (3, 1, N'搖滾', N'C區', 6000.0000, 3)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (4, 1, N'搖滾', N'D區', 6000.0000, 4)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (5, 1, N'紅', N'2B', 6000.0000, 5)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (6, 1, N'紅', N'2B', 5400.0000, 6)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (7, 1, N'紅', N'2C', 6000.0000, 7)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (8, 1, N'紅', N'2C', 5400.0000, 8)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (9, 1, N'紅', N'2D', 6000.0000, 9)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (10, 1, N'紅', N'2D', 5400.0000, 10)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (11, 1, N'紅', N'2E', 6000.0000, 11)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (12, 1, N'紅', N'2E', 5400.0000, 12)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (13, 1, N'紫', N'2B', 6000.0000, 13)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (14, 1, N'紫', N'2B', 5400.0000, 14)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (15, 1, N'紫', N'2C', 6000.0000, 15)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (16, 1, N'紫', N'2C', 5400.0000, 16)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (17, 1, N'紫', N'2D', 6000.0000, 17)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (18, 1, N'紫', N'2D', 5400.0000, 18)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (19, 1, N'紫', N'2E', 6000.0000, 19)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (20, 1, N'紫', N'2E', 5400.0000, 20)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (21, 1, N'黃', N'2A', 6000.0000, 21)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (22, 1, N'黃', N'2A', 5400.0000, 22)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (23, 1, N'黃', N'2B', 6000.0000, 23)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (24, 1, N'黃', N'2B', 5400.0000, 24)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (25, 1, N'黃', N'2C', 6000.0000, 25)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (26, 1, N'黃', N'2C', 5400.0000, 26)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (27, 1, N'黃', N'2D', 6000.0000, 27)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (28, 1, N'黃', N'2D', 5400.0000, 28)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (29, 1, N'黃', N'2E', 6000.0000, 29)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (30, 1, N'黃', N'2E', 5400.0000, 30)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (31, 1, N'黃', N'3A', 3800.0000, 31)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (32, 1, N'黃', N'3A', 3400.0000, 32)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (33, 1, N'黃', N'3A', 1400.0000, 33)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (34, 1, N'黃', N'3B', 3800.0000, 34)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (35, 1, N'黃', N'3B', 3400.0000, 35)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (36, 1, N'黃', N'3B', 1400.0000, 36)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (37, 1, N'黃', N'3C', 3800.0000, 37)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (38, 1, N'黃', N'3C', 3400.0000, 38)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (39, 1, N'黃', N'3C', 1400.0000, 39)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (40, 1, N'黃', N'3D', 3800.0000, 40)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (41, 1, N'黃', N'3D', 3400.0000, 41)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (42, 1, N'黃', N'3D', 1400.0000, 42)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (43, 1, N'黃', N'3E', 3800.0000, 43)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (44, 1, N'黃', N'3E', 3400.0000, 44)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (45, 1, N'黃', N'3E', 1400.0000, 45)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (46, 1, N'黃', N'3F', 3800.0000, 46)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (47, 1, N'黃', N'3F', 3400.0000, 47)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (48, 1, N'黃', N'3F', 1400.0000, 48)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (49, 1, N'黃', N'3G', 3800.0000, 49)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (50, 1, N'黃', N'3G', 3400.0000, 50)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (51, 1, N'黃', N'3G', 1400.0000, 51)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (52, 1, N'黃', N'3H', 3800.0000, 52)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (53, 1, N'黃', N'3H', 3400.0000, 53)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (54, 1, N'黃', N'3H', 1400.0000, 54)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (55, 1, N'黃', N'3I', 3800.0000, 55)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (56, 1, N'黃', N'3I', 3400.0000, 56)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (57, 1, N'黃', N'3I', 1400.0000, 57)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (58, 1, N'黃', N'3J', 3800.0000, 58)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (59, 1, N'黃', N'3J', 3400.0000, 59)
GO
INSERT [Tickets].[TicketGates] ([No], [TicketEventNo], [Gate], [Section], [ListPrice], [Sort]) VALUES (60, 1, N'黃', N'3J', 1400.0000, 60)
GO


INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1, 1, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2, 1, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3, 1, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4, 1, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (5, 1, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (6, 1, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (7, 1, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (8, 1, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (9, 1, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (10, 1, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (11, 1, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (12, 1, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (13, 1, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (14, 1, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (15, 1, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (16, 1, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (17, 1, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (18, 1, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (19, 1, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (20, 1, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (21, 1, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (22, 1, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (23, 1, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (24, 1, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (25, 1, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (26, 1, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (27, 1, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (28, 1, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (29, 1, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (30, 1, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (31, 1, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (32, 1, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (33, 1, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (34, 1, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (35, 1, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (36, 1, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (37, 1, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (38, 1, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (39, 1, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (40, 1, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (41, 1, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (42, 1, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (43, 1, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (44, 1, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (45, 1, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (46, 1, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (47, 1, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (48, 1, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (49, 1, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (50, 1, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (51, 1, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (52, 1, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (53, 1, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (54, 1, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (55, 1, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (56, 1, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (57, 1, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (58, 1, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (59, 1, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (60, 1, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (61, 1, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (62, 1, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (63, 1, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (64, 1, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (65, 1, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (66, 1, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (67, 1, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (68, 1, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (69, 1, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (70, 1, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (71, 1, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (72, 1, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (73, 1, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (74, 1, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (75, 1, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (76, 1, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (77, 1, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (78, 1, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (79, 1, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (80, 1, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (81, 1, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (82, 1, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (83, 1, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (84, 1, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (85, 1, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (86, 1, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (87, 1, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (88, 1, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (89, 1, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (90, 1, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (91, 1, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (92, 1, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (93, 1, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (94, 1, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (95, 1, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (96, 1, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (97, 1, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (98, 1, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (99, 1, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (100, 1, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (101, 1, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (102, 1, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (103, 1, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (104, 1, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (105, 1, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (106, 1, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (107, 1, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (108, 1, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (109, 1, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (110, 1, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (111, 1, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (112, 1, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (113, 1, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (114, 1, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (115, 1, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (116, 1, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (117, 1, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (118, 1, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (119, 1, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (120, 1, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (121, 1, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (122, 1, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (123, 1, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (124, 1, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (125, 1, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (126, 1, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (127, 1, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (128, 1, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (129, 1, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (130, 1, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (131, 1, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (132, 1, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (133, 1, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (134, 1, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (135, 1, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (136, 1, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (137, 1, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (138, 1, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (139, 1, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (140, 1, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (141, 1, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (142, 1, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (143, 1, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (144, 1, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (145, 1, N'13', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (146, 1, N'13', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (147, 1, N'13', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (148, 1, N'13', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (149, 1, N'13', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (150, 1, N'13', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (151, 1, N'13', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (152, 1, N'13', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (153, 1, N'13', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (154, 1, N'13', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (155, 1, N'13', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (156, 1, N'13', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (157, 1, N'14', N'1', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (158, 1, N'14', N'2', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (159, 1, N'14', N'3', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (160, 1, N'14', N'4', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (161, 1, N'14', N'5', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (162, 1, N'14', N'6', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (163, 1, N'14', N'7', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (164, 1, N'14', N'8', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (165, 1, N'14', N'9', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (166, 1, N'14', N'10', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (167, 1, N'14', N'11', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (168, 1, N'14', N'12', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (169, 1, N'15', N'1', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (170, 1, N'15', N'2', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (171, 1, N'15', N'3', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (172, 1, N'15', N'4', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (173, 1, N'15', N'5', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (174, 1, N'15', N'6', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (175, 1, N'15', N'7', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (176, 1, N'15', N'8', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (177, 1, N'15', N'9', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (178, 1, N'15', N'10', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (179, 1, N'15', N'11', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (180, 1, N'15', N'12', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (181, 1, N'16', N'1', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (182, 1, N'16', N'2', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (183, 1, N'16', N'3', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (184, 1, N'16', N'4', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (185, 1, N'16', N'5', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (186, 1, N'16', N'6', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (187, 1, N'16', N'7', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (188, 1, N'16', N'8', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (189, 1, N'16', N'9', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (190, 1, N'16', N'10', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (191, 1, N'16', N'11', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (192, 1, N'16', N'12', 192)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (193, 1, N'17', N'1', 193)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (194, 1, N'17', N'2', 194)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (195, 1, N'17', N'3', 195)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (196, 1, N'17', N'4', 196)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (197, 1, N'17', N'5', 197)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (198, 1, N'17', N'6', 198)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (199, 1, N'17', N'7', 199)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (200, 1, N'17', N'8', 200)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (201, 1, N'17', N'9', 201)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (202, 1, N'17', N'10', 202)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (203, 1, N'17', N'11', 203)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (204, 1, N'17', N'12', 204)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (205, 1, N'18', N'1', 205)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (206, 1, N'18', N'2', 206)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (207, 1, N'18', N'3', 207)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (208, 1, N'18', N'4', 208)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (209, 1, N'18', N'5', 209)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (210, 1, N'18', N'6', 210)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (211, 1, N'18', N'7', 211)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (212, 1, N'18', N'8', 212)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (213, 1, N'18', N'9', 213)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (214, 1, N'18', N'10', 214)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (215, 1, N'18', N'11', 215)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (216, 1, N'18', N'12', 216)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (217, 1, N'19', N'1', 217)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (218, 1, N'19', N'2', 218)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (219, 1, N'19', N'3', 219)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (220, 1, N'19', N'4', 220)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (221, 1, N'19', N'5', 221)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (222, 1, N'19', N'6', 222)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (223, 1, N'19', N'7', 223)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (224, 1, N'19', N'8', 224)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (225, 1, N'19', N'9', 225)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (226, 1, N'19', N'10', 226)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (227, 1, N'19', N'11', 227)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (228, 1, N'19', N'12', 228)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (229, 1, N'20', N'1', 229)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (230, 1, N'20', N'2', 230)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (231, 1, N'20', N'3', 231)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (232, 1, N'20', N'4', 232)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (233, 1, N'20', N'5', 233)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (234, 1, N'20', N'6', 234)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (235, 1, N'20', N'7', 235)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (236, 1, N'20', N'8', 236)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (237, 1, N'20', N'9', 237)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (238, 1, N'20', N'10', 238)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (239, 1, N'20', N'11', 239)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (240, 1, N'20', N'12', 240)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (241, 2, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (242, 2, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (243, 2, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (244, 2, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (245, 2, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (246, 2, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (247, 2, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (248, 2, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (249, 2, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (250, 2, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (251, 2, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (252, 2, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (253, 2, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (254, 2, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (255, 2, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (256, 2, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (257, 2, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (258, 2, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (259, 2, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (260, 2, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (261, 2, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (262, 2, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (263, 2, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (264, 2, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (265, 2, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (266, 2, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (267, 2, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (268, 2, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (269, 2, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (270, 2, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (271, 2, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (272, 2, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (273, 2, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (274, 2, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (275, 2, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (276, 2, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (277, 2, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (278, 2, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (279, 2, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (280, 2, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (281, 2, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (282, 2, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (283, 2, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (284, 2, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (285, 2, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (286, 2, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (287, 2, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (288, 2, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (289, 2, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (290, 2, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (291, 2, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (292, 2, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (293, 2, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (294, 2, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (295, 2, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (296, 2, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (297, 2, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (298, 2, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (299, 2, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (300, 2, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (301, 2, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (302, 2, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (303, 2, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (304, 2, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (305, 2, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (306, 2, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (307, 2, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (308, 2, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (309, 2, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (310, 2, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (311, 2, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (312, 2, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (313, 2, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (314, 2, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (315, 2, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (316, 2, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (317, 2, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (318, 2, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (319, 2, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (320, 2, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (321, 2, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (322, 2, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (323, 2, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (324, 2, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (325, 2, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (326, 2, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (327, 2, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (328, 2, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (329, 2, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (330, 2, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (331, 2, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (332, 2, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (333, 2, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (334, 2, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (335, 2, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (336, 2, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (337, 2, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (338, 2, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (339, 2, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (340, 2, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (341, 2, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (342, 2, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (343, 2, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (344, 2, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (345, 2, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (346, 2, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (347, 2, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (348, 2, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (349, 2, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (350, 2, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (351, 2, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (352, 2, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (353, 2, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (354, 2, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (355, 2, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (356, 2, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (357, 2, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (358, 2, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (359, 2, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (360, 2, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (361, 2, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (362, 2, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (363, 2, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (364, 2, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (365, 2, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (366, 2, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (367, 2, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (368, 2, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (369, 2, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (370, 2, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (371, 2, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (372, 2, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (373, 2, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (374, 2, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (375, 2, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (376, 2, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (377, 2, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (378, 2, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (379, 2, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (380, 2, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (381, 2, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (382, 2, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (383, 2, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (384, 2, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (385, 2, N'13', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (386, 2, N'13', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (387, 2, N'13', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (388, 2, N'13', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (389, 2, N'13', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (390, 2, N'13', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (391, 2, N'13', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (392, 2, N'13', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (393, 2, N'13', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (394, 2, N'13', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (395, 2, N'13', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (396, 2, N'13', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (397, 2, N'14', N'1', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (398, 2, N'14', N'2', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (399, 2, N'14', N'3', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (400, 2, N'14', N'4', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (401, 2, N'14', N'5', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (402, 2, N'14', N'6', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (403, 2, N'14', N'7', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (404, 2, N'14', N'8', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (405, 2, N'14', N'9', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (406, 2, N'14', N'10', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (407, 2, N'14', N'11', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (408, 2, N'14', N'12', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (409, 2, N'15', N'1', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (410, 2, N'15', N'2', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (411, 2, N'15', N'3', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (412, 2, N'15', N'4', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (413, 2, N'15', N'5', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (414, 2, N'15', N'6', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (415, 2, N'15', N'7', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (416, 2, N'15', N'8', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (417, 2, N'15', N'9', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (418, 2, N'15', N'10', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (419, 2, N'15', N'11', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (420, 2, N'15', N'12', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (421, 2, N'16', N'1', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (422, 2, N'16', N'2', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (423, 2, N'16', N'3', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (424, 2, N'16', N'4', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (425, 2, N'16', N'5', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (426, 2, N'16', N'6', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (427, 2, N'16', N'7', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (428, 2, N'16', N'8', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (429, 2, N'16', N'9', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (430, 2, N'16', N'10', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (431, 2, N'16', N'11', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (432, 2, N'16', N'12', 192)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (433, 2, N'17', N'1', 193)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (434, 2, N'17', N'2', 194)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (435, 2, N'17', N'3', 195)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (436, 2, N'17', N'4', 196)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (437, 2, N'17', N'5', 197)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (438, 2, N'17', N'6', 198)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (439, 2, N'17', N'7', 199)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (440, 2, N'17', N'8', 200)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (441, 2, N'17', N'9', 201)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (442, 2, N'17', N'10', 202)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (443, 2, N'17', N'11', 203)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (444, 2, N'17', N'12', 204)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (445, 2, N'18', N'1', 205)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (446, 2, N'18', N'2', 206)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (447, 2, N'18', N'3', 207)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (448, 2, N'18', N'4', 208)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (449, 2, N'18', N'5', 209)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (450, 2, N'18', N'6', 210)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (451, 2, N'18', N'7', 211)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (452, 2, N'18', N'8', 212)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (453, 2, N'18', N'9', 213)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (454, 2, N'18', N'10', 214)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (455, 2, N'18', N'11', 215)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (456, 2, N'18', N'12', 216)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (457, 2, N'19', N'1', 217)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (458, 2, N'19', N'2', 218)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (459, 2, N'19', N'3', 219)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (460, 2, N'19', N'4', 220)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (461, 2, N'19', N'5', 221)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (462, 2, N'19', N'6', 222)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (463, 2, N'19', N'7', 223)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (464, 2, N'19', N'8', 224)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (465, 2, N'19', N'9', 225)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (466, 2, N'19', N'10', 226)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (467, 2, N'19', N'11', 227)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (468, 2, N'19', N'12', 228)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (469, 2, N'20', N'1', 229)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (470, 2, N'20', N'2', 230)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (471, 2, N'20', N'3', 231)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (472, 2, N'20', N'4', 232)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (473, 2, N'20', N'5', 233)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (474, 2, N'20', N'6', 234)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (475, 2, N'20', N'7', 235)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (476, 2, N'20', N'8', 236)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (477, 2, N'20', N'9', 237)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (478, 2, N'20', N'10', 238)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (479, 2, N'20', N'11', 239)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (480, 2, N'20', N'12', 240)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (481, 3, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (482, 3, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (483, 3, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (484, 3, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (485, 3, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (486, 3, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (487, 3, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (488, 3, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (489, 3, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (490, 3, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (491, 3, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (492, 3, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (493, 3, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (494, 3, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (495, 3, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (496, 3, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (497, 3, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (498, 3, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (499, 3, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (500, 3, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (501, 3, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (502, 3, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (503, 3, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (504, 3, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (505, 3, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (506, 3, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (507, 3, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (508, 3, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (509, 3, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (510, 3, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (511, 3, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (512, 3, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (513, 3, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (514, 3, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (515, 3, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (516, 3, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (517, 3, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (518, 3, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (519, 3, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (520, 3, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (521, 3, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (522, 3, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (523, 3, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (524, 3, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (525, 3, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (526, 3, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (527, 3, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (528, 3, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (529, 3, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (530, 3, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (531, 3, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (532, 3, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (533, 3, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (534, 3, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (535, 3, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (536, 3, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (537, 3, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (538, 3, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (539, 3, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (540, 3, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (541, 3, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (542, 3, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (543, 3, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (544, 3, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (545, 3, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (546, 3, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (547, 3, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (548, 3, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (549, 3, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (550, 3, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (551, 3, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (552, 3, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (553, 3, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (554, 3, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (555, 3, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (556, 3, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (557, 3, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (558, 3, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (559, 3, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (560, 3, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (561, 3, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (562, 3, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (563, 3, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (564, 3, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (565, 3, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (566, 3, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (567, 3, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (568, 3, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (569, 3, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (570, 3, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (571, 3, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (572, 3, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (573, 3, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (574, 3, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (575, 3, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (576, 3, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (577, 3, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (578, 3, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (579, 3, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (580, 3, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (581, 3, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (582, 3, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (583, 3, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (584, 3, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (585, 3, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (586, 3, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (587, 3, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (588, 3, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (589, 3, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (590, 3, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (591, 3, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (592, 3, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (593, 3, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (594, 3, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (595, 3, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (596, 3, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (597, 3, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (598, 3, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (599, 3, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (600, 3, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (601, 3, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (602, 3, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (603, 3, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (604, 3, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (605, 3, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (606, 3, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (607, 3, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (608, 3, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (609, 3, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (610, 3, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (611, 3, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (612, 3, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (613, 3, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (614, 3, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (615, 3, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (616, 3, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (617, 3, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (618, 3, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (619, 3, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (620, 3, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (621, 3, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (622, 3, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (623, 3, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (624, 3, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (625, 3, N'13', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (626, 3, N'13', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (627, 3, N'13', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (628, 3, N'13', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (629, 3, N'13', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (630, 3, N'13', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (631, 3, N'13', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (632, 3, N'13', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (633, 3, N'13', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (634, 3, N'13', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (635, 3, N'13', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (636, 3, N'13', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (637, 3, N'14', N'1', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (638, 3, N'14', N'2', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (639, 3, N'14', N'3', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (640, 3, N'14', N'4', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (641, 3, N'14', N'5', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (642, 3, N'14', N'6', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (643, 3, N'14', N'7', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (644, 3, N'14', N'8', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (645, 3, N'14', N'9', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (646, 3, N'14', N'10', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (647, 3, N'14', N'11', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (648, 3, N'14', N'12', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (649, 3, N'15', N'1', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (650, 3, N'15', N'2', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (651, 3, N'15', N'3', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (652, 3, N'15', N'4', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (653, 3, N'15', N'5', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (654, 3, N'15', N'6', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (655, 3, N'15', N'7', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (656, 3, N'15', N'8', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (657, 3, N'15', N'9', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (658, 3, N'15', N'10', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (659, 3, N'15', N'11', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (660, 3, N'15', N'12', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (661, 3, N'16', N'1', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (662, 3, N'16', N'2', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (663, 3, N'16', N'3', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (664, 3, N'16', N'4', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (665, 3, N'16', N'5', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (666, 3, N'16', N'6', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (667, 3, N'16', N'7', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (668, 3, N'16', N'8', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (669, 3, N'16', N'9', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (670, 3, N'16', N'10', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (671, 3, N'16', N'11', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (672, 3, N'16', N'12', 192)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (673, 3, N'17', N'1', 193)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (674, 3, N'17', N'2', 194)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (675, 3, N'17', N'3', 195)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (676, 3, N'17', N'4', 196)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (677, 3, N'17', N'5', 197)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (678, 3, N'17', N'6', 198)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (679, 3, N'17', N'7', 199)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (680, 3, N'17', N'8', 200)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (681, 3, N'17', N'9', 201)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (682, 3, N'17', N'10', 202)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (683, 3, N'17', N'11', 203)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (684, 3, N'17', N'12', 204)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (685, 3, N'18', N'1', 205)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (686, 3, N'18', N'2', 206)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (687, 3, N'18', N'3', 207)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (688, 3, N'18', N'4', 208)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (689, 3, N'18', N'5', 209)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (690, 3, N'18', N'6', 210)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (691, 3, N'18', N'7', 211)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (692, 3, N'18', N'8', 212)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (693, 3, N'18', N'9', 213)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (694, 3, N'18', N'10', 214)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (695, 3, N'18', N'11', 215)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (696, 3, N'18', N'12', 216)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (697, 3, N'19', N'1', 217)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (698, 3, N'19', N'2', 218)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (699, 3, N'19', N'3', 219)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (700, 3, N'19', N'4', 220)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (701, 3, N'19', N'5', 221)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (702, 3, N'19', N'6', 222)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (703, 3, N'19', N'7', 223)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (704, 3, N'19', N'8', 224)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (705, 3, N'19', N'9', 225)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (706, 3, N'19', N'10', 226)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (707, 3, N'19', N'11', 227)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (708, 3, N'19', N'12', 228)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (709, 3, N'20', N'1', 229)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (710, 3, N'20', N'2', 230)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (711, 3, N'20', N'3', 231)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (712, 3, N'20', N'4', 232)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (713, 3, N'20', N'5', 233)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (714, 3, N'20', N'6', 234)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (715, 3, N'20', N'7', 235)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (716, 3, N'20', N'8', 236)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (717, 3, N'20', N'9', 237)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (718, 3, N'20', N'10', 238)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (719, 3, N'20', N'11', 239)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (720, 3, N'20', N'12', 240)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (721, 4, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (722, 4, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (723, 4, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (724, 4, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (725, 4, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (726, 4, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (727, 4, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (728, 4, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (729, 4, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (730, 4, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (731, 4, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (732, 4, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (733, 4, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (734, 4, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (735, 4, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (736, 4, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (737, 4, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (738, 4, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (739, 4, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (740, 4, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (741, 4, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (742, 4, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (743, 4, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (744, 4, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (745, 4, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (746, 4, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (747, 4, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (748, 4, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (749, 4, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (750, 4, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (751, 4, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (752, 4, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (753, 4, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (754, 4, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (755, 4, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (756, 4, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (757, 4, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (758, 4, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (759, 4, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (760, 4, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (761, 4, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (762, 4, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (763, 4, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (764, 4, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (765, 4, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (766, 4, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (767, 4, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (768, 4, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (769, 4, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (770, 4, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (771, 4, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (772, 4, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (773, 4, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (774, 4, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (775, 4, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (776, 4, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (777, 4, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (778, 4, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (779, 4, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (780, 4, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (781, 4, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (782, 4, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (783, 4, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (784, 4, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (785, 4, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (786, 4, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (787, 4, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (788, 4, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (789, 4, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (790, 4, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (791, 4, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (792, 4, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (793, 4, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (794, 4, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (795, 4, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (796, 4, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (797, 4, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (798, 4, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (799, 4, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (800, 4, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (801, 4, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (802, 4, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (803, 4, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (804, 4, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (805, 4, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (806, 4, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (807, 4, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (808, 4, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (809, 4, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (810, 4, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (811, 4, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (812, 4, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (813, 4, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (814, 4, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (815, 4, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (816, 4, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (817, 4, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (818, 4, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (819, 4, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (820, 4, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (821, 4, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (822, 4, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (823, 4, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (824, 4, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (825, 4, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (826, 4, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (827, 4, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (828, 4, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (829, 4, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (830, 4, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (831, 4, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (832, 4, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (833, 4, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (834, 4, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (835, 4, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (836, 4, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (837, 4, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (838, 4, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (839, 4, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (840, 4, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (841, 4, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (842, 4, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (843, 4, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (844, 4, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (845, 4, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (846, 4, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (847, 4, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (848, 4, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (849, 4, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (850, 4, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (851, 4, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (852, 4, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (853, 4, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (854, 4, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (855, 4, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (856, 4, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (857, 4, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (858, 4, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (859, 4, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (860, 4, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (861, 4, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (862, 4, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (863, 4, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (864, 4, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (865, 4, N'13', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (866, 4, N'13', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (867, 4, N'13', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (868, 4, N'13', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (869, 4, N'13', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (870, 4, N'13', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (871, 4, N'13', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (872, 4, N'13', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (873, 4, N'13', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (874, 4, N'13', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (875, 4, N'13', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (876, 4, N'13', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (877, 4, N'14', N'1', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (878, 4, N'14', N'2', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (879, 4, N'14', N'3', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (880, 4, N'14', N'4', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (881, 4, N'14', N'5', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (882, 4, N'14', N'6', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (883, 4, N'14', N'7', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (884, 4, N'14', N'8', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (885, 4, N'14', N'9', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (886, 4, N'14', N'10', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (887, 4, N'14', N'11', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (888, 4, N'14', N'12', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (889, 4, N'15', N'1', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (890, 4, N'15', N'2', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (891, 4, N'15', N'3', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (892, 4, N'15', N'4', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (893, 4, N'15', N'5', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (894, 4, N'15', N'6', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (895, 4, N'15', N'7', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (896, 4, N'15', N'8', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (897, 4, N'15', N'9', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (898, 4, N'15', N'10', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (899, 4, N'15', N'11', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (900, 4, N'15', N'12', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (901, 4, N'16', N'1', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (902, 4, N'16', N'2', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (903, 4, N'16', N'3', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (904, 4, N'16', N'4', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (905, 4, N'16', N'5', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (906, 4, N'16', N'6', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (907, 4, N'16', N'7', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (908, 4, N'16', N'8', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (909, 4, N'16', N'9', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (910, 4, N'16', N'10', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (911, 4, N'16', N'11', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (912, 4, N'16', N'12', 192)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (913, 4, N'17', N'1', 193)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (914, 4, N'17', N'2', 194)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (915, 4, N'17', N'3', 195)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (916, 4, N'17', N'4', 196)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (917, 4, N'17', N'5', 197)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (918, 4, N'17', N'6', 198)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (919, 4, N'17', N'7', 199)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (920, 4, N'17', N'8', 200)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (921, 4, N'17', N'9', 201)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (922, 4, N'17', N'10', 202)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (923, 4, N'17', N'11', 203)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (924, 4, N'17', N'12', 204)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (925, 4, N'18', N'1', 205)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (926, 4, N'18', N'2', 206)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (927, 4, N'18', N'3', 207)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (928, 4, N'18', N'4', 208)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (929, 4, N'18', N'5', 209)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (930, 4, N'18', N'6', 210)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (931, 4, N'18', N'7', 211)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (932, 4, N'18', N'8', 212)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (933, 4, N'18', N'9', 213)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (934, 4, N'18', N'10', 214)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (935, 4, N'18', N'11', 215)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (936, 4, N'18', N'12', 216)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (937, 4, N'19', N'1', 217)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (938, 4, N'19', N'2', 218)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (939, 4, N'19', N'3', 219)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (940, 4, N'19', N'4', 220)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (941, 4, N'19', N'5', 221)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (942, 4, N'19', N'6', 222)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (943, 4, N'19', N'7', 223)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (944, 4, N'19', N'8', 224)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (945, 4, N'19', N'9', 225)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (946, 4, N'19', N'10', 226)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (947, 4, N'19', N'11', 227)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (948, 4, N'19', N'12', 228)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (949, 4, N'20', N'1', 229)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (950, 4, N'20', N'2', 230)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (951, 4, N'20', N'3', 231)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (952, 4, N'20', N'4', 232)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (953, 4, N'20', N'5', 233)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (954, 4, N'20', N'6', 234)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (955, 4, N'20', N'7', 235)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (956, 4, N'20', N'8', 236)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (957, 4, N'20', N'9', 237)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (958, 4, N'20', N'10', 238)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (959, 4, N'20', N'11', 239)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (960, 4, N'20', N'12', 240)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (961, 5, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (962, 5, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (963, 5, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (964, 5, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (965, 5, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (966, 5, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (967, 5, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (968, 5, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (969, 6, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (970, 6, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (971, 6, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (972, 6, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (973, 5, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (974, 5, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (975, 5, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (976, 5, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (977, 5, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (978, 5, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (979, 5, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (980, 5, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (981, 6, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (982, 6, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (983, 6, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (984, 6, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (985, 5, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (986, 5, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (987, 5, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (988, 5, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (989, 5, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (990, 5, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (991, 5, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (992, 5, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (993, 6, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (994, 6, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (995, 6, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (996, 6, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (997, 5, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (998, 5, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (999, 5, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1000, 5, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1001, 5, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1002, 5, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1003, 5, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1004, 5, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1005, 6, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1006, 6, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1007, 6, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1008, 6, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1009, 5, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1010, 5, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1011, 5, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1012, 5, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1013, 5, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1014, 5, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1015, 5, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1016, 5, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1017, 6, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1018, 6, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1019, 6, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1020, 6, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1021, 5, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1022, 5, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1023, 5, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1024, 5, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1025, 5, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1026, 5, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1027, 5, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1028, 5, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1029, 6, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1030, 6, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1031, 6, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1032, 6, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1033, 5, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1034, 5, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1035, 5, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1036, 5, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1037, 5, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1038, 5, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1039, 5, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1040, 5, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1041, 6, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1042, 6, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1043, 6, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1044, 6, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1045, 5, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1046, 5, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1047, 5, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1048, 5, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1049, 5, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1050, 5, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1051, 5, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1052, 5, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1053, 6, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1054, 6, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1055, 6, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1056, 6, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1057, 5, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1058, 5, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1059, 5, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1060, 5, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1061, 5, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1062, 5, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1063, 5, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1064, 5, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1065, 6, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1066, 6, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1067, 6, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1068, 6, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1069, 5, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1070, 5, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1071, 5, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1072, 5, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1073, 5, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1074, 5, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1075, 5, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1076, 5, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1077, 6, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1078, 6, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1079, 6, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1080, 6, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1081, 5, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1082, 5, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1083, 5, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1084, 5, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1085, 5, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1086, 5, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1087, 5, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1088, 5, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1089, 6, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1090, 6, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1091, 6, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1092, 6, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1093, 5, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1094, 5, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1095, 5, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1096, 5, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1097, 5, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1098, 5, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1099, 5, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1100, 5, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1101, 6, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1102, 6, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1103, 6, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1104, 6, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1105, 7, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1106, 7, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1107, 7, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1108, 7, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1109, 7, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1110, 7, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1111, 7, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1112, 7, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1113, 8, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1114, 8, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1115, 8, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1116, 8, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1117, 7, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1118, 7, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1119, 7, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1120, 7, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1121, 7, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1122, 7, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1123, 7, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1124, 7, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1125, 8, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1126, 8, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1127, 8, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1128, 8, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1129, 7, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1130, 7, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1131, 7, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1132, 7, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1133, 7, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1134, 7, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1135, 7, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1136, 7, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1137, 8, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1138, 8, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1139, 8, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1140, 8, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1141, 7, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1142, 7, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1143, 7, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1144, 7, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1145, 7, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1146, 7, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1147, 7, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1148, 7, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1149, 8, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1150, 8, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1151, 8, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1152, 8, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1153, 7, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1154, 7, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1155, 7, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1156, 7, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1157, 7, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1158, 7, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1159, 7, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1160, 7, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1161, 8, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1162, 8, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1163, 8, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1164, 8, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1165, 7, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1166, 7, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1167, 7, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1168, 7, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1169, 7, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1170, 7, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1171, 7, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1172, 7, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1173, 8, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1174, 8, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1175, 8, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1176, 8, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1177, 7, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1178, 7, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1179, 7, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1180, 7, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1181, 7, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1182, 7, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1183, 7, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1184, 7, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1185, 8, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1186, 8, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1187, 8, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1188, 8, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1189, 7, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1190, 7, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1191, 7, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1192, 7, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1193, 7, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1194, 7, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1195, 7, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1196, 7, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1197, 8, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1198, 8, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1199, 8, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1200, 8, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1201, 7, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1202, 7, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1203, 7, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1204, 7, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1205, 7, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1206, 7, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1207, 7, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1208, 7, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1209, 8, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1210, 8, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1211, 8, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1212, 8, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1213, 7, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1214, 7, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1215, 7, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1216, 7, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1217, 7, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1218, 7, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1219, 7, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1220, 7, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1221, 8, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1222, 8, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1223, 8, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1224, 8, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1225, 7, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1226, 7, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1227, 7, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1228, 7, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1229, 7, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1230, 7, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1231, 7, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1232, 7, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1233, 8, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1234, 8, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1235, 8, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1236, 8, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1237, 7, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1238, 7, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1239, 7, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1240, 7, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1241, 7, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1242, 7, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1243, 7, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1244, 7, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1245, 8, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1246, 8, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1247, 8, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1248, 8, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1249, 9, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1250, 9, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1251, 9, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1252, 9, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1253, 9, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1254, 9, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1255, 9, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1256, 9, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1257, 10, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1258, 10, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1259, 10, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1260, 10, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1261, 9, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1262, 9, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1263, 9, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1264, 9, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1265, 9, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1266, 9, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1267, 9, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1268, 9, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1269, 10, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1270, 10, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1271, 10, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1272, 10, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1273, 9, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1274, 9, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1275, 9, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1276, 9, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1277, 9, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1278, 9, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1279, 9, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1280, 9, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1281, 10, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1282, 10, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1283, 10, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1284, 10, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1285, 9, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1286, 9, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1287, 9, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1288, 9, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1289, 9, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1290, 9, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1291, 9, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1292, 9, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1293, 10, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1294, 10, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1295, 10, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1296, 10, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1297, 9, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1298, 9, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1299, 9, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1300, 9, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1301, 9, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1302, 9, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1303, 9, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1304, 9, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1305, 10, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1306, 10, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1307, 10, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1308, 10, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1309, 9, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1310, 9, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1311, 9, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1312, 9, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1313, 9, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1314, 9, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1315, 9, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1316, 9, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1317, 10, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1318, 10, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1319, 10, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1320, 10, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1321, 9, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1322, 9, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1323, 9, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1324, 9, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1325, 9, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1326, 9, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1327, 9, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1328, 9, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1329, 10, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1330, 10, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1331, 10, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1332, 10, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1333, 9, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1334, 9, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1335, 9, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1336, 9, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1337, 9, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1338, 9, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1339, 9, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1340, 9, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1341, 10, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1342, 10, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1343, 10, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1344, 10, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1345, 9, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1346, 9, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1347, 9, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1348, 9, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1349, 9, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1350, 9, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1351, 9, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1352, 9, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1353, 10, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1354, 10, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1355, 10, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1356, 10, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1357, 9, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1358, 9, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1359, 9, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1360, 9, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1361, 9, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1362, 9, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1363, 9, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1364, 9, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1365, 10, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1366, 10, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1367, 10, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1368, 10, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1369, 9, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1370, 9, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1371, 9, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1372, 9, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1373, 9, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1374, 9, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1375, 9, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1376, 9, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1377, 10, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1378, 10, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1379, 10, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1380, 10, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1381, 9, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1382, 9, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1383, 9, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1384, 9, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1385, 9, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1386, 9, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1387, 9, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1388, 9, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1389, 10, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1390, 10, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1391, 10, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1392, 10, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1393, 11, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1394, 11, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1395, 11, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1396, 11, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1397, 11, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1398, 11, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1399, 11, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1400, 11, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1401, 12, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1402, 12, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1403, 12, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1404, 12, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1405, 11, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1406, 11, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1407, 11, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1408, 11, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1409, 11, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1410, 11, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1411, 11, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1412, 11, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1413, 12, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1414, 12, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1415, 12, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1416, 12, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1417, 11, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1418, 11, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1419, 11, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1420, 11, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1421, 11, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1422, 11, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1423, 11, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1424, 11, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1425, 12, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1426, 12, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1427, 12, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1428, 12, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1429, 11, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1430, 11, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1431, 11, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1432, 11, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1433, 11, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1434, 11, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1435, 11, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1436, 11, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1437, 12, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1438, 12, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1439, 12, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1440, 12, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1441, 11, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1442, 11, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1443, 11, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1444, 11, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1445, 11, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1446, 11, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1447, 11, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1448, 11, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1449, 12, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1450, 12, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1451, 12, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1452, 12, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1453, 11, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1454, 11, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1455, 11, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1456, 11, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1457, 11, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1458, 11, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1459, 11, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1460, 11, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1461, 12, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1462, 12, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1463, 12, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1464, 12, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1465, 11, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1466, 11, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1467, 11, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1468, 11, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1469, 11, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1470, 11, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1471, 11, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1472, 11, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1473, 12, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1474, 12, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1475, 12, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1476, 12, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1477, 11, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1478, 11, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1479, 11, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1480, 11, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1481, 11, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1482, 11, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1483, 11, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1484, 11, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1485, 12, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1486, 12, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1487, 12, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1488, 12, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1489, 11, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1490, 11, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1491, 11, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1492, 11, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1493, 11, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1494, 11, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1495, 11, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1496, 11, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1497, 12, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1498, 12, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1499, 12, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1500, 12, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1501, 11, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1502, 11, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1503, 11, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1504, 11, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1505, 11, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1506, 11, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1507, 11, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1508, 11, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1509, 12, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1510, 12, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1511, 12, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1512, 12, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1513, 11, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1514, 11, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1515, 11, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1516, 11, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1517, 11, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1518, 11, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1519, 11, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1520, 11, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1521, 12, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1522, 12, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1523, 12, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1524, 12, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1525, 11, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1526, 11, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1527, 11, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1528, 11, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1529, 11, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1530, 11, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1531, 11, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1532, 11, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1533, 12, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1534, 12, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1535, 12, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1536, 12, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1537, 13, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1538, 13, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1539, 13, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1540, 13, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1541, 13, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1542, 13, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1543, 13, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1544, 13, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1545, 14, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1546, 14, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1547, 14, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1548, 14, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1549, 13, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1550, 13, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1551, 13, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1552, 13, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1553, 13, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1554, 13, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1555, 13, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1556, 13, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1557, 14, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1558, 14, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1559, 14, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1560, 14, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1561, 13, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1562, 13, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1563, 13, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1564, 13, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1565, 13, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1566, 13, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1567, 13, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1568, 13, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1569, 14, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1570, 14, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1571, 14, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1572, 14, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1573, 13, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1574, 13, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1575, 13, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1576, 13, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1577, 13, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1578, 13, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1579, 13, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1580, 13, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1581, 14, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1582, 14, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1583, 14, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1584, 14, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1585, 13, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1586, 13, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1587, 13, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1588, 13, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1589, 13, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1590, 13, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1591, 13, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1592, 13, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1593, 14, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1594, 14, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1595, 14, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1596, 14, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1597, 13, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1598, 13, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1599, 13, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1600, 13, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1601, 13, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1602, 13, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1603, 13, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1604, 13, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1605, 14, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1606, 14, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1607, 14, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1608, 14, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1609, 13, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1610, 13, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1611, 13, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1612, 13, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1613, 13, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1614, 13, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1615, 13, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1616, 13, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1617, 14, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1618, 14, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1619, 14, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1620, 14, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1621, 13, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1622, 13, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1623, 13, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1624, 13, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1625, 13, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1626, 13, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1627, 13, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1628, 13, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1629, 14, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1630, 14, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1631, 14, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1632, 14, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1633, 13, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1634, 13, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1635, 13, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1636, 13, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1637, 13, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1638, 13, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1639, 13, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1640, 13, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1641, 14, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1642, 14, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1643, 14, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1644, 14, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1645, 13, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1646, 13, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1647, 13, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1648, 13, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1649, 13, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1650, 13, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1651, 13, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1652, 13, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1653, 14, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1654, 14, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1655, 14, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1656, 14, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1657, 13, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1658, 13, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1659, 13, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1660, 13, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1661, 13, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1662, 13, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1663, 13, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1664, 13, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1665, 14, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1666, 14, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1667, 14, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1668, 14, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1669, 13, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1670, 13, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1671, 13, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1672, 13, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1673, 13, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1674, 13, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1675, 13, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1676, 13, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1677, 14, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1678, 14, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1679, 14, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1680, 14, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1681, 15, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1682, 15, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1683, 15, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1684, 15, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1685, 15, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1686, 15, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1687, 15, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1688, 15, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1689, 16, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1690, 16, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1691, 16, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1692, 16, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1693, 15, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1694, 15, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1695, 15, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1696, 15, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1697, 15, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1698, 15, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1699, 15, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1700, 15, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1701, 16, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1702, 16, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1703, 16, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1704, 16, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1705, 15, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1706, 15, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1707, 15, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1708, 15, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1709, 15, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1710, 15, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1711, 15, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1712, 15, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1713, 16, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1714, 16, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1715, 16, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1716, 16, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1717, 15, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1718, 15, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1719, 15, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1720, 15, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1721, 15, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1722, 15, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1723, 15, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1724, 15, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1725, 16, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1726, 16, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1727, 16, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1728, 16, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1729, 15, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1730, 15, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1731, 15, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1732, 15, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1733, 15, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1734, 15, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1735, 15, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1736, 15, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1737, 16, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1738, 16, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1739, 16, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1740, 16, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1741, 15, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1742, 15, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1743, 15, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1744, 15, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1745, 15, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1746, 15, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1747, 15, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1748, 15, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1749, 16, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1750, 16, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1751, 16, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1752, 16, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1753, 15, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1754, 15, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1755, 15, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1756, 15, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1757, 15, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1758, 15, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1759, 15, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1760, 15, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1761, 16, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1762, 16, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1763, 16, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1764, 16, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1765, 15, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1766, 15, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1767, 15, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1768, 15, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1769, 15, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1770, 15, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1771, 15, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1772, 15, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1773, 16, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1774, 16, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1775, 16, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1776, 16, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1777, 15, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1778, 15, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1779, 15, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1780, 15, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1781, 15, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1782, 15, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1783, 15, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1784, 15, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1785, 16, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1786, 16, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1787, 16, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1788, 16, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1789, 15, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1790, 15, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1791, 15, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1792, 15, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1793, 15, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1794, 15, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1795, 15, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1796, 15, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1797, 16, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1798, 16, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1799, 16, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1800, 16, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1801, 15, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1802, 15, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1803, 15, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1804, 15, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1805, 15, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1806, 15, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1807, 15, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1808, 15, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1809, 16, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1810, 16, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1811, 16, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1812, 16, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1813, 15, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1814, 15, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1815, 15, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1816, 15, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1817, 15, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1818, 15, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1819, 15, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1820, 15, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1821, 16, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1822, 16, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1823, 16, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1824, 16, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1825, 17, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1826, 17, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1827, 17, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1828, 17, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1829, 17, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1830, 17, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1831, 17, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1832, 17, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1833, 18, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1834, 18, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1835, 18, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1836, 18, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1837, 17, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1838, 17, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1839, 17, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1840, 17, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1841, 17, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1842, 17, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1843, 17, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1844, 17, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1845, 18, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1846, 18, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1847, 18, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1848, 18, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1849, 17, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1850, 17, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1851, 17, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1852, 17, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1853, 17, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1854, 17, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1855, 17, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1856, 17, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1857, 18, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1858, 18, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1859, 18, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1860, 18, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1861, 17, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1862, 17, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1863, 17, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1864, 17, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1865, 17, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1866, 17, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1867, 17, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1868, 17, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1869, 18, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1870, 18, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1871, 18, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1872, 18, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1873, 17, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1874, 17, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1875, 17, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1876, 17, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1877, 17, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1878, 17, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1879, 17, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1880, 17, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1881, 18, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1882, 18, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1883, 18, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1884, 18, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1885, 17, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1886, 17, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1887, 17, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1888, 17, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1889, 17, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1890, 17, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1891, 17, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1892, 17, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1893, 18, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1894, 18, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1895, 18, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1896, 18, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1897, 17, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1898, 17, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1899, 17, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1900, 17, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1901, 17, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1902, 17, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1903, 17, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1904, 17, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1905, 18, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1906, 18, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1907, 18, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1908, 18, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1909, 17, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1910, 17, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1911, 17, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1912, 17, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1913, 17, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1914, 17, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1915, 17, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1916, 17, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1917, 18, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1918, 18, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1919, 18, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1920, 18, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1921, 17, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1922, 17, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1923, 17, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1924, 17, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1925, 17, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1926, 17, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1927, 17, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1928, 17, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1929, 18, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1930, 18, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1931, 18, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1932, 18, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1933, 17, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1934, 17, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1935, 17, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1936, 17, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1937, 17, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1938, 17, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1939, 17, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1940, 17, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1941, 18, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1942, 18, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1943, 18, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1944, 18, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1945, 17, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1946, 17, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1947, 17, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1948, 17, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1949, 17, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1950, 17, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1951, 17, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1952, 17, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1953, 18, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1954, 18, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1955, 18, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1956, 18, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1957, 17, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1958, 17, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1959, 17, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1960, 17, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1961, 17, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1962, 17, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1963, 17, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1964, 17, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1965, 18, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1966, 18, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1967, 18, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1968, 18, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1969, 19, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1970, 19, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1971, 19, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1972, 19, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1973, 19, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1974, 19, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1975, 19, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1976, 19, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1977, 20, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1978, 20, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1979, 20, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1980, 20, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1981, 19, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1982, 19, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1983, 19, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1984, 19, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1985, 19, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1986, 19, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1987, 19, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1988, 19, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1989, 20, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1990, 20, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1991, 20, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1992, 20, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1993, 19, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1994, 19, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1995, 19, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1996, 19, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1997, 19, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1998, 19, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (1999, 19, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2000, 19, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2001, 20, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2002, 20, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2003, 20, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2004, 20, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2005, 19, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2006, 19, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2007, 19, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2008, 19, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2009, 19, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2010, 19, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2011, 19, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2012, 19, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2013, 20, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2014, 20, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2015, 20, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2016, 20, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2017, 19, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2018, 19, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2019, 19, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2020, 19, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2021, 19, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2022, 19, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2023, 19, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2024, 19, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2025, 20, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2026, 20, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2027, 20, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2028, 20, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2029, 19, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2030, 19, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2031, 19, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2032, 19, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2033, 19, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2034, 19, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2035, 19, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2036, 19, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2037, 20, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2038, 20, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2039, 20, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2040, 20, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2041, 19, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2042, 19, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2043, 19, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2044, 19, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2045, 19, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2046, 19, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2047, 19, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2048, 19, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2049, 20, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2050, 20, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2051, 20, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2052, 20, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2053, 19, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2054, 19, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2055, 19, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2056, 19, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2057, 19, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2058, 19, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2059, 19, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2060, 19, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2061, 20, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2062, 20, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2063, 20, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2064, 20, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2065, 19, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2066, 19, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2067, 19, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2068, 19, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2069, 19, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2070, 19, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2071, 19, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2072, 19, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2073, 20, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2074, 20, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2075, 20, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2076, 20, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2077, 19, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2078, 19, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2079, 19, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2080, 19, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2081, 19, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2082, 19, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2083, 19, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2084, 19, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2085, 20, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2086, 20, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2087, 20, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2088, 20, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2089, 19, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2090, 19, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2091, 19, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2092, 19, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2093, 19, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2094, 19, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2095, 19, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2096, 19, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2097, 20, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2098, 20, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2099, 20, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2100, 20, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2101, 19, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2102, 19, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2103, 19, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2104, 19, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2105, 19, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2106, 19, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2107, 19, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2108, 19, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2109, 20, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2110, 20, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2111, 20, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2112, 20, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2113, 21, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2114, 21, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2115, 21, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2116, 21, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2117, 21, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2118, 21, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2119, 21, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2120, 21, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2121, 22, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2122, 22, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2123, 22, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2124, 22, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2125, 21, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2126, 21, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2127, 21, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2128, 21, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2129, 21, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2130, 21, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2131, 21, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2132, 21, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2133, 22, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2134, 22, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2135, 22, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2136, 22, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2137, 21, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2138, 21, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2139, 21, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2140, 21, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2141, 21, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2142, 21, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2143, 21, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2144, 21, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2145, 22, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2146, 22, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2147, 22, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2148, 22, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2149, 21, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2150, 21, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2151, 21, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2152, 21, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2153, 21, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2154, 21, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2155, 21, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2156, 21, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2157, 22, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2158, 22, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2159, 22, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2160, 22, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2161, 21, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2162, 21, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2163, 21, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2164, 21, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2165, 21, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2166, 21, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2167, 21, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2168, 21, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2169, 22, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2170, 22, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2171, 22, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2172, 22, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2173, 21, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2174, 21, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2175, 21, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2176, 21, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2177, 21, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2178, 21, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2179, 21, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2180, 21, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2181, 22, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2182, 22, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2183, 22, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2184, 22, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2185, 21, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2186, 21, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2187, 21, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2188, 21, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2189, 21, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2190, 21, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2191, 21, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2192, 21, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2193, 22, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2194, 22, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2195, 22, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2196, 22, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2197, 21, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2198, 21, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2199, 21, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2200, 21, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2201, 21, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2202, 21, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2203, 21, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2204, 21, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2205, 22, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2206, 22, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2207, 22, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2208, 22, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2209, 21, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2210, 21, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2211, 21, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2212, 21, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2213, 21, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2214, 21, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2215, 21, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2216, 21, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2217, 22, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2218, 22, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2219, 22, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2220, 22, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2221, 21, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2222, 21, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2223, 21, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2224, 21, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2225, 21, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2226, 21, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2227, 21, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2228, 21, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2229, 22, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2230, 22, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2231, 22, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2232, 22, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2233, 21, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2234, 21, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2235, 21, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2236, 21, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2237, 21, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2238, 21, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2239, 21, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2240, 21, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2241, 22, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2242, 22, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2243, 22, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2244, 22, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2245, 21, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2246, 21, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2247, 21, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2248, 21, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2249, 21, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2250, 21, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2251, 21, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2252, 21, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2253, 22, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2254, 22, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2255, 22, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2256, 22, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2257, 23, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2258, 23, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2259, 23, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2260, 23, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2261, 23, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2262, 23, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2263, 23, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2264, 23, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2265, 24, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2266, 24, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2267, 24, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2268, 24, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2269, 23, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2270, 23, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2271, 23, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2272, 23, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2273, 23, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2274, 23, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2275, 23, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2276, 23, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2277, 24, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2278, 24, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2279, 24, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2280, 24, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2281, 23, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2282, 23, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2283, 23, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2284, 23, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2285, 23, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2286, 23, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2287, 23, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2288, 23, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2289, 24, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2290, 24, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2291, 24, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2292, 24, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2293, 23, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2294, 23, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2295, 23, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2296, 23, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2297, 23, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2298, 23, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2299, 23, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2300, 23, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2301, 24, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2302, 24, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2303, 24, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2304, 24, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2305, 23, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2306, 23, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2307, 23, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2308, 23, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2309, 23, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2310, 23, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2311, 23, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2312, 23, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2313, 24, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2314, 24, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2315, 24, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2316, 24, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2317, 23, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2318, 23, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2319, 23, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2320, 23, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2321, 23, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2322, 23, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2323, 23, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2324, 23, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2325, 24, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2326, 24, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2327, 24, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2328, 24, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2329, 23, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2330, 23, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2331, 23, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2332, 23, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2333, 23, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2334, 23, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2335, 23, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2336, 23, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2337, 24, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2338, 24, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2339, 24, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2340, 24, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2341, 23, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2342, 23, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2343, 23, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2344, 23, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2345, 23, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2346, 23, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2347, 23, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2348, 23, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2349, 24, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2350, 24, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2351, 24, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2352, 24, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2353, 23, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2354, 23, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2355, 23, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2356, 23, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2357, 23, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2358, 23, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2359, 23, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2360, 23, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2361, 24, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2362, 24, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2363, 24, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2364, 24, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2365, 23, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2366, 23, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2367, 23, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2368, 23, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2369, 23, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2370, 23, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2371, 23, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2372, 23, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2373, 24, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2374, 24, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2375, 24, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2376, 24, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2377, 23, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2378, 23, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2379, 23, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2380, 23, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2381, 23, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2382, 23, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2383, 23, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2384, 23, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2385, 24, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2386, 24, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2387, 24, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2388, 24, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2389, 23, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2390, 23, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2391, 23, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2392, 23, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2393, 23, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2394, 23, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2395, 23, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2396, 23, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2397, 24, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2398, 24, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2399, 24, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2400, 24, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2401, 25, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2402, 25, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2403, 25, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2404, 25, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2405, 25, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2406, 25, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2407, 25, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2408, 25, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2409, 26, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2410, 26, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2411, 26, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2412, 26, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2413, 25, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2414, 25, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2415, 25, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2416, 25, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2417, 25, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2418, 25, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2419, 25, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2420, 25, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2421, 26, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2422, 26, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2423, 26, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2424, 26, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2425, 25, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2426, 25, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2427, 25, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2428, 25, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2429, 25, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2430, 25, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2431, 25, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2432, 25, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2433, 26, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2434, 26, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2435, 26, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2436, 26, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2437, 25, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2438, 25, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2439, 25, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2440, 25, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2441, 25, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2442, 25, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2443, 25, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2444, 25, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2445, 26, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2446, 26, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2447, 26, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2448, 26, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2449, 25, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2450, 25, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2451, 25, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2452, 25, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2453, 25, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2454, 25, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2455, 25, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2456, 25, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2457, 26, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2458, 26, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2459, 26, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2460, 26, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2461, 25, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2462, 25, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2463, 25, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2464, 25, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2465, 25, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2466, 25, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2467, 25, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2468, 25, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2469, 26, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2470, 26, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2471, 26, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2472, 26, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2473, 25, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2474, 25, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2475, 25, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2476, 25, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2477, 25, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2478, 25, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2479, 25, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2480, 25, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2481, 26, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2482, 26, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2483, 26, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2484, 26, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2485, 25, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2486, 25, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2487, 25, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2488, 25, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2489, 25, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2490, 25, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2491, 25, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2492, 25, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2493, 26, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2494, 26, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2495, 26, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2496, 26, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2497, 25, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2498, 25, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2499, 25, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2500, 25, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2501, 25, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2502, 25, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2503, 25, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2504, 25, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2505, 26, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2506, 26, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2507, 26, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2508, 26, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2509, 25, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2510, 25, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2511, 25, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2512, 25, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2513, 25, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2514, 25, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2515, 25, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2516, 25, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2517, 26, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2518, 26, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2519, 26, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2520, 26, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2521, 25, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2522, 25, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2523, 25, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2524, 25, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2525, 25, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2526, 25, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2527, 25, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2528, 25, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2529, 26, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2530, 26, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2531, 26, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2532, 26, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2533, 25, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2534, 25, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2535, 25, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2536, 25, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2537, 25, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2538, 25, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2539, 25, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2540, 25, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2541, 26, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2542, 26, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2543, 26, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2544, 26, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2545, 27, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2546, 27, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2547, 27, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2548, 27, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2549, 27, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2550, 27, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2551, 27, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2552, 27, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2553, 28, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2554, 28, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2555, 28, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2556, 28, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2557, 27, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2558, 27, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2559, 27, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2560, 27, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2561, 27, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2562, 27, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2563, 27, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2564, 27, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2565, 28, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2566, 28, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2567, 28, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2568, 28, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2569, 27, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2570, 27, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2571, 27, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2572, 27, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2573, 27, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2574, 27, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2575, 27, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2576, 27, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2577, 28, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2578, 28, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2579, 28, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2580, 28, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2581, 27, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2582, 27, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2583, 27, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2584, 27, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2585, 27, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2586, 27, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2587, 27, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2588, 27, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2589, 28, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2590, 28, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2591, 28, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2592, 28, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2593, 27, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2594, 27, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2595, 27, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2596, 27, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2597, 27, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2598, 27, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2599, 27, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2600, 27, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2601, 28, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2602, 28, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2603, 28, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2604, 28, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2605, 27, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2606, 27, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2607, 27, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2608, 27, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2609, 27, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2610, 27, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2611, 27, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2612, 27, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2613, 28, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2614, 28, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2615, 28, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2616, 28, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2617, 27, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2618, 27, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2619, 27, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2620, 27, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2621, 27, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2622, 27, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2623, 27, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2624, 27, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2625, 28, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2626, 28, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2627, 28, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2628, 28, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2629, 27, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2630, 27, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2631, 27, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2632, 27, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2633, 27, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2634, 27, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2635, 27, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2636, 27, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2637, 28, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2638, 28, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2639, 28, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2640, 28, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2641, 27, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2642, 27, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2643, 27, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2644, 27, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2645, 27, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2646, 27, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2647, 27, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2648, 27, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2649, 28, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2650, 28, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2651, 28, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2652, 28, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2653, 27, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2654, 27, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2655, 27, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2656, 27, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2657, 27, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2658, 27, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2659, 27, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2660, 27, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2661, 28, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2662, 28, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2663, 28, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2664, 28, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2665, 27, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2666, 27, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2667, 27, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2668, 27, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2669, 27, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2670, 27, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2671, 27, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2672, 27, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2673, 28, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2674, 28, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2675, 28, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2676, 28, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2677, 27, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2678, 27, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2679, 27, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2680, 27, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2681, 27, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2682, 27, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2683, 27, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2684, 27, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2685, 28, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2686, 28, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2687, 28, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2688, 28, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2689, 29, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2690, 29, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2691, 29, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2692, 29, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2693, 29, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2694, 29, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2695, 29, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2696, 29, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2697, 30, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2698, 30, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2699, 30, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2700, 30, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2701, 29, N'2', N'1', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2702, 29, N'2', N'2', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2703, 29, N'2', N'3', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2704, 29, N'2', N'4', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2705, 29, N'2', N'5', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2706, 29, N'2', N'6', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2707, 29, N'2', N'7', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2708, 29, N'2', N'8', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2709, 30, N'2', N'9', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2710, 30, N'2', N'10', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2711, 30, N'2', N'11', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2712, 30, N'2', N'12', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2713, 29, N'3', N'1', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2714, 29, N'3', N'2', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2715, 29, N'3', N'3', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2716, 29, N'3', N'4', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2717, 29, N'3', N'5', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2718, 29, N'3', N'6', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2719, 29, N'3', N'7', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2720, 29, N'3', N'8', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2721, 30, N'3', N'9', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2722, 30, N'3', N'10', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2723, 30, N'3', N'11', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2724, 30, N'3', N'12', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2725, 29, N'4', N'1', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2726, 29, N'4', N'2', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2727, 29, N'4', N'3', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2728, 29, N'4', N'4', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2729, 29, N'4', N'5', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2730, 29, N'4', N'6', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2731, 29, N'4', N'7', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2732, 29, N'4', N'8', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2733, 30, N'4', N'9', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2734, 30, N'4', N'10', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2735, 30, N'4', N'11', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2736, 30, N'4', N'12', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2737, 29, N'5', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2738, 29, N'5', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2739, 29, N'5', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2740, 29, N'5', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2741, 29, N'5', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2742, 29, N'5', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2743, 29, N'5', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2744, 29, N'5', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2745, 30, N'5', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2746, 30, N'5', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2747, 30, N'5', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2748, 30, N'5', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2749, 29, N'6', N'1', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2750, 29, N'6', N'2', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2751, 29, N'6', N'3', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2752, 29, N'6', N'4', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2753, 29, N'6', N'5', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2754, 29, N'6', N'6', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2755, 29, N'6', N'7', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2756, 29, N'6', N'8', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2757, 30, N'6', N'9', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2758, 30, N'6', N'10', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2759, 30, N'6', N'11', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2760, 30, N'6', N'12', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2761, 29, N'7', N'1', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2762, 29, N'7', N'2', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2763, 29, N'7', N'3', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2764, 29, N'7', N'4', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2765, 29, N'7', N'5', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2766, 29, N'7', N'6', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2767, 29, N'7', N'7', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2768, 29, N'7', N'8', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2769, 30, N'7', N'9', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2770, 30, N'7', N'10', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2771, 30, N'7', N'11', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2772, 30, N'7', N'12', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2773, 29, N'8', N'1', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2774, 29, N'8', N'2', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2775, 29, N'8', N'3', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2776, 29, N'8', N'4', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2777, 29, N'8', N'5', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2778, 29, N'8', N'6', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2779, 29, N'8', N'7', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2780, 29, N'8', N'8', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2781, 30, N'8', N'9', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2782, 30, N'8', N'10', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2783, 30, N'8', N'11', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2784, 30, N'8', N'12', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2785, 29, N'9', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2786, 29, N'9', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2787, 29, N'9', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2788, 29, N'9', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2789, 29, N'9', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2790, 29, N'9', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2791, 29, N'9', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2792, 29, N'9', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2793, 30, N'9', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2794, 30, N'9', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2795, 30, N'9', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2796, 30, N'9', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2797, 29, N'10', N'1', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2798, 29, N'10', N'2', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2799, 29, N'10', N'3', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2800, 29, N'10', N'4', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2801, 29, N'10', N'5', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2802, 29, N'10', N'6', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2803, 29, N'10', N'7', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2804, 29, N'10', N'8', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2805, 30, N'10', N'9', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2806, 30, N'10', N'10', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2807, 30, N'10', N'11', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2808, 30, N'10', N'12', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2809, 29, N'11', N'1', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2810, 29, N'11', N'2', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2811, 29, N'11', N'3', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2812, 29, N'11', N'4', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2813, 29, N'11', N'5', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2814, 29, N'11', N'6', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2815, 29, N'11', N'7', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2816, 29, N'11', N'8', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2817, 30, N'11', N'9', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2818, 30, N'11', N'10', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2819, 30, N'11', N'11', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2820, 30, N'11', N'12', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2821, 29, N'12', N'1', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2822, 29, N'12', N'2', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2823, 29, N'12', N'3', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2824, 29, N'12', N'4', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2825, 29, N'12', N'5', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2826, 29, N'12', N'6', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2827, 29, N'12', N'7', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2828, 29, N'12', N'8', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2829, 30, N'12', N'9', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2830, 30, N'12', N'10', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2831, 30, N'12', N'11', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2832, 30, N'12', N'12', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2833, 31, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2834, 31, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2835, 31, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2836, 31, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2837, 31, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2838, 31, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2839, 32, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2840, 32, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2841, 32, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2842, 32, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2843, 32, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2844, 32, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2845, 33, N'1', N'13', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2846, 33, N'1', N'14', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2847, 33, N'1', N'15', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2848, 33, N'1', N'16', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2849, 31, N'2', N'1', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2850, 31, N'2', N'2', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2851, 31, N'2', N'3', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2852, 31, N'2', N'4', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2853, 31, N'2', N'5', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2854, 31, N'2', N'6', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2855, 32, N'2', N'7', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2856, 32, N'2', N'8', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2857, 32, N'2', N'9', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2858, 32, N'2', N'10', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2859, 32, N'2', N'11', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2860, 32, N'2', N'12', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2861, 33, N'2', N'13', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2862, 33, N'2', N'14', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2863, 33, N'2', N'15', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2864, 33, N'2', N'16', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2865, 31, N'3', N'1', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2866, 31, N'3', N'2', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2867, 31, N'3', N'3', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2868, 31, N'3', N'4', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2869, 31, N'3', N'5', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2870, 31, N'3', N'6', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2871, 32, N'3', N'7', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2872, 32, N'3', N'8', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2873, 32, N'3', N'9', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2874, 32, N'3', N'10', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2875, 32, N'3', N'11', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2876, 32, N'3', N'12', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2877, 33, N'3', N'13', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2878, 33, N'3', N'14', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2879, 33, N'3', N'15', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2880, 33, N'3', N'16', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2881, 31, N'4', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2882, 31, N'4', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2883, 31, N'4', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2884, 31, N'4', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2885, 31, N'4', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2886, 31, N'4', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2887, 32, N'4', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2888, 32, N'4', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2889, 32, N'4', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2890, 32, N'4', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2891, 32, N'4', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2892, 32, N'4', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2893, 33, N'4', N'13', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2894, 33, N'4', N'14', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2895, 33, N'4', N'15', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2896, 33, N'4', N'16', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2897, 31, N'5', N'1', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2898, 31, N'5', N'2', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2899, 31, N'5', N'3', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2900, 31, N'5', N'4', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2901, 31, N'5', N'5', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2902, 31, N'5', N'6', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2903, 32, N'5', N'7', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2904, 32, N'5', N'8', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2905, 32, N'5', N'9', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2906, 32, N'5', N'10', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2907, 32, N'5', N'11', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2908, 32, N'5', N'12', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2909, 33, N'5', N'13', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2910, 33, N'5', N'14', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2911, 33, N'5', N'15', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2912, 33, N'5', N'16', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2913, 31, N'6', N'1', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2914, 31, N'6', N'2', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2915, 31, N'6', N'3', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2916, 31, N'6', N'4', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2917, 31, N'6', N'5', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2918, 31, N'6', N'6', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2919, 32, N'6', N'7', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2920, 32, N'6', N'8', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2921, 32, N'6', N'9', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2922, 32, N'6', N'10', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2923, 32, N'6', N'11', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2924, 32, N'6', N'12', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2925, 33, N'6', N'13', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2926, 33, N'6', N'14', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2927, 33, N'6', N'15', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2928, 33, N'6', N'16', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2929, 31, N'7', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2930, 31, N'7', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2931, 31, N'7', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2932, 31, N'7', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2933, 31, N'7', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2934, 31, N'7', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2935, 32, N'7', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2936, 32, N'7', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2937, 32, N'7', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2938, 32, N'7', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2939, 32, N'7', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2940, 32, N'7', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2941, 33, N'7', N'13', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2942, 33, N'7', N'14', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2943, 33, N'7', N'15', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2944, 33, N'7', N'16', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2945, 31, N'8', N'1', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2946, 31, N'8', N'2', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2947, 31, N'8', N'3', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2948, 31, N'8', N'4', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2949, 31, N'8', N'5', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2950, 31, N'8', N'6', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2951, 32, N'8', N'7', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2952, 32, N'8', N'8', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2953, 32, N'8', N'9', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2954, 32, N'8', N'10', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2955, 32, N'8', N'11', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2956, 32, N'8', N'12', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2957, 33, N'8', N'13', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2958, 33, N'8', N'14', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2959, 33, N'8', N'15', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2960, 33, N'8', N'16', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2961, 31, N'9', N'1', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2962, 31, N'9', N'2', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2963, 31, N'9', N'3', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2964, 31, N'9', N'4', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2965, 31, N'9', N'5', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2966, 31, N'9', N'6', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2967, 32, N'9', N'7', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2968, 32, N'9', N'8', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2969, 32, N'9', N'9', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2970, 32, N'9', N'10', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2971, 32, N'9', N'11', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2972, 32, N'9', N'12', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2973, 33, N'9', N'13', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2974, 33, N'9', N'14', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2975, 33, N'9', N'15', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2976, 33, N'9', N'16', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2977, 31, N'10', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2978, 31, N'10', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2979, 31, N'10', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2980, 31, N'10', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2981, 31, N'10', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2982, 31, N'10', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2983, 32, N'10', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2984, 32, N'10', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2985, 32, N'10', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2986, 32, N'10', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2987, 32, N'10', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2988, 32, N'10', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2989, 33, N'10', N'13', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2990, 33, N'10', N'14', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2991, 33, N'10', N'15', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2992, 33, N'10', N'16', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2993, 31, N'11', N'1', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2994, 31, N'11', N'2', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2995, 31, N'11', N'3', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2996, 31, N'11', N'4', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2997, 31, N'11', N'5', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2998, 31, N'11', N'6', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (2999, 32, N'11', N'7', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3000, 32, N'11', N'8', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3001, 32, N'11', N'9', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3002, 32, N'11', N'10', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3003, 32, N'11', N'11', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3004, 32, N'11', N'12', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3005, 33, N'11', N'13', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3006, 33, N'11', N'14', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3007, 33, N'11', N'15', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3008, 33, N'11', N'16', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3009, 31, N'12', N'1', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3010, 31, N'12', N'2', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3011, 31, N'12', N'3', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3012, 31, N'12', N'4', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3013, 31, N'12', N'5', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3014, 31, N'12', N'6', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3015, 32, N'12', N'7', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3016, 32, N'12', N'8', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3017, 32, N'12', N'9', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3018, 32, N'12', N'10', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3019, 32, N'12', N'11', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3020, 32, N'12', N'12', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3021, 33, N'12', N'13', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3022, 33, N'12', N'14', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3023, 33, N'12', N'15', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3024, 33, N'12', N'16', 192)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3025, 34, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3026, 34, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3027, 34, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3028, 34, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3029, 34, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3030, 34, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3031, 35, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3032, 35, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3033, 35, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3034, 35, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3035, 35, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3036, 35, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3037, 36, N'1', N'13', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3038, 36, N'1', N'14', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3039, 36, N'1', N'15', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3040, 36, N'1', N'16', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3041, 34, N'2', N'1', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3042, 34, N'2', N'2', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3043, 34, N'2', N'3', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3044, 34, N'2', N'4', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3045, 34, N'2', N'5', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3046, 34, N'2', N'6', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3047, 35, N'2', N'7', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3048, 35, N'2', N'8', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3049, 35, N'2', N'9', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3050, 35, N'2', N'10', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3051, 35, N'2', N'11', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3052, 35, N'2', N'12', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3053, 36, N'2', N'13', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3054, 36, N'2', N'14', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3055, 36, N'2', N'15', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3056, 36, N'2', N'16', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3057, 34, N'3', N'1', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3058, 34, N'3', N'2', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3059, 34, N'3', N'3', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3060, 34, N'3', N'4', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3061, 34, N'3', N'5', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3062, 34, N'3', N'6', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3063, 35, N'3', N'7', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3064, 35, N'3', N'8', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3065, 35, N'3', N'9', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3066, 35, N'3', N'10', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3067, 35, N'3', N'11', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3068, 35, N'3', N'12', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3069, 36, N'3', N'13', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3070, 36, N'3', N'14', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3071, 36, N'3', N'15', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3072, 36, N'3', N'16', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3073, 34, N'4', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3074, 34, N'4', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3075, 34, N'4', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3076, 34, N'4', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3077, 34, N'4', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3078, 34, N'4', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3079, 35, N'4', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3080, 35, N'4', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3081, 35, N'4', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3082, 35, N'4', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3083, 35, N'4', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3084, 35, N'4', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3085, 36, N'4', N'13', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3086, 36, N'4', N'14', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3087, 36, N'4', N'15', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3088, 36, N'4', N'16', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3089, 34, N'5', N'1', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3090, 34, N'5', N'2', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3091, 34, N'5', N'3', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3092, 34, N'5', N'4', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3093, 34, N'5', N'5', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3094, 34, N'5', N'6', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3095, 35, N'5', N'7', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3096, 35, N'5', N'8', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3097, 35, N'5', N'9', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3098, 35, N'5', N'10', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3099, 35, N'5', N'11', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3100, 35, N'5', N'12', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3101, 36, N'5', N'13', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3102, 36, N'5', N'14', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3103, 36, N'5', N'15', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3104, 36, N'5', N'16', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3105, 34, N'6', N'1', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3106, 34, N'6', N'2', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3107, 34, N'6', N'3', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3108, 34, N'6', N'4', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3109, 34, N'6', N'5', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3110, 34, N'6', N'6', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3111, 35, N'6', N'7', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3112, 35, N'6', N'8', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3113, 35, N'6', N'9', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3114, 35, N'6', N'10', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3115, 35, N'6', N'11', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3116, 35, N'6', N'12', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3117, 36, N'6', N'13', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3118, 36, N'6', N'14', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3119, 36, N'6', N'15', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3120, 36, N'6', N'16', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3121, 34, N'7', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3122, 34, N'7', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3123, 34, N'7', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3124, 34, N'7', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3125, 34, N'7', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3126, 34, N'7', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3127, 35, N'7', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3128, 35, N'7', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3129, 35, N'7', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3130, 35, N'7', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3131, 35, N'7', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3132, 35, N'7', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3133, 36, N'7', N'13', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3134, 36, N'7', N'14', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3135, 36, N'7', N'15', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3136, 36, N'7', N'16', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3137, 34, N'8', N'1', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3138, 34, N'8', N'2', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3139, 34, N'8', N'3', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3140, 34, N'8', N'4', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3141, 34, N'8', N'5', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3142, 34, N'8', N'6', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3143, 35, N'8', N'7', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3144, 35, N'8', N'8', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3145, 35, N'8', N'9', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3146, 35, N'8', N'10', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3147, 35, N'8', N'11', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3148, 35, N'8', N'12', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3149, 36, N'8', N'13', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3150, 36, N'8', N'14', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3151, 36, N'8', N'15', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3152, 36, N'8', N'16', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3153, 34, N'9', N'1', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3154, 34, N'9', N'2', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3155, 34, N'9', N'3', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3156, 34, N'9', N'4', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3157, 34, N'9', N'5', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3158, 34, N'9', N'6', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3159, 35, N'9', N'7', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3160, 35, N'9', N'8', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3161, 35, N'9', N'9', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3162, 35, N'9', N'10', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3163, 35, N'9', N'11', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3164, 35, N'9', N'12', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3165, 36, N'9', N'13', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3166, 36, N'9', N'14', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3167, 36, N'9', N'15', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3168, 36, N'9', N'16', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3169, 34, N'10', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3170, 34, N'10', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3171, 34, N'10', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3172, 34, N'10', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3173, 34, N'10', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3174, 34, N'10', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3175, 35, N'10', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3176, 35, N'10', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3177, 35, N'10', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3178, 35, N'10', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3179, 35, N'10', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3180, 35, N'10', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3181, 36, N'10', N'13', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3182, 36, N'10', N'14', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3183, 36, N'10', N'15', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3184, 36, N'10', N'16', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3185, 34, N'11', N'1', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3186, 34, N'11', N'2', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3187, 34, N'11', N'3', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3188, 34, N'11', N'4', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3189, 34, N'11', N'5', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3190, 34, N'11', N'6', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3191, 35, N'11', N'7', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3192, 35, N'11', N'8', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3193, 35, N'11', N'9', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3194, 35, N'11', N'10', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3195, 35, N'11', N'11', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3196, 35, N'11', N'12', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3197, 36, N'11', N'13', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3198, 36, N'11', N'14', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3199, 36, N'11', N'15', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3200, 36, N'11', N'16', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3201, 34, N'12', N'1', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3202, 34, N'12', N'2', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3203, 34, N'12', N'3', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3204, 34, N'12', N'4', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3205, 34, N'12', N'5', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3206, 34, N'12', N'6', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3207, 35, N'12', N'7', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3208, 35, N'12', N'8', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3209, 35, N'12', N'9', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3210, 35, N'12', N'10', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3211, 35, N'12', N'11', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3212, 35, N'12', N'12', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3213, 36, N'12', N'13', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3214, 36, N'12', N'14', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3215, 36, N'12', N'15', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3216, 36, N'12', N'16', 192)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3217, 37, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3218, 37, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3219, 37, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3220, 37, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3221, 37, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3222, 37, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3223, 38, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3224, 38, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3225, 38, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3226, 38, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3227, 38, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3228, 38, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3229, 39, N'1', N'13', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3230, 39, N'1', N'14', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3231, 39, N'1', N'15', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3232, 39, N'1', N'16', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3233, 37, N'2', N'1', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3234, 37, N'2', N'2', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3235, 37, N'2', N'3', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3236, 37, N'2', N'4', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3237, 37, N'2', N'5', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3238, 37, N'2', N'6', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3239, 38, N'2', N'7', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3240, 38, N'2', N'8', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3241, 38, N'2', N'9', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3242, 38, N'2', N'10', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3243, 38, N'2', N'11', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3244, 38, N'2', N'12', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3245, 39, N'2', N'13', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3246, 39, N'2', N'14', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3247, 39, N'2', N'15', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3248, 39, N'2', N'16', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3249, 37, N'3', N'1', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3250, 37, N'3', N'2', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3251, 37, N'3', N'3', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3252, 37, N'3', N'4', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3253, 37, N'3', N'5', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3254, 37, N'3', N'6', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3255, 38, N'3', N'7', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3256, 38, N'3', N'8', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3257, 38, N'3', N'9', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3258, 38, N'3', N'10', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3259, 38, N'3', N'11', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3260, 38, N'3', N'12', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3261, 39, N'3', N'13', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3262, 39, N'3', N'14', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3263, 39, N'3', N'15', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3264, 39, N'3', N'16', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3265, 37, N'4', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3266, 37, N'4', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3267, 37, N'4', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3268, 37, N'4', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3269, 37, N'4', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3270, 37, N'4', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3271, 38, N'4', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3272, 38, N'4', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3273, 38, N'4', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3274, 38, N'4', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3275, 38, N'4', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3276, 38, N'4', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3277, 39, N'4', N'13', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3278, 39, N'4', N'14', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3279, 39, N'4', N'15', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3280, 39, N'4', N'16', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3281, 37, N'5', N'1', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3282, 37, N'5', N'2', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3283, 37, N'5', N'3', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3284, 37, N'5', N'4', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3285, 37, N'5', N'5', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3286, 37, N'5', N'6', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3287, 38, N'5', N'7', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3288, 38, N'5', N'8', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3289, 38, N'5', N'9', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3290, 38, N'5', N'10', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3291, 38, N'5', N'11', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3292, 38, N'5', N'12', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3293, 39, N'5', N'13', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3294, 39, N'5', N'14', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3295, 39, N'5', N'15', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3296, 39, N'5', N'16', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3297, 37, N'6', N'1', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3298, 37, N'6', N'2', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3299, 37, N'6', N'3', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3300, 37, N'6', N'4', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3301, 37, N'6', N'5', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3302, 37, N'6', N'6', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3303, 38, N'6', N'7', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3304, 38, N'6', N'8', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3305, 38, N'6', N'9', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3306, 38, N'6', N'10', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3307, 38, N'6', N'11', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3308, 38, N'6', N'12', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3309, 39, N'6', N'13', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3310, 39, N'6', N'14', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3311, 39, N'6', N'15', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3312, 39, N'6', N'16', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3313, 37, N'7', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3314, 37, N'7', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3315, 37, N'7', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3316, 37, N'7', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3317, 37, N'7', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3318, 37, N'7', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3319, 38, N'7', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3320, 38, N'7', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3321, 38, N'7', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3322, 38, N'7', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3323, 38, N'7', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3324, 38, N'7', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3325, 39, N'7', N'13', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3326, 39, N'7', N'14', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3327, 39, N'7', N'15', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3328, 39, N'7', N'16', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3329, 37, N'8', N'1', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3330, 37, N'8', N'2', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3331, 37, N'8', N'3', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3332, 37, N'8', N'4', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3333, 37, N'8', N'5', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3334, 37, N'8', N'6', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3335, 38, N'8', N'7', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3336, 38, N'8', N'8', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3337, 38, N'8', N'9', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3338, 38, N'8', N'10', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3339, 38, N'8', N'11', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3340, 38, N'8', N'12', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3341, 39, N'8', N'13', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3342, 39, N'8', N'14', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3343, 39, N'8', N'15', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3344, 39, N'8', N'16', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3345, 37, N'9', N'1', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3346, 37, N'9', N'2', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3347, 37, N'9', N'3', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3348, 37, N'9', N'4', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3349, 37, N'9', N'5', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3350, 37, N'9', N'6', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3351, 38, N'9', N'7', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3352, 38, N'9', N'8', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3353, 38, N'9', N'9', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3354, 38, N'9', N'10', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3355, 38, N'9', N'11', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3356, 38, N'9', N'12', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3357, 39, N'9', N'13', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3358, 39, N'9', N'14', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3359, 39, N'9', N'15', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3360, 39, N'9', N'16', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3361, 37, N'10', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3362, 37, N'10', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3363, 37, N'10', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3364, 37, N'10', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3365, 37, N'10', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3366, 37, N'10', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3367, 38, N'10', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3368, 38, N'10', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3369, 38, N'10', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3370, 38, N'10', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3371, 38, N'10', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3372, 38, N'10', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3373, 39, N'10', N'13', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3374, 39, N'10', N'14', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3375, 39, N'10', N'15', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3376, 39, N'10', N'16', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3377, 37, N'11', N'1', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3378, 37, N'11', N'2', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3379, 37, N'11', N'3', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3380, 37, N'11', N'4', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3381, 37, N'11', N'5', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3382, 37, N'11', N'6', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3383, 38, N'11', N'7', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3384, 38, N'11', N'8', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3385, 38, N'11', N'9', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3386, 38, N'11', N'10', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3387, 38, N'11', N'11', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3388, 38, N'11', N'12', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3389, 39, N'11', N'13', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3390, 39, N'11', N'14', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3391, 39, N'11', N'15', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3392, 39, N'11', N'16', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3393, 37, N'12', N'1', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3394, 37, N'12', N'2', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3395, 37, N'12', N'3', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3396, 37, N'12', N'4', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3397, 37, N'12', N'5', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3398, 37, N'12', N'6', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3399, 38, N'12', N'7', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3400, 38, N'12', N'8', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3401, 38, N'12', N'9', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3402, 38, N'12', N'10', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3403, 38, N'12', N'11', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3404, 38, N'12', N'12', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3405, 39, N'12', N'13', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3406, 39, N'12', N'14', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3407, 39, N'12', N'15', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3408, 39, N'12', N'16', 192)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3409, 40, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3410, 40, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3411, 40, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3412, 40, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3413, 40, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3414, 40, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3415, 41, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3416, 41, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3417, 41, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3418, 41, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3419, 41, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3420, 41, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3421, 42, N'1', N'13', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3422, 42, N'1', N'14', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3423, 42, N'1', N'15', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3424, 42, N'1', N'16', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3425, 40, N'2', N'1', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3426, 40, N'2', N'2', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3427, 40, N'2', N'3', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3428, 40, N'2', N'4', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3429, 40, N'2', N'5', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3430, 40, N'2', N'6', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3431, 41, N'2', N'7', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3432, 41, N'2', N'8', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3433, 41, N'2', N'9', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3434, 41, N'2', N'10', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3435, 41, N'2', N'11', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3436, 41, N'2', N'12', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3437, 42, N'2', N'13', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3438, 42, N'2', N'14', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3439, 42, N'2', N'15', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3440, 42, N'2', N'16', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3441, 40, N'3', N'1', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3442, 40, N'3', N'2', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3443, 40, N'3', N'3', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3444, 40, N'3', N'4', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3445, 40, N'3', N'5', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3446, 40, N'3', N'6', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3447, 41, N'3', N'7', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3448, 41, N'3', N'8', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3449, 41, N'3', N'9', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3450, 41, N'3', N'10', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3451, 41, N'3', N'11', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3452, 41, N'3', N'12', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3453, 42, N'3', N'13', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3454, 42, N'3', N'14', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3455, 42, N'3', N'15', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3456, 42, N'3', N'16', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3457, 40, N'4', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3458, 40, N'4', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3459, 40, N'4', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3460, 40, N'4', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3461, 40, N'4', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3462, 40, N'4', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3463, 41, N'4', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3464, 41, N'4', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3465, 41, N'4', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3466, 41, N'4', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3467, 41, N'4', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3468, 41, N'4', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3469, 42, N'4', N'13', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3470, 42, N'4', N'14', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3471, 42, N'4', N'15', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3472, 42, N'4', N'16', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3473, 40, N'5', N'1', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3474, 40, N'5', N'2', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3475, 40, N'5', N'3', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3476, 40, N'5', N'4', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3477, 40, N'5', N'5', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3478, 40, N'5', N'6', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3479, 41, N'5', N'7', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3480, 41, N'5', N'8', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3481, 41, N'5', N'9', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3482, 41, N'5', N'10', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3483, 41, N'5', N'11', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3484, 41, N'5', N'12', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3485, 42, N'5', N'13', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3486, 42, N'5', N'14', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3487, 42, N'5', N'15', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3488, 42, N'5', N'16', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3489, 40, N'6', N'1', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3490, 40, N'6', N'2', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3491, 40, N'6', N'3', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3492, 40, N'6', N'4', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3493, 40, N'6', N'5', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3494, 40, N'6', N'6', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3495, 41, N'6', N'7', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3496, 41, N'6', N'8', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3497, 41, N'6', N'9', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3498, 41, N'6', N'10', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3499, 41, N'6', N'11', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3500, 41, N'6', N'12', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3501, 42, N'6', N'13', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3502, 42, N'6', N'14', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3503, 42, N'6', N'15', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3504, 42, N'6', N'16', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3505, 40, N'7', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3506, 40, N'7', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3507, 40, N'7', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3508, 40, N'7', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3509, 40, N'7', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3510, 40, N'7', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3511, 41, N'7', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3512, 41, N'7', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3513, 41, N'7', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3514, 41, N'7', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3515, 41, N'7', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3516, 41, N'7', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3517, 42, N'7', N'13', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3518, 42, N'7', N'14', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3519, 42, N'7', N'15', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3520, 42, N'7', N'16', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3521, 40, N'8', N'1', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3522, 40, N'8', N'2', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3523, 40, N'8', N'3', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3524, 40, N'8', N'4', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3525, 40, N'8', N'5', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3526, 40, N'8', N'6', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3527, 41, N'8', N'7', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3528, 41, N'8', N'8', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3529, 41, N'8', N'9', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3530, 41, N'8', N'10', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3531, 41, N'8', N'11', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3532, 41, N'8', N'12', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3533, 42, N'8', N'13', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3534, 42, N'8', N'14', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3535, 42, N'8', N'15', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3536, 42, N'8', N'16', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3537, 40, N'9', N'1', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3538, 40, N'9', N'2', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3539, 40, N'9', N'3', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3540, 40, N'9', N'4', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3541, 40, N'9', N'5', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3542, 40, N'9', N'6', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3543, 41, N'9', N'7', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3544, 41, N'9', N'8', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3545, 41, N'9', N'9', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3546, 41, N'9', N'10', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3547, 41, N'9', N'11', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3548, 41, N'9', N'12', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3549, 42, N'9', N'13', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3550, 42, N'9', N'14', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3551, 42, N'9', N'15', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3552, 42, N'9', N'16', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3553, 40, N'10', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3554, 40, N'10', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3555, 40, N'10', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3556, 40, N'10', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3557, 40, N'10', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3558, 40, N'10', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3559, 41, N'10', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3560, 41, N'10', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3561, 41, N'10', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3562, 41, N'10', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3563, 41, N'10', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3564, 41, N'10', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3565, 42, N'10', N'13', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3566, 42, N'10', N'14', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3567, 42, N'10', N'15', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3568, 42, N'10', N'16', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3569, 40, N'11', N'1', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3570, 40, N'11', N'2', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3571, 40, N'11', N'3', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3572, 40, N'11', N'4', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3573, 40, N'11', N'5', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3574, 40, N'11', N'6', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3575, 41, N'11', N'7', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3576, 41, N'11', N'8', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3577, 41, N'11', N'9', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3578, 41, N'11', N'10', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3579, 41, N'11', N'11', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3580, 41, N'11', N'12', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3581, 42, N'11', N'13', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3582, 42, N'11', N'14', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3583, 42, N'11', N'15', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3584, 42, N'11', N'16', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3585, 40, N'12', N'1', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3586, 40, N'12', N'2', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3587, 40, N'12', N'3', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3588, 40, N'12', N'4', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3589, 40, N'12', N'5', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3590, 40, N'12', N'6', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3591, 41, N'12', N'7', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3592, 41, N'12', N'8', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3593, 41, N'12', N'9', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3594, 41, N'12', N'10', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3595, 41, N'12', N'11', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3596, 41, N'12', N'12', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3597, 42, N'12', N'13', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3598, 42, N'12', N'14', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3599, 42, N'12', N'15', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3600, 42, N'12', N'16', 192)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3601, 43, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3602, 43, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3603, 43, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3604, 43, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3605, 43, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3606, 43, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3607, 44, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3608, 44, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3609, 44, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3610, 44, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3611, 44, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3612, 44, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3613, 45, N'1', N'13', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3614, 45, N'1', N'14', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3615, 45, N'1', N'15', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3616, 45, N'1', N'16', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3617, 43, N'2', N'1', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3618, 43, N'2', N'2', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3619, 43, N'2', N'3', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3620, 43, N'2', N'4', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3621, 43, N'2', N'5', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3622, 43, N'2', N'6', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3623, 44, N'2', N'7', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3624, 44, N'2', N'8', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3625, 44, N'2', N'9', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3626, 44, N'2', N'10', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3627, 44, N'2', N'11', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3628, 44, N'2', N'12', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3629, 45, N'2', N'13', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3630, 45, N'2', N'14', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3631, 45, N'2', N'15', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3632, 45, N'2', N'16', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3633, 43, N'3', N'1', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3634, 43, N'3', N'2', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3635, 43, N'3', N'3', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3636, 43, N'3', N'4', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3637, 43, N'3', N'5', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3638, 43, N'3', N'6', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3639, 44, N'3', N'7', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3640, 44, N'3', N'8', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3641, 44, N'3', N'9', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3642, 44, N'3', N'10', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3643, 44, N'3', N'11', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3644, 44, N'3', N'12', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3645, 45, N'3', N'13', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3646, 45, N'3', N'14', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3647, 45, N'3', N'15', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3648, 45, N'3', N'16', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3649, 43, N'4', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3650, 43, N'4', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3651, 43, N'4', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3652, 43, N'4', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3653, 43, N'4', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3654, 43, N'4', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3655, 44, N'4', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3656, 44, N'4', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3657, 44, N'4', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3658, 44, N'4', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3659, 44, N'4', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3660, 44, N'4', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3661, 45, N'4', N'13', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3662, 45, N'4', N'14', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3663, 45, N'4', N'15', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3664, 45, N'4', N'16', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3665, 43, N'5', N'1', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3666, 43, N'5', N'2', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3667, 43, N'5', N'3', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3668, 43, N'5', N'4', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3669, 43, N'5', N'5', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3670, 43, N'5', N'6', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3671, 44, N'5', N'7', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3672, 44, N'5', N'8', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3673, 44, N'5', N'9', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3674, 44, N'5', N'10', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3675, 44, N'5', N'11', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3676, 44, N'5', N'12', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3677, 45, N'5', N'13', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3678, 45, N'5', N'14', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3679, 45, N'5', N'15', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3680, 45, N'5', N'16', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3681, 43, N'6', N'1', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3682, 43, N'6', N'2', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3683, 43, N'6', N'3', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3684, 43, N'6', N'4', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3685, 43, N'6', N'5', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3686, 43, N'6', N'6', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3687, 44, N'6', N'7', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3688, 44, N'6', N'8', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3689, 44, N'6', N'9', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3690, 44, N'6', N'10', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3691, 44, N'6', N'11', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3692, 44, N'6', N'12', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3693, 45, N'6', N'13', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3694, 45, N'6', N'14', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3695, 45, N'6', N'15', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3696, 45, N'6', N'16', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3697, 43, N'7', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3698, 43, N'7', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3699, 43, N'7', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3700, 43, N'7', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3701, 43, N'7', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3702, 43, N'7', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3703, 44, N'7', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3704, 44, N'7', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3705, 44, N'7', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3706, 44, N'7', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3707, 44, N'7', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3708, 44, N'7', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3709, 45, N'7', N'13', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3710, 45, N'7', N'14', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3711, 45, N'7', N'15', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3712, 45, N'7', N'16', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3713, 43, N'8', N'1', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3714, 43, N'8', N'2', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3715, 43, N'8', N'3', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3716, 43, N'8', N'4', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3717, 43, N'8', N'5', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3718, 43, N'8', N'6', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3719, 44, N'8', N'7', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3720, 44, N'8', N'8', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3721, 44, N'8', N'9', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3722, 44, N'8', N'10', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3723, 44, N'8', N'11', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3724, 44, N'8', N'12', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3725, 45, N'8', N'13', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3726, 45, N'8', N'14', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3727, 45, N'8', N'15', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3728, 45, N'8', N'16', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3729, 43, N'9', N'1', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3730, 43, N'9', N'2', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3731, 43, N'9', N'3', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3732, 43, N'9', N'4', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3733, 43, N'9', N'5', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3734, 43, N'9', N'6', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3735, 44, N'9', N'7', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3736, 44, N'9', N'8', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3737, 44, N'9', N'9', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3738, 44, N'9', N'10', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3739, 44, N'9', N'11', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3740, 44, N'9', N'12', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3741, 45, N'9', N'13', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3742, 45, N'9', N'14', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3743, 45, N'9', N'15', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3744, 45, N'9', N'16', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3745, 43, N'10', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3746, 43, N'10', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3747, 43, N'10', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3748, 43, N'10', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3749, 43, N'10', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3750, 43, N'10', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3751, 44, N'10', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3752, 44, N'10', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3753, 44, N'10', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3754, 44, N'10', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3755, 44, N'10', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3756, 44, N'10', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3757, 45, N'10', N'13', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3758, 45, N'10', N'14', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3759, 45, N'10', N'15', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3760, 45, N'10', N'16', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3761, 43, N'11', N'1', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3762, 43, N'11', N'2', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3763, 43, N'11', N'3', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3764, 43, N'11', N'4', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3765, 43, N'11', N'5', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3766, 43, N'11', N'6', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3767, 44, N'11', N'7', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3768, 44, N'11', N'8', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3769, 44, N'11', N'9', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3770, 44, N'11', N'10', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3771, 44, N'11', N'11', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3772, 44, N'11', N'12', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3773, 45, N'11', N'13', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3774, 45, N'11', N'14', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3775, 45, N'11', N'15', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3776, 45, N'11', N'16', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3777, 43, N'12', N'1', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3778, 43, N'12', N'2', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3779, 43, N'12', N'3', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3780, 43, N'12', N'4', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3781, 43, N'12', N'5', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3782, 43, N'12', N'6', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3783, 44, N'12', N'7', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3784, 44, N'12', N'8', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3785, 44, N'12', N'9', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3786, 44, N'12', N'10', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3787, 44, N'12', N'11', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3788, 44, N'12', N'12', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3789, 45, N'12', N'13', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3790, 45, N'12', N'14', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3791, 45, N'12', N'15', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3792, 45, N'12', N'16', 192)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3793, 46, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3794, 46, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3795, 46, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3796, 46, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3797, 46, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3798, 46, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3799, 47, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3800, 47, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3801, 47, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3802, 47, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3803, 47, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3804, 47, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3805, 48, N'1', N'13', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3806, 48, N'1', N'14', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3807, 48, N'1', N'15', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3808, 48, N'1', N'16', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3809, 46, N'2', N'1', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3810, 46, N'2', N'2', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3811, 46, N'2', N'3', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3812, 46, N'2', N'4', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3813, 46, N'2', N'5', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3814, 46, N'2', N'6', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3815, 47, N'2', N'7', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3816, 47, N'2', N'8', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3817, 47, N'2', N'9', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3818, 47, N'2', N'10', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3819, 47, N'2', N'11', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3820, 47, N'2', N'12', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3821, 48, N'2', N'13', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3822, 48, N'2', N'14', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3823, 48, N'2', N'15', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3824, 48, N'2', N'16', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3825, 46, N'3', N'1', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3826, 46, N'3', N'2', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3827, 46, N'3', N'3', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3828, 46, N'3', N'4', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3829, 46, N'3', N'5', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3830, 46, N'3', N'6', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3831, 47, N'3', N'7', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3832, 47, N'3', N'8', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3833, 47, N'3', N'9', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3834, 47, N'3', N'10', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3835, 47, N'3', N'11', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3836, 47, N'3', N'12', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3837, 48, N'3', N'13', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3838, 48, N'3', N'14', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3839, 48, N'3', N'15', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3840, 48, N'3', N'16', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3841, 46, N'4', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3842, 46, N'4', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3843, 46, N'4', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3844, 46, N'4', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3845, 46, N'4', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3846, 46, N'4', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3847, 47, N'4', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3848, 47, N'4', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3849, 47, N'4', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3850, 47, N'4', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3851, 47, N'4', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3852, 47, N'4', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3853, 48, N'4', N'13', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3854, 48, N'4', N'14', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3855, 48, N'4', N'15', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3856, 48, N'4', N'16', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3857, 46, N'5', N'1', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3858, 46, N'5', N'2', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3859, 46, N'5', N'3', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3860, 46, N'5', N'4', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3861, 46, N'5', N'5', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3862, 46, N'5', N'6', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3863, 47, N'5', N'7', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3864, 47, N'5', N'8', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3865, 47, N'5', N'9', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3866, 47, N'5', N'10', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3867, 47, N'5', N'11', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3868, 47, N'5', N'12', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3869, 48, N'5', N'13', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3870, 48, N'5', N'14', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3871, 48, N'5', N'15', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3872, 48, N'5', N'16', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3873, 46, N'6', N'1', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3874, 46, N'6', N'2', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3875, 46, N'6', N'3', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3876, 46, N'6', N'4', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3877, 46, N'6', N'5', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3878, 46, N'6', N'6', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3879, 47, N'6', N'7', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3880, 47, N'6', N'8', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3881, 47, N'6', N'9', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3882, 47, N'6', N'10', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3883, 47, N'6', N'11', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3884, 47, N'6', N'12', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3885, 48, N'6', N'13', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3886, 48, N'6', N'14', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3887, 48, N'6', N'15', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3888, 48, N'6', N'16', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3889, 46, N'7', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3890, 46, N'7', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3891, 46, N'7', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3892, 46, N'7', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3893, 46, N'7', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3894, 46, N'7', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3895, 47, N'7', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3896, 47, N'7', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3897, 47, N'7', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3898, 47, N'7', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3899, 47, N'7', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3900, 47, N'7', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3901, 48, N'7', N'13', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3902, 48, N'7', N'14', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3903, 48, N'7', N'15', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3904, 48, N'7', N'16', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3905, 46, N'8', N'1', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3906, 46, N'8', N'2', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3907, 46, N'8', N'3', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3908, 46, N'8', N'4', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3909, 46, N'8', N'5', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3910, 46, N'8', N'6', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3911, 47, N'8', N'7', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3912, 47, N'8', N'8', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3913, 47, N'8', N'9', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3914, 47, N'8', N'10', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3915, 47, N'8', N'11', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3916, 47, N'8', N'12', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3917, 48, N'8', N'13', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3918, 48, N'8', N'14', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3919, 48, N'8', N'15', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3920, 48, N'8', N'16', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3921, 46, N'9', N'1', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3922, 46, N'9', N'2', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3923, 46, N'9', N'3', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3924, 46, N'9', N'4', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3925, 46, N'9', N'5', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3926, 46, N'9', N'6', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3927, 47, N'9', N'7', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3928, 47, N'9', N'8', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3929, 47, N'9', N'9', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3930, 47, N'9', N'10', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3931, 47, N'9', N'11', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3932, 47, N'9', N'12', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3933, 48, N'9', N'13', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3934, 48, N'9', N'14', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3935, 48, N'9', N'15', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3936, 48, N'9', N'16', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3937, 46, N'10', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3938, 46, N'10', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3939, 46, N'10', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3940, 46, N'10', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3941, 46, N'10', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3942, 46, N'10', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3943, 47, N'10', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3944, 47, N'10', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3945, 47, N'10', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3946, 47, N'10', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3947, 47, N'10', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3948, 47, N'10', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3949, 48, N'10', N'13', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3950, 48, N'10', N'14', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3951, 48, N'10', N'15', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3952, 48, N'10', N'16', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3953, 46, N'11', N'1', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3954, 46, N'11', N'2', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3955, 46, N'11', N'3', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3956, 46, N'11', N'4', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3957, 46, N'11', N'5', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3958, 46, N'11', N'6', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3959, 47, N'11', N'7', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3960, 47, N'11', N'8', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3961, 47, N'11', N'9', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3962, 47, N'11', N'10', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3963, 47, N'11', N'11', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3964, 47, N'11', N'12', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3965, 48, N'11', N'13', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3966, 48, N'11', N'14', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3967, 48, N'11', N'15', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3968, 48, N'11', N'16', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3969, 46, N'12', N'1', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3970, 46, N'12', N'2', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3971, 46, N'12', N'3', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3972, 46, N'12', N'4', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3973, 46, N'12', N'5', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3974, 46, N'12', N'6', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3975, 47, N'12', N'7', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3976, 47, N'12', N'8', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3977, 47, N'12', N'9', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3978, 47, N'12', N'10', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3979, 47, N'12', N'11', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3980, 47, N'12', N'12', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3981, 48, N'12', N'13', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3982, 48, N'12', N'14', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3983, 48, N'12', N'15', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3984, 48, N'12', N'16', 192)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3985, 49, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3986, 49, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3987, 49, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3988, 49, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3989, 49, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3990, 49, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3991, 50, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3992, 50, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3993, 50, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3994, 50, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3995, 50, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3996, 50, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3997, 51, N'1', N'13', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3998, 51, N'1', N'14', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (3999, 51, N'1', N'15', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4000, 51, N'1', N'16', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4001, 49, N'2', N'1', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4002, 49, N'2', N'2', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4003, 49, N'2', N'3', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4004, 49, N'2', N'4', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4005, 49, N'2', N'5', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4006, 49, N'2', N'6', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4007, 50, N'2', N'7', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4008, 50, N'2', N'8', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4009, 50, N'2', N'9', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4010, 50, N'2', N'10', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4011, 50, N'2', N'11', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4012, 50, N'2', N'12', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4013, 51, N'2', N'13', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4014, 51, N'2', N'14', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4015, 51, N'2', N'15', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4016, 51, N'2', N'16', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4017, 49, N'3', N'1', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4018, 49, N'3', N'2', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4019, 49, N'3', N'3', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4020, 49, N'3', N'4', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4021, 49, N'3', N'5', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4022, 49, N'3', N'6', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4023, 50, N'3', N'7', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4024, 50, N'3', N'8', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4025, 50, N'3', N'9', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4026, 50, N'3', N'10', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4027, 50, N'3', N'11', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4028, 50, N'3', N'12', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4029, 51, N'3', N'13', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4030, 51, N'3', N'14', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4031, 51, N'3', N'15', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4032, 51, N'3', N'16', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4033, 49, N'4', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4034, 49, N'4', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4035, 49, N'4', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4036, 49, N'4', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4037, 49, N'4', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4038, 49, N'4', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4039, 50, N'4', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4040, 50, N'4', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4041, 50, N'4', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4042, 50, N'4', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4043, 50, N'4', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4044, 50, N'4', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4045, 51, N'4', N'13', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4046, 51, N'4', N'14', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4047, 51, N'4', N'15', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4048, 51, N'4', N'16', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4049, 49, N'5', N'1', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4050, 49, N'5', N'2', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4051, 49, N'5', N'3', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4052, 49, N'5', N'4', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4053, 49, N'5', N'5', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4054, 49, N'5', N'6', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4055, 50, N'5', N'7', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4056, 50, N'5', N'8', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4057, 50, N'5', N'9', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4058, 50, N'5', N'10', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4059, 50, N'5', N'11', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4060, 50, N'5', N'12', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4061, 51, N'5', N'13', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4062, 51, N'5', N'14', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4063, 51, N'5', N'15', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4064, 51, N'5', N'16', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4065, 49, N'6', N'1', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4066, 49, N'6', N'2', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4067, 49, N'6', N'3', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4068, 49, N'6', N'4', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4069, 49, N'6', N'5', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4070, 49, N'6', N'6', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4071, 50, N'6', N'7', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4072, 50, N'6', N'8', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4073, 50, N'6', N'9', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4074, 50, N'6', N'10', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4075, 50, N'6', N'11', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4076, 50, N'6', N'12', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4077, 51, N'6', N'13', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4078, 51, N'6', N'14', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4079, 51, N'6', N'15', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4080, 51, N'6', N'16', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4081, 49, N'7', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4082, 49, N'7', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4083, 49, N'7', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4084, 49, N'7', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4085, 49, N'7', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4086, 49, N'7', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4087, 50, N'7', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4088, 50, N'7', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4089, 50, N'7', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4090, 50, N'7', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4091, 50, N'7', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4092, 50, N'7', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4093, 51, N'7', N'13', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4094, 51, N'7', N'14', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4095, 51, N'7', N'15', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4096, 51, N'7', N'16', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4097, 49, N'8', N'1', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4098, 49, N'8', N'2', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4099, 49, N'8', N'3', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4100, 49, N'8', N'4', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4101, 49, N'8', N'5', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4102, 49, N'8', N'6', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4103, 50, N'8', N'7', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4104, 50, N'8', N'8', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4105, 50, N'8', N'9', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4106, 50, N'8', N'10', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4107, 50, N'8', N'11', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4108, 50, N'8', N'12', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4109, 51, N'8', N'13', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4110, 51, N'8', N'14', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4111, 51, N'8', N'15', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4112, 51, N'8', N'16', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4113, 49, N'9', N'1', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4114, 49, N'9', N'2', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4115, 49, N'9', N'3', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4116, 49, N'9', N'4', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4117, 49, N'9', N'5', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4118, 49, N'9', N'6', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4119, 50, N'9', N'7', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4120, 50, N'9', N'8', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4121, 50, N'9', N'9', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4122, 50, N'9', N'10', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4123, 50, N'9', N'11', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4124, 50, N'9', N'12', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4125, 51, N'9', N'13', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4126, 51, N'9', N'14', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4127, 51, N'9', N'15', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4128, 51, N'9', N'16', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4129, 49, N'10', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4130, 49, N'10', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4131, 49, N'10', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4132, 49, N'10', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4133, 49, N'10', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4134, 49, N'10', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4135, 50, N'10', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4136, 50, N'10', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4137, 50, N'10', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4138, 50, N'10', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4139, 50, N'10', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4140, 50, N'10', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4141, 51, N'10', N'13', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4142, 51, N'10', N'14', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4143, 51, N'10', N'15', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4144, 51, N'10', N'16', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4145, 49, N'11', N'1', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4146, 49, N'11', N'2', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4147, 49, N'11', N'3', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4148, 49, N'11', N'4', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4149, 49, N'11', N'5', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4150, 49, N'11', N'6', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4151, 50, N'11', N'7', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4152, 50, N'11', N'8', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4153, 50, N'11', N'9', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4154, 50, N'11', N'10', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4155, 50, N'11', N'11', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4156, 50, N'11', N'12', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4157, 51, N'11', N'13', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4158, 51, N'11', N'14', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4159, 51, N'11', N'15', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4160, 51, N'11', N'16', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4161, 49, N'12', N'1', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4162, 49, N'12', N'2', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4163, 49, N'12', N'3', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4164, 49, N'12', N'4', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4165, 49, N'12', N'5', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4166, 49, N'12', N'6', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4167, 50, N'12', N'7', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4168, 50, N'12', N'8', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4169, 50, N'12', N'9', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4170, 50, N'12', N'10', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4171, 50, N'12', N'11', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4172, 50, N'12', N'12', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4173, 51, N'12', N'13', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4174, 51, N'12', N'14', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4175, 51, N'12', N'15', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4176, 51, N'12', N'16', 192)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4177, 52, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4178, 52, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4179, 52, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4180, 52, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4181, 52, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4182, 52, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4183, 53, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4184, 53, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4185, 53, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4186, 53, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4187, 53, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4188, 53, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4189, 54, N'1', N'13', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4190, 54, N'1', N'14', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4191, 54, N'1', N'15', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4192, 54, N'1', N'16', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4193, 52, N'2', N'1', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4194, 52, N'2', N'2', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4195, 52, N'2', N'3', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4196, 52, N'2', N'4', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4197, 52, N'2', N'5', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4198, 52, N'2', N'6', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4199, 53, N'2', N'7', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4200, 53, N'2', N'8', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4201, 53, N'2', N'9', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4202, 53, N'2', N'10', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4203, 53, N'2', N'11', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4204, 53, N'2', N'12', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4205, 54, N'2', N'13', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4206, 54, N'2', N'14', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4207, 54, N'2', N'15', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4208, 54, N'2', N'16', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4209, 52, N'3', N'1', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4210, 52, N'3', N'2', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4211, 52, N'3', N'3', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4212, 52, N'3', N'4', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4213, 52, N'3', N'5', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4214, 52, N'3', N'6', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4215, 53, N'3', N'7', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4216, 53, N'3', N'8', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4217, 53, N'3', N'9', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4218, 53, N'3', N'10', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4219, 53, N'3', N'11', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4220, 53, N'3', N'12', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4221, 54, N'3', N'13', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4222, 54, N'3', N'14', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4223, 54, N'3', N'15', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4224, 54, N'3', N'16', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4225, 52, N'4', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4226, 52, N'4', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4227, 52, N'4', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4228, 52, N'4', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4229, 52, N'4', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4230, 52, N'4', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4231, 53, N'4', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4232, 53, N'4', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4233, 53, N'4', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4234, 53, N'4', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4235, 53, N'4', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4236, 53, N'4', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4237, 54, N'4', N'13', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4238, 54, N'4', N'14', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4239, 54, N'4', N'15', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4240, 54, N'4', N'16', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4241, 52, N'5', N'1', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4242, 52, N'5', N'2', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4243, 52, N'5', N'3', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4244, 52, N'5', N'4', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4245, 52, N'5', N'5', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4246, 52, N'5', N'6', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4247, 53, N'5', N'7', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4248, 53, N'5', N'8', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4249, 53, N'5', N'9', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4250, 53, N'5', N'10', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4251, 53, N'5', N'11', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4252, 53, N'5', N'12', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4253, 54, N'5', N'13', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4254, 54, N'5', N'14', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4255, 54, N'5', N'15', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4256, 54, N'5', N'16', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4257, 52, N'6', N'1', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4258, 52, N'6', N'2', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4259, 52, N'6', N'3', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4260, 52, N'6', N'4', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4261, 52, N'6', N'5', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4262, 52, N'6', N'6', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4263, 53, N'6', N'7', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4264, 53, N'6', N'8', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4265, 53, N'6', N'9', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4266, 53, N'6', N'10', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4267, 53, N'6', N'11', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4268, 53, N'6', N'12', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4269, 54, N'6', N'13', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4270, 54, N'6', N'14', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4271, 54, N'6', N'15', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4272, 54, N'6', N'16', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4273, 52, N'7', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4274, 52, N'7', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4275, 52, N'7', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4276, 52, N'7', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4277, 52, N'7', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4278, 52, N'7', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4279, 53, N'7', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4280, 53, N'7', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4281, 53, N'7', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4282, 53, N'7', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4283, 53, N'7', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4284, 53, N'7', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4285, 54, N'7', N'13', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4286, 54, N'7', N'14', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4287, 54, N'7', N'15', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4288, 54, N'7', N'16', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4289, 52, N'8', N'1', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4290, 52, N'8', N'2', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4291, 52, N'8', N'3', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4292, 52, N'8', N'4', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4293, 52, N'8', N'5', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4294, 52, N'8', N'6', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4295, 53, N'8', N'7', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4296, 53, N'8', N'8', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4297, 53, N'8', N'9', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4298, 53, N'8', N'10', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4299, 53, N'8', N'11', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4300, 53, N'8', N'12', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4301, 54, N'8', N'13', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4302, 54, N'8', N'14', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4303, 54, N'8', N'15', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4304, 54, N'8', N'16', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4305, 52, N'9', N'1', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4306, 52, N'9', N'2', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4307, 52, N'9', N'3', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4308, 52, N'9', N'4', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4309, 52, N'9', N'5', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4310, 52, N'9', N'6', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4311, 53, N'9', N'7', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4312, 53, N'9', N'8', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4313, 53, N'9', N'9', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4314, 53, N'9', N'10', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4315, 53, N'9', N'11', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4316, 53, N'9', N'12', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4317, 54, N'9', N'13', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4318, 54, N'9', N'14', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4319, 54, N'9', N'15', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4320, 54, N'9', N'16', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4321, 52, N'10', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4322, 52, N'10', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4323, 52, N'10', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4324, 52, N'10', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4325, 52, N'10', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4326, 52, N'10', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4327, 53, N'10', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4328, 53, N'10', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4329, 53, N'10', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4330, 53, N'10', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4331, 53, N'10', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4332, 53, N'10', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4333, 54, N'10', N'13', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4334, 54, N'10', N'14', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4335, 54, N'10', N'15', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4336, 54, N'10', N'16', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4337, 52, N'11', N'1', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4338, 52, N'11', N'2', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4339, 52, N'11', N'3', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4340, 52, N'11', N'4', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4341, 52, N'11', N'5', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4342, 52, N'11', N'6', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4343, 53, N'11', N'7', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4344, 53, N'11', N'8', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4345, 53, N'11', N'9', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4346, 53, N'11', N'10', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4347, 53, N'11', N'11', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4348, 53, N'11', N'12', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4349, 54, N'11', N'13', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4350, 54, N'11', N'14', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4351, 54, N'11', N'15', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4352, 54, N'11', N'16', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4353, 52, N'12', N'1', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4354, 52, N'12', N'2', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4355, 52, N'12', N'3', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4356, 52, N'12', N'4', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4357, 52, N'12', N'5', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4358, 52, N'12', N'6', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4359, 53, N'12', N'7', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4360, 53, N'12', N'8', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4361, 53, N'12', N'9', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4362, 53, N'12', N'10', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4363, 53, N'12', N'11', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4364, 53, N'12', N'12', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4365, 54, N'12', N'13', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4366, 54, N'12', N'14', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4367, 54, N'12', N'15', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4368, 54, N'12', N'16', 192)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4369, 55, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4370, 55, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4371, 55, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4372, 55, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4373, 55, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4374, 55, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4375, 56, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4376, 56, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4377, 56, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4378, 56, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4379, 56, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4380, 56, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4381, 57, N'1', N'13', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4382, 57, N'1', N'14', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4383, 57, N'1', N'15', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4384, 57, N'1', N'16', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4385, 55, N'2', N'1', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4386, 55, N'2', N'2', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4387, 55, N'2', N'3', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4388, 55, N'2', N'4', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4389, 55, N'2', N'5', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4390, 55, N'2', N'6', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4391, 56, N'2', N'7', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4392, 56, N'2', N'8', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4393, 56, N'2', N'9', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4394, 56, N'2', N'10', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4395, 56, N'2', N'11', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4396, 56, N'2', N'12', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4397, 57, N'2', N'13', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4398, 57, N'2', N'14', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4399, 57, N'2', N'15', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4400, 57, N'2', N'16', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4401, 55, N'3', N'1', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4402, 55, N'3', N'2', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4403, 55, N'3', N'3', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4404, 55, N'3', N'4', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4405, 55, N'3', N'5', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4406, 55, N'3', N'6', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4407, 56, N'3', N'7', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4408, 56, N'3', N'8', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4409, 56, N'3', N'9', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4410, 56, N'3', N'10', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4411, 56, N'3', N'11', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4412, 56, N'3', N'12', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4413, 57, N'3', N'13', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4414, 57, N'3', N'14', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4415, 57, N'3', N'15', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4416, 57, N'3', N'16', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4417, 55, N'4', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4418, 55, N'4', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4419, 55, N'4', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4420, 55, N'4', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4421, 55, N'4', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4422, 55, N'4', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4423, 56, N'4', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4424, 56, N'4', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4425, 56, N'4', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4426, 56, N'4', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4427, 56, N'4', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4428, 56, N'4', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4429, 57, N'4', N'13', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4430, 57, N'4', N'14', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4431, 57, N'4', N'15', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4432, 57, N'4', N'16', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4433, 55, N'5', N'1', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4434, 55, N'5', N'2', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4435, 55, N'5', N'3', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4436, 55, N'5', N'4', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4437, 55, N'5', N'5', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4438, 55, N'5', N'6', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4439, 56, N'5', N'7', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4440, 56, N'5', N'8', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4441, 56, N'5', N'9', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4442, 56, N'5', N'10', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4443, 56, N'5', N'11', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4444, 56, N'5', N'12', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4445, 57, N'5', N'13', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4446, 57, N'5', N'14', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4447, 57, N'5', N'15', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4448, 57, N'5', N'16', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4449, 55, N'6', N'1', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4450, 55, N'6', N'2', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4451, 55, N'6', N'3', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4452, 55, N'6', N'4', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4453, 55, N'6', N'5', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4454, 55, N'6', N'6', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4455, 56, N'6', N'7', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4456, 56, N'6', N'8', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4457, 56, N'6', N'9', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4458, 56, N'6', N'10', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4459, 56, N'6', N'11', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4460, 56, N'6', N'12', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4461, 57, N'6', N'13', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4462, 57, N'6', N'14', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4463, 57, N'6', N'15', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4464, 57, N'6', N'16', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4465, 55, N'7', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4466, 55, N'7', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4467, 55, N'7', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4468, 55, N'7', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4469, 55, N'7', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4470, 55, N'7', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4471, 56, N'7', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4472, 56, N'7', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4473, 56, N'7', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4474, 56, N'7', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4475, 56, N'7', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4476, 56, N'7', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4477, 57, N'7', N'13', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4478, 57, N'7', N'14', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4479, 57, N'7', N'15', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4480, 57, N'7', N'16', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4481, 55, N'8', N'1', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4482, 55, N'8', N'2', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4483, 55, N'8', N'3', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4484, 55, N'8', N'4', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4485, 55, N'8', N'5', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4486, 55, N'8', N'6', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4487, 56, N'8', N'7', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4488, 56, N'8', N'8', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4489, 56, N'8', N'9', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4490, 56, N'8', N'10', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4491, 56, N'8', N'11', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4492, 56, N'8', N'12', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4493, 57, N'8', N'13', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4494, 57, N'8', N'14', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4495, 57, N'8', N'15', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4496, 57, N'8', N'16', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4497, 55, N'9', N'1', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4498, 55, N'9', N'2', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4499, 55, N'9', N'3', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4500, 55, N'9', N'4', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4501, 55, N'9', N'5', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4502, 55, N'9', N'6', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4503, 56, N'9', N'7', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4504, 56, N'9', N'8', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4505, 56, N'9', N'9', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4506, 56, N'9', N'10', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4507, 56, N'9', N'11', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4508, 56, N'9', N'12', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4509, 57, N'9', N'13', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4510, 57, N'9', N'14', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4511, 57, N'9', N'15', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4512, 57, N'9', N'16', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4513, 55, N'10', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4514, 55, N'10', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4515, 55, N'10', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4516, 55, N'10', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4517, 55, N'10', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4518, 55, N'10', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4519, 56, N'10', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4520, 56, N'10', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4521, 56, N'10', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4522, 56, N'10', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4523, 56, N'10', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4524, 56, N'10', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4525, 57, N'10', N'13', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4526, 57, N'10', N'14', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4527, 57, N'10', N'15', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4528, 57, N'10', N'16', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4529, 55, N'11', N'1', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4530, 55, N'11', N'2', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4531, 55, N'11', N'3', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4532, 55, N'11', N'4', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4533, 55, N'11', N'5', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4534, 55, N'11', N'6', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4535, 56, N'11', N'7', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4536, 56, N'11', N'8', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4537, 56, N'11', N'9', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4538, 56, N'11', N'10', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4539, 56, N'11', N'11', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4540, 56, N'11', N'12', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4541, 57, N'11', N'13', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4542, 57, N'11', N'14', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4543, 57, N'11', N'15', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4544, 57, N'11', N'16', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4545, 55, N'12', N'1', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4546, 55, N'12', N'2', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4547, 55, N'12', N'3', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4548, 55, N'12', N'4', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4549, 55, N'12', N'5', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4550, 55, N'12', N'6', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4551, 56, N'12', N'7', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4552, 56, N'12', N'8', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4553, 56, N'12', N'9', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4554, 56, N'12', N'10', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4555, 56, N'12', N'11', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4556, 56, N'12', N'12', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4557, 57, N'12', N'13', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4558, 57, N'12', N'14', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4559, 57, N'12', N'15', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4560, 57, N'12', N'16', 192)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4561, 58, N'1', N'1', 1)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4562, 58, N'1', N'2', 2)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4563, 58, N'1', N'3', 3)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4564, 58, N'1', N'4', 4)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4565, 58, N'1', N'5', 5)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4566, 58, N'1', N'6', 6)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4567, 59, N'1', N'7', 7)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4568, 59, N'1', N'8', 8)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4569, 59, N'1', N'9', 9)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4570, 59, N'1', N'10', 10)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4571, 59, N'1', N'11', 11)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4572, 59, N'1', N'12', 12)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4573, 60, N'1', N'13', 13)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4574, 60, N'1', N'14', 14)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4575, 60, N'1', N'15', 15)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4576, 60, N'1', N'16', 16)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4577, 58, N'2', N'1', 17)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4578, 58, N'2', N'2', 18)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4579, 58, N'2', N'3', 19)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4580, 58, N'2', N'4', 20)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4581, 58, N'2', N'5', 21)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4582, 58, N'2', N'6', 22)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4583, 59, N'2', N'7', 23)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4584, 59, N'2', N'8', 24)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4585, 59, N'2', N'9', 25)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4586, 59, N'2', N'10', 26)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4587, 59, N'2', N'11', 27)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4588, 59, N'2', N'12', 28)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4589, 60, N'2', N'13', 29)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4590, 60, N'2', N'14', 30)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4591, 60, N'2', N'15', 31)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4592, 60, N'2', N'16', 32)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4593, 58, N'3', N'1', 33)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4594, 58, N'3', N'2', 34)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4595, 58, N'3', N'3', 35)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4596, 58, N'3', N'4', 36)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4597, 58, N'3', N'5', 37)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4598, 58, N'3', N'6', 38)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4599, 59, N'3', N'7', 39)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4600, 59, N'3', N'8', 40)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4601, 59, N'3', N'9', 41)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4602, 59, N'3', N'10', 42)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4603, 59, N'3', N'11', 43)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4604, 59, N'3', N'12', 44)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4605, 60, N'3', N'13', 45)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4606, 60, N'3', N'14', 46)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4607, 60, N'3', N'15', 47)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4608, 60, N'3', N'16', 48)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4609, 58, N'4', N'1', 49)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4610, 58, N'4', N'2', 50)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4611, 58, N'4', N'3', 51)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4612, 58, N'4', N'4', 52)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4613, 58, N'4', N'5', 53)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4614, 58, N'4', N'6', 54)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4615, 59, N'4', N'7', 55)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4616, 59, N'4', N'8', 56)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4617, 59, N'4', N'9', 57)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4618, 59, N'4', N'10', 58)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4619, 59, N'4', N'11', 59)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4620, 59, N'4', N'12', 60)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4621, 60, N'4', N'13', 61)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4622, 60, N'4', N'14', 62)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4623, 60, N'4', N'15', 63)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4624, 60, N'4', N'16', 64)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4625, 58, N'5', N'1', 65)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4626, 58, N'5', N'2', 66)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4627, 58, N'5', N'3', 67)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4628, 58, N'5', N'4', 68)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4629, 58, N'5', N'5', 69)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4630, 58, N'5', N'6', 70)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4631, 59, N'5', N'7', 71)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4632, 59, N'5', N'8', 72)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4633, 59, N'5', N'9', 73)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4634, 59, N'5', N'10', 74)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4635, 59, N'5', N'11', 75)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4636, 59, N'5', N'12', 76)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4637, 60, N'5', N'13', 77)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4638, 60, N'5', N'14', 78)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4639, 60, N'5', N'15', 79)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4640, 60, N'5', N'16', 80)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4641, 58, N'6', N'1', 81)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4642, 58, N'6', N'2', 82)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4643, 58, N'6', N'3', 83)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4644, 58, N'6', N'4', 84)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4645, 58, N'6', N'5', 85)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4646, 58, N'6', N'6', 86)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4647, 59, N'6', N'7', 87)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4648, 59, N'6', N'8', 88)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4649, 59, N'6', N'9', 89)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4650, 59, N'6', N'10', 90)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4651, 59, N'6', N'11', 91)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4652, 59, N'6', N'12', 92)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4653, 60, N'6', N'13', 93)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4654, 60, N'6', N'14', 94)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4655, 60, N'6', N'15', 95)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4656, 60, N'6', N'16', 96)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4657, 58, N'7', N'1', 97)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4658, 58, N'7', N'2', 98)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4659, 58, N'7', N'3', 99)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4660, 58, N'7', N'4', 100)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4661, 58, N'7', N'5', 101)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4662, 58, N'7', N'6', 102)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4663, 59, N'7', N'7', 103)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4664, 59, N'7', N'8', 104)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4665, 59, N'7', N'9', 105)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4666, 59, N'7', N'10', 106)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4667, 59, N'7', N'11', 107)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4668, 59, N'7', N'12', 108)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4669, 60, N'7', N'13', 109)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4670, 60, N'7', N'14', 110)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4671, 60, N'7', N'15', 111)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4672, 60, N'7', N'16', 112)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4673, 58, N'8', N'1', 113)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4674, 58, N'8', N'2', 114)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4675, 58, N'8', N'3', 115)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4676, 58, N'8', N'4', 116)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4677, 58, N'8', N'5', 117)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4678, 58, N'8', N'6', 118)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4679, 59, N'8', N'7', 119)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4680, 59, N'8', N'8', 120)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4681, 59, N'8', N'9', 121)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4682, 59, N'8', N'10', 122)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4683, 59, N'8', N'11', 123)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4684, 59, N'8', N'12', 124)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4685, 60, N'8', N'13', 125)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4686, 60, N'8', N'14', 126)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4687, 60, N'8', N'15', 127)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4688, 60, N'8', N'16', 128)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4689, 58, N'9', N'1', 129)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4690, 58, N'9', N'2', 130)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4691, 58, N'9', N'3', 131)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4692, 58, N'9', N'4', 132)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4693, 58, N'9', N'5', 133)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4694, 58, N'9', N'6', 134)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4695, 59, N'9', N'7', 135)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4696, 59, N'9', N'8', 136)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4697, 59, N'9', N'9', 137)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4698, 59, N'9', N'10', 138)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4699, 59, N'9', N'11', 139)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4700, 59, N'9', N'12', 140)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4701, 60, N'9', N'13', 141)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4702, 60, N'9', N'14', 142)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4703, 60, N'9', N'15', 143)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4704, 60, N'9', N'16', 144)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4705, 58, N'10', N'1', 145)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4706, 58, N'10', N'2', 146)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4707, 58, N'10', N'3', 147)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4708, 58, N'10', N'4', 148)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4709, 58, N'10', N'5', 149)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4710, 58, N'10', N'6', 150)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4711, 59, N'10', N'7', 151)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4712, 59, N'10', N'8', 152)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4713, 59, N'10', N'9', 153)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4714, 59, N'10', N'10', 154)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4715, 59, N'10', N'11', 155)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4716, 59, N'10', N'12', 156)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4717, 60, N'10', N'13', 157)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4718, 60, N'10', N'14', 158)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4719, 60, N'10', N'15', 159)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4720, 60, N'10', N'16', 160)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4721, 58, N'11', N'1', 161)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4722, 58, N'11', N'2', 162)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4723, 58, N'11', N'3', 163)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4724, 58, N'11', N'4', 164)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4725, 58, N'11', N'5', 165)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4726, 58, N'11', N'6', 166)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4727, 59, N'11', N'7', 167)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4728, 59, N'11', N'8', 168)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4729, 59, N'11', N'9', 169)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4730, 59, N'11', N'10', 170)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4731, 59, N'11', N'11', 171)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4732, 59, N'11', N'12', 172)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4733, 60, N'11', N'13', 173)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4734, 60, N'11', N'14', 174)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4735, 60, N'11', N'15', 175)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4736, 60, N'11', N'16', 176)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4737, 58, N'12', N'1', 177)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4738, 58, N'12', N'2', 178)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4739, 58, N'12', N'3', 179)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4740, 58, N'12', N'4', 180)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4741, 58, N'12', N'5', 181)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4742, 58, N'12', N'6', 182)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4743, 59, N'12', N'7', 183)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4744, 59, N'12', N'8', 184)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4745, 59, N'12', N'9', 185)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4746, 59, N'12', N'10', 186)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4747, 59, N'12', N'11', 187)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4748, 59, N'12', N'12', 188)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4749, 60, N'12', N'13', 189)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4750, 60, N'12', N'14', 190)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4751, 60, N'12', N'15', 191)
GO
INSERT [Tickets].[TicketSeats] ([No], [TicketGateNo], [Row], [Seat], [Sort]) VALUES (4752, 60, N'12', N'16', 192)
GO




