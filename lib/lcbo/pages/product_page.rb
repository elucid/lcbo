module LCBO
  class ProductPage

    include CrawlKit::Page

    uri 'http://lcbo.com/lcbo-ear/lcbo/product/details.do?' \
        'language=EN&itemNumber={product_no}'

    on :before_parse, :verify_response_not_blank
    on :after_parse,  :verify_product_details_form
    on :after_parse,  :verify_product_name
    on :after_parse,  :verify_third_info_cell

    emits :product_no do
      query_params[:product_no].to_i
    end

    emits :name do
      CrawlKit::TitleCaseHelper[product_details_form('itemName')]
    end

    emits :price_in_cents do
      (product_details_form('price').to_f * 100).to_i
    end

    emits :regular_price_in_cents do
      if has_limited_time_offer
        info_cell_line_after('Was:').sub('$ ', '').to_f * 100
      else
        price_in_cents
      end
    end

    emits :limited_time_offer_savings_in_cents do
      regular_price_in_cents - price_in_cents
    end

    emits :limited_time_offer_ends_on do
      if has_limited_time_offer
        CrawlKit::FastDateHelper[info_cell_line_after('Until')]
      else
        nil
      end
    end

    emits :bonus_reward_miles do
      if has_bonus_reward_miles
        info_cell_line_after('Earn').to_i
      else
        0
      end
    end

    emits :bonus_reward_miles_ends_on do
      if has_bonus_reward_miles
        CrawlKit::FastDateHelper[info_cell_line_after('Until')]
      else
        nil
      end
    end

    emits :stock_type do
      product_details_form('stock type')
    end

    emits :primary_category do
      if stock_category
        cat = stock_category.split(',')[0]
        cat ? cat.strip : cat
      end
    end

    emits :secondary_category do
      if stock_category
        cat = stock_category.split(',')[1]
        cat ? cat.strip : cat
      end
    end

    emits :origin do
      match = find_info_line(/\AMade in: /)
      if match
        place = match.
          gsub('Made in: ', '').
          gsub('/Californie', '').
          gsub('Bosnia\'Hercegovina', 'Bosnia and Herzegovina').
          gsub('Is. Of', 'Island of').
          gsub('Italy Quality', 'Italy').
          gsub('Usa-', '').
          gsub(', Rep. Of', '').
          gsub('&', 'and')
        place.split(',').map { |s| s.strip }.uniq.join(', ')
      end
    end

    emits :package do
      @package ||= begin
        string = info_cell_lines[2]
        string.include?('Price: ') ? nil : string.sub('|','').strip
      end
    end

    emits :package_unit_type do
      volume_helper.unit_type
    end

    emits :package_unit_volume_in_milliliters do
      volume_helper.unit_volume
    end

    emits :total_package_units do
      volume_helper.total_units
    end

    emits :total_package_volume_in_milliliters do
      volume_helper.package_volume
    end

    emits :volume_in_milliliters do
      CrawlKit::VolumeHelper[package]
    end

    emits :alcohol_content do
      match = find_info_line(/ Alcohol\/Vol.\Z/)
      if match
        ac = match.gsub(/%| Alcohol\/Vol./, '').to_f
        ac.zero? ? nil : (ac * 100).to_i
      end
    end

    emits :sugar_content do
      match = match = find_info_line(/\ASugar Content : /)
      if match
        match.gsub('Sugar Content : ', '')
      end
    end

    emits :producer_name do
      match = find_info_line(/\ABy: /)
      if match
        CrawlKit::TitleCaseHelper[
          match.gsub(/By: |Tasting Note|Serving Suggestion|NOTE:/, '')
        ]
      end
    end

    emits :released_on do
      if html.include?('Release Date:')
        date = info_cell_line_after('Release Date:')
        date == 'N/A' ? nil : CrawlKit::FastDateHelper[date]
      else
        nil
      end
    end

    emits :is_discontinued do
      html.include?('PRODUCT DISCONTINUED')
    end

    emits :has_limited_time_offer do
      html.include?('<B>Limited Time Offer</B>')
    end

    emits :has_bonus_reward_miles do
      html.include?('<B>Bonus Reward Miles Offer</B>')
    end

    emits :is_seasonal do
      html.include?('<font color="#ff0000">SEASONAL/LIMITED QUANTITIES</font>')
    end

    emits :is_vqa do
      html.include?('This is a <B>VQA</B> wine')
    end

    emits :description do
      if html.include?('<B>Description</B>')
        match = html.match(/<B>Description<\/B><\/font><BR>\n\t\t\t(.*)<BR>\n\t\t\t<BR>/m)
        match ? match.captures[0] : nil
      else
        nil
      end
    end

    emits :serving_suggestion do
      if html.include?('<B>Serving Suggestion</B>')
        match = html.match(/<B>Serving Suggestion<\/B><\/font><BR>\n\t\t\t(.*)<BR><BR>/m)
        match ? match.captures[0] : nil
      else
        nil
      end
    end

    emits :tasting_note do
      if html.include?('<B>Tasting Note</B>')
        match = html.match(/<B>Tasting Note<\/B><\/font><BR>\n\t\t\t(.*)<BR>\n\t\t\t<BR>/m)
        match ? match.captures[0] : nil
      else
        nil
      end
    end

    def volume_helper
      @volume_helper ||= CrawlKit::VolumeHelper.new(package)
    end

    def has_package?
      !info_cell_lines[2].include?('Price:')
    end

    def stock_category
      cat = get_info_lines_at_offset(12).reject do |line|
        l = line.strip
        l == '' ||
        l.include?('Price:') ||
        l.include?('Bonus Reward Miles Offer') ||
        l.include?('Value Added Promotion') ||
        l.include?('Limited Time Offer') ||
        l.include?('NOTE:')
      end.first
      cat ? cat.strip : nil
    end

    def product_details_form(name)
      doc.css("form[name=\"productdetails\"] input[name=\"#{name}\"]")[0].
        attributes['value'].to_s
    end

    def get_info_lines_at_offset(offset)
      raw_info_cell_lines.select do |line|
        match = line.scan(/\A[\s]+/)[0]
        match ? offset == match.size : false
      end
    end

    def info_cell_text
      @info_cell_text ||= info_cell_lines.join("\n")
    end

    def find_info_line(regexp)
      info_cell_lines.select { |l| l =~ regexp }.first
    end

    def raw_info_cell_lines
      @raw_info_cell_lines ||= info_cell_element.content.split(/\n/)
    end

    def info_cell_lines
      @info_cell_lines ||= begin
        raw_info_cell_lines.map { |l| l.strip }.reject { |l| l == '' }
      end
    end

    def info_cell_line_after(item)
      i = info_cell_lines.index(item)
      return unless i
      info_cell_lines[i + 1]
    end

    def info_cell_html
      @info_cell_html ||= info_cell_element.inner_html
    end

    def info_cell_element
      doc.css('table[width="478"] td[height="271"] td[colspan="2"].main_font')[0]
    end

    def verify_third_info_cell
      return unless has_package? && info_cell_lines[2][0,1] != '|'
      raise CrawlKit::MalformedDocumentError,
        "Expected third line in info cell to begin with bar. LCBO No: " \
        "#{product_no}, Dump: #{info_cell_lines[2].inspect}"
    end

    def verify_response_not_blank
      return unless html.strip == ''
      raise CrawlKit::MissingResourceError,
        "product #{product_no} does not appear to exist"
    end

    def verify_product_name
      return unless product_details_form('itemName').strip == ''
      raise CrawlKit::MissingResourceError,
        "can not locate name for product #{product_no}"
    end

    def verify_product_details_form
      return unless doc.css('form[name="productdetails"]').empty?
      raise CrawlKit::MalformedDocumentError,
        "productdetails form not found in doc for product #{product_no}"
    end

  end
end
