#encoding=utf-8

require 'qt'
require 'qtwebkit'
require 'eventmachine'
require 'json'
require 'thin'
require 'date'

module QtKendo
  SOURCE = <<EOS
  <!doctype html>
  <html>
      <head>
          <meta charset="UTF-8">
          <title>QtKendoGraph</title>
          <link href="./kendoui/styles/kendo.common.css" rel="stylesheet"/>
          <link href="./kendoui/styles/kendo.default.css" rel="stylesheet"/>
          <script src="./kendoui/js/jquery.min.js"></script>
          <script src="./kendoui/js/kendo.core.min.js"></script>
          <script src="./kendoui/js/kendo.data.min.js"></script>
          <script src="./kendoui/js/kendo.chart.min.js"></script>
      </head>
      <body>
          <div id="example" class="k-content">
              <div class="chart-wrapper">
                  <div id="chart"></div>
              </div>
              <script>
                  function lineChart(d) {
                      $("#chart").kendoChart({
                          title: {
                              text: d.title
                          },
                          dataSource: new kendo.data.DataSource(
                            {
                              transport: {
                               read: {
                                 url: "http://127.0.0.1:8080/stats.json",
                                 dataType: "json",
                                 data: {
                                   type: d.type,
                                   sdate: d.sdate,
                                   edate: d.edate,
                                   unit: d.unit
                                 }
                               }
                              }
                            }
                          ),
                          legend: {
                              position: "bottom"
                          },
                          seriesDefaults: {
                              type: "line"
                          },
                          series: [{
                              field: "count",
                              name: d.valueName || "counts"
                          }],
                          categoryAxis: {
                              field: "period",
                              name: d.periodName || "period"
                          },
                          tooltip: {
                              visible: true
                          },
                          seriesClick: function(e) {
                              observer.draw_pie(e.category);
                          }
                      });
                  }

                  function stackedChart(d) {
                      $("#chart").kendoChart({
                          title: {
                              text: d.title
                          },
                          dataSource: new kendo.data.DataSource(
                            {
                              transport: {
                               read: {
                                 url: "http://127.0.0.1:8080/all_stats.json",
                                 dataType: "json",
                                 data: {
                                   type: d.type,
                                   sdate: d.sdate,
                                   edate: d.edate,
                                   unit: d.unit
                                 }
                               }
                              }
                            }
                          ),
                          legend: {
                              position: "bottom"
                          }, 
                          seriesDefaults: {
                              type: "column",
                              stack: true
                          },
                          series: d.seriesInfo,
                          categoryAxis: {
                              field: "period"
                          },
                          tooltip: {
                              visible: true
                          }
                      });
                  }

                  function pieChart(d) {
                      $("#chart").kendoChart({
                          title: {
                              text: d.title
                          },
                          dataSource: new kendo.data.DataSource(
                            {
                              transport: {
                               read: {
                                 url: "http://127.0.0.1:8080/sub_stats.json",
                                 dataType: "json",
                                 data: {
                                   type: d.type,
                                   sdate: d.sdate,
                                   edate: d.edate,
                                   unit: d.unit,
                                   period: d.period
                                 }
                               }
                              }
                            }
                          ),
                          legend: {
                              position: "bottom"
                          },
                          series: [{
                              type: "pie",
                              field: "count",
                              categoryField: "category"
                          }],
                          tooltip: {
                              visible: true
                          },
                          seriesClick: function(e) {
                              observer.draw();
                          }
                      });
                  }
              </script>
          </div>
      </body>
  </html>
