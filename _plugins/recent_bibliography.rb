# {% recent_bibliography CATEGORY %} lists the entries of one `category` from assets/ref.bib
# dated within the twelve months before the build (BibTeX field `ym` = year * 100 + month).
# The page only updates when the site is rebuilt.
require 'date'

module Jekyll
  class RecentBibliographyTag < Liquid::Tag
    def initialize(tag_name, markup, tokens)
      super
      @category = markup.strip
    end

    def render(context)
      start = context.registers[:site].time.to_date << 12
      cutoff = start.year * 100 + start.month
      Liquid::Template.parse("{% bibliography --query @*[category=#{@category} && ym>=#{cutoff}] %}").render!(context)
    end
  end
end

Liquid::Template.register_tag('recent_bibliography', Jekyll::RecentBibliographyTag)
