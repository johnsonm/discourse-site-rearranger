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

  def migrateRetortToReactions(allowed:, likes: nil, emojimap: nil)
    # migrate where possible without overriding any existing likes
    # this is a necessarily lossy conversion, and is consistent only by ordering of PostDetail
    # no attempt is made to prefer one PostDetail record over another
    emojimap = {} if emojimap.nil?
    allowed.each do |a|
      emojimap[a] = a
    end
    retort = "retort".freeze
    emojiType = "emoji".freeze
    usermap = Hash.new { |hash, username| hash[username] = User.find_by_username(username) }
    postmap = Hash.new { |hash, post_id| hash[post_id] = Post.find(post_id) }
    likeType = PostActionType.where(name_key: "like").pluck(:id).first

    PostDetail.where(extra: retort).each do |pd|
      begin
        p = postmap[pd.post_id]
      rescue
        # PostDetail not consistent WRT delete
        $stderr.puts sprintf("Could not find post for %d: %s / %s", pd.post_id, pd.key, pd.value)
        next
      end
      emoji = pd.key.split('|').first
      users = JSON.parse(pd.value)
      users.each do |user|
        u = usermap[user]
        next if u.nil? # changed user name or deleted user leaves orphaned Retorts
        if likes.include?(emoji)
          pa = PostAction.where(post_id: p.id, user_id: u.id, post_action_type_id: likeType).first
          next unless pa.nil?
          $stderr.puts sprintf("Adding like for Retort %s for user %s in %s", emoji, user, p.url)
          PostActionCreator.create(u, p, :like, created_at: pd.created_at, silent: true)
        elsif emojimap.has_key?(emoji)
          e = emojimap[emoji]
          r = DiscourseReactions::Reaction.where(post_id: p.id, reaction_type: emojiType, reaction_value: e).first_or_create
          ru = DiscourseReactions::ReactionUser.where(user_id: u.id, post_id: p.id).first
          next unless ru.nil?
          $stderr.puts sprintf("Converting Retort %s to Reaction %s for user %s in %s", emoji, e, user, p.url)
          DiscourseReactions::ReactionUser.create(reaction_id: r.id, user_id: u.id, post_id: p.id, created_at: pd.created_at)
        else
          $stderr.puts sprintf("Ignoring unmapped Retort %s for user %s in %s", emoji, user, p.url)
        end
      end
    end
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
    return if @slugTagRedirects.length == 0

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

