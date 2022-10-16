require_relative "../../config/environment"
require 'yaml'

### Usage:
#
# scripts/rearrange.rb rearrange.yaml
#
# rearrange.yaml Format:
# ---
# - operationName:
#     context: optional string to print but otherwise ignore
#     arg1: value
#     arg2: value
# - nextOpName:
#     arg1: value
#     arg2: value
#
# For example, it might look like this:
# ---
# - describe:
#     context: Old Name
#     category: 7
#     name: New Name
#     description: New description of category
#     slug: new-slug
# - movePosts:
#     context: move only faq posts from the Support category to the Documentation category
#     source: 3 # Support category ID
#     target: 6 # Documentation category ID
#     withTag: faq
#     hide: false # do not hide the Support category when done
# - movePosts:
#     context: consolidate How-To category into documentation with how-to tag
#     source: 8 # How-To category ID
#     target: 6 # Documentation category ID
#     addTag: how-to
#     hide: true # hide the old How-To category, visible only to Admin
#
# The operations are class method names, and the arguments are the keyword
# arguments taken by the operation. The `context` is printed as a debugging aid.
# This could be done by appending lines to this script that look like:
#
#     ops.describe(context: "Old Name", category: 7, name: "New Name, description: "New description of category", slug: "new-slug")
#     ops.movePosts(context: "move only faq posts from the Support category to the Documentation category", source: 3, target: 6, withTag: "faq", hide: false)
#
# but the YAML file is easier.
#
#

class Operations
  def describe(category:, name: nil, description: nil, color: nil, slug: nil)
    c = Category.find(category)
    c.name = name unless name.nil?
    c.description = description unless description.nil?
    c.slug = slug unless slug.nil?
    c.color = color unless color.nil?
    c.rename_category_definition
    c.save
  end

  def redirect(url:, category:)
    Permalink.create(url: url, category_id: category)
  end

  def movePosts(source:, target:, addTag: nil, withTag: nil, hide: nil, redirect: nil)
    if hide.nil?
      if withTag
        hide = false
        redirect = false
      else
        hide = true
        redirect = true
      end
    end
    self.tagCategory(category: source, tag: addTag) unless addTag.nil?
    category_topic = Category.find(source).topic_id
    topics = Topic.where(category_id: source).where.not(id: category_topic)
    topics = topics.joins(:tags).where(tags: {name: withTag}) unless withTag.nil?
    topics.update_all(category_id: target)
    url = Category.find(source).url
    self.redirect(url: url, category: target) if redirect
    self.hideCategory(category: source) if hide
  end

  def setHiddenCategory(category:)
    @hiddenCategory = category
  end

  def hideCategory(category:)
    c = Category.find(category)
    c.set_permissions({:admins => :full})
    c.save!
    self.reparentCategory(category: category, parent: @hiddenCategory) if @hiddenCategory
  end

  def exposeCategory(category:)
    c = Category.find(category)
    c.set_permissions({:everyone => :full})
    c.save!
  end

  def publicCategoriesReadonly()
    g = Guardian.new # anonymous
    Category.all.each do |c|
      if g.can_see_category?(c)
        c.set_permissions({:everyone => :readonly, :admins => :full})
        c.save
      end
    end
  end

  def removeTagInCategory(category:, tag:)
    t = Tag.find_by_name(tag)
    t.topics.where(category_id: category).each do |topic|
      topic.tags = topic.tags.where.not(id: t.id)
      topic.save
    end
  end

  def tagCategory(category:, tag:)
    guardian = Guardian.new(Discourse.system_user)
    c = Category.find(category)
    c.topics.find_each do |topic|
      DiscourseTagging.tag_topic_by_names(topic, guardian, [tag], append: true)
    end
  end

  def reparentCategory(category:, parent:, recolor: true)
    p = Category.find(parent)
    c = Category.find(category)
    c.parent_category_id = p.id
    c.color = p.color if recolor
    c.save
  end

  def init(config:)
    @cfg = YAML.load(File.read(config))
  end

  def announce(op:, args:)
    context = args.delete(:context)
    $stderr.puts "=========="
    $stderr.puts context unless context.nil?
    $stderr.puts op + ": " + args.to_s
    args
  end

  def iterate
    @cfg.each do |item|
      op = item.keys[0]
      args = item[op].transform_keys(&:to_sym)
      args = self.announce(op: op, args: args)
      self.send(op, **args)
    end
  end

  def finalize
    Category.update_stats
  end
end

ops = Operations.new
ops.init(config: ARGV[0])
ops.iterate
ops.finalize

