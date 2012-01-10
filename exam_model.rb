#encoding = utf-8

require 'rubygems'
require 'sequel'

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

# Exam.filter(:modality=>'MR').group_and_count(:strftime.sql_function("%Y%m", :sdate).as(:month)).all