# Discourse Site Rearranger

This script is a framework for making scripted changes to a Discourse
site.  Its existing functionality might be enough for your purposes, or
you might need to extend it.

**This script does no error checking. It fails silently. Use it on a
staging server with a copy of your site and verify that it has taken
the actions you want rather than running it on a live site.**

## Configuration

A YAML file specifies the actions to take and the order to take them
in. The script reads the YAML file and takes the specified actions,
one at a time.

```yaml
---
- operationName:
    context: optional string to print but otherwise ignore
    arg1: value
    arg2: value
- nextOpName:
    arg1: value
    arg2: value
```

For example, it might look like this:

```yaml
---
- describe:
    context: Old Name
    category: 7
    name: New Name
    description: New description of category
    slug: new-slug
- movePosts:
    context: move only faq posts from the Support category to the Documentation category
    source: 3 # Support category ID
    target: 6 # Documentation category ID
    withTag: faq
    hide: false # do not hide the Support category when done
- movePosts:
    context: consolidate How-To category into documentation with how-to tag
    source: 8 # How-To category ID
    target: 6 # Documentation category ID
    addTag: how-to
    hide: true # hide the old How-To category, visible only to Admin
```

The operations are class method names, and the arguments are the
keyword arguments taken by the operation. The `context` is printed
as a debugging aid.  This could be done by appending lines near
the end of the script that look like:

```ruby
ops.describe(context: "Old Name", category: 7, name: "New Name, description: "New description of category", slug: "new-slug")
ops.movePosts(context: "move only faq posts from the Support category to the Documentation category", source: 3, target: 6, withTag: "faq", hide: false)
ops.movePosts(context: "consolidate How-To category into documentation with how-to tag", source: 8, target: 6, addTag: "how-to", hide: true)
```

but the YAML file is easier to read and modify.

You'll need to copy the YAML file into your running Discourses
app.  One way to do that is through the `shared/tmp` directory.

```bash
# cp rearrange.yaml /var/discourse/shared/app/tmp/
```

## Provided methods

These methods may or may not meet all your needs. You may have to
change, expand, or augment them.  This is intended to be a starting
framework to make it easier to rearrange your site.

All arguments are named.

Note that named arguments with no default value are required; those
with a default value provided are optional.

### Specifying categories

The `category`, `source`, `target`, and `parent` arguments are
always numeric category IDs, not names or slugs.

### Describing context

Every action can be provided with a `context` string which is printed
out during execution to help you remember what your script is doing.
These are not shown in the individual method examples, but the framework
supports them for every method, including any new ones you add.

### setHiddenCategory

```ruby
def setHiddenCategory(category:)
```

```yaml
- setHiddenCategory:
    category: 20 # ID
```

If you move all topics out of a category with `movePosts`, then by
default the category out of which they have moved will be hidden. If
you `setHiddenCategory` then it will additionally move the category
to the specified different parent category specifically for holding
the hidden categories.

If you use this method, it will probably be the first method called.

### describe

```ruby
def describe(category:, name: nil, description: nil, color: nil, slug: nil)
```

```yaml
- describe:
    category: 20
    name: Display Name
    description: Text of first paragraph of category topic
    color: 0F0F0F # 6-character hex color code string
    slug: category-slug # string
```

### redirect

```ruby
def redirect(url:, category:)
```

```yaml
- redirect:
    url: /url/path # not the full URL; the path is called "url" internally
    category: 20 $ ID
```

This specifically does a redirect to a category. Note that when moving
all posts from one category to another, by default a redirect is automatically
created.

### movePosts

```ruby
def movePosts(source:, target:, addTag: nil, withTag: nil, hide: nil, redirect: nil)
```

```yaml
- movePosts:
    source: 4
    target: 2
    addTag: someTag
```

Not all argument combinations are meaningful.  In particular, the
`withTag:` argument normally indicates that only a subset of the
topics in the `source:` category are moved to the `target:` category.
In this case, the `source:` category will neither be hidden nor a
redirect created by default. However, if `withTag:` is not provided,
then all the posts (except the topic post) are moved.

If all the posts are being moved (that is, `withTag` has not been
set), then by default (unless `hide: false) the `source:` category
will be hidden using the `hideCategory` action.

It is reasonable to provide both `withTag:` and `addTag:`; then all
posts matching `withTag:` will both be moved and have the `addTag:`
added to them, and `withTag:` will remain on the moved posts.

### hideCategory

```ruby
def hideCategory(category:)
```

```yaml
- hideCategory:
    category: 14
```

Hide the category by restricting it to be viewable only by
`admins`. Additionally, if a hidden category has been set, the
category will be reparented to the hidden category.  The category
being moved must have no child categories, or the reparenting action
will _silently_ fail.

### exposeCategory

```ruby
def exposeCategory(category:)
```

```yaml
- exposeCategory:
    category: 14
```

The inverse of `hideCategory`; gives `full` permissions to `everyone` 
for that category.

### removeTagInCategory

```ruby
def removeTagInCategory(category:, tag:)
```

```yaml
- removeTagInCategory:
    category: 13
    tag: tag-to-remove
```

Removes the specified `tag:` from every topic in the `category:`

### tagCategory

```ruby
def tagCategory(category:, tag:)
```

```yaml
- tagCategory:
    category: 15
    tag: tag-to-add
```

The inverse of `removeTagInCategory`; adds `tag:` to every topic in `category:`

### reparentCategory

```ruby
def reparentCategory(category:, parent:, recolor: true)
```

```yaml
- reparentCategory:
    category: 24
    parent: 17
```

Make the `category:` be a sub-category of `parent:` and optionally (by default)
change the color associated with `category:` to match the color of `parent:`

### Usage

If these methods already cover all of your needs, you can
use this script as-is.  You can simply copy rearrange.rb to a
`script/discourse-site-rearranger/` directory in your Discourse
instance, or clone this repository into your running Discourse:

```bash
# cd /var/discourse
# ./launcher enter app
# git clone https://github.com/johnsonm/discourse-site-rearranger.git script/discourse-site-rearranger
# ruby script/discourse-site-rearranger/rearrange.rb /shared/tmp/rearrange.yaml
```

This will print progress output something like this:

```
==========
Move hidden categories out of the way so they don't clutter admin view
setHiddenCategory: {:category=>11}
==========
Rename Old Name to New Name
describe: {:category=>7, :name=>"New Name", :description=>"New description of category", :slug=>"new-slug"}
==========
move only faq posts from the Support category to the Documentation category
movePosts: {:source=>3, :withTag=>"faq", :target=>6}
==========
```

If you need to add more actions, you can fork this repository, add the actions
you want, and clone it in the same way but from your fork.  Alternatively,
you can just edit it and copy it into the same location without cloning.

For example, if you want to permanently delete all topics in a
category, you might define a `destroyAllInCategory` action, like this:

```ruby
  def destroyAllInCategory(category:)
    Topic.where(category_id: category).destroy_all
  end
```

