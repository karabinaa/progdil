require 'erb'
require 'yaml'

task :exam do
  Dir.foreach("_exams/") do |sourceFile|
    unless ((source == "..") or  (sourceFile == "."))

      fpath = YAML.load_file("_exams/"+sourceFile) 
      title = dosya_yolu["title"]
      footer = dosya_yolu["footer"]

      questions = fpath["q"]
    
      j = 0
      questions = []
 
      for question in questions
        holder = File.read("_includes/q/"+ question)
        questions[j] = holder
        j=j+1
      end
  
      mdholder = File.read("_templates/exam.md.erb")
      erbholder = ERB.new(read_md)
   
      foo =  erbholder.result(binding)
      fholder = File.open("md_dosyasi.md","w")
      fholder.write(foo)
      fholder.close
      sh "markdown2pdf md_dosyasi.md"
      sh "rm -f md_dosyasi.md"
    end
  end
end

task :default => :exam