
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

namespace eTicketLoaderApp
{
    class Program
    {
        public static int GlobalEventNo = 1;

        /// <summary>要建立的執行緒最大值</summary>
        static int _taskLimit = 10000;

        static bool _exit = false;
        
        static void Main(string[] args)
        {
            List<Task> _tasks;

            _tasks = new List<Task>();

            for (int i = 0; i < _taskLimit; i++)
                _tasks.Add(new Task(eShopTickeBuyer));

            for (int i = 0; i < _taskLimit; i++)
                _tasks[i].Start();

            while (_exit == false)
            {
                _exit = true;

                for (int i = 0; i < _taskLimit; i++)
                {
                    if (_tasks[i].Status == TaskStatus.Running)
                    {

                    }

                    if (_tasks[i].Status == TaskStatus.Running
                        || _tasks[i].Status == TaskStatus.WaitingToRun)
                    {
                        Thread.Sleep(10);
                        _exit = false;
                        continue;
                    }
                }

                if (_exit == false)
                    continue;

                _exit = true;

                Thread.Sleep(100);
            }



            Console.WriteLine("press any key to exit");
            Console.ReadKey();
        }

        static void eShopTickeBuyer()
        {
            var _randomService = new RandomService();
            var _tickeService = new TicketService();
            var _logService = new LogService();

            Log _log;

            while (true)
            {
                Stopwatch _stopwatch = new Stopwatch();

                _stopwatch.Reset();
                _stopwatch.Start();

                var _alltickets = _tickeService.GetTicketEventStatus(GlobalEventNo);
                var _tickets = _tickeService.GetSellableTickets(_alltickets);

                if (_tickets == null)
                    break;

                _log = new Log();

                try
                {
                    var _buyer = _randomService.GetRandomTicket(_tickets);

                    var _IsSuccess = _tickeService.BuyTicketAuto(_buyer);

                    _stopwatch.Stop();

                    _log.MemberGUID = _buyer.memberGUID;
                    _log.TicketNumber = _buyer.TicketCount;
                    _log.ListPrice = (-1);
                    _log.Elapsed = Convert.ToInt32(_stopwatch.ElapsedMilliseconds);
                    _log.IsSuccess = _IsSuccess;

                }
                catch (Exception ex)
                {
                    _log.Exception = ex.Message;
                }

                _logService.AddLog(_log);
            }
        }
    }

}
