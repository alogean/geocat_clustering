require 'rubygems'
require 'find'
require 'nokogiri'
require 'rdf'
require 'rdf/ntriples'
require 'rdf/turtle'
require 'json'

include RDF     


def xml_to_rdf(root_directory_path="../db/sitg_catalog", output_ttl_file, baseuri)
    
  # Open of a turtle writter with various prefixes
    
  RDF::Writer.for(:ntriples)
  RDF::Writer.open(output_ttl_file,
    :base_uri => baseuri,
    :prefixes => {
    nil     => "http://www.sitg.ch/thesaurus/ns#",
    :foaf   => "http://xmlns.com/foaf/0.1/",
    :rdf    => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    :rdfs   => "http://www.w3.org/2000/01/rdf-schema#",
    :owl    => "http://www.w3.org/2002/07/owl#",
    :skos   => "http://www.w3.org/2004/02/skos/core#",
    :dct    => "http://purl.org/dc/terms/",
    :coll   => "http://www.sitg.ch/thesaurus/collections/",
    :schema => "http://www.sitg.ch/thesaurus/schema#"
  }) do |writer|   
    writer << RDF::Graph.new do |graph| 
      temp = Hash.new
      root_node = RDF::Node.new
      graph << RDF::Statement.new(root_node, RDF::type, RDF::SKOS.Concept)
      graph << RDF::Statement.new(root_node, RDF::SKOS.prefLabel, RDF::Literal.new("SITG", :language => :fr))    
      Find.find('./' + root_directory_path) do |path|
        if File.directory? path
           parent_node = RDF::Node.new
           name = path.split("/").last
           graph << RDF::Statement.new(parent_node, RDF::type, RDF::SKOS.Concept)
           graph << RDF::Statement.new(parent_node, RDF::SKOS.prefLabel, RDF::Literal.new(name, :language => :fr))
           graph << RDF::Statement.new(parent_node, RDF::SKOS.broader, root_node.to_s)
           temp[path] = parent_node
        else   
          parent_path_name = path.gsub("/" + path.split("/").last, "")
          name = path.split("/").last.gsub(".xml", "").gsub("_", " ")
          doc = Nokogiri::XML(File.open(File.open(path)), nil, 'UTF-8')
          title = getfromxml doc, '//idCitation/resTitle'
          organisation = getfromxml doc, '//rpOrgName'
          content = getfromxml doc, '//idAbs'
          definition = organisation + "\n\n" + content
          terminal_node = RDF::Node.new
          graph << RDF::Statement.new(terminal_node, RDF::type, RDF::SKOS.Concept)
          graph << RDF::Statement.new(terminal_node, RDF::SKOS.prefLabel, RDF::Literal.new(name, :language => :fr))
          graph << RDF::Statement.new(terminal_node, RDF::SKOS.altLabel, RDF::Literal.new(title, :language => :fr))
          graph << RDF::Statement.new(terminal_node, RDF::SKOS.definition, RDF::Literal.new(definition, :language => :fr))
          graph << RDF::Statement.new(terminal_node, RDF::SKOS.broader, temp[parent_path_name].to_s)
        end
      end
    end
  end
end


def xml_to_csv(root_directory_path='../db/sitg_catalog')
  puts "source, target"
  Find.find(root_directory_path) do |path|
    if File.directory? path
       name = path.split("/").last
       root = path.split("/")[-2]
       puts root + "," + name
    else   
      parent_path_name = path.split("/")[-2]
      name = path.split("/").last
      doc = Nokogiri::XML(File.open(File.open(path)), nil, 'UTF-8')
      title = getfromxml doc, '//idCitation/resTitle'
      organisation = getfromxml doc, '//rpOrgName'
      content = getfromxml doc, '//idAbs'
      definition = organisation + "\n\n" + content
      puts parent_path_name + "," + fo(title)
    end   
  end
end


def xml_to_hash(root_directory_path='../db/sitg_catalog')
  h = Hash.new
  Find.find(root_directory_path) do |path|
    if !File.directory? path
      name = path.split("/").last
      doc = Nokogiri::XML(File.open(File.open(path)), nil, 'UTF-8')
      title = getfromxml doc, '//idCitation/resTitle'
      organisation = getfromxml doc, '//rpOrgName'
      content = getfromxml doc, '//idAbs'
      h[name] = { 
        :title => fo(title), 
        :organisation => fo(organisation), 
        :content => fo(content) 
      }
    end   
  end
  return h
