# encoding: utf-8
# Met à jour le site à partir du dossier d'évaluation (Excel), puis commit, push et suivi du déploiement.
#
#   ruby scripts/mettre-a-jour.rb [fichier.xlsx] [--oui] [--sans-publier]
#
#   fichier.xlsx    le dossier d'évaluation ; à défaut, le dernier fichier utilisé ou une question
#   --oui           publie sans demander de confirmation
#   --sans-publier  régénère les fichiers seulement (ni commit, ni push)
#
# Seules deux feuilles sont lues, et seulement des colonnes publiques :
#   « RECHER_Recap_subv… » -> _data/grants.yml  (subventions obtenues, SANS les montants)
#   « Références »         -> assets/ref.bib    (publications et présentations)
# Le fichier Excel n'est jamais copié dans le dépôt : il contient des données confidentielles.
#
# Compatible Ruby 2.6 et plus (Ruby fourni avec macOS, RubyInstaller sous Windows), sans gem à installer.

require 'zlib'
require 'rexml/document'
require 'yaml'
require 'json'
require 'open3'
require 'net/http'
require 'uri'

ROOT = File.expand_path('..', __dir__)
SITE_URL = 'https://labsnc.ca/'
LAST_PATH = File.join(__dir__, '.chemin-excel')
GRANTS_FILE = File.join(ROOT, '_data', 'grants.yml')
BIB_FILE = File.join(ROOT, 'assets', 'ref.bib')
WINDOWS = Gem.win_platform?

$stdout.sync = true

def say(msg = '') puts msg end
def ask(prompt)
  print prompt
  ($stdin.gets || '').dup.force_encoding('UTF-8').scrub('').delete("﻿").strip
end
def step(msg) puts "\n== #{msg}" end
def fail!(msg)
  warn "\nERREUR : #{msg}"
  exit 1
end

# ---------------------------------------------------------------- arguments
args = ARGV.dup
AUTO_YES = !args.delete('--oui').nil?
NO_PUBLISH = !args.delete('--sans-publier').nil?
excel = args.first

