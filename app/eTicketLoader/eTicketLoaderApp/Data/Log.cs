using System;
using System.Collections.Generic;
using System.Text;

namespace eTicketLoaderApp
{
    public sealed class Log
    {
        public int No { get; set; }
        public Nullable<DateTimeOffset> EventDateTime { get; set; }

        public Nullable<Guid> MemberGUID { get; set; }

        public int TicketNumber { get; set; }

        public int? Elapsed { get; set; }
        public bool? IsSuccess { get; set; }

        public string Exception { get; set; }
        public int Retry { get; set; }
    }
}