end


def jsontree ( input_ttl_file, output_json, json_root_node_name="sitg_catalog")
  # output Hash
  oh = { :name => json_root_node_name, :children => [] }
  
  graph = RDF::Graph.load(input_ttl_file )
  
  queryConcept = RDF::Query.new({
    :concept => {
      RDF.type  => RDF::SKOS.Concept,
      RDF::SKOS.definition => :definition,
      RDF::SKOS.note => :note
    }
  })
  queryCollection = RDF::Query.new({
    :collection => {
      RDF.type  => RDF::SKOS.Collection,
      RDF::SKOS.note => :note
    }
  })
  queryCollectionMembers = RDF::Query.new({
    :collection => {
      RDF.type  => RDF::SKOS.Collection,
      RDF::SKOS.member => :members
    }
  })
  
  # hash containing the filename as key and for each key the title, organisation and content
  mainDic = xml_to_hash
  
  # Build a hash containing the concept as key and for each key the filename and note
  conceptDico = Hash.new
  queryConcept.execute(graph).each do |solution|
    #puts solution.definition.to_s
    conceptDico[solution.concept] = { 
      :title => solution.definition.to_s.gsub("SITG_XML_COMPLET/", ""), 
      :note => get_list_from_note(solution.note.to_s, solution.concept.to_s.split("_").last) 
    }
  end
  
  memberHash = Hash.new
  queryCollectionMembers.execute(graph).each do |member|
    key = member.collection.to_s.gsub("http://www.sitg.ch/","")
    member = { 
        :title => get_title(mainDic, conceptDico[member.members][:title]), 
        :note => conceptDico[member.members][:note]
    }
    if memberHash.has_key? key then 
      memberHash[key] << member
    else 
      memberHash[key] = [ member ]
    end
  end
  
  queryCollection.execute(graph).each do |solution|
    colname = solution.collection.to_s.gsub("http://www.sitg.ch/","")
    collectionHash = { :name => colname , :children => [], :note => get_list_from_note(solution.note.to_s, colname.split("_").last) }
    memberHash[colname].each do |item|
      #puts item.to_s
      memberH = {:name => item[:title], :size => 3000, :note => item[:note] }
      #puts memberH.to_s
      collectionHash[:children] << memberH
    end 
    oh[:children] << collectionHash
  end

  File.open(output_json, 'w') { |file| 
    file.write(oh.to_json) 
  }
  
end

# Here some helper methods

def get_list_from_note(note, cluster_name)
  min = 1000000
  max = 0
  list = []
  note.gsub("[", "").gsub("]", "").split(",").each do |item|
    a = item.split("=")
    list << { :text => a[0].gsub(" ", ""), :size => a[1].to_f }
    if a[1].to_f < min 
      min = a[1].to_f
    end
    if a[1].to_f > max 
      max = a[1].to_f
    end
  end
  list.each do |v|
    v[:size] =  v[:size]* 1000
  end
  list << { :text => cluster_name , :size => 100 }
  list  
end


def get_title(dic, key)
  if dic.has_key? key then
    dic[key][:title]
  else 
    key
  end
end


def add_to_catalog ( key, value, hash)
    if !hash.has_key? key
        hash[key] = Array.new
    end
    hash[key] << value
end


def getfromxml ( doc, xpath )
    result = doc.xpath(xpath).first
    if !result.nil?
        result.content
        else ""
    end  
end


def fo(mystring)
    mystring.gsub(/\s{2,}/, ' ').gsub(",", "")
end


def ttl_to_json(source_dir="../db/clustering_results")
  Find.find(source_dir) do |path|
    if !File.directory? path
      if path.split(".").last == "ttl"
        nt = path.gsub(".ttl", ".nt")
        json = path.gsub(".ttl", ".json")
        puts "Processing " + path
        #system( "rapper #{path} -i turtle -o ntriples > #{nt}" )  
        jsontree(nt, json)
      end
    end
  end
end

ttl_to_json
