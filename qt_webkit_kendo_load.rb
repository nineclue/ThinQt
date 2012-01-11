#encoding=utf-8

require 'qt'
require 'qtwebkit'
require 'eventmachine'
require 'json'
require 'thin'
require './exam_model'

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
                               url: "http://127.0.0.1:8080/us_stats.json",
                               dataType: "json"
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
                            name: "검사 건수"
                        }],
                        categoryAxis: {
                            field: "month"
                        },
                        tooltip: {
                            visible: true
                        },
                        seriesClick: function(e) {
                            observer.notify_select(e.category);
                        }
                    });
                }

                function columnChart(d) {
                    $("#chart").kendoChart({
                        title: {
                            text: d.title
                        },
                        dataSource: new kendo.data.DataSource(
                          {
                            transport: {
                             read: {
                               url: "http://127.0.0.1:8080/stacked_stats.json",
                               dataType: "json"
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
                        series: [{
                            field: "ABD",
                            name: "복부"
                        }, {
                            field: "HEART",
                            name: "심장"
                        }, {
                            field: "MS",
                            name: "근골격"
                        }, {
                            field: "THYROID",
                            name: "갑상선"
                        }],
                        categoryAxis: {
                            field: "month"
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
                                 q: d.category
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
                            field: "value",
                            categoryField: "category"
                        }],
                        tooltip: {
                            visible: true
                        },
                        seriesClick: function(e) {
                            observer.notify_select(e.category);
                        }
                    });
                }
            </script>
        </div>
    </body>
</html>
EOS

class MyWidget < Qt::Widget
  slots :add_js_object, 'notify_select(QString)', :quit, :pie, :stacked, 'run_java_script(bool)'
  
  def initialize(parent = nil, http_server)
    super(parent)
    @http_server = http_server
    
    @web = Qt::WebView.new(self)
	
    pie = Qt::PushButton.new('파이 차트', self)
    connect(pie, SIGNAL('clicked()'), self, SLOT('pie()'))
    stack = Qt::PushButton.new('컬럼 차트', self)
    connect(stack, SIGNAL('clicked()'), self, SLOT('stacked()'))

    quit = Qt::PushButton.new('종료', self)
    connect(quit, SIGNAL('clicked()'), self, SLOT('quit()'))
	
    layout = Qt::VBoxLayout.new
    layout.addWidget(@web)
    hlayout = Qt::HBoxLayout.new
    hlayout.addWidget(pie)
    hlayout.addWidget(stack)
    layout.addLayout(hlayout)
    layout.addWidget(quit)
    setLayout(layout)
    
    base = Qt::Url.fromLocalFile("#{Dir.getwd}/")
	  @web.set_html(SOURCE, base)
	  connect(@web.page.mainFrame, SIGNAL('javaScriptWindowObjectCleared()'), self, SLOT('add_js_object()'))
	  connect(@web.page.mainFrame, SIGNAL('loadFinished(bool)'), self, SLOT('run_java_script(bool)'))
  end

  def add_js_object()
	  @web.page.mainFrame.add_to_java_script_window_object('observer', self)
  end
  
  def pie()
    @web.page.mainFrame.evaluate_java_script('pieChart({title:"세부 항목", category:"2012-01"})')
  end
  
  def stacked()
    p 'stacked'    
    @web.page.mainFrame.evaluate_java_script('columnChart({title:"세부 항목"})')
  end
  
  def run_java_script(success)
    p "run javascript"
    @web.page.mainFrame.evaluate_java_script('$(document).ready(function() { lineChart({title:"초음파 검사", seriesName:"매달 count"}); });')
  end
  
  def notify_select(n)
	  p "노드가 선택되었습니다. 근데 과연 노티될까요? #{n.class} : #{n.force_encoding('UTF-8')}"
  end
  
  def quit()
    # Qt::Application.instance.quit
    @http_server.stop!
    EM.next_tick { EM.stop }
  end
end

class Stats
  def call(env)
    # "Access-Control-Allow-Origin : *" is required to ovoid Origin null not allowed problem, EUREKA!
    [200, {"Content-Type"=>"application/json", "Access-Control-Allow-Origin"=>"*"}, 
    # [JSON.generate(Exam.join(Study, :id=>:sid).filter(:modality=>'US').group_and_count(:strftime.sql_function("%Y%m", :sdate).as(:month)).order(:month).map { |x| x.values })]]
    [JSON.generate(Exam.filter(:modality=>'US').group_and_count(:strftime.sql_function("%Y년%m월", :sdate).as(:month)).map { |x| x.values})]]
  end
end

class StackedStats
  def restructure
    r =  Exam.join(Study, :id=>:sid).filter(:modality=>'US').group_and_count(:strftime.sql_function("%Y%m", :sdate).as(:month), :studies__category).order(:month, :studies__category)
    current_month = {}
    result = []
    r.each do |s|
      if current_month[:month] != s.values[:month]
        result << current_month if current_month.size > 0
        current_month = {:month=>s.values[:month]}
      end
      current_month[s.values[:category]] = s.values[:count]
    end
    result << current_month
  end
  def call(env)
    # "Access-Control-Allow-Origin : *" is required to ovoid Origin null not allowed problem, EUREKA!
    [200, {"Content-Type"=>"application/json", "Access-Control-Allow-Origin"=>"*"}, [JSON.generate(restructure)]]
  end
end

EM.run do  
  server = Thin::Server.new('0.0.0.0', 8080) do
    use Rack::CommonLogger
    map '/exam_stats.json' do
      run Proc.new { |env| [200, {"Content-Type"=>"application/json", "Access-Control-Allow-Origin"=>"*"}, 
        [JSON.generate([{:month=>"201109", "count"=>100}, {:month=>"201110", "count"=>200}, {"month"=>"201111", "count"=>210}])]
        ]}
    end
    map '/sub_stats.json' do
      run Proc.new { |env| 
        p "sub_stat : q is #{env['QUERY_STRING'].match(/q=(.+)/)[1]}"
        # p env.inspect
        [200, {"Content-Type"=>"application/json", "Access-Control-Allow-Origin"=>"*"}, 
        [JSON.generate([{:category=>"MS", :value=>100}, {:category=>"ABD", :value=>200}, {:category=>"HEART", :value=>210}])]]
      }
    end
    map '/us_stats.json' do
      run Stats.new
    end
    map '/stacked_stats.json' do
      run StackedStats.new
    end
  end
  
  app = Qt::Application.new(ARGV)

  widget = MyWidget.new(nil, server)
  widget.show

  EM.add_periodic_timer(0.02) { app.process_events }  

  server.start 
end
