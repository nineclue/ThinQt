#encoding = utf-8

require 'rubygems'
require 'sequel'
require './qt_kendo'

# DB = Sequel.sqlite('exams.db', :loggers=> [Logger.new('db.log')])
DB = Sequel.sqlite('exams.db')

class Exam < Sequel::Model
  many_to_one :study, :key=>:sid, :primary_key=>:id
  many_to_one :physician, :class=>:Doctor, :key=>:odoc, :primary_key=>:id
  many_to_one :reporter, :class=>:Doctor, :key=>:rdoc, :primary_key=>:id
end

class Doctor < Sequel::Model
  one_to_many :orders, :class=>:Exam, :primary_key=>:id, :key=>:odoc
  one_to_many :reports, :class=>:Exam, :primary_key=>:id, :key=>:rdoc
end

class Study < Sequel::Model
  one_to_many :exams, :primary_key=>:id, :key=>:sid
end

class RadInfo
  # range of date
  # [min, max] or min format (max is set to today)
  def date_range
    Exam.min(:sdate)
  end
  
  # list of possible data types, [ [:description, :type], ... ]
  def types
    [ ['Ultralound Studies', :us], ['MR Studies', :mr] ]
  end
  
  # query data between start, end dates : for line graph
  # type : same is return value of types
  # start_date, end_date : DateTime objects
  # unit : one of :day, :week, :month, :quarter, :half, :year
  # data format [ {:period=>..., :count=>...}, ... ]
  def query(type, start_date, end_date, unit)
    add_period(Exam.filter(:modality=>type.to_s.upcase), unit).where(:sdate=>start_date..end_date).order(:sdate).map { |x| x.values }
    # eval "Exam.filter(:modality=>#{type.to_s.upcase}).group_and_count(#{period}).as(:month)).where(:sdate=>start_date..end_date).order(:sdate).map { |x| x.values }"
  end
  
  # query subdata in period : for pie graph
  # data format [ {:name=>..., :count=>... }, ... ]
  def sub_query(type, period, unit)
    add_period(Exam.join(Study, :id=>:sid).filter(:modality=>type.to_s.upcase), unit, :studies__category).having(:period=>period).order(:sdate).map { |x| x.values }
  end
  
  # query all data between start, end dates : for stacked graph
  # data format [ {:period=>..., :name field=>:count}, ... ]
  def all_query(type, start_date, end_date, unit)
    result = []
    current_period = {}
    add_period(Exam.join(Study, :id=>:sid).filter(:modality=>type.to_s.upcase), unit, :studies__category).where(:sdate=>start_date..end_date).order(:sdate).each do |x|
      if (current_period[:period] != x.values[:period])
        result << current_period unless current_period.size == 0
        current_period = { :period => x.values[:period] }
      end
      current_period[x.values[:category]] = x.values[:count]
    end
    result << current_period unless current_period.size == 0 
    result  
  end
  
  def add_period(dataset, unit, extra_field = nil)
    case unit.to_sym
    when :day
      if extra_field.nil?
        dataset.group_and_count(:strftime.sql_function("%Y-%m-%d", :sdate).as(:period))
      else
        dataset.group_and_count(:strftime.sql_function("%Y-%m-%d", :sdate).as(:period), extra_field)
      end
    when :week
      if extra_field.nil?
        dataset.group_and_count(:strftime.sql_function("%Y-%W", :sdate).as(:period))
      else
        dataset.group_and_count(:strftime.sql_function("%Y-%W", :sdate).as(:period), extra_field)
      end
    when :month
      if extra_field.nil?
        dataset.group_and_count(:strftime.sql_function("%Y-%m", :sdate).as(:period))
      else
        dataset.group_and_count(:strftime.sql_function("%Y-%m", :sdate).as(:period), extra_field)
      end
    when :quarter
      if extra_field.nil?
        dataset.group_and_count((:strftime.sql_function("%Y", :sdate)+'-'+((:strftime.sql_function("%m", :sdate)-1)/3+1)).as(:period))
      else
        dataset.group_and_count((:strftime.sql_function("%Y", :sdate)+'-'+((:strftime.sql_function("%m", :sdate)-1)/3+1)).as(:period), extra_field)
      end
    when :half
      if extra_field.nil?
        dataset.group_and_count((:strftime.sql_function("%Y", :sdate)+'-'+((:strftime.sql_function("%m", :sdate)-1)/6+1)).as(:period))
      else
        dataset.group_and_count((:strftime.sql_function("%Y", :sdate)+'-'+((:strftime.sql_function("%m", :sdate)-1)/6+1)).as(:period), extra_field)
      end
    when :year 
      if extra_field.nil?
        dataset.group_and_count(:strftime.sql_function("%Y", :sdate).as(:period))
      else
        dataset.group_and_count(:strftime.sql_function("%Y", :sdate).as(:period), extra_field)
      end
    end
  end
end

QtKendo.run(RadInfo)