EOS

  class MyWidget < Qt::Widget
    attr_reader :units
    slots :add_js_object, :update_calendar, :update_end_date, :enable_redraw, :draw, 'draw_pie(QString)', :quit, 'run_java_script(bool)', 'toggle_stacked(bool)'
  
    def initialize(parent = nil, query_object, http_server)
      super(parent)
      @query_object = query_object
      @http_server = http_server
      min_date, max_date = query_object.date_range
      @min_date = DateTime.parse(min_date)
      @max_date = (max_date.nil?) ? DateTime.new : DateTime.parse(max_date)
      @end_date = DateTime.new
      @stacked_graph = false
      
      init_widgets
    end
    
    # initialize widgets, connecting signals / slots
    # intialized variables other than widgets
    #   1. @symbols : symbol of query_object's type 
    #   2. @units : date units
    def init_widgets
      @web = Qt::WebView.new(self)
      @redraw = Qt::PushButton.new('Redraw', @web)
      @redraw.move(10, 5)
      @redraw.enabled = false
      connect(@redraw, SIGNAL('clicked()'), self, SLOT('draw()'))
      @symbols = []
      
      @graph_list = Qt::ListWidget.new
      @query_object.types.each do |t|
        Qt::ListWidgetItem.new(t[0], @graph_list)
        @symbols << t[1]
      end
      @graph_list.currentRow = 0
      connect(@graph_list, SIGNAL('currentRowChanged(int)'), self, SLOT('enable_redraw()'))
    
      @number_list = Qt::ListWidget.new
      (1..12).each do |n|
        Qt::ListWidgetItem.new(n.to_s, @number_list)
      end
      @number_list.currentRow = 6
      connect(@number_list, SIGNAL('currentRowChanged(int)'), self, SLOT('update_calendar()'))
      connect(@number_list, SIGNAL('currentRowChanged(int)'), self, SLOT('enable_redraw()'))
      
      @units = [:day, :week, :month, :quarter, :half, :year]
      @unit_list = Qt::ListWidget.new
      ['day', 'week', 'month', 'quarter', 'half', 'year'].each do |p|
        Qt::ListWidgetItem.new(p, @unit_list)
      end
      @unit_list.currentRow = 0
      connect(@unit_list, SIGNAL('currentRowChanged(int)'), self, SLOT('update_calendar()'))
      connect(@unit_list, SIGNAL('currentRowChanged(int)'), self, SLOT('enable_redraw()'))
      
      @calendar = Qt::CalendarWidget.new
      connect(@calendar, SIGNAL('selectionChanged()'), self, SLOT('update_end_date()'))
      connect(@calendar, SIGNAL('selectionChanged()'), self, SLOT('enable_redraw()'))
      @calendar.selectedDate = start_date

      if @query_object.respond_to?(:all_query)
        stacked = Qt::CheckBox.new('stacked', self)
        connect(stacked, SIGNAL('toggled(bool)'), self, SLOT('toggle_stacked(bool)'))
        connect(stacked, SIGNAL('toggled(bool)'), self, SLOT('enable_redraw()'))
      end
      
      quit = Qt::PushButton.new('Quit', self)
      connect(quit, SIGNAL('clicked()'), self, SLOT('quit()'))

      grid = Qt::GridLayout.new
      grid.addWidget(@graph_list, 0, 0)
      grid.addWidget(@calendar, 0, 1)
      grid.addWidget(@number_list, 0, 2)
      grid.addWidget(@unit_list, 0, 3)
      grid.addWidget(@web, 1, 0, 1, 4)
      grid.addWidget(stacked, 2, 0, 1, 1)
      grid.addWidget(quit, 2, 2, 1, 2)
      grid.setColumnStretch(0, 20)
      grid.setColumnStretch(1, 20)
      grid.setColumnStretch(2, 5)
      grid.setColumnStretch(3, 5)
      grid.setRowStretch(0, 20)
      grid.setRowStretch(1, 70)
      grid.setRowStretch(2, 5)
      setLayout(grid)
      
      resize(800, 700)

      base = Qt::Url.fromLocalFile("#{Dir.getwd}/")
  	  @web.set_html(SOURCE, base)
  	  connect(@web.page.mainFrame, SIGNAL('javaScriptWindowObjectCleared()'), self, SLOT('add_js_object()'))
  	  connect(@web.page.mainFrame, SIGNAL('loadFinished(bool)'), self, SLOT('run_java_script(bool)'))
    end
    
    # enable redraw button
    # connected : list widget's change signal
    def enable_redraw
      @redraw.enabled = true
    end
    
    # update calendar widget's date
    # called : number / unit list's change signal
    def update_calendar
      @calendar.selectedDate = start_date
    end
    
    # calculated date (QDate) according to number, unit from today
    # called : widget init, update_calendar
    def start_date
      now = DateTime.now
      case @unit_list.currentRow
      when 0     # day
        start = now - @number_list.currentRow
        year, month, day = start.year, start.month, start.day
      when 1     # week
        mday = now - (now.wday==0 ? 6 : now.wday - 1)
        start = mday - @number_list.currentRow * 7
        year, month, day = start.year, start.month, start.day
      when 2     # month        
        year, month, day = now.year, now.month, 1
        @number_list.currentRow.times do
          month -= 1
          if month == 0
            year -= 1
            month = 12
          end
        end
      when 3     # quarter (3 months)
        year, month, day = now.year, now.month, 1
        @number_list.currentRow.times do
          month -= 3
          if month < 1
            year -= 1
            month += 12
          end
        end
        month = ((month-1) / 3) * 3 + 1
      when 4     # half (6 months)
        year, month, day = now.year, now.month, 1
        @number_list.currentRow.times do
          month -= 6
          if month < 1
            year -= 1
            month += 12
          end
        end
        month = ((month-1) / 6) * 6 + 1        
      when 5     # year
        year, month, day = now.year - @number_list.currentRow, 1, 1
      end
      Qt::Date.new(year, month, day)      
    end

    # called from update_end_date
    def last_day(year, month)
      (month == 2) ? (DateTime.leap?(year) ? 29 : 28) : ((month <= 7 and month.odd?) or (month >= 8 and month.even?)) ? 31 : 30
    end
    
    # updates instance variable @end_date
    # connected to calendar's change event
    def update_end_date
      year, month, day = @calendar.selectedDate.year, @calendar.selectedDate.month, @calendar.selectedDate.day
      start_date = DateTime.new(year, month, day)
      case @unit_list.currentRow
      when 0     # day
        edate = start_date + @number_list.currentRow
        year, month, day = edate.year, edate.month, edate.day
      when 1     # week
        mday = start_date - (start_date.wday==0 ? 6 : start_date.wday - 1)
        edate = mday + @number_list.currentRow * 7 + 6        # sunday
        year, month, day = edate.year, edate.month, edate.day
      when 2     # month        
        @number_list.currentRow.times do
          month += 1
          if month == 13
            year += 1
            month = 1
          end
        end
        day = last_day(year, month)
      when 3     # quarter (3 months)
        @number_list.currentRow.times do
          month += 3
          if month > 12
            year += 1
            month -= 12
          end
        end
        month = ((month-1) / 3) * 3 + 1
        day = last_day(year, month)        
      when 4     # half (6 months)
        @number_list.currentRow.times do
          month += 6
          if month > 12
            year += 1
            month -= 12
          end
        end
        month = ((month-1) / 6) * 6 + 1
        day = last_day(year, month)
      when 5     # year
        year, month, day = start_date.year + @number_list.currentRow, 12, 31
      end
      today = DateTime.now
      end_date = DateTime.new(year, month, day)
      @end_date = (today < end_date) ? today : end_date
    end
    
    # add self to javascript world as variable 'observer'    
    def add_js_object()
  	  @web.page.mainFrame.add_to_java_script_window_object('observer', self)
    end
    
    # draw chart 
    # called : redraw button cliked signal
    def draw
      @redraw.enabled = false
      if @stacked_graph
        p parameters = js_object(:seriesInfo=>'[{field: "ABD", name: "Abdomen"}, {field: "HEART", name: "Heart"}, {field: "MS", name: "Musculoskeletal"}, {field: "THYROID", name: "Thyroid"}]')
        @web.page.mainFrame.evaluate_java_script("stackedChart(#{parameters})")        
      else
        parameters = js_object
        @web.page.mainFrame.evaluate_java_script("lineChart(#{parameters})")
      end
    end
    
    # stacked check box slot
    def toggle_stacked(flag)
      @stacked_graph = flag
    end
    
    # make javascript object string according to type, start_date, end_date, unit
    # parameter period is for sub_query
    def js_object(args={})
      params = ''
      args.each_pair do |k, v|
        params += "#{k}:#{v}, "
      end
      "{ %s title:\"#{@graph_list.currentItem.text}\", type:\"#{@symbols[@graph_list.currentRow]}\", 
      unit:\"#{@units[@unit_list.currentRow]}\", 
      sdate:\"#{@calendar.selectedDate.toString('yyyy-MM-dd')}\", 
        edate:\"#{@end_date.strftime('%Y-%m-%d')}\"}" % params
    end
    
    def run_java_script(success)
      parameters = js_object
      @web.page.mainFrame.evaluate_java_script("$(document).ready(function() { lineChart(#{parameters}); });")
    end
  
    def draw_pie(n)      
      parameters = js_object(:period=>"\"#{n}\"")
      @web.page.mainFrame.evaluate_java_script("pieChart(#{parameters})")
    end
  
    def quit()
      @http_server.stop!
      EM.next_tick { EM.stop }
    end
  end

  def run(klass, port=8080)
    EM.run do

      query_object = klass.new
      
      server = Thin::Server.new('0.0.0.0', port) do
        use Rack::CommonLogger
        map '/stats.json' do
          run Proc.new { |env| 
            params = Hash[env['QUERY_STRING'].split('&').collect { |q| q.split('=')}]
            [ 200, {"Content-Type"=>"application/json", "Access-Control-Allow-Origin"=>"*"}, 
              [JSON.generate(query_object.query(params['type'], Date.strptime(params['sdate']), 
                  Date.strptime(params['edate']), params['unit'].to_sym))]
            ]}
        end
        map '/sub_stats.json' do
          run Proc.new { |env| 
            params = Hash[env['QUERY_STRING'].split('&').collect { |q| q.split('=')}]
            [ 200, {"Content-Type"=>"application/json", "Access-Control-Allow-Origin"=>"*"}, 
              [JSON.generate(query_object.sub_query(params['type'], params['period'], params['unit'].to_sym))]
            ]}
        end
        map '/all_stats.json' do
          run Proc.new { |env| 
            params = Hash[env['QUERY_STRING'].split('&').collect { |q| q.split('=')}]
            [ 200, {"Content-Type"=>"application/json", "Access-Control-Allow-Origin"=>"*"}, 
              [JSON.generate(query_object.all_query(params['type'], Date.strptime(params['sdate']), 
                  Date.strptime(params['edate']), params['unit'].to_sym))]
            ]}
        end
      end
  
      app = Qt::Application.new(ARGV)

      widget = MyWidget.new(nil, query_object, server)
      widget.show

      EM.add_periodic_timer(0.02) { app.process_events }  

      server.start 
    end    
  end
    
  module_function :run
end