# template is no longer accessible via LOAD_PATH, but it hasn't changed in two years, so:
# subpar, I know, but it works for now.
class ActsAsTaggableOnMigration < ActiveRecord::Migration
  def self.up
    create_table :tags do |t|
      t.string :name
    end

    create_table :taggings do |t|
      t.references :tag

      # You should make sure that the column created is
      # long enough to store the required class names.
      t.references :taggable, :polymorphic => true
      t.references :tagger, :polymorphic => true

      # Limit is created to prevent MySQL error on index
      # length for MyISAM table type: http://bit.ly/vgW2Ql
      t.string :context, :limit => 128

      t.datetime :created_at
    end

    add_index :taggings, :tag_id
    add_index :taggings, [:taggable_id, :taggable_type, :context]
  end

  def self.down
    drop_table :taggings
    drop_table :tags
  end
end



class RedmineActsAsTaggableOn::Migration < ActsAsTaggableOnMigration
  class SchemaMismatchError < StandardError; end

  def up
    enforce_declarations!
    check_for_old_style_plugins

    if ok_to_go_up?
      super
    else
      say 'Not creating "tags" and "taggings" because they already exist'
    end
  end

  def down
    enforce_declarations!

    if ok_to_go_down?
      super
    else
      say 'Not dropping "tags" and "taggings" because they\'re still needed by'
      say 'the following plugins:'
      plugins_still_using_tables.each { |p| say p.id, true }
    end
  end

  private
  def enforce_declarations!
    unless current_plugin_declaration_made?
      msg = "You have to declare that you need redmine_acts_as_taggable_on inside\n"
      msg << "init.rb. See https://github.com/hdgarrood/redmine_acts_as_taggable_on\n"
      msg << "for more details.\n\n"
      fail msg
    end
  end

  def current_plugin_declaration_made?
    current_plugin.requires_acts_as_taggable_on?
  end

  def current_plugin
    Redmine::Plugin::Migrator.current_plugin
  end

  # Check if any plugins are using acts-as-taggable-on directly; the purpose of
  # this is only to print a warning if so.
  def check_for_old_style_plugins
    Redmine::Plugin.all.each { |p| p.requires_acts_as_taggable_on? }
    nil
  end

  def ok_to_go_up?
    tables_already_exist = %w(tags taggings).any? do |table|
      ActiveRecord::Base.connection.table_exists? table
    end
    if tables_already_exist
      assert_schema_match!
      return false
    end
    true
  end

  def assert_schema_match!
    if (obtain_structure('tags') != expected_tags_structure) ||
       (obtain_structure('taggings') != expected_taggings_structure)
      msg = "A plugin is already using the \"tags\" or \"taggings\" tables, and\n"
      msg << "the structure of the table does not match the structure expected\n"
      msg << "by #{current_plugin.id}.\n"
      raise SchemaMismatchError, msg
    end
  end

  def obtain_structure(table_name)
    ActiveRecord::Base.connection.columns(table_name).
      reject { |c| %w(created_at updated_at id).include? c.name }.
      map { |c| [c.name, c.type.to_s] }.
      sort
  end

  def expected_tags_structure
    [
      ['name', 'string']
    ]
  end

  def expected_taggings_structure
    [
      ['tag_id', 'integer'],
      ['taggable_id', 'integer'],
      ['taggable_type', 'string'],
      ['tagger_id', 'integer'],
      ['tagger_type', 'string'],
      ['context', 'string'],
    ].sort
  end

  # A list of plugins which are using the acts_as_taggable_on tables (excluding
  # the current one)
  def plugins_still_using_tables
    Redmine::Plugin.all.
      select(&:using_acts_as_taggable_on_tables?).
      reject {|p| p == Redmine::Plugin::Migrator.current_plugin }
  end

  def ok_to_go_down?
    plugins_still_using_tables.empty?
  end
end
