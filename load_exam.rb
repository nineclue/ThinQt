#encoding = utf-8

require 'rubygems'
require 'sequel'
require 'date'
require 'logger'

# DB = Sequel.sqlite('exams.db', :loggers=> [Logger.new('db.log')])
DB = Sequel.sqlite('exams.db')

DB.create_table?(:doctors) do
  primary_key :id
  String      :pacs_id, :size=>6, :fixed=>true
  String      :name
end

DB.create_table?(:studies) do
  primary_key :id
  String      :name
  String      :category
end

DB.create_table?(:exams) do
  primary_key :id
  String      :pid, :size=>10, :fixed=>true
  String      :pname
  Integer     :age
  String      :sex, :size=>1, :fixed=>true
  DateTime    :sdate
  String      :modality, :size=>2, :fixed=>true
  foreign_key :sid, :studies
  foreign_key :odoc, :doctors
  DateTime    :rdate
  foreign_key :rdoc, :doctors
end

exams = DB[:exams]
doctors = DB[:doctors]
studies = DB[:studies]

if doctors.count == 0
  doctors.insert(:pacs_id=>'090003', :name=>'허서구')
  doctors.insert(:pacs_id=>'110001', :name=>'유현석')
  doctors.insert(:pacs_id=>'000001', :name=>'강남욱')
  doctors.insert(:pacs_id=>'090001', :name=>'김형종')
  doctors.insert(:pacs_id=>'100011', :name=>'박필재')
  doctors.insert(:pacs_id=>'110002', :name=>'최승헌')
  doctors.insert(:pacs_id=>'110022', :name=>'이병국')
  doctors.insert(:pacs_id=>'110024', :name=>'변양호')
end
  
Dir.glob('*txt') do |fn|
  open(fn, 'r:euc-kr') do |f|
    f.readlines.each do |l|
      comps = l.strip.split("\t")
      next unless comps.size == 10 and comps[0] =~ /\d+/
      age = comps[2].match(/\d+/)[0].to_i
      study = comps[6].upcase
      sid = studies['name=?', study]
      if sid.nil?
        print "#{study.encode('utf-8')}의 category를 입력하세요 : "
        cat = gets.strip.upcase
        sid = studies.insert(:name=>study, :category=>cat)
      else
        sid = sid[:id]
      end
      physician = doctors['pacs_id=?', comps[7]]
      # 외부 판독인 경우 처방의에 nil이 들어갈 수 있다
      physician = physician[:id] unless physician.nil?
      rdoc = doctors['name=?', comps[9]]
      if rdoc.nil?
        puts "Unknown reporter : #{comps[9].encode('utf-8')}\r\n"
        next
      end
      exams.insert(:pid=>comps[0], :pname=>comps[1].encode('utf-8'), :age=>age, :sex=>comps[3],
          :sdate=>DateTime.parse(comps[4]).strftime("%Y-%m-%d %H:%M:%S"), :modality=>comps[5], :sid=>sid,
          :odoc=>physician, :rdate=>DateTime.parse(comps[8]).strftime("%Y-%m-%d %H:%M:%S"), :rdoc=>rdoc[:id])
    end
  end
end
