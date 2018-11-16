using System;
using System.Collections.Generic;
using System.Text;

namespace eTicketLoaderApp
{
    public sealed class TicketBuyer
    {
        public int TicketEventNo { get; set; }
        public int GateNo { get; set; }
        public Nullable<Guid> memberGUID { get; set; }
        public int TicketCount { get; set; }
    }
}
