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
        <title>영상의학과 검사</title>
        <link href="./kendoui/examples/shared/styles/examples.css" rel="stylesheet"/>
        <link href="./kendoui/examples/shared/styles/examples-offline.css" rel="stylesheet"/>
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
                function createChart() {
                    $("#chart").kendoChart({
                        title: {
                            text: "미래병원 영상의학검사"
                        },
                        dataSource: new kendo.data.DataSource(
                          {
                            transport: {
                             read: {
                               url: "http://127.0.0.1:8080/mr_stats.json",
                               dataType: "json"
                             }
                            }
                          }
                        ),
                        legend: {
                            position: "bottom"
                        },
                        series: [{
                            type: "line",
                            field: "count",
                            name: "매달 count"
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

                function pieChart(c) {
                    $("#chart").kendoChart({
                        title: {
                            text: "미래병원 영상의학검사"
                        },
                        dataSource: new kendo.data.DataSource(
                          {
                            transport: {
                             read: {
                               url: "http://127.0.0.1:8080/sub_stats.json",
                               dataType: "json",
                               data: {
                                 q: c
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

                $(document).ready(function() {
                    setTimeout(function() {
                        createChart();

                        // Initialize the chart with a delay to make sure
                        // the initial animation is visible
                    }, 400);
                });
            </script>
        </div>
    </body>
</html>
EOS

class MyWidget < Qt::Widget
  slots :add_js_object, 'notify_select(QString)', :quit, :pie
  
  def initialize(parent = nil, http_server)
    super(parent)
    @http_server = http_server
    
    @web = Qt::WebView.new(self)
	
    pie = Qt::PushButton.new('파이 차트', self)
    connect(pie, SIGNAL('clicked()'), self, SLOT('pie()'))
    quit = Qt::PushButton.new('종료', self)
    connect(quit, SIGNAL('clicked()'), self, SLOT('quit()'))
	
    layout = Qt::VBoxLayout.new
    layout.addWidget(@web)
    layout.addWidget(quit)
    setLayout(layout)
    
    base = Qt::Url.fromLocalFile("#{Dir.getwd}/")
	  @web.set_html(SOURCE, base)
	  connect(@web.page.mainFrame, SIGNAL('javaScriptWindowObjectCleared()'), self, SLOT('add_js_object()'))
  end

  def add_js_object()
	  @web.page.mainFrame.add_to_java_script_window_object('observer', self)
  end
  
  def pie()
    @web.page.mainFrame.evaluate_java_script('pieChart("2012-01")')
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
      [JSON.generate(Exam.filter(:modality=>'US').group_and_count(:strftime.sql_function("%Y년%m월", :sdate).as(:month)).map { |x| x.values})]]
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
    map '/mr_stats.json' do
      run Stats.new
    end
  end
  
  app = Qt::Application.new(ARGV)

  widget = MyWidget.new(nil, server)
  widget.show

  EM.add_periodic_timer(0.02) { app.process_events }  

  server.start 
end
