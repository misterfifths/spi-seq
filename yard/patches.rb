# frozen_string_literal: true

require "yard/templates/helpers/html_helper"

# yard rather inconsistently qualifies classes/methods. Since users are going
# to be dealing with core.rb, which includes the important stuff in the global
# namespace, these patches hack off module names wherever we can. It also tries
# harder to make relative paths to methods that belong to the same class that's
# being documented (e.g. Chord#intervals on the Chord page should just be
# #intervals).

module YARD::Templates::Helpers::HtmlHelper
  # This is for the return type of methods. It uses the `@return` string
  # verbatim when not linking the text (i.e. in the summaries at the top of
  # the file).
  alias __orig_sig_types signature_types
  def signature_types(meth, link = true)
    __orig_sig_types(meth, link).gsub(/\b(?:\w+::)+(\w+)/, '\1')
  end

  # Method signatures and @returns go through this method with an explicit
  # `title`, which the original method uses verbatim, so minimize that. Also
  # by default it doesn't construct relative paths, so we get things like
  # the documentation for Chord saying things like "enumerable over its
  # Chord#intervals", which is silly.
  alias __orig_link_object link_object
  def link_object(obj, title = nil, anchor = nil, relative = true)
    if title.is_a?(String)
      # This may be user-provided text like `{#method this}`, so don't blow it
      # away, just try to minimize it.
      title = title.split("::").last
    elsif title.nil?
      resolved_obj = YARD::Registry.resolve(object, obj, true, true)
      if resolved_obj.is_a?(YARD::CodeObjects::Base)
        if resolved_obj.is_a?(YARD::CodeObjects::MethodObject) && resolved_obj.parent.is_a?(YARD::CodeObjects::ModuleObject)
          # Take module methods down to just the method name. This is a little
          # overzealous, but good enough. What we really want is complicated -
          # something like "if it would be included in the global namespace via
          # core, don't qualify it", which is hard to express here.
          title = resolved_obj.name.to_s
        else
          # Construct a path relative to the object we're working with.
          title = object.relative_path(resolved_obj).split("::").last
        end
      elsif resolved_obj.is_a?(YARD::CodeObjects::Proxy)
        title = resolved_obj.title
      end
    end

    __orig_link_object(obj, title, anchor, relative)
  end
end