def clean_path(p)
  p = p.to_s.strip.sub(/\A(['"])(.*)\1\z/, '\2')
  p = p.gsub(/\\(.)/, '\1') unless WINDOWS # macOS : « Mon\ dossier » quand on glisse un fichier dans le Terminal
  p
end

if excel.nil? && File.exist?(LAST_PATH)
  previous = File.read(LAST_PATH, encoding: 'utf-8').strip
  if File.exist?(previous)
    answer = ask("Fichier Excel : #{previous}\nEntrée pour l'utiliser, ou glissez un autre fichier ici : ")
    excel = answer.empty? ? previous : answer
  end
end
excel ||= ask('Glissez le fichier Excel (dossier d\'évaluation) dans cette fenêtre, puis appuyez sur Entrée : ')
excel = File.expand_path(clean_path(excel))
fail!("fichier introuvable : #{excel}") unless File.file?(excel)
fail!('le fichier doit être un classeur .xlsx') unless excel.downcase.end_with?('.xlsx')
if excel.downcase.start_with?(ROOT.downcase + '/') || excel.downcase.start_with?(ROOT.downcase + '\\')
  fail!("le fichier Excel ne doit pas se trouver dans le dossier du site (#{ROOT}) : il serait publié.")
end
File.write(LAST_PATH, excel)

# ---------------------------------------------------------------- lecture du classeur (zip + XML)
def read_zip(path)
  data = File.binread(path)
  eocd = data.rindex("PK\x05\x06".b) or fail!('fichier .xlsx illisible (fermez-le dans Excel et réessayez)')
  count = data[eocd + 10, 2].unpack1('v')
  pos = data[eocd + 16, 4].unpack1('V')
  files = {}
  count.times do
    fail!('fichier .xlsx corrompu') unless data[pos, 4].unpack1('V') == 0x02014b50
    method = data[pos + 10, 2].unpack1('v')
    csize = data[pos + 20, 4].unpack1('V')
    nlen, elen, clen = data[pos + 28, 6].unpack('vvv')
    local = data[pos + 42, 4].unpack1('V')
    name = data[pos + 46, nlen].force_encoding('UTF-8')
    lnlen, lelen = data[local + 26, 4].unpack('vv')
    raw = data[local + 30 + lnlen + lelen, csize]
    if method.zero?
      files[name] = raw
    else
      z = Zlib::Inflate.new(-Zlib::MAX_WBITS)
      files[name] = z.inflate(raw)
      z.finish
      z.close
    end
    files[name].force_encoding('UTF-8')
    pos += 46 + nlen + elen + clen
  end
  files
end

def norm(s)
  s.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/\s+/, ' ').strip
end

# Renvoie { nom_de_feuille => [ { 'row' => n, 'cells' => { 'A' => '...' } } ] }
def read_workbook(path)
  zip = read_zip(path)
  xml = ->(name) { REXML::Document.new(zip.fetch(name) { fail!("élément manquant dans le classeur : #{name}") }) }
  strings = []
  if zip['xl/sharedStrings.xml']
    xml['xl/sharedStrings.xml'].elements.each('sst/si') do |si|
      strings << REXML::XPath.match(si, './/t[not(ancestor::rPh)]').map(&:text).join
    end
  end
  rels = {}
  xml['xl/_rels/workbook.xml.rels'].elements.each('Relationships/Relationship') do |r|
    rels[r.attributes['Id']] = r.attributes['Target'].sub(%r{\A/?xl/}, '')
  end
  sheets = {}
  xml['xl/workbook.xml'].elements.each('workbook/sheets/sheet') do |sh|
    rows = []
    xml["xl/#{rels[sh.attributes['r:id']]}"].elements.each('worksheet/sheetData/row') do |row|
      cells = {}
      row.elements.each('c') do |c|
        v = c.elements['v'] && c.elements['v'].text
        v = strings[v.to_i] if c.attributes['t'] == 's' && v
        v = REXML::XPath.match(c, './/t').map(&:text).join if c.attributes['t'] == 'inlineStr'
        cells[c.attributes['r'].gsub(/\d/, '')] = v if v && !v.empty?
      end
      rows << { 'row' => row.attributes['r'].to_i, 'cells' => cells } unless cells.empty?
    end
    sheets[sh.attributes['name']] = rows
  end
  sheets
end

def find_sheet(sheets, prefix)
  name = sheets.keys.find { |n| norm(n).start_with?(norm(prefix)) }
  fail!("feuille « #{prefix}… » introuvable. Feuilles du classeur : #{sheets.keys.join(', ')}") unless name
  sheets[name]
end

# Repère les colonnes par leur en-tête (première ligne), pour résister aux colonnes ajoutées ou déplacées.
def columns(rows, wanted)
  header = rows.first['cells']
  wanted.each_with_object({}) do |(key, label), cols|
    letter = header.find { |_, v| norm(v).start_with?(norm(label)) }
    fail!("colonne « #{label} » introuvable dans la feuille (en-têtes : #{header.values.join(' | ')})") unless letter
    cols[key] = letter.first
  end
end

def records(rows, cols)
  rows.drop(1).map do |r|
    rec = { row: r['row'] }
    cols.each { |key, letter| rec[key] = r['cells'][letter] }
    rec
  end
end

# ---------------------------------------------------------------- règles de mise en forme
TYPOS = {
  'diffsuion' => 'diffusion', 'Recherxche' => 'Recherche', 'factros' => 'factors', 'Variablité' => 'Variabilité',
  'fréauence' => 'fréquence', 'distnace' => 'distance', 'comprative' => 'comparative', 'sensorimotricété' => 'sensorimotricité',
  'congèrs' => 'congrès', 'clniques' => 'cliniques', 'cogntive' => 'cognitive', 'incarne et' => 'incarnée et',
  'Lièges' => 'Liège', '« Les' => 'Les', 'Pachete, A,' => 'Pachete, A.,', 'Marcotte, M.' => 'Marcotte, K.',
  ', Date Septembre 2025 ou 2026?' => ''
}.freeze
def fix(s)
  TYPOS.reduce(s.to_s.gsub(/\s+/, ' ').strip) { |t, (a, b)| t.gsub(a, b) }
end

# Subventions : titres et organismes reformulés (clé = numéro « # » de la ligne).
GRANT_TITLES = {
  '2' => 'Group singing to support social well-being and communication in adults with communication disorders: A knowledge generation and mobilization partnership (SingWell)',
  '3' => 'Fonds de démarrage de la recherche',
  '10' => 'Traqueur oculaire Spark et logiciel E-Prime',
  '11' => 'Organisation d’un colloque au 91e congrès de l’Acfas (Ottawa, mai 2024) : « Cognition incarnée et située : applications en santé »',
  '17' => 'Effets du vieillissement sur les capacités de lecture de mots selon leur dominance perceptuelle : une étude en imagerie optique',
  '22' => 'Organisation d’un colloque (octobre 2025) : « Cognition incarnée et située : applications en santé »',
  '27' => 'Chaire de recherche Émergence : liens entre sensorimotricité et langage',
  '34' => 'Équipement pour l’étude des gestes co-verbaux chez les aînés'
}.freeze
FUNDERS = {
  /Plan d'action/ => 'Ministère de la Santé et des Services sociaux (Plan d’action pour les personnes proches aidantes)',
  /CogNAC/ => 'Groupe de recherche CogNAC, UQTR', /CRSH/ => 'CRSH', /Bio-Imagerie/ => 'Réseau de bio-imagerie du Québec',
  /Fonds de démarrage/ => 'UQTR', /Mobilier|MAO/ => 'UQTR, budget MAO', /Fonds d'animation/ => 'UQTR, Fonds d’animation et de diffusion de la recherche',
  /PAIR/ => 'UQTR, programme PAIR', /planification/ => 'UQTR, planification stratégique', /RQRV/ => 'Réseau québécois de recherche sur le vieillissement (RQRV)',
  /Fondation UQTR/ => 'Fondation UQTR', /APPI/ => 'Université Lyon 2 (APPI)', /^UQTR/ => 'UQTR'
}.freeze
ROLES = { 'PI' => 'pi', 'co-PI' => 'copi' }.freeze

# Publications : corrections (clé = début du titre dans l'Excel, sans tenir compte des accents ni de la casse ;
# « only » limite la correction à un type BibTeX quand deux entrées portent le même titre).
BIB_OVERRIDES = {
  'Functional connectivity in post-stroke aphasia' => { author: ['Durand, Édith'] },
  'Application de la thérapie Personalized Observation' => { journal: 'Glossa', volume: '134', pages: '1--28', url: 'https://glossa.fr/index.php/glossa/article/view/1381' },
  'Evaluation et prise en charge des troubles du langage' => { booktitle: 'Évaluation et prise en charge des troubles du langage', publisher: 'De Boeck Supérieur' },
  'Les ressources numériques au service de la collaboration' => { only: 'article', journal: 'Étudier le langage à l’ère numérique', pages: '47' },
  'Analyse des contributions rédactionnelles' => { journal: 'Sciences et technologies de l’information et de la communication pour l’éducation et la formation', volume: '30', number: '2' },
  'Cognition incarnée et située : Quand le langage' => { booktitle: 'Langage oral : nouvelles approches incarnées de la parole atypique', publisher: 'De Boeck Supérieur', editor: 'Devevey, Alain' },
  'Intervention en langage oral auprès des personnes avec aphasie' => { booktitle: 'Nouvelles approches incarnées de la parole atypique', publisher: 'De Boeck Supérieur', editor: 'Devevey, Alain' },
  'Sous le regard du personnel soignant' => { doi: '10.13140/RG.2.2.11880.23049' },
  'Chapitre 14. Apport de la cognition incarnée' => { booktitle: 'Maladie d’Alzheimer, approche intégrative', editor: 'Simoes Loureiro, Isabelle' },
  'Chant choral communautaire et cohésion de groupe' => { booktitle: '93e congrès de l’Acfas, Université du Québec à Trois-Rivières' },
  'Le langage au rythme du souffle' => { author: ['Durand, Édith', '{Association des personnes aphasiques de Mauricie Centre-du-Québec}'] },
  'Des mots aux gestes: Explorer les processus cognitifs' => { url: nil } # lien OneDrive personnel : non publié
}.freeze
PRIVATE_STATUS = ['en préparation', 'in prep', 'soumis'].freeze
BIB_TYPES = { 'article' => 'article', 'inbook' => 'incollection', 'conférence' => 'inproceedings', 'conference' => 'inproceedings', 'misc' => 'misc' }.freeze
MONTHS = { 'jan' => 1, 'janv' => 1, 'janvier' => 1, 'feb' => 2, 'fev' => 2, 'fevrier' => 2, 'mar' => 3, 'mars' => 3, 'march' => 3,
           'apr' => 4, 'avril' => 4, 'may' => 5, 'mai' => 5, 'jun' => 6, 'june' => 6, 'juin' => 6, 'jul' => 7, 'july' => 7, 'juillet' => 7,
           'aug' => 8, 'aout' => 8, 'sep' => 9, 'sept' => 9, 'septembre' => 9, 'oct' => 10, 'octobre' => 10, 'nov' => 11, 'novembre' => 11,
           'novembre-decembre' => 11, 'dec' => 12, 'decembre' => 12 }.freeze
MON = %w[_ jan feb mar apr may jun jul aug sep oct nov dec].freeze
CANON = { /\ADurand\b/ => 'Durand, Édith', /\AAnsaldo\b/ => 'Ansaldo, Ana Inés', /\AMasson-Trottier\b/ => 'Masson-Trottier, Michèle', /\ABoulenger\b/ => 'Boulenger, Véronique',
          /\AValentin, (V|Victoria)\b/ => 'Valentin, Victoria', /\ALefebvre, (E|Emie|Émie)\b/ => 'Lefebvre, Émie', /\AZumbansen\b/ => 'Zumbansen, Anna', /\AAnglade\b/ => 'Anglade, Carole',
          /\AVallet\b/ => 'Vallet, Guillaume T.', /\AMoritz-Gasser\b/ => 'Moritz-Gasser, Sylvie', /\ABrambati\b/ => 'Brambati, Simona Maria',
          /\AJoyal\b/ => 'Joyal, Élodie', /\ABaron, E/ => 'Baron, Évelyne', /\AMarcotte, K/ => 'Marcotte, Karine', /\AMarion-Flamand\b/ => 'Marion-Flamand, Marc-André' }.freeze

def canon(n)
  hit = CANON.find { |re, _| n =~ re }
  hit ? hit.last : n
end

def flip(n)
  n = n.strip
  return n if n.include?(',')
  parts = n.split(' ')
  parts.size < 2 ? n : "#{parts.last}, #{parts[0..-2].join(' ')}"
end

def authors(raw)
  s = fix(raw)
  list =
    if s.include?(';') then s.split(';')
    elsif s.include?(' and ') then s.split(' and ')
    elsif s =~ /\A[^,]+, (?:[A-ZÉ]\.[ -]?)+/ then s.scan(/([^,&]+?), ((?:[A-ZÉ]\.[ -]?)+)/).map { |l, f| "#{l.strip}, #{f.strip}" }
    else s.split(/, | et /)
    end
  list.map { |n| canon(flip(n.gsub(/\A&\s*/, ''))) }
end

def bib_override(title, type)
  t = norm(title)
  hit = BIB_OVERRIDES.find { |prefix, ov| t.start_with?(norm(prefix)) && (ov[:only].nil? || ov[:only] == type) }
  hit ? hit.last : {}
end

# ---------------------------------------------------------------- génération
def build_grants(rows)
  cols = columns(rows, id: '#', year: 'Année', title: 'Demande de subvention', funder: 'Organisme', role: 'Rôle',
                       status: 'Statut', awarded: 'Montant obtenu')
  awarded = records(rows, cols).select { |c| c[:status].to_s.strip == 'Octroi' && c[:awarded].to_s =~ /\A\d+(\.\d+)?\z/ && c[:id] }
  grants = awarded.map do |c|
    id = c[:id].to_s.sub(/\.0\z/, '')
    title = GRANT_TITLES[id] || fix(c[:title]).sub(/\A.*?\(\d{4}\)\.\s*/, '').sub(/\s*\[?\(?Grant[^\]\)]*[\]\)]\.?\s*\z/i, '').sub(/\.\s*\z/, '')
    funder = FUNDERS.find { |re, _| c[:funder].to_s =~ re }
    # Le montant sert seulement à repérer les subventions obtenues : il n'est jamais écrit.
    { 'year' => c[:year].to_i, 'title' => title, 'funder' => funder ? funder.last : fix(c[:funder]), 'role' => ROLES[c[:role].to_s.strip] || 'collab' }
  end
  grants.sort_by { |g| [-g['year'], g['title']] }
