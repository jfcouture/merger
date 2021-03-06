module Merger
  class Merge
    attr_reader :keep, :duplicates, :options
  
    def initialize(*records)
      @options = records.extract_options!
      @options[:destroy] = true unless @options.has_key?(:destroy)
      records = records.flatten.uniq
      @keep = options[:keep] || records.sort_by(&:id).first
      @duplicates = records - [@keep]
    end
  
    def ignored_associations
      return @ignored if @ignored
      @ignored = Array(options[:skip_association])
      keep.class.reflect_on_all_associations.each do |association|
        @ignored << association.name if association.through_reflection
      end
      @ignored
    end

    def associations!
      keep.class.reflect_on_all_associations.each do |association|
        duplicates.each do |record|
          next if ignored_associations.include?(association.name)
          case association.macro
          when :has_many, :has_and_belongs_to_many
            name = "#{association.name.to_s}"
            if options[:fast]
              record.send("#{name}").update_all(association.primary_key_name => keep.id)
            else
              keep.send("#{name}=", keep.send(name) | record.send(name))
            end
          when :belongs_to, :has_one
            keep.send("#{association.name}=", record.send(association.name)) if keep.send("#{association.name}").nil?
          end
        end
      end
    end
    
    def merge!
      keep.class.transaction do
        duplicates.each {|duplicate| duplicate.send(:before_merge, keep) if duplicate.respond_to?(:before_merge) }
        associations!
        duplicates.each {|duplicate| duplicate.send(:after_merge, keep) if duplicate.respond_to?(:after_merge) }
        
        if options[:destroy]
          duplicates.each do |dup|
            dup.reload
            dup.destroy
          end
        end
        
      end
    end
  
  end
end