# frozen_string_literal: true

require 'require_all'
require 'scraped'
require 'scraperwiki'
require 'active_support'
require 'active_support/core_ext/string'
require 'wikidata_ids_decorator'
require 'table_unspanner'
require 'wikisnakker'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

# require_rel 'lib'

def scrape(h)
  url, klass = h.to_a.first
  klass.new(response: Scraped::Request.new(url: url).response)
end

class MayorsListPage < Scraped::HTML
  decorator WikidataIdsDecorator::Links

  field :mayors do
    table.xpath('tr[td]').map do |tr|
      fragment(tr => Mayor)
    end
  end

  private

  def table
    @table ||= TableUnspanner::UnspannedTable.new(noko.at_xpath('.//table[1]')).nokogiri_node
  end
end

class Mayor < Scraped::HTML
  field :id do
    name.parameterize
  end

  field :name do
    name_text.tidy
  end

  field :party do
    noko.xpath('td[5]/a/@title|td[5]/text()').text.tidy
  end

  field :commune do
    noko.xpath('td[1]').text.tidy
  end

  field :commune_wikidata do
    noko.xpath('td[1]/a/@wikidata').text.tidy
  end

  private

  def name_text
    if noko.xpath('td[2]/a').any?
      noko.xpath('td[2]/a').text
    else
      noko.xpath('td[2]/text()').text
    end
  end
end

wikipedia_url = 'https://fr.wikipedia.org/wiki/Liste_des_maires_des_grandes_villes_fran%C3%A7aises'

page = scrape(wikipedia_url => MayorsListPage)

mayors = page.mayors.map(&:to_h)

wikidata_ids = mayors.map { |m| m[:commune_wikidata] }

# P374 is the INSEE municipality code in Wikidata
insee_code_lookup = Wikisnakker::Item.find(wikidata_ids).map { |i| [i.id, i.P374.to_s] }.to_h

mayors.each do |m|
  ScraperWiki.save_sqlite([:id], m.merge(insee_code: insee_code_lookup[m[:commune_wikidata]]))
end
