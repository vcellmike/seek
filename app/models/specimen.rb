require 'grouped_pagination'
require 'acts_as_authorized'
require 'subscribable'
require 'acts_as_scalable'
class Specimen < ActiveRecord::Base
  include Subscribable

   acts_as_scalable
  acts_as_authorized

  before_save  :clear_garbage


  has_many :samples
  has_many :activity_logs, :as => :activity_loggable
  has_many :assets_creators, :dependent => :destroy, :as => :asset, :foreign_key => :asset_id
  has_many :creators, :class_name => "Person", :through => :assets_creators, :order=>'assets_creators.id'
#  accepts_nested_attributes_for :creators
  belongs_to :institution
  belongs_to :culture_growth_type
  belongs_to :strain

  has_one :organism, :through=>:strain


  alias_attribute :description, :comments

  HUMANIZED_COLUMNS = Seek::Config.is_virtualliver ? {} : {:lab_internal_number=> "lab internal identifier", :born => 'culture starting date', :culture_growth_type => 'culture type', :provider_id => "provider's cell culture identifier"}

  validates_numericality_of :age, :only_integer => true, :greater_than=> 0, :allow_nil=> true, :message => "is not a positive integer"
  validates_presence_of :title,:lab_internal_number, :contributor,:strain

  validates_presence_of :institution if Seek::Config.is_virtualliver
  validates_uniqueness_of :title

  def self.sop_sql()
  'SELECT sop_versions.* FROM sop_versions ' + 'INNER JOIN sop_specimens ' +
  'ON sop_specimens.sop_id = sop_versions.sop_id ' +
  'WHERE (sop_specimens.sop_version = sop_versions.version ' +
  'AND sop_specimens.specimen_id = #{self.id})'
  end

  has_many :sops,:class_name => "Sop::Version",:finder_sql => self.sop_sql()
  has_many :sop_masters,:class_name => "SopSpecimen"
  grouped_pagination :pages=>("A".."Z").to_a, :default_page => Seek::Config.default_page(self.name.underscore.pluralize)

  def related_people
    creators
  end  
  
  searchable do
    text :description,:title,:lab_internal_number
    text :culture_growth_type do
      culture_growth_type.try :title
    end
    
    text :strain do
      strain.try :title
    end
    
    text :institution do
      institution.try :name
    end if Seek::Config.is_virtualliver
  end if Seek::Config.solr_enabled

  def age_in_weeks
    if !age.nil?
      age.to_s + " (weeks)"
    end
  end

  def can_delete? user=User.current_user
    samples.empty? && super
  end

  def self.user_creatable?
    true
  end

  def clear_garbage
    if culture_growth_type.try(:title)=="in vivo"
      self.medium=nil
      self.culture_format=nil
      self.temperature=nil
      self.ph=nil
      self.confluency=nil
      self.passage=nil
      self.viability=nil
      self.purity=nil
    end
    if culture_growth_type.try(:title)=="cultured cell line"||culture_growth_type.try(:title)=="primary cell culture"
      self.sex=nil
      self.born=nil
      self.age=nil
    end

  end

  def strain_title
    self.strain.try(:title)
  end

  def strain_title= title
    existing = Strain.all.select{|s|s.title==title}.first
    if existing.blank?
      self.strain = Strain.create(:title=>title)
    else
      self.strain= existing
    end
  end

  def clone_with_associations
    new_object= self.clone
    new_object.policy = self.policy.deep_copy
    new_object.sop_masters = self.try(:sop_masters)
    new_object.creators = self.try(:creators)
    new_object.project_ids = self.project_ids
    new_object.scale_ids = self.scale_ids

    return new_object
  end


  def self.human_attribute_name(attribute)
    HUMANIZED_COLUMNS[attribute.to_sym] || super
  end

  def born_info
    if born.nil?
      ''
    else
      if try(:born).hour == 0 && try(:born).min == 0 && try(:born).sec == 0
        try(:born).strftime('%d/%m/%Y')
      else
        try(:born).strftime('%d/%m/%Y @ %H:%M:%S')
      end
    end
  end

end
