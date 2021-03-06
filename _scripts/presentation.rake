require 'pathname'
require 'pythonconfig'
require 'yaml'
# pathname, pythonconfig, yaml modüllerindeki fonksiyonların kullanılabilmesi için bağımlılık bildirildi

CONFIG = Config.fetch('presentation', {})
# sunumu al

PRESENTATION_DIR = CONFIG.fetch('directory', 'p') # PRESENTATION_DIR a directory içindekileri ata
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg') #
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html') # PRESANTATION_DIR ile index.html yi birleştir INDEX_FILE a ata
IMAGE_GEOMETRY = [ 733, 550 ] # Maximum resim boyutlarını 733x550 olarak ata
DEPEND_KEYS    = %w(source css js) # bağımlı anahtarları ata
DEPEND_ALWAYS  = %w(media) # sürekli bağımlıları ata

TASKS = {
    :index   => 'sunumları indeksle',
    :build   => 'sunumları oluştur',
    :clean   => 'sunumları temizle',
    :view    => 'sunumları görüntüle',
    :run     => 'sunumları sun',
    :optim   => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}
# görevler ve açıklamalarını tanımlanmış 


presentation   = {} 
tag            = {}



class File
  @@absolute_path_here = Pathname.new(Pathname.pwd)   #dosya yolunu statik absolute_path_here değişkenine ata
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end
  def self.to_filelist(path)
    File.directory?(path) ?                                          
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :  
      [path]
  end
end
# File classını tanımlanmış , File classı içerisinde  to_herepath ve to_filelist methodlarını tanımlanmış



def png_comment(file, string)
  require 'chunky_png' 
  require 'oily_png'
  #fonksiyonun chunky_png ve oily_png modullerine bağımlılığı belirtilmiş
  image = ChunkyPNG::Image.from_file(file) #resmi image değişkenine ata 
  image.metadata['Comment'] = 'raked'      #yorumu ekle
  image.save(file)                         #resmin son halini kaydet
end
#png dosyalarına yorum ekleyecek png_comment fonksiyonu tanımlanmış 


def png_optim(file, threshold=40000)
  return if File.new(file).size < threshold  # sadece boyutu verilen değerden küçük olanlara işlem yap
  sh "pngnq -f -e .png-nq #{file}"
  out = "#{file}-nq"
  if File.exist?(out)
    $?.success? ? File.rename(out, file) : File.delete(out) #isim çakışması var mı? varsa çöz .
  end
  png_comment(file, 'raked')
end
#png dosyalarını optimize edicek png_optim fonksiyonu tanımlanmış


def jpg_optim(file)
  sh "jpegoptim -q -m80 #{file}"
  sh "mogrify -comment 'raked' #{file}"
end
# jpg dosyalarını optimize edicek jpg_optim fonksiyonu tanımlanmış 


def optim
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]

  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }
  end

  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }
    size, i = [w, h].each_with_index.max      
    if size > IMAGE_GEOMETRY[i]                         #resimler istenilen boyuttan büyükse 
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s 
      sh "mogrify -resize #{arg} #{f}"                  # yeniden boyutlandır
    end
  end

  pngs.each { |f| png_optim(f) } # her bir pngs için png_optim fonksiyonunu kullan 
  jpgs.each { |f| jpg_optim(f) } # her biri jpgs için jpg_optim fonksiyonunu kullan

  (pngs + jpgs).each do |f|    # jpgs ve pngs ler için 
    name = File.basename f     
    FileList["*/*.md"].each do |src| #md dosyarlarını oluştur                    
      sh "grep -q '(.*#{name})' #{src} && touch #{src}" # ekrana birşey basma (-q (quiet))
    end
  end
end

default_conffile = File.expand_path(DEFAULT_CONFFILE)  #default_conffile a DEFAULT_CONFFİLE ın tam yolunu ata

FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir|  
  next unless File.directory?(dir)
  chdir dir do
    name = File.basename(dir)
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    config = File.open(conffile, "r") do |f|
      PythonConfig::ConfigParser.new(f)
    end

    landslide = config['landslide']
    if ! landslide                                             #landslide tanımlanmamışsa
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış"  #standar error a hata mesajı bas
      exit 1   # 1 den çık
    end

    if landslide['destination']                                                         # destination ayarı kullanılmışsa
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin" # standart error a hata mesejı bas
      exit 1  # 1 den çık
    end

    if File.exists?('index.md')  #index.md dosyası varsa
      base = 'index'             # base değişkenine 'index' ata
      ispublic = true            # ispublic değikenine true boolen değerini ata (dışarı açık)
    elsif File.exists?('presentation.md') #üstteki if içine girmemişsen, presentation.md dosyasının var mı diye bak varsa
      base = 'presentation'               # base değişkenine 'presentation' ata
      ispublic = false                    # ispublic değişkenine false boolen değerini ata (dışarı açık değil)
    else  # her iki dosya da yoksa 
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı" # standart error a hata mesajı bas
      exit 1  #1 den çık
    end

    basename = base + '.html'   # base name i base.hml olarak ata (örnek : base = 'index' ise basename = 'index.html')
    thumbnail = File.to_herepath(base + '.png') #thumbnail e base.png (base='index' için index.png) dosyasını at 
    target = File.to_herepath(basename) # basename in tuttuğu dosyayı target e ata

    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end

    deps.map! { |e| File.to_herepath(e) } 
    deps.delete(target) # target i sil
    deps.delete(thumbnail) # thumbnail i sil

    tags = []

   presentation[dir] = {
      :basename  => basename,	# üreteceğimiz sunum dosyasının baz adı
      :conffile  => conffile,	# landslide konfigürasyonu (mutlak dosya yolu)
      :deps      => deps,	# sunum bağımlılıkları
      :directory => dir,	# sunum dizini (tepe dizine göreli)
      :name      => name,	# sunum ismi
      :public    => ispublic,	# sunum dışarı açık mı
      :tags      => tags,	# sunum etiketleri
      :target    => target,	# üreteceğimiz sunum dosyası (tepe dizine göreli)
      :thumbnail => thumbnail, 	# sunum için küçük resim
    }
  end
end

presentation.each do |k, v| # her bir sunum dosyası için
  v[:tags].each do |t|      # etiketleme yap
    tag[t] ||= []
    tag[t] << k
  end
end

tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten]  # görevler sekmesi

presentation.each do |presentation, data|
  ns = namespace presentation do
    file data[:target] => data[:deps] do |t|  #içeriği al 
      chdir presentation do                   # sunumu hazırla 
        sh "landslide -i #{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        unless data[:basename] == 'presentation.html'
          mv 'presentation.html', data[:basename]
        end
      end
    end

    file data[:thumbnail] => data[:target] do   #thumbnaili (küçük resmi) target e (hedef dosyaya) gönder
      next unless data[:public]                 # dışa açık değilse 
      sh "cutycapt " +
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " + #thumbnaili düzenle 
          "--min-width=1024 " +
          "--min-height=768 " +
          "--delay=1000"
      sh "mogrify -resize 240 #{data[:thumbnail]}"   #thumbnaili yeniden boyutlandır
      png_optim(data[:thumbnail])                    #png_optim fonksiyonu ile optimize et.
    end

    task :optim do
      chdir presentation do
        optim
      end
    end

    task :index => data[:thumbnail]  #indexle (index görevini uygula)

    task :build => [:optim, data[:target], :index] # optim target ve index i build et (build görevini uygula)

    task :view do
      if File.exists?(data[:target]) #hedef dosya varsa
        sh "touch #{data[:directory]}; #{browse_command data[:target]}" # istenilenleri oluştur
      else # diğer durum için (dosya yoksa)
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin" # standart error a hata mesajı bas
      end
    end

    task :run => [:build, :view] # build ve view görevlerini çalıştır

    task :clean do          # targeti(hedef dosyayı)
      rm_f data[:target]    # ve thumbnaili (küçük resmi)
      rm_f data[:thumbnail] # temizle
    end

    task :default => :build # öntanımlı rake görevini build olarak ayarla 
  end

  ns.tasks.map(&:to_s).each do |t|                  #görev tablosuna 
    _, _, name = t.partition(":").map(&:to_sym)     #verilen 
    next unless tasktab[name]                       #görevleri 
    tasktab[name][:tasks] << t                      #ekle
  end
end

namespace :p do #üst isimuzayında aşağıdakileri yap 
  tasktab.each do |name, info| #görev listesinin her elamnı için 
    desc info[:desc]           #yeni görevleri tanıma 
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do
    index = YAML.load_file(INDEX_FILE) || {} 
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations'] # koşul sağlanmadığı sürece
      index['presentations'] = presentations                 # index['presentation'] değerini presentation a eşitle
      File.open(INDEX_FILE, 'w') do |f|                      # INDEX_FILE ı yazılabilir olarak aç
        f.write(index.to_yaml)                               # index i yaml a çevirdikten sonra yaz
        f.write("---\n")                                     # '---\n' dizgisini yaz
      end
    end
  end

  desc "sunum menüsü"
  task :menu do
    lookup = Hash[
      *presentation.sort_by do |k, v|
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu|
      menu.default = "1"
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke
  end
  task :m => :menu     # m için menü görevini çalıştır .
end

desc "sunum menüsü"
task :p => ["p:menu"]
task :presentation => :p