end

def build_bib(rows)
  cols = columns(rows, type: 'Type BibTeX', status: 'Specificit', year: 'Année', month: 'Mois', authors: 'Auteurs', title: 'Titre',
                       venue: 'Revue', volume: 'Volume', number: 'Numéro', pages: 'Pages', doi: 'DOI', url: 'URL', publisher: 'Éditeur')
  seen = Hash.new(0)
  entries = []
  records(rows, cols).each do |c|
    status = c[:status].to_s.strip.downcase
    type = BIB_TYPES[c[:type].to_s.strip.downcase]
    next if c[:title].nil? || type.nil? || PRIVATE_STATUS.include?(status)
    ov = bib_override(c[:title], type)
    auth = ov[:author] || authors(c[:authors])
    next if auth.empty?
    cat = case status
          when 'orale-invitée' then 'invitee'
          when 'orale', 'affiche', 'vulgarisation' then status
          when 'sous presse', 'in press' then 'souspresse'
          when 'registered' then 'protocole'
          else { 'incollection' => 'chapitre', 'inproceedings' => 'communication', 'misc' => 'ressource' }[type] || 'article'
          end
    year = c[:year].to_s.sub(/\.0\z/, '')
    venue = ov[:journal] || ov[:booktitle] || fix(c[:venue]).sub(/\A(Dans|In) /, '').sub(/\.\z/, '')
    f = { author: auth.join(' and '), title: fix(c[:title]).sub(/\.\z/, ''), year: year }
    m = MONTHS[norm(c[:month])]
    case type
    when 'article' then f[:journal] = venue
    when 'incollection', 'inproceedings' then f[:booktitle] = venue unless venue.empty?
    else f[:howpublished] = venue unless venue.empty?
    end
    f[:volume] = (ov[:volume] || c[:volume]) && (ov[:volume] || c[:volume]).sub('Volume ', '')
    f[:number] = ov[:number] || c[:number]
    f[:pages] = ov[:pages] || (c[:pages] && c[:pages].gsub('–', '--'))
    f[:publisher] = ov[:publisher] || (type != 'inproceedings' ? c[:publisher] : nil)
    f[:editor] = ov[:editor]
    f[:doi] = ov[:doi] || c[:doi]
    f[:url] = ov.key?(:url) ? ov[:url] : (c[:doi] ? nil : c[:url] && c[:url].strip)
    f[:category] = cat
    f[:ym] = year.to_i * 100 + (m || 0)
    key = auth.first[/\A\{?[^,\s}]+/].downcase.tr('{', '').unicode_normalize(:nfd).gsub(/\p{Mn}/, '').gsub(/[^a-z-]/, '') + year
    seen[key] += 1
    key = "#{key}#{(96 + seen[key]).chr}" if seen[key] > 1
    body = f.reject { |_, v| v.nil? || v.to_s.empty? }.map do |k, v|
      value = v.to_s.gsub('&', '\\\\&')
      "  #{k.to_s.ljust(12)} = {#{k == :title ? "{#{value}}" : value}}"
    end
    body << "  month        = #{MON[m]}" if m
    entries << { ym: f[:ym], text: "@#{type}{#{key},\n#{body.join(",\n")}\n}\n", cat: cat, title: f[:title] }
  end
  # Plus récent d'abord ; à date égale, l'ordre du classeur est conservé.
  entries.each_with_index.sort_by { |e, i| [-e[:ym], i] }.map(&:first)
end

def grants_yaml(grants)
  "# Subventions obtenues (source : dossier d'évaluation). Montants volontairement omis.\n" \
  "# role : pi, copi ou collab (libellés traduits dans _data/i18n.yml)\n" + grants.to_yaml.sub(/\A---\n/, '')
end

def bib_text(entries)
  "% Publications du laboratoire SNC (source : dossier d'évaluation, feuille Références).\n" \
  "% `category` choisit la section : article, chapitre, souspresse, invitee, orale, affiche, communication, vulgarisation, ressource, protocole.\n" \
  "% `ym` (année x 100 + mois) sert au filtre « moins d'un an » de la page Actualités.\n\n" + entries.map { |e| e[:text] }.join("\n")
end

def old_titles(path, pattern)
  File.exist?(path) ? File.read(path, encoding: 'utf-8').scan(pattern).flatten.map(&:strip) : []
end

def report(label, before, after)
  added = after - before
  removed = before - after
  say "#{label} : #{after.size} (#{added.size} ajout(s), #{removed.size} retrait(s))"
  added.each { |t| say "  + #{t[0, 110]}" }
  removed.each { |t| say "  - #{t[0, 110]}" }
end

# ---------------------------------------------------------------- git
def git(*cmd, allow_fail: false)
  out, status = Open3.capture2e('git', *cmd, chdir: ROOT)
  fail!("git #{cmd.join(' ')}\n#{out}") unless status.success? || allow_fail
  [out.strip, status.success?]
end

def github_slug
  url, = git('remote', 'get-url', 'origin')
  url[%r{github\.com[:/](?:[^@/]+@)?([^/]+/[^/.]+?)(?:\.git)?\z}, 1] || url[%r{github\.com[:/]([^/]+/[^/]+?)(?:\.git)?\z}, 1]
end

def api(path)
  uri = URI("https://api.github.com#{path}")
  res = Net::HTTP.get_response(uri)
  res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
rescue StandardError
  nil
end

def follow_deployment(slug, sha)
  say "Compilation et déploiement sur GitHub (2 à 5 minutes) : https://github.com/#{slug}/actions"
  deadline = Time.now + 15 * 60
  last = nil
  while Time.now < deadline
    runs = api("/repos/#{slug}/actions/runs?head_sha=#{sha}&per_page=5")
    run = runs && runs['workflow_runs'] && runs['workflow_runs'].first
    if run
      state = run['status'] == 'completed' ? run['conclusion'] : run['status']
      if state != last
        say "  état : #{{ 'pending' => 'en attente', 'waiting' => 'en attente', 'requested' => 'en attente', 'queued' => 'en file d\'attente',
                      'in_progress' => 'en cours', 'success' => 'réussi', 'failure' => 'échec', 'cancelled' => 'annulé' }[state] || state}"
        last = state
      end
      if run['status'] == 'completed'
        return say("\nSite à jour : #{SITE_URL}\n(le cache peut afficher l'ancienne version encore quelques minutes ; Ctrl+F5 ou Cmd+Maj+R pour recharger)") if run['conclusion'] == 'success'
        fail!("le déploiement a échoué. Détails : #{run['html_url']}")
      end
    end
    sleep 10
  end
  say "Le déploiement n'est pas terminé après 15 minutes. Suivez-le ici : https://github.com/#{slug}/actions"
