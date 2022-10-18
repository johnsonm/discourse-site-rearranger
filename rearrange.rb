require_relative "../../config/environment"
require 'yaml'

### Usage:
#
# scripts/rearrange.rb rearrange.yaml
#

class Operations
  def describe(category:, name: nil, description: nil, color: nil, slug: nil)
    c = Category.find(category)
    c.name = name unless name.nil?
    c.description = description unless description.nil?
    unless slug.nil?
      c.slug = slug
      @slugTagRedirects[category] = category
    end
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
    @slugTagRedirects[source] =  target if hide or redirect
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

  def _formatSlugTag(c)
    if c.slug_path.length == 1
      return sprintf("#%s", c.slug)
    else
      return sprintf("#%s:%s", *c.slug_path)
    end
  end

  def _loadSlugTags()
    tags = {}
    Category.all.each do |c|
      tags[c.id] = _formatSlugTag(c)
    end
    tags
  end

  def _remapSlugs()
    # remap all existing slugs with ":" in them before any parent-only slugs
    # note that the parent-only slugs will cover parent slug changed but child
    # slug not changed
    childSourceMappings = []
    parentSourceMappings = []
    allSourceTags = []
    @slugTagRedirects.each do |source, target|
      from = @startTags[source]
      to = _formatSlugTag(Category.find(target))
      if from.include? ':'
        childSourceMappings.append([from, to])
      else
        parentSourceMappings.append([from, to])
      end
      allSourceTags.append(Regexp.escape(from))
    end
    sourceMappings = childSourceMappings + parentSourceMappings
    sourceMappings.each do |from, to|
      $stderr.puts sprintf('mapping %s to %s', from, to)
    end

    findRe = "(" + allSourceTags.join("|") + ")"
    Post.raw_match(findRe, 'regex').find_each do |p|
      raw = p.raw
      sourceMappings.each do |from, to|
        raw = raw.gsub(from, to)
      end
      if raw == p.raw
        # No case-sensitive option available, Discourse uses ILIKE
        $stderr.puts "Not changed: " + p.url
      else
        $stderr.puts "Changed: " + p.url
        p.revise(Discourse.system_user, { raw: raw }, bypass_bump: true, skip_revision: true)
      end
    end
  end

  def init(config:)
    @cfg = YAML.load(File.read(config))
    @startTags = self._loadSlugTags() # category => original slug text
    @slugTagRedirects = {} # source => target category IDs; source==target for changed slug
  end

  def _announce(op:, args:)
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
      args = self._announce(op: op, args: args)
      self.send(op, **args)
    end
  end

  def finalize
    Category.update_stats
    self._remapSlugs
  end
end

ops = Operations.new
ops.init(config: ARGV[0])
ops.iterate
ops.finalize

