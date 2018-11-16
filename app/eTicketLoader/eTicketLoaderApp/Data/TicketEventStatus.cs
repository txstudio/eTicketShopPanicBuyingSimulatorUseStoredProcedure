using System;
using System.Collections.Generic;
using System.Text;

namespace eTicketLoaderApp
{
    public sealed class TicketEventStatus
    {
        public int TicketGateNo { get; set; }
        public string Gate { get; set; }
        public string Section { get; set; }
        public Nullable<Decimal> ListPrice { get; set; }
        public int TicketSell { get; set; }
        public int TicketTotal { get; set; }

        public int TicketLeft
        {
            get
            {
                return (this.TicketTotal - this.TicketSell);
            }
        }

    }
}
