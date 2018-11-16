
using System;
using System.Collections.Generic;
using System.Text;

namespace eTicketLoaderApp
{
    public class LogService
    {
        public LogService()
        {

        }

        public void AddLog(Log log)
        {
            using (TicketContextProvider context = new TicketContext())
            {
                context.Log.AddLog(log);
            }
        }
    }
}
