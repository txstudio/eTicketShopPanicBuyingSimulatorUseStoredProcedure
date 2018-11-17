
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Text;

namespace eTicketLoaderApp
{

    public sealed class LogRepository : ILogRepository
    {
        private string _connectionString;

        public LogRepository(string connectionString)
        {
            this._connectionString = connectionString;
        }

        public void AddLog(Log item)
        {
            using (SqlConnection _conn = new SqlConnection())
            {
                _conn.ConnectionString = this._connectionString;

                SqlCommand _cmd;

                _cmd = new SqlCommand();
                _cmd.Connection = _conn;

                _cmd.CommandText = "[Logs].[AddLog]";
                _cmd.CommandType = CommandType.StoredProcedure;

                _cmd.Parameters.Add("@memberGUID", SqlDbType.UniqueIdentifier);
                _cmd.Parameters.Add("@TicketNumber", SqlDbType.Int);
                _cmd.Parameters.Add("@Elapsed", SqlDbType.Int);
                _cmd.Parameters.Add("@IsSuccess", SqlDbType.Bit);
                _cmd.Parameters.Add("@Exception", SqlDbType.NVarChar, 250);
                _cmd.Parameters.Add("@Retry", SqlDbType.Int);

                _cmd.Parameters["@memberGUID"].Value = item.MemberGUID;
                _cmd.Parameters["@TicketNumber"].Value = item.TicketNumber;
                _cmd.Parameters["@Elapsed"].Value = item.Elapsed;
                _cmd.Parameters["@IsSuccess"].Value = item.IsSuccess;

                if (string.IsNullOrWhiteSpace(item.Exception) == true)
                    _cmd.Parameters["@Exception"].Value = DBNull.Value;
                else
                    _cmd.Parameters["@Exception"].Value = item.Exception;

                _cmd.Parameters["@Retry"].Value = item.Retry;

                _conn.Open();
                _cmd.ExecuteNonQuery();
                _conn.Close();
            }
        }
    }
}
