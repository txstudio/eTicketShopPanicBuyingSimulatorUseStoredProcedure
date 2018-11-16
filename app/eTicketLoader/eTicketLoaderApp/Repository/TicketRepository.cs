
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Text;

namespace eTicketLoaderApp
{

    public sealed class TicketRepository : ITicketRepository
    {
        private string _connectionString;

        public TicketRepository(string connectionString)
        {
            this._connectionString = connectionString;
        }

        public IEnumerable<TicketEventStatus> GetTicketEventStatus(int eventNo)
        {
            IEnumerable<TicketEventStatus> _status;

            _status = null;

            using (SqlConnection _conn = new SqlConnection())
            {
                _conn.ConnectionString = this._connectionString;

                SqlCommand _cmd;

                _cmd = new SqlCommand();
                _cmd.Connection = _conn;

                _cmd.CommandText = "SELECT * FROM [Tickets].[GetTicketEventStatus](@TicketEventNo)";
                _cmd.CommandType = CommandType.Text;

                _cmd.Parameters.Add("@TicketEventNo", SqlDbType.Int);
                _cmd.Parameters["@TicketEventNo"].Value = eventNo;

                _conn.Open();

                var _reader = _cmd.ExecuteReader();

                _status = this.MapToTicketEventStatus(_reader);

                _conn.Close();
            }

            return _status;
        }

        public bool BuyTicketAuto(TicketBuyer buyer)
        {
            using (SqlConnection _conn = new SqlConnection())
            {
                _conn.ConnectionString = this._connectionString;

                SqlCommand _cmd;

                _cmd = new SqlCommand();
                _cmd.Connection = _conn;

                _cmd.CommandText = "[Tickets].[BuyTicketAuto]";
                _cmd.CommandType = CommandType.StoredProcedure;

                _cmd.Parameters.Add("@TicketEventNo", SqlDbType.Int);
                _cmd.Parameters.Add("@GateNo", SqlDbType.Int);
                _cmd.Parameters.Add("@memberGUID", SqlDbType.UniqueIdentifier);
                _cmd.Parameters.Add("@TicketCount", SqlDbType.TinyInt);
                _cmd.Parameters.Add("@IsSuccess", SqlDbType.Bit);


                _cmd.Parameters["@TicketEventNo"].Value = buyer.TicketEventNo;
                _cmd.Parameters["@GateNo"].Value = buyer.GateNo;
                _cmd.Parameters["@memberGUID"].Value = buyer.memberGUID;
                _cmd.Parameters["@TicketCount"].Value = buyer.TicketCount;
                _cmd.Parameters["@IsSuccess"].Value = DBNull.Value;

                _cmd.Parameters["@IsSuccess"].Direction = ParameterDirection.Output;

                _conn.Open();
                _cmd.ExecuteNonQuery();
                _conn.Close();

                if(_cmd.Parameters["@IsSuccess"].Value == DBNull.Value)
                    return false;

                return Convert.ToBoolean(_cmd.Parameters["@IsSuccess"].Value);
            }
        }


        private IEnumerable<TicketEventStatus> MapToTicketEventStatus(SqlDataReader reader)
        {
            if (reader.HasRows == false)
                return null;

            List<TicketEventStatus> _items;
            TicketEventStatus _item;

            _items = new List<TicketEventStatus>();

            while (reader.Read())
            {
                _item = new TicketEventStatus();

                if (reader.IsDBNull(0) == false)
                    _item.TicketGateNo = reader.GetInt32(0);
                if (reader.IsDBNull(1) == false)
                    _item.Gate = reader.GetString(1);
                if (reader.IsDBNull(2) == false)
                    _item.Section = reader.GetString(2);
                if (reader.IsDBNull(3) == false)
                    _item.ListPrice = reader.GetDecimal(3);
                if (reader.IsDBNull(4) == false)
                    _item.TicketSell = reader.GetInt32(4);
                if (reader.IsDBNull(5) == false)
                    _item.TicketTotal = reader.GetInt32(5);

                _items.Add(_item);
            }

            return _items.ToArray();
        }
    }
}