end

# ---------------------------------------------------------------- programme principal
step 'Lecture du fichier Excel'
say excel
sheets = read_workbook(excel)
grants = build_grants(find_sheet(sheets, 'RECHER_Recap_subv'))
entries = build_bib(find_sheet(sheets, 'Références'))
fail!('aucune subvention ni publication lue : vérifiez le fichier') if grants.empty? || entries.empty?

grants_out = grants_yaml(grants)
bib_out = bib_text(entries)
fail!('un montant en dollars apparaît dans les subventions : publication annulée') if grants.to_yaml =~ /\$|\d\s*k?\s*CAD/i

unless NO_PUBLISH
  step 'Récupération de la dernière version du site'
  git('--version', allow_fail: true).last or fail!('git est introuvable : installez-le (https://git-scm.com).')
  git('pull', '--rebase', '--autostash', 'origin', 'main')
end

step 'Mise à jour des données'
before_grants = old_titles(GRANTS_FILE, /^  title: (.*)$/)
before_bib = old_titles(BIB_FILE, /^  title\s+= \{\{(.*)\}\},?$/)
File.write(GRANTS_FILE, grants_out)
File.write(BIB_FILE, bib_out)
report('Subventions', before_grants, old_titles(GRANTS_FILE, /^  title: (.*)$/))
report('Publications et présentations', before_bib, old_titles(BIB_FILE, /^  title\s+= \{\{(.*)\}\},?$/))
say "Par section : #{entries.group_by { |e| e[:cat] }.map { |k, v| "#{k} #{v.size}" }.join(', ')}"

if NO_PUBLISH
  say "\nFichiers régénérés (option --sans-publier) : rien n'a été publié."
  exit 0
end

files = ['_data/grants.yml', 'assets/ref.bib']
_, unchanged = git('diff', '--quiet', '--', *files, allow_fail: true)
if unchanged
  say "\nAucun changement par rapport au site en ligne : rien à publier."
  exit 0
end

step 'Publication'
unless AUTO_YES
  unless ask('Publier ces changements sur le site ? (o/N) ').downcase.start_with?('o', 'y')
    git('checkout', '--', *files)
    say 'Annulé : les fichiers ont été remis dans leur état précédent.'
    exit 0
  end
end
stamp = File.mtime(excel).strftime('%Y-%m-%d')
git('add', '--', *files)
git('commit', '-m', "Mise à jour des données depuis le dossier d'évaluation (#{stamp})", '--', *files)
git('push', 'origin', 'main')
sha, = git('rev-parse', 'HEAD')
say "Envoyé sur GitHub (commit #{sha[0, 7]})."

step 'Déploiement'
slug = github_slug
slug ? follow_deployment(slug, sha) : say("Le site sera recompilé par GitHub Actions dans quelques minutes : #{SITE_URL}")
