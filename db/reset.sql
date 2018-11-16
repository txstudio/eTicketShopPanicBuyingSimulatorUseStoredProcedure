USE [eTicketShop]
GO

TRUNCATE TABLE [Tickets].[TicketOrders]
GO

EXEC [Tickets].[CreateTicketOrderByEventNo] 1,N'測試管理員'
GO

TRUNCATE TABLE [Logs].[Logs]
GO