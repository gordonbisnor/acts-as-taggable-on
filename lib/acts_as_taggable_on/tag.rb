module ActsAsTaggableOn
  class Tag < ::ActiveRecord::Base
    include ActsAsTaggableOn::Utils

    scope :visible, :conditions => { :visible => true }
  
  def self.related items
    taggables = items.map(&:taggable)
    results = taggables.map { |item|   
      item.tags.all({
        :select => "name", 
        :conditions => { :visible => true }
        }) if item.present?
      }.flatten.reject{|x| x.nil? }.map(&:name)
    results.reject! { |x| @tag == x } 
    results.sort.uniq
  end
  
  def update_hidden_or_visibles
    if related_hidden_ids.present?
      related_tags.clear
      hidden_tags = Tag.find(:all, :conditions => { :id => related_hidden_ids })
      related_tags << hidden_tags if hidden_tags.present?
    end
    
    if related_visible_ids.present?
      related_visible_tags.clear
      visible_tags = Tag.find(:all, :conditions => { :id => related_visible_ids })
      related_visible_tags << visible_tags if visible_tags.present?
    end
  end
  
  attr_accessor :related_hidden_ids, :related_visible_ids
  
  def find_related_tags_and_update_articles
    if related_tags.present?
      a = Article.find_tagged_with(name)
      a.map(&:save) if a.present?
      l = LearningCurve.find_tagged_with(name)
      l.map(&:save) if l.present?
    end
  end

  def hidden?
    !visible
  end

  default_scope :order => "name ASC"

  has_many :related_hidden_tags, :foreign_key => "hidden_tag_id"
  has_many :related_tags, :through => :related_hidden_tags, :source => :tag
  has_many :visible_tag_relationships, :foreign_key => "tag_id", :class_name => "RelatedHiddenTag"
  has_many :related_visible_tags, :through => :visible_tag_relationships, :source => :tag
    
  after_save :update_hidden_or_visibles
  after_save :find_related_tags_and_update_articles

    attr_accessible :name if defined?(ActiveModel::MassAssignmentSecurity)
    
    ### ASSOCIATIONS:

    has_many :taggings, :dependent => :destroy, :class_name => 'ActsAsTaggableOn::Tagging'

    ### VALIDATIONS:

    validates_presence_of :name
    validates_uniqueness_of :name, :if => :validates_name_uniqueness?
    validates_length_of :name, :maximum => 255

    # monkey patch this method if don't need name uniqueness validation
    def validates_name_uniqueness?
      true
    end

    ### SCOPES:

    def self.named(name)
      if ActsAsTaggableOn.strict_case_match
        where(["name = #{binary}?", name])
      else
        where(["lower(name) = ?", name.downcase])
      end
    end

    def self.named_any(list)
      if ActsAsTaggableOn.strict_case_match
        where(list.map { |tag| sanitize_sql(["name = #{binary}?", tag.to_s.mb_chars]) }.join(" OR "))
      else
        where(list.map { |tag| sanitize_sql(["lower(name) = ?", tag.to_s.mb_chars.downcase]) }.join(" OR "))
      end
    end

    def self.named_like(name)
      where(["name #{like_operator} ? ESCAPE '!'", "%#{escape_like(name)}%"])
    end

    def self.named_like_any(list)
      where(list.map { |tag| sanitize_sql(["name #{like_operator} ? ESCAPE '!'", "%#{escape_like(tag.to_s)}%"]) }.join(" OR "))
    end

    ### CLASS METHODS:

    def self.find_or_create_with_like_by_name(name)
      if (ActsAsTaggableOn.strict_case_match)
        self.find_or_create_all_with_like_by_name([name]).first
      else
        named_like(name).first || create(:name => name)
      end
    end

    def self.find_or_create_all_with_like_by_name(*list)
      list = [list].flatten

      return [] if list.empty?

      existing_tags = Tag.named_any(list)

      list.map do |tag_name|
        comparable_tag_name = comparable_name(tag_name)
        existing_tag = existing_tags.find { |tag| comparable_name(tag.name) == comparable_tag_name }

        existing_tag || Tag.create(:name => tag_name)
      end
    end

    ### INSTANCE METHODS:

    def ==(object)
      super || (object.is_a?(Tag) && name == object.name)
    end

    def to_s
      name
    end

    def count
      read_attribute(:count).to_i
    end

    class << self
      private

      def comparable_name(str)
        str.mb_chars.downcase.to_s
      end

      def binary
        /mysql/ === ActiveRecord::Base.connection_config[:adapter] ? "BINARY " : nil
      end
    end
  end
end
