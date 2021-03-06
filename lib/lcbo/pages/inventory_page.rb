module LCBO
  class InventoryPage

    include CrawlKit::Page

    uri 'http://www.lcbo.com/lcbo-ear/lcbo/product/inventory/searchResults.do' \
        '?language=EN&itemNumber={product_no}'

    emits :product_no do
      query_params[:product_no].to_i
    end

    emits :inventory_count do
      inventories.reduce(0) { |sum, inv| sum + inv[:quantity] }
    end

    emits :inventories do
      # [updated_on, store_no, quantity]
      doc.css('table[cellpadding="3"] tr[bgcolor] > td[width="17%"] > a.item-details-col5').zip(
      doc.css('table[cellpadding="3"] tr[bgcolor] > td > a.item-details-col0'),
      doc.css('table[cellpadding="3"] tr[bgcolor] > td[width="13%"]')).map do |updated_on, store_no, quantity|
        {
          :updated_on => CrawlKit::FastDateHelper[updated_on.text.strip],
          :store_no => store_no["href"].match(/\?STORE=([0-9]{1,3})\&/)[1].to_i,
          :quantity => quantity.content.strip.to_i,
        }
      end
    end
  end
end
