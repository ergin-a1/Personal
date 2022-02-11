{
  title: 'Google Ads',

  connection: {
    fields: [
      {
        name: 'client_id',
        hint: 'You can find your client ID by logging in to your ' \
          "<a href='https://console.developers.google.com/' " \
          "target='_blank'>Google Developers Console</a> account. " \
          "After logging in, click on 'Credentials' to show your " \
          'OAuth 2.0 client IDs. <br> Alternatively, you can create your ' \
          "Oauth 2.0 credentials by clicking on 'Create credentials' => " \
          "'Oauth client ID'. <br> Please use <b>https://www.workato.com/" \
          'oauth/callback</b> for the redirect URI when registering your ' \
          'OAuth client. <br> More information about authentication ' \
          "can be found <a href='https://developers.google.com/identity/" \
          "protocols/OAuth2?hl=en_US' target='_blank'>here</a>.",
        optional: false
      },
      {
        name: 'client_secret',
        hint: 'You can find your client secret by logging in to your ' \
          "<a href='https://console.developers.google.com/' " \
          "target='_blank'>Google Developers Console</a> account. " \
          "After logging in, click on 'Credentials' to show your " \
          'OAuth 2.0 client IDs and select your desired account name. ' \
          '<br> Alternatively, you can create your ' \
          "Oauth 2.0 credentials by clicking on 'Create credentials' => " \
          "'Oauth client ID'. <br> More information about authentication " \
          "can be found <a href='https://developers.google.com/identity/" \
          "protocols/OAuth2?hl=en_US' target='_blank'>here</a>.",
        optional: false,
        control_type: 'password'
      },
      {
        name: 'developer_token',
        control_type: 'password',
        optional: false,
        hint: 'The developer token generated when you signed up for ' \
          'AdWords API. You must have a Google Ads manager account to apply ' \
          'for access to the API. <br> Sign in ' \
          "<a href='https://ads.google.com/home/tools/manager-accounts/' " \
          "target='_blank'>here</a> then navigate to <b>TOOLS & " \
          'SETTINGS > SETUP > API Center</b>. The API Center option will ' \
          'appear only for Google Ads Manager Accounts. <br> ' \
          "Click <a href='https://support.google.com/google-ads/" \
          "answer/7459399' target='_blank'>here</a> for more information " \
          'on how to create your Google Ads manager account. <br> More ' \
          "information abour Developer tokens here <a href='https://" \
          "developers.google.com/adwords/api/docs/guides/signup' " \
          "target='_blank'>here</a>."
      },
      {
        name: 'manager_account_customer_id',
        hint: 'Customer ID of the target Google Ads manager account. ' \
          'It must be the customer ID for the manager account overseeing ' \
          'the underlying advertising accounts. <br> The manager account ' \
          "customer ID can be found <a href='https://ads.google.com/" \
          "aw/accountaccess/managers' target='_blank'>here</a>. <br> There " \
          'may be several manager accounts. It is advisable to pick the ' \
          'manager account linked to your team and the ID is a 10 digit ' \
          'string in the form XXXXXXXXXX.',
        optional: false
      },
      {
        name: 'api_version',
        optional: false,
        hint: 'Google Ads API version, e.g. <b>v8</b>'
      }
    ],

    authorization: {
      type: 'oauth2',

      authorization_url: lambda do |connection|
        'https://accounts.google.com/o/oauth2/auth?' \
        "client_id=#{connection['client_id']}" \
        '&scope=https://www.googleapis.com/auth/adwords' \
        '&response_type=code' \
        '&prompt=consent' \
        '&access_type=offline'
      end,

      acquire: lambda do |connection, auth_code, redirect_uri|
        response = post('https://accounts.google.com/o/oauth2/token').
                   payload(client_id: connection['client_id'],
                           client_secret: connection['client_secret'],
                           grant_type: 'authorization_code',
                           code: auth_code,
                           scope: 'https://www.googleapis.com/auth/adwords',
                           redirect_uri: redirect_uri).
                   request_format_www_form_urlencoded
        [response, nil, nil]
      end,
      refresh: lambda do |connection, refresh_token|
        post('https://accounts.google.com/o/oauth2/token').
          payload(client_id: connection['client_id'],
                  client_secret: connection['client_secret'],
                  scope: 'https://www.googleapis.com/auth/adwords',
                  grant_type: 'refresh_token',
                  refresh_token: refresh_token).
          request_format_www_form_urlencoded
      end,

      refresh_on: [401, 500],

      apply: lambda do |connection, access_token|
        case_sensitive_headers(Authorization: "Bearer #{access_token}",
                               'developer-token': connection['developer_token'],
                               'login-customer-id': connection['manager_account_customer_id'])
      end
    },
    base_uri: lambda do |connection|
      "https://googleads.googleapis.com/#{connection['api_version']}/"
    end
  },

  test: lambda do |connection|
    get("customers/#{connection['manager_account_customer_id']}")
  end,

  methods: {
    make_schema_builder_fields_sticky: lambda do |schema|
      schema.map do |field|
        if field['properties'].present?
          field['properties'] = call('make_schema_builder_fields_sticky',
                                     field['properties'])
        end
        field['sticky'] = true

        field
      end
    end,
    format_schema: lambda do |input|
      input&.map do |field|
        if (props = field[:properties])
          field[:properties] = call('format_schema', props)
        elsif (props = field['properties'])
          field['properties'] = call('format_schema', props)
        end
        if (name = field[:name])
          field[:label] = field[:label].presence || name.labelize
          field[:name] = name.gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        elsif (name = field['name'])
          field['label'] = field['label'].presence || name.labelize
          field['name'] = name.gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        end

        field
      end
    end,
    format_payload: lambda do |payload|
      if payload.is_a?(Array)
        payload.map do |array_value|
          call('format_payload', array_value)
        end
      elsif payload.is_a?(Hash)
        payload.each_with_object({}) do |(key, value), hash|
          key = key.gsub(/__[0-9a-fA-F]+__/) do |string|
            string.gsub(/__/, '').decode_hex.as_utf8
          end
          value = call('format_payload', value) if value.is_a?(Array) || value.is_a?(Hash)
          hash[key] = value
        end
      end
    end,
    format_response: lambda do |response|
      response = response&.compact unless response.is_a?(String) || response
      if response.is_a?(Array)
        response.map do |array_value|
          call('format_response', array_value)
        end
      elsif response.is_a?(Hash)
        response.each_with_object({}) do |(key, value), hash|
          key = key.gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
          if value.is_a?(Array) || value.is_a?(Hash)
            value = call('format_response', value)
          end
          hash[key] = value
        end
      else
        response
      end
    end,

    build_query: lambda do |input|
      fields = case input['object_name']
               when 'campaign'
                 %w[campaign.accessible_bidding_strategy
                    campaign.ad_serving_optimization_status
                    campaign.advertising_channel_sub_type
                    campaign.advertising_channel_type
                    campaign.app_campaign_setting.app_id
                    campaign.app_campaign_setting.app_store
                    campaign.app_campaign_setting.bidding_strategy_goal_type
                    campaign.base_campaign
                    campaign.bidding_strategy
                    campaign.bidding_strategy_type
                    campaign.campaign_budget
                    campaign.commission.commission_rate_micros
                    campaign.dynamic_search_ads_setting.domain_name
                    campaign.dynamic_search_ads_setting.feeds
                    campaign.dynamic_search_ads_setting.language_code
                    campaign.dynamic_search_ads_setting.use_supplied_urls_only
                    campaign.end_date
                    campaign.excluded_parent_asset_field_types
                    campaign.experiment_type
                    campaign.final_url_suffix
                    campaign.frequency_caps
                    campaign.geo_target_type_setting.negative_geo_target_type
                    campaign.geo_target_type_setting.positive_geo_target_type
                    campaign.hotel_setting.hotel_center_id
                    campaign.id
                    campaign.labels
                    campaign.local_campaign_setting.location_source_type
                    campaign.manual_cpc.enhanced_cpc_enabled
                    campaign.manual_cpm
                    campaign.manual_cpv
                    campaign.maximize_conversion_value.target_roas
                    campaign.maximize_conversions.target_cpa
                    campaign.name
                    campaign.network_settings.target_content_network
                    campaign.network_settings.target_google_search
                    campaign.network_settings.target_partner_search_network
                    campaign.network_settings.target_search_network
                    campaign.optimization_goal_setting.optimization_goal_types
                    campaign.optimization_score
                    campaign.payment_mode
                    campaign.percent_cpc.cpc_bid_ceiling_micros
                    campaign.percent_cpc.enhanced_cpc_enabled
                    campaign.real_time_bidding_setting.opt_in
                    campaign.resource_name
                    campaign.selective_optimization.conversion_actions
                    campaign.serving_status
                    campaign.shopping_setting.campaign_priority
                    campaign.shopping_setting.enable_local
                    campaign.shopping_setting.merchant_id
                    campaign.shopping_setting.sales_country
                    campaign.start_date
                    campaign.status
                    campaign.target_cpa.cpc_bid_ceiling_micros
                    campaign.target_cpa.cpc_bid_floor_micros
                    campaign.target_cpa.target_cpa_micros
                    campaign.target_cpm
                    campaign.target_impression_share.cpc_bid_ceiling_micros
                    campaign.target_impression_share.location
                    campaign.target_impression_share.location_fraction_micros
                    campaign.target_roas.cpc_bid_ceiling_micros
                    campaign.target_roas.cpc_bid_floor_micros
                    campaign.target_roas.target_roas
                    campaign.target_spend.cpc_bid_ceiling_micros
                    campaign.target_spend.target_spend_micros
                    campaign.targeting_setting.target_restrictions
                    campaign.tracking_setting.tracking_url
                    campaign.tracking_url_template
                    campaign.url_custom_parameters
                    campaign.vanity_pharma.vanity_pharma_display_url_mode
                    campaign.vanity_pharma.vanity_pharma_text
                    campaign.video_brand_safety_suitability]
               when 'customer_client'
                 %w[customer_client.applied_labels
                    customer_client.client_customer
                    customer_client.currency_code
                    customer_client.descriptive_name
                    customer_client.hidden
                    customer_client.id
                    customer_client.level
                    customer_client.manager
                    customer_client.resource_name
                    customer_client.test_account
                    customer_client.time_zone]
               when 'user_list'
                 %w[user_list.access_reason
                    user_list.account_user_list_status
                    user_list.type
                    user_list.size_range_for_search
                    user_list.size_range_for_display
                    user_list.size_for_search
                    user_list.size_for_display
                    user_list.similar_user_list.seed_user_list
                    user_list.rule_based_user_list.prepopulation_status
                    user_list.rule_based_user_list.expression_rule_user_list.rule.rule_type
                    user_list.rule_based_user_list.expression_rule_user_list.rule.rule_item_groups
                    user_list.rule_based_user_list.date_specific_rule_user_list.start_date
                    user_list.rule_based_user_list.date_specific_rule_user_list.rule.rule_type
                    user_list.rule_based_user_list.date_specific_rule_user_list.rule.rule_item_groups
                    user_list.rule_based_user_list.date_specific_rule_user_list.end_date
                    user_list.rule_based_user_list.combined_rule_user_list.rule_operator
                    user_list.rule_based_user_list.combined_rule_user_list.right_operand.rule_type
                    user_list.rule_based_user_list.combined_rule_user_list.right_operand.rule_item_groups
                    user_list.rule_based_user_list.combined_rule_user_list.left_operand.rule_type
                    user_list.rule_based_user_list.combined_rule_user_list.left_operand.rule_item_groups
                    user_list.resource_name
                    user_list.read_only
                    user_list.name
                    user_list.membership_status
                    user_list.membership_life_span
                    user_list.match_rate_percentage
                    user_list.logical_user_list.rules
                    user_list.integration_code
                    user_list.id
                    user_list.eligible_for_search
                    user_list.eligible_for_display
                    user_list.description
                    user_list.basic_user_list.actions
                    user_list.closing_reason
                    user_list.crm_based_user_list.app_id
                    user_list.crm_based_user_list.data_source_type
                    user_list.crm_based_user_list.upload_key_type]
               when 'ad_group'
                 %w[ad_group.ad_rotation_mode
                    ad_group.base_ad_group
                    ad_group.campaign
                    ad_group.cpc_bid_micros
                    ad_group.cpm_bid_micros
                    ad_group.cpv_bid_micros
                    ad_group.display_custom_bid_dimension
                    ad_group.effective_target_cpa_micros
                    ad_group.effective_target_cpa_source
                    ad_group.effective_target_roas
                    ad_group.effective_target_roas_source
                    ad_group.excluded_parent_asset_field_types
                    ad_group.explorer_auto_optimizer_setting.opt_in
                    ad_group.final_url_suffix
                    ad_group.id
                    ad_group.labels
                    ad_group.name
                    ad_group.percent_cpc_bid_micros
                    ad_group.resource_name
                    ad_group.status
                    ad_group.target_cpa_micros
                    ad_group.target_cpm_micros
                    ad_group.target_roas
                    ad_group.targeting_setting.target_restrictions
                    ad_group.tracking_url_template
                    ad_group.type
                    ad_group.url_custom_parameters]
               when 'ad_group_ad'
                 %w[ad_group_ad.action_items
                    ad_group_ad.ad.added_by_google_ads
                    ad_group_ad.ad.app_ad.descriptions
                    ad_group_ad.ad.app_ad.headlines
                    ad_group_ad.ad.app_ad.html5_media_bundles
                    ad_group_ad.ad.app_ad.images
                    ad_group_ad.ad.app_ad.mandatory_ad_text
                    ad_group_ad.ad.app_ad.youtube_videos
                    ad_group_ad.ad.app_engagement_ad.descriptions
                    ad_group_ad.ad.app_engagement_ad.headlines
                    ad_group_ad.ad.app_engagement_ad.images
                    ad_group_ad.ad.app_engagement_ad.videos
                    ad_group_ad.ad.app_pre_registration_ad.descriptions
                    ad_group_ad.ad.app_pre_registration_ad.headlines
                    ad_group_ad.ad.app_pre_registration_ad.images
                    ad_group_ad.ad.app_pre_registration_ad.youtube_videos
                    ad_group_ad.ad.call_ad.business_name
                    ad_group_ad.ad.call_ad.call_tracked
                    ad_group_ad.ad.call_ad.conversion_action
                    ad_group_ad.ad.call_ad.conversion_reporting_state
                    ad_group_ad.ad.call_ad.country_code
                    ad_group_ad.ad.call_ad.description1
                    ad_group_ad.ad.call_ad.description2
                    ad_group_ad.ad.call_ad.disable_call_conversion
                    ad_group_ad.ad.call_ad.headline1
                    ad_group_ad.ad.call_ad.headline2
                    ad_group_ad.ad.call_ad.path1
                    ad_group_ad.ad.call_ad.path2
                    ad_group_ad.ad.call_ad.phone_number
                    ad_group_ad.ad.call_ad.phone_number_verification_url
                    ad_group_ad.ad.device_preference
                    ad_group_ad.ad.display_upload_ad.display_upload_product_type
                    ad_group_ad.ad.display_upload_ad.media_bundle
                    ad_group_ad.ad.display_url
                    ad_group_ad.ad.expanded_dynamic_search_ad.description
                    ad_group_ad.ad.expanded_dynamic_search_ad.description2
                    ad_group_ad.ad.expanded_text_ad.description
                    ad_group_ad.ad.expanded_text_ad.description2
                    ad_group_ad.ad.expanded_text_ad.headline_part1
                    ad_group_ad.ad.expanded_text_ad.headline_part2
                    ad_group_ad.ad.expanded_text_ad.headline_part3
                    ad_group_ad.ad.expanded_text_ad.path1
                    ad_group_ad.ad.expanded_text_ad.path2
                    ad_group_ad.ad.final_app_urls
                    ad_group_ad.ad.final_mobile_urls
                    ad_group_ad.ad.final_url_suffix
                    ad_group_ad.ad.final_urls
                    ad_group_ad.ad.gmail_ad.header_image
                    ad_group_ad.ad.gmail_ad.marketing_image
                    ad_group_ad.ad.gmail_ad.marketing_image_description
                    ad_group_ad.ad.gmail_ad.marketing_image_display_call_to_action.text
                    ad_group_ad.ad.gmail_ad.marketing_image_display_call_to_action.text_color
                    ad_group_ad.ad.gmail_ad.marketing_image_display_call_to_action.url_collection_id
                    ad_group_ad.ad.gmail_ad.marketing_image_headline
                    ad_group_ad.ad.gmail_ad.product_images
                    ad_group_ad.ad.gmail_ad.product_videos
                    ad_group_ad.ad.gmail_ad.teaser.business_name
                    ad_group_ad.ad.gmail_ad.teaser.description
                    ad_group_ad.ad.gmail_ad.teaser.headline
                    ad_group_ad.ad.gmail_ad.teaser.logo_image
                    ad_group_ad.ad.hotel_ad
                    ad_group_ad.ad.id
                    ad_group_ad.ad.image_ad.image_url
                    ad_group_ad.ad.image_ad.mime_type
                    ad_group_ad.ad.image_ad.name
                    ad_group_ad.ad.image_ad.pixel_height
                    ad_group_ad.ad.image_ad.pixel_width
                    ad_group_ad.ad.image_ad.preview_image_url
                    ad_group_ad.ad.image_ad.preview_pixel_height
                    ad_group_ad.ad.image_ad.preview_pixel_width
                    ad_group_ad.ad.legacy_app_install_ad
                    ad_group_ad.ad.legacy_responsive_display_ad.accent_color
                    ad_group_ad.ad.legacy_responsive_display_ad.allow_flexible_color
                    ad_group_ad.ad.legacy_responsive_display_ad.business_name
                    ad_group_ad.ad.legacy_responsive_display_ad.call_to_action_text
                    ad_group_ad.ad.legacy_responsive_display_ad.description
                    ad_group_ad.ad.legacy_responsive_display_ad.format_setting
                    ad_group_ad.ad.legacy_responsive_display_ad.logo_image
                    ad_group_ad.ad.legacy_responsive_display_ad.long_headline
                    ad_group_ad.ad.legacy_responsive_display_ad.main_color
                    ad_group_ad.ad.legacy_responsive_display_ad.marketing_image
                    ad_group_ad.ad.legacy_responsive_display_ad.price_prefix
                    ad_group_ad.ad.legacy_responsive_display_ad.promo_text
                    ad_group_ad.ad.legacy_responsive_display_ad.short_headline
                    ad_group_ad.ad.legacy_responsive_display_ad.square_logo_image
                    ad_group_ad.ad.legacy_responsive_display_ad.square_marketing_image
                    ad_group_ad.ad.local_ad.call_to_actions
                    ad_group_ad.ad.local_ad.descriptions
                    ad_group_ad.ad.local_ad.headlines
                    ad_group_ad.ad.local_ad.logo_images
                    ad_group_ad.ad.local_ad.marketing_images
                    ad_group_ad.ad.local_ad.path1
                    ad_group_ad.ad.local_ad.path2
                    ad_group_ad.ad.local_ad.videos
                    ad_group_ad.ad.name
                    ad_group_ad.ad.resource_name
                    ad_group_ad.ad.responsive_display_ad.accent_color
                    ad_group_ad.ad.responsive_display_ad.allow_flexible_color
                    ad_group_ad.ad.responsive_display_ad.business_name
                    ad_group_ad.ad.responsive_display_ad.call_to_action_text
                    ad_group_ad.ad.responsive_display_ad.control_spec.enable_asset_enhancements
                    ad_group_ad.ad.responsive_display_ad.control_spec.enable_autogen_video
                    ad_group_ad.ad.responsive_display_ad.descriptions
                    ad_group_ad.ad.responsive_display_ad.format_setting
                    ad_group_ad.ad.responsive_display_ad.headlines
                    ad_group_ad.ad.responsive_display_ad.logo_images
                    ad_group_ad.ad.responsive_display_ad.long_headline
                    ad_group_ad.ad.responsive_display_ad.main_color
                    ad_group_ad.ad.responsive_display_ad.marketing_images
                    ad_group_ad.ad.responsive_display_ad.price_prefix
                    ad_group_ad.ad.responsive_display_ad.promo_text
                    ad_group_ad.ad.responsive_display_ad.square_logo_images
                    ad_group_ad.ad.responsive_display_ad.square_marketing_images
                    ad_group_ad.ad.responsive_display_ad.youtube_videos
                    ad_group_ad.ad.responsive_search_ad.descriptions
                    ad_group_ad.ad.responsive_search_ad.headlines
                    ad_group_ad.ad.responsive_search_ad.path1
                    ad_group_ad.ad.responsive_search_ad.path2
                    ad_group_ad.ad.shopping_comparison_listing_ad.headline
                    ad_group_ad.ad.shopping_product_ad
                    ad_group_ad.ad.shopping_smart_ad
                    ad_group_ad.ad.smart_campaign_ad.descriptions
                    ad_group_ad.ad.smart_campaign_ad.headlines
                    ad_group_ad.ad.system_managed_resource_source
                    ad_group_ad.ad.text_ad.description1
                    ad_group_ad.ad.text_ad.description2
                    ad_group_ad.ad.text_ad.headline
                    ad_group_ad.ad.tracking_url_template
                    ad_group_ad.ad.type
                    ad_group_ad.ad.url_collections
                    ad_group_ad.ad.url_custom_parameters
                    ad_group_ad.ad.video_ad.bumper.companion_banner.asset
                    ad_group_ad.ad.video_ad.discovery.description1
                    ad_group_ad.ad.video_ad.discovery.description2
                    ad_group_ad.ad.video_ad.discovery.headline
                    ad_group_ad.ad.video_ad.discovery.thumbnail
                    ad_group_ad.ad.video_ad.in_stream.action_button_label
                    ad_group_ad.ad.video_ad.in_stream.action_headline
                    ad_group_ad.ad.video_ad.in_stream.companion_banner.asset
                    ad_group_ad.ad.video_ad.non_skippable.action_button_label
                    ad_group_ad.ad.video_ad.non_skippable.action_headline
                    ad_group_ad.ad.video_ad.non_skippable.companion_banner.asset
                    ad_group_ad.ad.video_ad.out_stream.description
                    ad_group_ad.ad.video_ad.out_stream.headline
                    ad_group_ad.ad.video_ad.video.asset
                    ad_group_ad.ad.video_responsive_ad.call_to_actions
                    ad_group_ad.ad.video_responsive_ad.companion_banners
                    ad_group_ad.ad.video_responsive_ad.descriptions
                    ad_group_ad.ad.video_responsive_ad.headlines
                    ad_group_ad.ad.video_responsive_ad.long_headlines
                    ad_group_ad.ad.video_responsive_ad.videos
                    ad_group_ad.ad_group
                    ad_group_ad.ad_strength
                    ad_group_ad.labels
                    ad_group_ad.policy_summary.approval_status
                    ad_group_ad.policy_summary.policy_topic_entries
                    ad_group_ad.policy_summary.review_status
                    ad_group_ad.resource_name
                    ad_group_ad.status]
               end

      id = if input['object_name'] == 'ad_group_ad'
             'ad_group_ad.ad.id'
           else
             "#{input['object_name']}.id"
           end
      query_fields = input&.[]('fields') || fields.smart_join(',')
      ordering_field = input&.dig('ordering', 'sort_field') || id
      sort_order = input&.dig('ordering', 'sort_order') || 'ASC'

      query =
        if input['filter'].present?
          "SELECT #{query_fields}
          FROM #{input['object_name']}
          WHERE #{input['filter']}
          ORDER BY #{ordering_field} #{sort_order}"
        else
          "SELECT #{query_fields}
          FROM #{input['object_name']}
          ORDER BY #{ordering_field} #{sort_order}"
        end
      query
    end,
    build_report_query: lambda do |input|
      date_range =
        if input['date_range_type'] == 'CUSTOM_DATE'
          min_date = input&.dig('date_range', 'min')
          max_date = input&.dig('date_range', 'max')

          min_date_formatted = if min_date.present?
                                 min_date.to_date.strftime('%Y-%m-%d')
                               else
                                 '1970-01-01'
                               end
          max_date_formatted = if max_date.present?
                                 max_date.to_date.strftime('%Y-%m-%d')
                               else
                                 today.to_date.strftime('%Y-%m-%d')
                               end

          "segments.date BETWEEN '#{min_date_formatted}' AND '#{max_date_formatted}'"
        elsif input['date_range_type'].present?
          "segments.date DURING #{input['date_range_type']}"
        end
      query_fields = input&.[]('fields')
      ordering_field = input&.dig('ordering', 'sort_field').presence
      sort_order = input&.dig('ordering', 'sort_order').presence

      filter = [input['filter'], date_range].smart_join(' AND ')
      query = {
        'SELECT' => query_fields,
        'FROM' => input['report_type'],
        'WHERE' => filter,
        'ORDER_BY' => "#{ordering_field} #{sort_order}".presence
      }.compact

      query.map do |key, value|
        "#{key.split('_').smart_join(' ')} #{value}"
      end.smart_join("\n")
    end,
    mutate_endpoint: lambda do |input|
      case input['object_name']
      when 'campaign'
        "customers/#{input['client_customer_id']}/campaigns:mutate"
      when 'user_list'
        "customers/#{input['client_customer_id']}/userLists:mutate"
      end
    end,
    generate_update_mask: lambda do |input|
      input.map do |key, value|
        if value.is_a?(Hash)
          "#{key}.#{call('generate_update_mask', value)}"
        else
          key
        end
      end.smart_join(',')
    end
  },

  object_definitions: {
    custom_action_input: {
      fields: lambda do |connection, config_fields|
        verb = config_fields['verb']
        input_schema = parse_json(config_fields.dig('input', 'schema') || '[]')
        data_props =
          input_schema.map do |field|
            if config_fields['request_type'] == 'multipart' &&
               field['binary_content'] == 'true'
              field['type'] = 'object'
              field['properties'] = [
                { name: 'file_content', optional: false },
                {
                  name: 'content_type',
                  default: 'text/plain',
                  sticky: true
                },
                { name: 'original_filename', sticky: true }
              ]
            end
            field
          end
        data_props = call('make_schema_builder_fields_sticky', data_props)
        input_data =
          if input_schema.present?
            if input_schema.dig(0, 'type') == 'array' &&
               input_schema.dig(0, 'details', 'fake_array')
              {
                name: 'data',
                type: 'array',
                of: 'object',
                properties: data_props.dig(0, 'properties')
              }
            else
              { name: 'data', type: 'object', properties: data_props }
            end
          end

        [
          {
            name: 'path',
            hint: 'Base URI is <b>' \
            "https://googleads.googleapis.com/#{connection['api_version']}/" \
            '</b> - path will be appended to this URI. Use absolute URI to ' \
            'override this base URI.',
            optional: false
          },
          if %w[post put patch].include?(verb)
            {
              name: 'request_type',
              default: 'json',
              sticky: true,
              extends_schema: true,
              control_type: 'select',
              pick_list: [
                ['JSON request body', 'json'],
                ['URL encoded form', 'url_encoded_form'],
                ['Mutipart form', 'multipart'],
                ['Raw request body', 'raw']
              ]
            }
          end,
          {
            name: 'response_type',
            default: 'json',
            sticky: false,
            extends_schema: true,
            control_type: 'select',
            pick_list: [['JSON response', 'json'], ['Raw response', 'raw']]
          },
          if %w[get options delete].include?(verb)
            {
              name: 'input',
              label: 'Request URL parameters',
              sticky: true,
              add_field_label: 'Add URL parameter',
              control_type: 'form-schema-builder',
              type: 'object',
              properties: [
                {
                  name: 'schema',
                  sticky: input_schema.blank?,
                  extends_schema: true
                },
                input_data
              ].compact
            }
          else
            {
              name: 'input',
              label: 'Request body parameters',
              sticky: true,
              type: 'object',
              properties:
                if config_fields['request_type'] == 'raw'
                  [{
                    name: 'data',
                    sticky: true,
                    control_type: 'text-area',
                    type: 'string'
                  }]
                else
                  [
                    {
                      name: 'schema',
                      sticky: input_schema.blank?,
                      extends_schema: true,
                      schema_neutral: true,
                      control_type: 'schema-designer',
                      sample_data_type: 'json_input',
                      custom_properties:
                        if config_fields['request_type'] == 'multipart'
                          [{
                            name: 'binary_content',
                            label: 'File attachment',
                            default: false,
                            optional: true,
                            sticky: true,
                            render_input: 'boolean_conversion',
                            parse_output: 'boolean_conversion',
                            control_type: 'checkbox',
                            type: 'boolean'
                          }]
                        end
                    },
                    input_data
                  ].compact
                end
            }
          end,
          {
            name: 'request_headers',
            sticky: false,
            extends_schema: true,
            control_type: 'key_value',
            empty_list_title: 'Does this HTTP request require headers?',
            empty_list_text: 'Refer to the API documentation and add ' \
            'required headers to this HTTP request',
            item_label: 'Header',
            type: 'array',
            of: 'object',
            properties: [{ name: 'key' }, { name: 'value' }]
          },
          unless config_fields['response_type'] == 'raw'
            {
              name: 'output',
              label: 'Response body',
              sticky: true,
              extends_schema: true,
              schema_neutral: true,
              control_type: 'schema-designer',
              sample_data_type: 'json_input'
            }
          end,
          {
            name: 'response_headers',
            sticky: false,
            extends_schema: true,
            schema_neutral: true,
            control_type: 'schema-designer',
            sample_data_type: 'json_input'
          }
        ].compact
      end
    },
    custom_action_output: {
      fields: lambda do |_connection, config_fields|
        response_body = { name: 'body' }

        [
          if config_fields['response_type'] == 'raw'
            response_body
          elsif (output = config_fields['output'])
            output_schema = call('format_schema', parse_json(output))
            if output_schema.dig(0, 'type') == 'array' &&
               output_schema.dig(0, 'details', 'fake_array')
              response_body[:type] = 'array'
              response_body[:properties] = output_schema.dig(0, 'properties')
            else
              response_body[:type] = 'object'
              response_body[:properties] = output_schema
            end

            response_body
          end,
          if (headers = config_fields['response_headers'])
            header_props = parse_json(headers)&.map do |field|
              if field[:name].present?
                field[:name] = field[:name].gsub(/\W/, '_').downcase
              elsif field['name'].present?
                field['name'] = field['name'].gsub(/\W/, '_').downcase
              end
              field
            end

            { name: 'headers', type: 'object', properties: header_props }
          end
        ].compact
      end
    },

    retrieve_report_input: {
      fields: lambda do |_connection, config_fields|
        fields = config_fields['report_type'].present? ? "#{config_fields['report_type']}_report_fields" : []
        report_with_date = %w[
          customer ad_group ad_group_ad
          age_range_view campaign_audience_view ad_group_audience_view
          group_placement_view bidding_strategy call_view ad_schedule_view
          location_view campaign video display_keyword_view
          topic_view gender_view geographic_view user_location_view
          dynamic_search_ads_search_term_view
          keyword_view landing_page_view expanded_landing_page_view
          paid_organic_search_term_view parental_status_view feed_item_target feed_item
          feed_placeholder_view managed_placement_view product_group_view search_term_view
          shopping_performance_view detail_placement_view distance_view
        ]
        [
          {
            name: 'client_customer_id',
            hint: 'Customer ID of the target Google Ads account, typically ' \
              'in the form of "1234567890". <b>It must be the advertising ' \
              'account being managed by your manager account.</b>',
            optional: false
          },
          {
            name: 'report_type', optional: false, control_type: 'select',
            pick_list: 'report_types', extends_schema: true,
            hint: 'The report type to retrieve.',
            toggle_hint: 'Select report type',
            toggle_field: {
              name: 'report_type', label: 'Report type', type: 'string',
              control_type: 'text',
              toggle_hint: 'Use custom value',
              hint: 'Enter corresponding report name in Google Ads. Click <a href=' \
                "'https://developers.google.com/google-ads/api/docs/migration/mapping'" \
                " target='_blank'>here</a> for the report mappings."
            }
          },
          if report_with_date.include?(config_fields['report_type'])
            {
              name: 'date_range_type', optional: false, control_type: 'select',
              pick_list: 'date_range_types', extends_schema: true,
              hint: 'Pick the predefined date ranges that data should be ' \
              'included in the report.'
            }
          elsif config_fields['report_type'] == 'CLICK_PERFORMANCE_REPORT'
            {
              name: 'date_range_type', optional: false, control_type: 'select',
              pick_list: [
                %w[Today TODAY],
                %w[Yesterday YESTERDAY],
                %w[Custom\ date CUSTOM_DATE]
              ],
              extends_schema: true,
              hint: 'Pick the predefined date ranges that data should be ' \
              'included in the report.'
            }
          end,
          if config_fields['date_range_type'] == 'CUSTOM_DATE'
            {
              name: 'date_range', sticky: true, optional: true, type: :object,
              hint: 'The custom date range to retrieve the report.',
              properties: [
                {
                  name: 'min', label: 'Minimum date', optional: true,
                  sticky: true, type: 'date', control_type: 'date',
                  hint: 'The latest date in the date range to retrieve the ' \
                  'report. Not specifying this field returns ' \
                  '<b>Start of UTC time</b> by default.'
                },
                {
                  name: 'max', label: 'Maximum date', optional: true,
                  sticky: true, type: 'date', control_type: 'date',
                  hint: 'The earliest date in the date range to retrieve the ' \
                    'report. Not specifying this field returns ' \
                    '<b>Today</b> by default.'
                }
              ]
            }
          end,
          {
            name: 'fields',
            control_type: 'multiselect',
            delimiter: ',',
            optional: false,
            pick_list: fields,
            toggle_hint: 'Select from options',
            hint: 'The list of fields to include in the result. All fields will be returned by default.',
            toggle_field: {
              name: 'fields',
              label: 'Field names',
              type: 'string',
              control_type: 'text',
              optional: false,
              toggle_hint: 'Use custom value',
              hint: 'Enter field names separated by comma. Click <a href=' \
              "'https://developers.google.com/google-ads/api/fields/v8/#{config_fields['object_name']}_query_builder' " \
              "target='_blank'>here</a> for more details about the selectable fields (under SELECT clause)."
            }
          },
          {
            name: 'filter',
            label: 'Query filter',
            sticky: true,
            hint: 'Enter a query filter (<b>WHERE clause</b>) using <a href=' \
            "'https://developers.google.com/google-ads/api/docs/query/grammar?hl=en' " \
            "target='_blank'>Google Ads Query Language</a>.<br>" \
            "e.g. <b>campaign.status = 'PAUSED'</b> or <b>segments.date DURING LAST_30_DAYS</b><br>" \
            "Click <a href='https://developers.google.com/google-ads/api/fields/v8/#{config_fields['object_name']}_query_builder' " \
            "target='_blank'>here</a> for more details about the filterable fields and supported operators (under WHERE clause)."
          },
          {
            name: 'ordering', sticky: true, type: 'object', properties: [
              {
                name: 'sort_field',
                sticky: true,
                hint: 'Enter field name. Click <a href=' \
                "'https://developers.google.com/google-ads/api/fields/v8/#{config_fields['object_name']}_query_builder' " \
                "target='_blank'>here</a> for more details about the sortable fields (under ORDER BY clause)."
              },
              { name: 'sort_order',
                sticky: true,
                control_type: 'select',
                hint: 'The order to sort the results on.',
                pick_list: 'sort_order',
                toggle_hint: 'Select from options',
                toggle_field: {
                  name: 'sort_order',
                  label: 'Sort order',
                  type: 'string',
                  optional: true,
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: DESC, ASC'
                } }
            ]
          },
          {
            name: 'page_token',
            label: 'Page token',
            sticky: true,
            hint: 'Token of the page to retrieve. If not specified, the first page of results will be returned. ' \
            'Use the value obtained from <b>Next page token</b> in the previous response in order to ' \
            'request the next page of results.'
          },
          {
            name: 'page_size',
            label: 'Page size',
            sticky: true,
            type: 'integer',
            control_type: 'integer',
            default: '100',
            hint: 'Maximum number of results to return in this page. ' \
            'Set this to a reasonable value to limit the number of results returned per page.<br>' \
            'The default value is 100.'
          }
        ].compact
      end
    },
    get_object_input: {
      fields: lambda do |_connection, _input|
        [
          {
            name: 'client_customer_id',
            hint: 'Customer ID of the target Google Ads account, typically ' \
              'in the form of "1234567890". <b>It must be the advertising ' \
              'account being managed by your manager account.</b>',
            optional: false
          },
          {
            name: 'id', label: 'Campaign ID', optional: false
          }
        ]
      end
    },
    get_object_output: {
      fields: lambda do |_connection, config_fields, object_definitions|
        object_definitions[config_fields['object_name']]
      end
    },
    search_object_input: {
      fields: lambda do |_connection, config_fields|
        fields = config_fields['object_name'].present? ? "#{config_fields['object_name']}_fields" : []
        [
          {
            name: 'client_customer_id',
            hint: 'Customer ID of the target Google Ads account, typically ' \
              'in the form of "1234567890". <b>It must be the advertising ' \
              'account being managed by your manager account.</b>',
            optional: false
          },
          {
            name: 'fields',
            control_type: 'multiselect',
            delimiter: ',',
            sticky: true,
            pick_list: fields,
            toggle_hint: 'Select from options',
            hint: 'The list of fields to include in the result. All fields will be returned by default.',
            toggle_field: {
              name: 'fields',
              label: 'Field names',
              type: 'string',
              control_type: 'text',
              optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Enter field names separated by comma. Click <a href=' \
              "'https://developers.google.com/google-ads/api/fields/v8/#{config_fields['object_name']}_query_builder' " \
              "target='_blank'>here</a> for more details about the selectable fields (under SELECT clause)."
            }
          },
          {
            name: 'filter',
            label: 'Query filter',
            sticky: true,
            hint: 'Enter a query filter (<b>WHERE clause</b>) using <a href=' \
            "'https://developers.google.com/google-ads/api/docs/query/grammar?hl=en' " \
            "target='_blank'>Google Ads Query Language</a>.<br>" \
            "e.g. <b>campaign.status = 'PAUSED'</b> or <b>segments.date DURING LAST_30_DAYS</b><br>" \
            "Click <a href='https://developers.google.com/google-ads/api/fields/v8/#{config_fields['object_name']}_query_builder' " \
            "target='_blank'>here</a> for more details about the filterable fields and supported operators (under WHERE clause)."
          },
          {
            name: 'ordering', sticky: true, type: 'object', properties: [
              {
                name: 'sort_field',
                sticky: true,
                hint: 'Enter field name. Click <a href=' \
                "'https://developers.google.com/google-ads/api/fields/v8/#{config_fields['object_name']}_query_builder' " \
                "target='_blank'>here</a> for more details about the sortable fields (under ORDER BY clause). " \
                'e.g. <b>campaign.id</b>'
              },
              { name: 'sort_order',
                sticky: true,
                control_type: 'select',
                hint: 'The order to sort the results on.',
                pick_list: 'sort_order',
                toggle_hint: 'Select from options',
                toggle_field: {
                  name: 'sort_order',
                  label: 'Sort order',
                  type: 'string',
                  optional: true,
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: DESC, ASC'
                } }
            ]
          },
          {
            name: 'page_token',
            label: 'Page token',
            hint: 'Token of the page to retrieve. If not specified, the first page of results will be returned. ' \
            'Use the value obtained from <b>Next page token</b> in the previous response in order to ' \
            'request the next page of results.'
          },
          {
            name: 'page_size',
            label: 'Page size',
            type: 'integer',
            control_type: 'integer',
            default: '100',
            hint: 'Maximum number of results to return in this page. ' \
            'Set this to a reasonable value to limit the number of results returned per page.<br>' \
            'The default value is 100.'
          }
        ]
      end
    },
    search_object_output: {
      fields: lambda do |_connection, config_fields, object_definitions|
        [
          { name: 'results', label: config_fields['object_name'].pluralize.labelize, type: 'array', of: 'object',
            properties: object_definitions[config_fields['object_name']] || [] },
          { name: 'nextPageToken' },
          { name: 'totalResultsCount', type: 'integer' },
          { name: 'fieldMask' }
        ]
      end
    },
    new_object_input: {
      fields: lambda do |_connection, config_fields, _object_definitions|
        [
          {
            name: 'object_name', label: 'Object', control_type: 'select',
            hint: 'Select Google Ads object, e.g. campaign.',
            pick_list: 'new_object_list',
            optional: false, extends_schema: true
          },
          {
            name: 'client_customer_id',
            hint: 'Customer ID of the target Google Ads account, typically ' \
              'in the form of "1234567890". <b>It must be the advertising ' \
              'account being managed by your manager account.</b>',
            optional: false
          },
          if config_fields['object_name'].present?
            {
              name: 'id',
              label: "#{config_fields['object_name'].capitalize.labelize} ID",
              hint: 'When you start recipe for the first time, it picks up ' \
                "trigger events from this specified #{config_fields['object_name'].capitalize.labelize} ID.<br>" \
                '<b>Leave empty to get events created from the beginning.</b>',
              sticky: true,
              optional: true
            }
          end
        ].compact
      end
    },
    new_object_output: {
      fields: lambda do |_connection, config_fields, object_definitions|
        object_definitions[config_fields['object_name']] if config_fields['object_name'].present?
      end
    },
    mutate_output: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'resourceName' },
          { name: 'partialFailureError', type: 'object', properties: [
            { name: 'code' },
            { name: 'message' },
            { name: 'details', type: 'array', of: 'string' }
          ] }
        ]
      end
    },
    create_object_input: {
      fields: lambda do |_connection, config_fields, object_definitions|
        fields = case config_fields['object_name']
                 when 'campaign'
                   object_definitions['campaign'].
                 ignored('id', 'resourceName', 'servingStatus', 'labels', 'experimentType', 'adServingOptimizationStatus',
                         'biddingStrategyType', 'accessibleBiddingStrategy', 'optimizationScore', 'manualCpv', 'manualCpm',
                         'trackingSetting', 'baseCampaign', 'videoBrandSafetySuitability').
                 required('advertisingChannelType', 'name')
                 when 'user_list'
                   object_definitions['user_list'].
                 ignored('id', 'resourceName', 'sizeRangeForDisplay', 'sizeRangeForSearch', 'type',
                         'accessReason', 'readOnly', 'sizeForDisplay', 'sizeForSearch',
                         'eligibleForDisplay', 'matchRatePercentage', 'similarUserList').
                 required('name')
                 end
        [
          {
            name: 'client_customer_id',
            hint: 'Customer ID of the target Google Ads account, typically ' \
              'in the form of "1234567890". <b>It must be the advertising ' \
              'account being managed by your manager account.</b>',
            optional: false
          }
        ].concat(fields)
      end
    },
    update_object_input: {
      fields: lambda do |_connection, config_fields, object_definitions|
        fields = case config_fields['object_name']
                 when 'campaign'
                   object_definitions['campaign'].
                 ignored('id', 'servingStatus', 'labels', 'experimentType', 'adServingOptimizationStatus',
                         'biddingStrategyType', 'accessibleBiddingStrategy', 'optimizationScore', 'manualCpv',
                         'advertisingChannelType', 'advertisingChannelSubType', 'hotelSetting', 'manualCpm',
                         'trackingSetting', 'baseCampaign', 'videoBrandSafetySuitability').
                 required('resourceName')
                 when 'user_list'
                   object_definitions['user_list'].
                 ignored('id', 'sizeRangeForDisplay', 'sizeRangeForSearch', 'type',
                         'accessReason', 'readOnly', 'sizeForDisplay', 'sizeForSearch',
                         'eligibleForDisplay', 'matchRatePercentage', 'similarUserList').
                 required('resourceName')
                 end
        [
          {
            name: 'client_customer_id',
            hint: 'Customer ID of the target Google Ads account, typically ' \
              'in the form of "1234567890". <b>It must be the advertising ' \
              'account being managed by your manager account.</b>',
            optional: false
          }
        ].concat(fields)
      end
    },
    delete_object_input: {
      fields: lambda do |_connection, config_fields, object_definitions|
        fields = case config_fields['object_name']
                 when 'campaign'
                   object_definitions['campaign'].only('resourceName').required('resourceName')
                 when 'user_list'
                   object_definitions['user_list'].only('resourceName').required('resourceName')
                 end
        [
          {
            name: 'client_customer_id',
            hint: 'Customer ID of the target Google Ads account, typically ' \
              'in the form of "1234567890". <b>It must be the advertising ' \
              'account being managed by your manager account.</b>',
            optional: false
          }
        ].concat(fields)
      end
    },
    campaign: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'id', sticky: true },
          { name: 'resourceName', sticky: true,
            hint: 'The resource name of the campaign.<br>Campaign resource names have the form:
            <b>customers/{customer_id}/campaigns/{campaign_id}</b>' },
          { name: 'status',
            control_type: 'select',
            sticky: true,
            pick_list: 'campaign_statuses',
            toggle_hint: 'Select from options',
            hint: 'Status of this campaign. When a new campaign is added, the status defaults to <b>ENABLED</b>.',
            toggle_field: {
              name: 'status',
              label: 'Status',
              type: 'string',
              optional: true,
              control_type: 'text',
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: ENABLED, PAUSED, and REMOVED'
            } },
          { name: 'servingStatus' },
          { name: 'adServingOptimizationStatus',
            control_type: 'select',
            sticky: true,
            pick_list: 'campaign_ad_serving_optimization_statuses',
            toggle_hint: 'Select from options',
            hint: 'The ad serving optimization status of the campaign.',
            toggle_field: {
              name: 'adServingOptimizationStatus',
              label: 'Ad serving optimization status',
              type: 'string',
              optional: true,
              control_type: 'text',
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: OPTIMIZE, CONVERSION_OPTIMIZE, ' \
              'ROTATE, UNAVAILABLE and ROTATE_INDEFINITELY.<br>' \
              "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8" \
              "/customers.campaigns#AdServingOptimizationStatus' " \
              "target='_blank'>here</a> for more details about the options."
            } },
          { name: 'advertisingChannelType',
            control_type: 'select',
            optional: false,
            pick_list: 'campaign_ad_channel_types',
            toggle_hint: 'Select from options',
            hint: 'The primary serving target for ads within the campaign.',
            toggle_field: {
              name: 'advertisingChannelType',
              label: 'Advertising channel type',
              type: 'string',
              optional: false,
              control_type: 'text',
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: SEARCH, DISPLAY, HOTEL, VIDEO, ' \
              'MULTI_CHANNEL, LOCAL, SMART, and SHOPPING.<br>' \
              "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
              "AdvertisingChannelType' " \
              "target='_blank'>here</a> for more details about the options."
            } },
          { name: 'advertisingChannelSubType',
            control_type: 'select',
            sticky: true,
            pick_list: 'campaign_ad_channel_sub_types',
            toggle_hint: 'Select from options',
            hint: 'Optional refinement to <b>Advertising channel type</b>. ' \
            'Must be a valid sub-type of the parent channel type.',
            toggle_field: {
              name: 'advertisingChannelSubType',
              label: 'Advertising channel sub type',
              type: 'string',
              optional: true,
              control_type: 'text',
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: SEARCH_MOBILE_APP, DISPLAY_MOBILE_APP,
              SEARCH_EXPRESS, DISPLAY_EXPRESS, SHOPPING_SMART_ADS, DISPLAY_GMAIL_AD,
              DISPLAY_SMART_CAMPAIGN, VIDEO_OUTSTREAM, VIDEO_ACTION, VIDEO_NON_SKIPPABLE,
              APP_CAMPAIGN, APP_CAMPAIGN_FOR_ENGAGEMENT, LOCAL_CAMPAIGN,
              SHOPPING_COMPARISON_LISTING_ADS, SMART_CAMPAIGN VIDEO_SEQUENCE.<br>' \
              "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
              "AdvertisingChannelSubType' " \
              "target='_blank'>here</a> for more details about the options."
            } },
          { name: 'urlCustomParameters', sticky: true, type: 'array', of: 'object',
            hint: 'The list of mappings used to substitute custom parameter tags.',
            properties: [
              { name: 'key', sticky: true },
              { name: 'value', sticky: true }
            ] },
          { name: 'realTimeBiddingSetting', sticky: true, type: 'object',
            hint: 'Settings for Real-Time Bidding, a feature only available for ' \
            'campaigns targeting the Ad Exchange network.',
            properties: [
              { name: 'optIn',
                type: 'boolean',
                control_type: 'checkbox',
                sticky: true,
                render_input: 'boolean_conversion',
                parse_output: 'boolean_conversion',
                toggle_hint: 'Select from options',
                hint: 'Whether the campaign is opted in to real-time bidding.',
                toggle_field: {
                  name: 'optIn',
                  label: 'Opt in',
                  type: 'string',
                  render_input: 'boolean_conversion',
                  parse_output: 'boolean_conversion',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: true and false.'
                } }
            ] },
          { name: 'networkSettings', sticky: true, type: 'object',
            hint: 'The network settings for the campaign.',
            properties: [
              { name: 'targetGoogleSearch',
                label: 'Target Google search',
                type: 'boolean',
                control_type: 'checkbox',
                sticky: true,
                render_input: 'boolean_conversion',
                parse_output: 'boolean_conversion',
                toggle_hint: 'Select from options',
                hint: 'Whether ads will be served with google.com search results.',
                toggle_field: {
                  name: 'targetGoogleSearch',
                  label: 'Target Google search',
                  type: 'string',
                  render_input: 'boolean_conversion',
                  parse_output: 'boolean_conversion',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: true and false.'
                } },
              { name: 'targetSearchNetwork',
                type: 'boolean',
                control_type: 'checkbox',
                sticky: true,
                render_input: 'boolean_conversion',
                parse_output: 'boolean_conversion',
                toggle_hint: 'Select from options',
                hint: 'Whether ads will be served on partner sites in the Google network.',
                toggle_field: {
                  name: 'targetSearchNetwork',
                  label: 'Target search network',
                  type: 'string',
                  render_input: 'boolean_conversion',
                  parse_output: 'boolean_conversion',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: true and false.'
                } },
              { name: 'targetContentNetwork',
                type: 'boolean',
                control_type: 'checkbox',
                sticky: true,
                render_input: 'boolean_conversion',
                parse_output: 'boolean_conversion',
                toggle_hint: 'Select from options',
                hint: 'Whether ads will be served on specified placements in the Google Display Network. ' \
                'Placements are specified using the Placement criterion.',
                toggle_field: {
                  name: 'targetContentNetwork',
                  label: 'Target content network',
                  type: 'string',
                  render_input: 'boolean_conversion',
                  parse_output: 'boolean_conversion',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: true and false.'
                } },
              { name: 'targetPartnerSearchNetwork',
                type: 'boolean',
                control_type: 'checkbox',
                sticky: true,
                render_input: 'boolean_conversion',
                parse_output: 'boolean_conversion',
                toggle_hint: 'Select from options',
                hint: 'Whether ads will be served on the Google Partner Network.',
                toggle_field: {
                  name: 'targetPartnerSearchNetwork',
                  label: 'Target partner search network',
                  type: 'string',
                  render_input: 'boolean_conversion',
                  parse_output: 'boolean_conversion',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: true and false.'
                } }
            ] },
          { name: 'hotelSetting', sticky: true, type: 'object',
            hint: 'The hotel setting for the campaign.',
            properties: [
              { name: 'hotelCenterId', sticky: true, hint: 'The linked Hotel Center account.' }
            ] },
          { name: 'dynamicSearchAdsSetting', sticky: true, type: 'object',
            hint: 'The setting for controlling Dynamic googleAds.search Ads (DSA).',
            properties: [
              { name: 'domainName', sticky: true },
              { name: 'languageCode', sticky: true,
                hint: 'The language code specifying the language of the domain, e.g., "en".' },
              { name: 'feeds', sticky: true, type: 'array', of: 'string',
                hint: 'The list of page feeds associated with the campaign.' },
              { name: 'useSuppliedUrlsOnly',
                label: 'Use supplied URLs only',
                type: 'boolean',
                control_type: 'checkbox',
                sticky: true,
                render_input: 'boolean_conversion',
                parse_output: 'boolean_conversion',
                toggle_hint: 'Select from options',
                hint: 'Whether the campaign uses advertiser supplied URLs exclusively.',
                toggle_field: {
                  name: 'useSuppliedUrlsOnly',
                  label: 'Use supplied URLs only',
                  type: 'string',
                  render_input: 'boolean_conversion',
                  parse_output: 'boolean_conversion',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: true and false.'
                } }
            ] },
          { name: 'shoppingSetting', sticky: true, type: 'object',
            hint: 'The setting for controlling Shopping campaigns.',
            properties: [
              { name: 'merchantId', sticky: true },
              { name: 'salesCountry', sticky: true,
                hint: 'Sales country of products to include in the campaign.' },
              { name: 'campaignPriority', sticky: true, type: 'integer', control_type: 'integer',
                parse_output: 'integer_conversion', render_input: 'integer_conversion',
                hint: 'Priority of the campaign. Campaigns with numerically higher priorities ' \
                'take precedence over those with lower priorities. ' \
                'This field is required for Shopping campaigns, with values between 0 and 2, inclusive. ' \
                'This field is optional for Smart Shopping campaigns, but must be equal to 3 if set.' },
              { name: 'enableLocal',
                type: 'boolean',
                control_type: 'checkbox',
                sticky: true,
                render_input: 'boolean_conversion',
                parse_output: 'boolean_conversion',
                toggle_hint: 'Select from options',
                hint: 'Whether to include local products.',
                toggle_field: {
                  name: 'enableLocal',
                  label: 'Enable local',
                  type: 'string',
                  render_input: 'boolean_conversion',
                  parse_output: 'boolean_conversion',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: true and false.'
                } }
            ] },
          { name: 'targetingSetting', sticky: true, type: 'object',
            hint: 'Setting for targeting related features.',
            properties: [
              { name: 'targetRestrictions', sticky: true, type: 'array', of: 'object',
                properties: [
                  { name: 'targetingDimension',
                    control_type: 'select',
                    sticky: true,
                    pick_list: 'campaign_targeting_dimensions',
                    toggle_hint: 'Select from options',
                    hint: 'The targeting dimension that these settings apply to.',
                    toggle_field: {
                      name: 'targetingDimension',
                      label: 'Targeting dimension',
                      type: 'string',
                      optional: true,
                      control_type: 'text',
                      toggle_hint: 'Use custom value',
                      hint: 'Allowed values are: KEYWORD, AUDIENCE, TOPIC,
                      GENDER, AGE_RANGE, PLACEMENT, PARENTAL_STATUS, INCOME_RANGE.<br>' \
                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                      "TargetingDimension' " \
                      "target='_blank'>here</a> for more details about the options."
                    } },
                  { name: 'bidOnly',
                    type: 'boolean',
                    control_type: 'checkbox',
                    sticky: true,
                    render_input: 'boolean_conversion',
                    parse_output: 'boolean_conversion',
                    toggle_hint: 'Select from options',
                    hint: 'Indicates whether to restrict your ads to show only for the criteria you ' \
                    'have selected for this Targeting dimension, or to target all values for this ' \
                    'Targeting dimension and show ads based on your targeting in other Targeting dimensions.',
                    toggle_field: {
                      name: 'bidOnly',
                      label: 'Bid only',
                      type: 'string',
                      render_input: 'boolean_conversion',
                      parse_output: 'boolean_conversion',
                      control_type: 'text',
                      optional: true,
                      toggle_hint: 'Use custom value',
                      hint: 'Allowed values are: true and false.'
                    } }
                ] },
              { name: 'targetRestrictionOperations', sticky: true, type: 'array', of: 'object',
                properties: [
                  { name: 'operator',
                    control_type: 'select',
                    sticky: true,
                    pick_list: 'campaign_targeting_dimension_operators',
                    toggle_hint: 'Select from options',
                    hint: 'Type of list operation to perform.',
                    toggle_field: {
                      name: 'operator',
                      label: 'Operator',
                      type: 'string',
                      optional: true,
                      control_type: 'text',
                      toggle_hint: 'Use custom value',
                      hint: 'Allowed values are: ADD and REMOVE.<br>' \
                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                      "TargetingSetting#Operator' " \
                      "target='_blank'>here</a> for more details about the options."
                    } },
                  { name: 'value', sticky: true, type: 'object',
                    properties: [
                      { name: 'targetingDimension',
                        control_type: 'select',
                        sticky: true,
                        pick_list: 'campaign_targeting_dimensions',
                        toggle_hint: 'Select from options',
                        hint: 'The targeting dimension that these settings apply to.',
                        toggle_field: {
                          name: 'targetingDimension',
                          label: 'Targeting dimension',
                          type: 'string',
                          optional: true,
                          control_type: 'text',
                          toggle_hint: 'Use custom value',
                          hint: 'Allowed values are: KEYWORD, AUDIENCE, TOPIC,
                          GENDER, AGE_RANGE, PLACEMENT, PARENTAL_STATUS, INCOME_RANGE.<br>' \
                          "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                          "TargetingDimension' " \
                          "target='_blank'>here</a> for more details about the options."
                        } },
                      { name: 'bidOnly',
                        type: 'boolean',
                        control_type: 'checkbox',
                        sticky: true,
                        render_input: 'boolean_conversion',
                        parse_output: 'boolean_conversion',
                        toggle_hint: 'Select from options',
                        hint: 'Indicates whether to restrict your ads to show only for the criteria you ' \
                        'have selected for this Targeting dimension, or to target all values for this ' \
                        'Targeting dimension and show ads based on your targeting in other Targeting dimensions.',
                        toggle_field: {
                          name: 'bidOnly',
                          label: 'Bid only',
                          type: 'string',
                          render_input: 'boolean_conversion',
                          parse_output: 'boolean_conversion',
                          control_type: 'text',
                          optional: true,
                          toggle_hint: 'Use custom value',
                          hint: 'Allowed values are: true and false.'
                        } }
                    ] }
                ] }
            ] },
          { name: 'geoTargetTypeSetting', sticky: true, type: 'object',
            hint: 'The setting for ads geotargeting.',
            properties: [
              { name: 'positiveGeoTargetType',
                control_type: 'select',
                sticky: true,
                pick_list: 'campaign_positive_geo_target_types',
                toggle_hint: 'Select from options',
                hint: 'The targeting dimension that these settings apply to.',
                toggle_field: {
                  name: 'positiveGeoTargetType',
                  label: 'Positive geo target type',
                  type: 'string',
                  optional: true,
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: PRESENCE_OR_INTEREST, SEARCH_INTEREST, PRESENCE.<br>' \
                  "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                  "customers.campaigns#PositiveGeoTargetType' " \
                  "target='_blank'>here</a> for more details about the options."
                } },
              { name: 'negativeGeoTargetType',
                control_type: 'select',
                sticky: true,
                pick_list: 'campaign_negative_geo_target_types',
                toggle_hint: 'Select from options',
                hint: 'The targeting dimension that these settings apply to.',
                toggle_field: {
                  name: 'negativeGeoTargetType',
                  label: 'Negative geo target type',
                  type: 'string',
                  optional: true,
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: PRESENCE_OR_INTEREST, PRESENCE.<br>' \
                  "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                  "customers.campaigns#NegativeGeoTargetType' " \
                  "target='_blank'>here</a> for more details about the options."
                } }
            ] },
          { name: 'localCampaignSetting', sticky: true, type: 'object',
            hint: 'The setting for local campaign.',
            properties: [
              { name: 'locationSourceType',
                control_type: 'select',
                sticky: true,
                pick_list: 'campaign_location_source_types',
                toggle_hint: 'Select from options',
                hint: 'The location source type for this local campaign.',
                toggle_field: {
                  name: 'locationSourceType',
                  label: 'Location source type',
                  type: 'string',
                  optional: true,
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: GOOGLE_MY_BUSINESS, and AFFILIATE.<br>' \
                  "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                  "customers.campaigns#LocationSourceType' " \
                  "target='_blank'>here</a> for more details about the options."
                } }
            ] },
          { name: 'appCampaignSetting', sticky: true, type: 'object',
            hint: 'The setting related to App Campaign.',
            properties: [
              { name: 'biddingStrategyGoalType',
                control_type: 'select',
                sticky: true,
                pick_list: 'campaign_bidding_strategy_goal_types',
                toggle_hint: 'Select from options',
                hint: 'Represents the goal which the bidding strategy of this app campaign should optimize towards.',
                toggle_field: {
                  name: 'biddingStrategyGoalType',
                  label: 'Bidding strategy goal type',
                  type: 'string',
                  optional: true,
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: OPTIMIZE_INSTALLS_TARGET_INSTALL_COST, ' \
                  'OPTIMIZE_IN_APP_CONVERSIONS_TARGET_INSTALL_COST, OPTIMIZE_IN_APP_CONVERSIONS_TARGET_CONVERSION_COST, ' \
                  'and OPTIMIZE_RETURN_ON_ADVERTISING_SPEND.<br>' \
                  "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                  "customers.campaigns#AppCampaignBiddingStrategyGoalType' " \
                  "target='_blank'>here</a> for more details about the options."
                } },
              { name: 'appStore',
                control_type: 'select',
                sticky: true,
                pick_list: 'campaign_app_stores',
                toggle_hint: 'Select from options',
                hint: 'The application store that distributes this specific app.',
                toggle_field: {
                  name: 'appStore',
                  label: 'App store',
                  type: 'string',
                  optional: true,
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: APPLE_APP_STORE, GOOGLE_APP_STORE.<br>' \
                  "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                  "customers.campaigns#AppCampaignAppStore' " \
                  "target='_blank'>here</a> for more details about the options."
                } },
              { name: 'appId', sticky: true, hint: 'A string that uniquely identifies a mobile application.' }
            ] },
          { name: 'labels', sticky: true, type: 'array', of: 'string' },
          { name: 'experimentType', sticky: true },
          { name: 'biddingStrategyType', sticky: true },
          { name: 'accessibleBiddingStrategy', sticky: true },
          { name: 'frequencyCaps', sticky: true, type: 'array', of: 'object',
            hint: 'A list that limits how often each user will see this campaign\'s ads.',
            properties: [
              { name: 'key', sticky: true, type: 'object',
                properties: [
                  { name: 'level',
                    control_type: 'select',
                    sticky: true,
                    pick_list: 'campaign_frequency_caps_levels',
                    toggle_hint: 'Select from options',
                    hint: 'The level on which the cap is to be applied (e.g. ad group ad, ad group). ' \
                    'The cap is applied to all the entities of this level.',
                    toggle_field: {
                      name: 'level',
                      label: 'Level',
                      type: 'string',
                      optional: true,
                      control_type: 'text',
                      toggle_hint: 'Use custom value',
                      hint: 'Allowed values are: AD_GROUP_AD, AD_GROUP, CAMPAIGN.<br>' \
                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                      "customers.campaigns#FrequencyCapLevel' " \
                      "target='_blank'>here</a> for more details about the options."
                    } },
                  { name: 'eventType',
                    control_type: 'select',
                    sticky: true,
                    pick_list: 'campaign_frequency_caps_event_types',
                    toggle_hint: 'Select from options',
                    hint: 'The type of event that the cap applies to (e.g. impression).',
                    toggle_field: {
                      name: 'eventType',
                      label: 'Event type',
                      type: 'string',
                      optional: true,
                      control_type: 'text',
                      toggle_hint: 'Use custom value',
                      hint: 'Allowed values are: IMPRESSION, VIDEO_VIEW.<br>' \
                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                      "customers.campaigns#FrequencyCapEventType' " \
                      "target='_blank'>here</a> for more details about the options."
                    } },
                  { name: 'timeUnit',
                    control_type: 'select',
                    sticky: true,
                    pick_list: 'campaign_frequency_caps_time_units',
                    toggle_hint: 'Select from options',
                    hint: 'Unit of time the cap is defined at (e.g. day, week).',
                    toggle_field: {
                      name: 'timeUnit',
                      label: 'Time unit',
                      type: 'string',
                      optional: true,
                      control_type: 'text',
                      toggle_hint: 'Use custom value',
                      hint: 'Allowed values are: DAY, WEEK, and MONTH.<br>' \
                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                      "customers.campaigns#FrequencyCapTimeUnit' " \
                      "target='_blank'>here</a> for more details about the options."
                    } },
                  { name: 'timeLength', sticky: true, type: 'integer', control_type: 'integer',
                    parse_output: 'integer_conversion', render_input: 'integer_conversion',
                    hint: 'Number of time units the cap lasts.' }
                ] },
              { name: 'cap', sticky: true, type: 'integer', control_type: 'integer',
                parse_output: 'integer_conversion', render_input: 'integer_conversion',
                hint: 'Maximum number of events allowed during the time range by this cap.' }
            ] },
          { name: 'videoBrandSafetySuitability' },
          { name: 'vanityPharma', sticky: true, type: 'object',
            hint: 'Describes how unbranded pharma ads will be displayed.',
            properties: [
              { name: 'vanityPharmaDisplayUrlMode',
                control_type: 'select',
                sticky: true,
                pick_list: 'campaign_vanity_pharma_display_url_modes',
                toggle_hint: 'Select from options',
                hint: 'The display mode for vanity pharma URLs.',
                toggle_field: {
                  name: 'vanityPharmaDisplayUrlMode',
                  label: 'Vanity pharma display URL mode',
                  type: 'string',
                  optional: true,
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: MANUFACTURER_WEBSITE_URL, ' \
                  'SEARCH_INTEREST and WEBSITE_DESCRIPTION.<br>' \
                  "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                  "customers.campaigns#VanityPharmaDisplayUrlMode' " \
                  "target='_blank'>here</a> for more details about the options."
                } },
              { name: 'vanityPharmaText',
                control_type: 'select',
                sticky: true,
                pick_list: 'campaign_vanity_pharma_texts',
                toggle_hint: 'Select from options',
                hint: 'The text that will be displayed in display URL of the text ad ' \
                'when website description is the selected display mode for vanity pharma URLs.',
                toggle_field: {
                  name: 'vanityPharmaText',
                  label: 'Vanity pharma text',
                  type: 'string',
                  optional: true,
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: PRESCRIPTION_TREATMENT_WEBSITE_EN, ' \
                  'PRESCRIPTION_TREATMENT_WEBSITE_ES, PRESCRIPTION_DEVICE_WEBSITE_EN, ' \
                  'PRESCRIPTION_DEVICE_WEBSITE_ES, MEDICAL_DEVICE_WEBSITE_EN, MEDICAL_DEVICE_WEBSITE_ES, ' \
                  'PREVENTATIVE_TREATMENT_WEBSITE_EN, PREVENTATIVE_TREATMENT_WEBSITE_ES, ' \
                  'PRESCRIPTION_CONTRACEPTION_WEBSITE_EN, PRESCRIPTION_CONTRACEPTION_WEBSITE_ES, ' \
                  'PRESCRIPTION_VACCINE_WEBSITE_EN, PRESCRIPTION_VACCINE_WEBSITE_ES.<br>' \
                  "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                  "customers.campaigns#VanityPharmaText' " \
                  "target='_blank'>here</a> for more details about the options."
                } }
            ] },
          { name: 'selectiveOptimization', sticky: true, type: 'object',
            hint: 'Selective optimization setting for this campaign, ' \
            'which includes a set of conversion actions to optimize this campaign towards.',
            properties: [
              { name: 'conversionActions', sticky: true, type: 'array', of: 'string',
                hint: 'The selected set of conversion actions for optimizing this campaign.' }
            ] },
          { name: 'optimizationGoalSetting', sticky: true, type: 'object',
            hint: 'Optimization goal setting for this campaign, ' \
            'which includes a set of optimization goal types.',
            properties: [
              { name: 'optimizationGoalTypes', sticky: true, type: 'array', of: 'string',
                hint: 'The list of optimization goal types.<br>' \
                "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                "customers.campaigns#OptimizationGoalSetting' " \
                "target='_blank'>here</a> for more details about the valid values." }
            ] },
          { name: 'trackingSetting', sticky: true, type: 'object',
            properties: [
              { name: 'trackingUrl', label: 'Tracking URL', sticky: true }
            ] },
          { name: 'paymentMode',
            control_type: 'select',
            sticky: true,
            pick_list: 'campaign_payment_modes',
            toggle_hint: 'Select from options',
            hint: 'Payment mode for the campaign.',
            toggle_field: {
              name: 'paymentMode',
              label: 'Payment mode',
              type: 'string',
              optional: true,
              control_type: 'text',
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: CLICKS, ' \
              'CONVERSION_VALUE, CONVERSIONS and GUEST_STAY.<br>' \
              "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
              "customers.campaigns#PaymentMode' " \
              "target='_blank'>here</a> for more details about the options."
            } },
          { name: 'excludedParentAssetFieldTypes', sticky: true, type: 'array', of: 'string',
            hint: 'The asset field types that should be excluded from this campaign. ' \
            'Asset links with these field types will not be inherited by this campaign from the upper level.<br>' \
             "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
             "AssetFieldType' " \
             "target='_blank'>here</a> for more details about the valid values." },
          { name: 'name', sticky: true, hint: 'The name of the campaign.' },
          { name: 'trackingUrlTemplate', sticky: true,
            hint: 'The URL template for constructing a tracking URL.' },
          { name: 'baseCampaign', sticky: true },
          { name: 'campaignBudget', sticky: true, hint: 'The budget of the campaign.' },
          { name: 'startDate', sticky: true, control_type: 'date', type: 'date' },
          { name: 'endDate', sticky: true, control_type: 'date', type: 'date' },
          { name: 'finalUrlSuffix', sticky: true,
            hint: 'Suffix used to append query parameters to landing pages that are served with parallel tracking.' },
          { name: 'optimizationScore', sticky: true, type: 'number', control_type: 'number' },
          { name: 'biddingStrategy', sticky: true,
            hint: 'Portfolio bidding strategy used by campaign.' },
          { name: 'commission', sticky: true, type: 'object',
            hint: 'Commission is an automatic bidding strategy in which the ' \
            'advertiser pays a certain portion of the conversion value.',
            properties: [
              { name: 'commissionRateMicros', sticky: true,
                hint: 'Commission rate defines the portion of the conversion value that ' \
                'the advertiser will be billed. A commission rate of x should be passed ' \
                'into this field as (x * 1,000,000). For example, 106,000 represents a ' \
                'commission rate of 0.106 (10.6%).' }
            ] },
          { name: 'manualCpc', sticky: true, label: 'Manual CPC', type: 'object',
            hint: 'Standard Manual CPC bidding strategy. Manual click-based bidding where user pays per click.',
            properties: [
              { name: 'enhancedCpcEnabled',
                label: 'Enhanced CPC enabled',
                type: 'boolean',
                control_type: 'checkbox',
                sticky: true,
                render_input: 'boolean_conversion',
                parse_output: 'boolean_conversion',
                toggle_hint: 'Select from options',
                hint: 'Whether bids are to be enhanced based on conversion optimizer data.',
                toggle_field: {
                  name: 'enhancedCpcEnabled',
                  label: 'Enhanced CPC enabled',
                  type: 'string',
                  render_input: 'boolean_conversion',
                  parse_output: 'boolean_conversion',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: true and false.'
                } }
            ] },
          { name: 'manualCpm' },
          { name: 'manualCpv' },
          { name: 'maximizeConversions', sticky: true, type: 'object',
            hint: 'Standard Maximize Conversions bidding strategy that ' \
            'automatically maximizes number of conversions while spending your budget.',
            properties: [
              { name: 'targetCpa', label: 'Target CPA', sticky: true,
                hint: 'The target cost-per-action (CPA) option. ' \
                'This is the average amount that you would like to spend per conversion action. ' \
                'If set, the bid strategy will get as many conversions as possible at or ' \
                'below the target cost-per-action. If the target CPA is not set, ' \
                'the bid strategy will aim to achieve the lowest possible CPA given the budget.' }
            ] },
          { name: 'maximizeConversionValue', sticky: true, type: 'object',
            hint: 'Standard Maximize Conversion Value bidding strategy that ' \
            'automatically sets bids to maximize revenue while spending your budget.',
            properties: [
              { name: 'targetRoas', label: 'Target ROAS', sticky: true,
                hint: 'The target return on ad spend (ROAS) option. ' \
                'If set, the bid strategy will maximize revenue while averaging ' \
                'the target return on ad spend. If the target ROAS is high, ' \
                'the bid strategy may not be able to spend the full budget. ' \
                'If the target ROAS is not set, the bid strategy will aim to ' \
                'achieve the highest possible ROAS for the budget.' }
            ] },
          { name: 'targetCpa', label: 'Target CPA', sticky: true, type: 'object',
            hint: 'Standard Target CPA bidding strategy that automatically sets bids ' \
            'to help get as many conversions as possible at the target cost-per-acquisition (CPA) you set.',
            properties: [
              { name: 'targetCpaMicros', label: 'Target CPA micros', sticky: true,
                hint: 'Average CPA target. This target should be greater than or ' \
                'equal to minimum billable unit based on the currency for the account.' },
              { name: 'cpcBidCeilingMicros', label: 'CPC bid ceiling micros', sticky: true,
                hint: 'Maximum bid limit that can be set by the bid strategy. ' \
                'The limit applies to all keywords managed by the strategy. ' \
                'This should only be set for portfolio bid strategies.' },
              { name: 'cpcBidFloorMicros', label: 'CPC bid floor micros', sticky: true,
                hint: 'Minimum bid limit that can be set by the bid strategy. ' \
                'The limit applies to all keywords managed by the strategy. ' \
                'This should only be set for portfolio bid strategies.' }
            ] },
          { name: 'targetImpressionShare', sticky: true, type: 'object',
            hint: 'Target Impression Share bidding strategy. ' \
            'An automated bidding strategy that sets bids to achieve a desired percentage of impressions.',
            properties: [
              { name: 'location',
                control_type: 'select',
                sticky: true,
                pick_list: 'campaign_target_impression_share_locations',
                toggle_hint: 'Select from options',
                hint: 'The targeted location on the search results page.',
                toggle_field: {
                  name: 'location',
                  label: 'Location',
                  type: 'string',
                  optional: true,
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: ANYWHERE_ON_PAGE, ' \
                  'TOP_OF_PAGE and ABSOLUTE_TOP_OF_PAGE.<br>' \
                  "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                  "TargetImpressionShareLocation' " \
                  "target='_blank'>here</a> for more details about the options."
                } },
              { name: 'locationFractionMicros', label: 'CPC bid ceiling micros', sticky: true,
                hint: 'The desired fraction of ads to be shown in the targeted location in micros. ' \
                'E.g. 1% = 10,000.' },
              { name: 'cpcBidCeilingMicros', label: 'CPC bid ceiling micros', sticky: true,
                hint: 'The highest CPC bid the automated bidding system is permitted to specify. ' \
                'This is a required field entered by the advertiser that sets the ' \
                'ceiling and specified in local micros.' }
            ] },
          { name: 'targetRoas', label: 'Target ROAS', sticky: true, type: 'object',
            hint: 'Standard Target ROAS bidding strategy that automatically ' \
            'maximizes revenue while averaging a specific target return on ad spend (ROAS).',
            properties: [
              { name: 'targetRoas', label: 'Target ROAS', sticky: true,
                type: 'number', control_type: 'number',
                parse_output: 'float_conversion', render_input: 'float_conversion',
                hint: 'The desired revenue (based on conversion data) per unit of spend. ' \
                'Value must be between 0.01 and 1000.0, inclusive.' },
              { name: 'cpcBidCeilingMicros', label: 'CPC bid ceiling micros', sticky: true,
                hint: 'Maximum bid limit that can be set by the bid strategy. ' \
                'The limit applies to all keywords managed by the strategy. ' \
                'This should only be set for portfolio bid strategies.' },
              { name: 'cpcBidFloorMicros', label: 'CPC bid floor micros', sticky: true,
                hint: 'Minimum bid limit that can be set by the bid strategy. ' \
                'The limit applies to all keywords managed by the strategy. ' \
                'This should only be set for portfolio bid strategies.' }
            ] },
          { name: 'targetSpend', sticky: true, type: 'object',
            hint: 'Standard Target Spend bidding strategy that ' \
            'automatically sets your bids to help get as many clicks as possible within your budget.',
            properties: [
              { name: 'cpcBidCeilingMicros', label: 'CPC bid ceiling micros', sticky: true,
                hint: 'Maximum bid limit that can be set by the bid strategy. ' \
                'The limit applies to all keywords managed by the strategy.' }
            ] },
          { name: 'percentCpc', sticky: true, label: 'Percent CPC', type: 'object',
            hint: 'Standard Percent Cpc bidding strategy where bids ' \
            'are a fraction of the advertised price for some good or service.',
            properties: [
              { name: 'cpcBidCeilingMicros', label: 'CPC bid ceiling micros', sticky: true,
                hint: 'Maximum bid limit that can be set by the bid strategy. ' \
                'This is an optional field entered by the advertiser and specified in local micros.' },
              { name: 'enhancedCpcEnabled',
                label: 'Enhanced CPC enabled',
                type: 'boolean',
                control_type: 'checkbox',
                sticky: true,
                render_input: 'boolean_conversion',
                parse_output: 'boolean_conversion',
                toggle_hint: 'Select from options',
                hint: 'Adjusts the bid for each auction upward or downward, ' \
                'depending on the likelihood of a conversion.',
                toggle_field: {
                  name: 'enhancedCpcEnabled',
                  label: 'Enhanced CPC enabled',
                  type: 'string',
                  render_input: 'boolean_conversion',
                  parse_output: 'boolean_conversion',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: true and false.'
                } }
            ] }
        ]
      end
    },
    customer_client: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'id' },
          { name: 'resourceName' },
          { name: 'appliedLabels', type: 'array', of: 'string' },
          { name: 'clientCustomer' },
          { name: 'hidden', type: 'boolean' },
          { name: 'level' },
          { name: 'timeZone' },
          { name: 'testAccount', type: 'boolean' },
          { name: 'manager', type: 'boolean' },
          { name: 'descriptiveName' },
          { name: 'currencyCode' }
        ]
      end
    },
    user_list: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'id', sticky: true },
          { name: 'resourceName', sticky: true,
            hint: 'The resource name of the user list.<br>User list resource names have the form:
            <b>customers/{customer_id}/userLists/{user_list_id}</b>' },
          { name: 'membershipStatus',
            control_type: 'select',
            sticky: true,
            pick_list: 'user_list_membership_statuses',
            toggle_hint: 'Select from options',
            hint: 'Membership status of this user list. ' \
            'Indicates whether a user list is open or active.',
            toggle_field: {
              name: 'membershipStatus',
              label: 'Membership status',
              type: 'string',
              optional: true,
              control_type: 'text',
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: OPEN and CLOSED.<br>' \
              "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
              "customers.userLists#UserListMembershipStatus' " \
              "target='_blank'>here</a> for more details about the options."
            } },
          { name: 'sizeRangeForDisplay', sticky: true },
          { name: 'sizeRangeForSearch', sticky: true },
          { name: 'type', sticky: true },
          { name: 'closingReason',
            control_type: 'select',
            sticky: true,
            pick_list: 'user_list_closing_reasons',
            toggle_hint: 'Select from options',
            hint: 'Indicating the reason why this user list membership status is closed. ' \
            'It is only populated on lists that were automatically closed due to inactivity, ' \
            'and will be cleared once the list membership status becomes open.',
            toggle_field: {
              name: 'closingReason',
              label: 'Closing reason',
              type: 'string',
              optional: true,
              control_type: 'text',
              toggle_hint: 'Use custom value',
              hint: 'Allowed value: UNUSED.<br>' \
              "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
              "customers.userLists#UserListClosingReason' " \
              "target='_blank'>here</a> for more details about the options."
            } },
          { name: 'accessReason', sticky: true },
          { name: 'accountUserListStatus',
            control_type: 'select',
            sticky: true,
            pick_list: 'user_list_statuses',
            toggle_hint: 'Select from options',
            hint: 'Indicates if this share is still enabled. ' \
            'When a UserList is shared with the user this field is set to ENABLED. ' \
            'Later the userList owner can decide to revoke the share and make it DISABLED. ' \
            'The default value of this field is set to ENABLED.',
            toggle_field: {
              name: 'accountUserListStatus',
              label: 'Account user list status',
              type: 'string',
              optional: true,
              control_type: 'text',
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: ENABLED and DISABLED.<br>' \
              "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
              "customers.userLists#UserListAccessStatus' " \
              "target='_blank'>here</a> for more details about the options."
            } },
          { name: 'readOnly', sticky: true, type: 'boolean' },
          { name: 'name', sticky: true, hint: 'Name of this user list.' },
          { name: 'description', sticky: true },
          { name: 'integrationCode', sticky: true,
            hint: 'An ID from external system. It is used by user list sellers to correlate IDs on their systems.' },
          { name: 'membershipLifeSpan', sticky: true,
            hint: 'Number of days a user\'s cookie stays on your list since its most ' \
            'recent addition to the list. This field must be between 0 and 540 inclusive. ' \
            'However, for CRM based userlists, this field can be set to 10000 which means no expiration.' },
          { name: 'sizeForDisplay', sticky: true },
          { name: 'sizeForSearch', sticky: true },
          { name: 'eligibleForSearch',
            type: 'boolean',
            control_type: 'checkbox',
            sticky: true,
            render_input: 'boolean_conversion',
            parse_output: 'boolean_conversion',
            toggle_hint: 'Select from options',
            hint: 'Indicates if this user list is eligible for Google googleAds.search Network.',
            toggle_field: {
              name: 'eligibleForSearch',
              label: 'Eligible for search',
              type: 'string',
              render_input: 'boolean_conversion',
              parse_output: 'boolean_conversion',
              control_type: 'text',
              optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: true and false.'
            } },
          { name: 'eligibleForDisplay', sticky: true },
          { name: 'matchRatePercentage', sticky: true,
            type: 'integer', control_type: 'integer',
            parse_output: 'integer_conversion', render_input: 'integer_conversion' },
          { name: 'crmBasedUserList', label: 'CRM based user list', sticky: true, type: 'object',
            hint: 'User list of CRM users provided by the advertiser.',
            properties: [
              { name: 'uploadKeyType',
                control_type: 'select',
                sticky: true,
                pick_list: 'user_list_upload_key_types',
                toggle_hint: 'Select from options',
                hint: 'Matching key type of the list. Mixed data types are not allowed on the same list.',
                toggle_field: {
                  name: 'uploadKeyType',
                  label: 'Upload key type',
                  type: 'string',
                  optional: true,
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: CONTACT_INFO, ' \
                  'CRM_ID and MOBILE_ADVERTISING_ID.<br>' \
                  "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                  "customers.userLists#CustomerMatchUploadKeyType' " \
                  "target='_blank'>here</a> for more details about the options."
                } },
              { name: 'dataSourceType',
                control_type: 'select',
                sticky: true,
                pick_list: 'user_list_data_source_types',
                toggle_hint: 'Select from options',
                hint: 'Data source of the list. ' \
                'Default value is <b>First party</b>. ' \
                'Only customers on the allow-list can create third-party sourced CRM lists.',
                toggle_field: {
                  name: 'dataSourceType',
                  label: 'Data source type',
                  type: 'string',
                  optional: true,
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: FIRST_PARTY, ' \
                  'THIRD_PARTY_CREDIT_BUREAU and THIRD_PARTY_VOTER_FILE.<br>' \
                  "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                  "customers.userLists#UserListCrmDataSourceType' " \
                  "target='_blank'>here</a> for more details about the options."
                } },
              { name: 'appId', sticky: true,
                hint: 'A string that uniquely identifies a mobile application from which the data was ' \
                'collected to the Google Ads API. For iOS, the ID string is the 9 digit string that ' \
                'appears at the end of an App Store URL (e.g., "476943146" for "Flood-It! 2" whose App ' \
                'Store link is http://itunes.apple.com/us/app/flood-it!-2/id476943146). ' \
                'For Android, the ID string is the application\'s package name ' \
                '(e.g., "com.labpixies.colordrips" for "Color Drips" given Google Play ' \
                'link: https://play.google.com/store/apps/details?id=com.labpixies.colordrips). ' \
                'Required when creating CrmBasedUserList for uploading mobile advertising IDs.' }
            ] },
          { name: 'similarUserList', sticky: true, type: 'object',
            properties: [
              { name: 'seedUserList', sticky: true }
            ] },
          { name: 'ruleBasedUserList', sticky: true, type: 'object',
            properties: [
              { name: 'prepopulationStatus',
                control_type: 'select',
                sticky: true,
                pick_list: 'user_list_prepopulation_statuses',
                toggle_hint: 'Select from options',
                hint: 'The status of pre-population. ' \
                'The field is default to NONE if not set which means the previous users will not be considered.',
                toggle_field: {
                  name: 'prepopulationStatus',
                  label: 'Prepopulation status',
                  type: 'string',
                  optional: true,
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are: REQUESTED, FINISHED and FAILED.<br>' \
                  "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                  "customers.userLists#UserListPrepopulationStatus' " \
                  "target='_blank'>here</a> for more details about the options."
                } },
              { name: 'combinedRuleUserList', sticky: true, type: 'object',
                hint: 'User lists defined by combining two rules.',
                properties: [
                  { name: 'leftOperand', sticky: true, type: 'object',
                    hint: 'Left operand of the combined rule. ' \
                    'This field is required and must be populated when creating new combined rule based user list.',
                    properties: [
                      { name: 'ruleType',
                        control_type: 'select',
                        sticky: true,
                        pick_list: 'user_list_combined_rule_types',
                        toggle_hint: 'Select from options',
                        hint: 'Rule type is used to determine how to group rule items.',
                        toggle_field: {
                          name: 'ruleType',
                          label: 'Rule type',
                          type: 'string',
                          optional: true,
                          control_type: 'text',
                          toggle_hint: 'Use custom value',
                          hint: 'Allowed values are: AND_OF_ORS and OR_OF_ANDS.<br>' \
                          "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                          "customers.userLists#UserListRuleType' " \
                          "target='_blank'>here</a> for more details about the options."
                        } },
                      { name: 'ruleItemGroups', sticky: true, type: 'array', of: 'object',
                        hint: 'List of rule item groups that defines this rule. ' \
                        'Rule item groups are grouped together based on rule type.',
                        properties: [
                          { name: 'ruleItems', sticky: true, type: 'array', of: 'object',
                            hint: 'Rule items that will be grouped together based on rule type.',
                            properties: [
                              { name: 'name', sticky: true },
                              { name: 'numberRuleItem', sticky: true, type: 'object',
                                hint: 'An atomic rule item composed of a number operation.',
                                properties: [
                                  { name: 'operator',
                                    control_type: 'select',
                                    sticky: true,
                                    pick_list: 'user_list_number_rule_operators',
                                    toggle_hint: 'Select from options',
                                    hint: 'Number comparison operator.',
                                    toggle_field: {
                                      name: 'operator',
                                      label: 'Operator',
                                      type: 'string',
                                      optional: true,
                                      control_type: 'text',
                                      toggle_hint: 'Use custom value',
                                      hint: 'Allowed values are: GREATER_THAN, GREATER_THAN_OR_EQUAL, ' \
                                      'EQUALS, NOT_EQUALS, LESS_THAN, LESS_THAN_OR_EQUAL and OR_OF_ANDS.<br>' \
                                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                                      "customers.userLists#UserListNumberRuleItemOperator' " \
                                      "target='_blank'>here</a> for more details about the options."
                                    } },
                                  { name: 'value', sticky: true, control_type: 'number', type: 'number',
                                    hint: 'Number value to be compared with the variable.' }
                                ] },
                              { name: 'stringRuleItem', sticky: true, type: 'object',
                                hint: 'An atomic rule item composed of a string operation.',
                                properties: [
                                  { name: 'operator',
                                    control_type: 'select',
                                    sticky: true,
                                    pick_list: 'user_list_string_rule_operators',
                                    toggle_hint: 'Select from options',
                                    hint: 'String comparison operator.',
                                    toggle_field: {
                                      name: 'operator',
                                      label: 'Operator',
                                      type: 'string',
                                      optional: true,
                                      control_type: 'text',
                                      toggle_hint: 'Use custom value',
                                      hint: 'Allowed values are: CONTAINS, EQUALS, ' \
                                      'STARTS_WITH, ENDS_WITH, NOT_EQUALS, NOT_CONTAINS, ' \
                                      'NOT_STARTS_WITH and NOT_ENDS_WITH.<br>' \
                                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                                      "customers.userLists#UserListStringRuleItemOperator' " \
                                      "target='_blank'>here</a> for more details about the options."
                                    } },
                                  { name: 'value', sticky: true,
                                    hint: 'The right hand side of the string rule item. ' \
                                    'For URLs or referrer URLs, the value can not contain illegal ' \
                                    'URL characters such as newlines, quotes, tabs, or parentheses.' }
                                ] },
                              { name: 'dateRuleItem', sticky: true, type: 'object',
                                hint: 'An atomic rule item composed of a date operation.',
                                properties: [
                                  { name: 'operator',
                                    control_type: 'select',
                                    sticky: true,
                                    pick_list: 'user_list_date_rule_operators',
                                    toggle_hint: 'Select from options',
                                    hint: 'Date comparison operator.',
                                    toggle_field: {
                                      name: 'operator',
                                      label: 'Operator',
                                      type: 'string',
                                      optional: true,
                                      control_type: 'text',
                                      toggle_hint: 'Use custom value',
                                      hint: 'Allowed values are: EQUALS, NOT_EQUALS, BEFORE and AFTER.<br>' \
                                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                                      "customers.userLists#UserListDateRuleItemOperator' " \
                                      "target='_blank'>here</a> for more details about the options."
                                    } },
                                  { name: 'value', sticky: true, type: 'date', control_type: 'date',
                                    hint: 'String representing date value to be compared with the rule variable. ' \
                                    'Times are reported in the customer\'s time zone.' },
                                  { name: 'offsetInDays', sticky: true, type: 'date', control_type: 'date',
                                    hint: 'The relative date value of the right hand side ' \
                                    'denoted by number of days offset from now. ' \
                                    'The value field will override this field when both are present.' }
                                ] }
                            ] }
                        ] }
                    ] },
                  { name: 'rightOperand', sticky: true, type: 'object',
                    hint: 'Right operand of the combined rule. ' \
                    'This field is required and must be populated when creating new combined rule based user list.',
                    properties: [
                      { name: 'ruleType',
                        control_type: 'select',
                        sticky: true,
                        pick_list: 'user_list_combined_rule_types',
                        toggle_hint: 'Select from options',
                        hint: 'Rule type is used to determine how to group rule items.',
                        toggle_field: {
                          name: 'ruleType',
                          label: 'Rule type',
                          type: 'string',
                          optional: true,
                          control_type: 'text',
                          toggle_hint: 'Use custom value',
                          hint: 'Allowed values are: AND_OF_ORS and OR_OF_ANDS.<br>' \
                          "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                          "customers.userLists#UserListRuleType' " \
                          "target='_blank'>here</a> for more details about the options."
                        } },
                      { name: 'ruleItemGroups', sticky: true, type: 'array', of: 'object',
                        hint: 'List of rule item groups that defines this rule. ' \
                        'Rule item groups are grouped together based on rule type.',
                        properties: [
                          { name: 'ruleItems', sticky: true, type: 'array', of: 'object',
                            hint: 'Rule items that will be grouped together based on rule type.',
                            properties: [
                              { name: 'name', sticky: true },
                              { name: 'numberRuleItem', sticky: true, type: 'object',
                                hint: 'An atomic rule item composed of a number operation.',
                                properties: [
                                  { name: 'operator',
                                    control_type: 'select',
                                    sticky: true,
                                    pick_list: 'user_list_number_rule_operators',
                                    toggle_hint: 'Select from options',
                                    hint: 'Number comparison operator.',
                                    toggle_field: {
                                      name: 'operator',
                                      label: 'Operator',
                                      type: 'string',
                                      optional: true,
                                      control_type: 'text',
                                      toggle_hint: 'Use custom value',
                                      hint: 'Allowed values are: GREATER_THAN, GREATER_THAN_OR_EQUAL, ' \
                                      'EQUALS, NOT_EQUALS, LESS_THAN, LESS_THAN_OR_EQUAL and OR_OF_ANDS.<br>' \
                                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                                      "customers.userLists#UserListNumberRuleItemOperator' " \
                                      "target='_blank'>here</a> for more details about the options."
                                    } },
                                  { name: 'value', sticky: true, control_type: 'number', type: 'number',
                                    hint: 'Number value to be compared with the variable.' }
                                ] },
                              { name: 'stringRuleItem', sticky: true, type: 'object',
                                hint: 'An atomic rule item composed of a string operation.',
                                properties: [
                                  { name: 'operator',
                                    control_type: 'select',
                                    sticky: true,
                                    pick_list: 'user_list_string_rule_operators',
                                    toggle_hint: 'Select from options',
                                    hint: 'String comparison operator.',
                                    toggle_field: {
                                      name: 'operator',
                                      label: 'Operator',
                                      type: 'string',
                                      optional: true,
                                      control_type: 'text',
                                      toggle_hint: 'Use custom value',
                                      hint: 'Allowed values are: CONTAINS, EQUALS, ' \
                                      'STARTS_WITH, ENDS_WITH, NOT_EQUALS, NOT_CONTAINS, ' \
                                      'NOT_STARTS_WITH and NOT_ENDS_WITH.<br>' \
                                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                                      "customers.userLists#UserListStringRuleItemOperator' " \
                                      "target='_blank'>here</a> for more details about the options."
                                    } },
                                  { name: 'value', sticky: true,
                                    hint: 'The right hand side of the string rule item. ' \
                                    'For URLs or referrer URLs, the value can not contain illegal ' \
                                    'URL characters such as newlines, quotes, tabs, or parentheses.' }
                                ] },
                              { name: 'dateRuleItem', sticky: true, type: 'object',
                                hint: 'An atomic rule item composed of a date operation.',
                                properties: [
                                  { name: 'operator',
                                    control_type: 'select',
                                    sticky: true,
                                    pick_list: 'user_list_date_rule_operators',
                                    toggle_hint: 'Select from options',
                                    hint: 'Date comparison operator.',
                                    toggle_field: {
                                      name: 'operator',
                                      label: 'Operator',
                                      type: 'string',
                                      optional: true,
                                      control_type: 'text',
                                      toggle_hint: 'Use custom value',
                                      hint: 'Allowed values are: EQUALS, NOT_EQUALS, BEFORE and AFTER.<br>' \
                                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                                      "customers.userLists#UserListDateRuleItemOperator' " \
                                      "target='_blank'>here</a> for more details about the options."
                                    } },
                                  { name: 'value', sticky: true, type: 'date', control_type: 'date',
                                    hint: 'String representing date value to be compared with the rule variable. ' \
                                    'Times are reported in the customer\'s time zone.' },
                                  { name: 'offsetInDays', sticky: true, type: 'date', control_type: 'date',
                                    hint: 'The relative date value of the right hand side ' \
                                    'denoted by number of days offset from now. ' \
                                    'The value field will override this field when both are present.' }
                                ] }
                            ] }
                        ] }
                    ] },
                  { name: 'ruleOperator',
                    control_type: 'select',
                    sticky: true,
                    pick_list: 'user_list_combined_rule_operators',
                    toggle_hint: 'Select from options',
                    hint: 'Operator to connect the two operands.',
                    toggle_field: {
                      name: 'ruleOperator',
                      label: 'Rule operator',
                      type: 'string',
                      optional: true,
                      control_type: 'text',
                      toggle_hint: 'Use custom value',
                      hint: 'Allowed values are: AND and AND_NOT.<br>' \
                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                      "customers.userLists#UserListCombinedRuleOperator' " \
                      "target='_blank'>here</a> for more details about the options."
                    } }
                ] },
              { name: 'dateSpecificRuleUserList', sticky: true, type: 'object',
                hint: 'Visitors of a page during specific dates. ' \
                'The visiting periods are defined as follows: ' \
                'Between start date (inclusive) and end date (inclusive); ' \
                'Before end date (exclusive) with start date = 2000-01-01; ' \
                'After start date (exclusive) with end date = 2037-12-30.',
                properties: [
                  { name: 'rule', sticky: true, type: 'object',
                    hint: 'Boolean rule that defines visitor of a page. ' \
                    'Required for creating a date specific rule user list.',
                    properties: [
                      { name: 'ruleType',
                        control_type: 'select',
                        sticky: true,
                        pick_list: 'user_list_combined_rule_types',
                        toggle_hint: 'Select from options',
                        hint: 'Rule type is used to determine how to group rule items.',
                        toggle_field: {
                          name: 'ruleType',
                          label: 'Rule type',
                          type: 'string',
                          optional: true,
                          control_type: 'text',
                          toggle_hint: 'Use custom value',
                          hint: 'Allowed values are: AND_OF_ORS and OR_OF_ANDS.<br>' \
                          "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                          "customers.userLists#UserListRuleType' " \
                          "target='_blank'>here</a> for more details about the options."
                        } },
                      { name: 'ruleItemGroups', sticky: true, type: 'array', of: 'object',
                        hint: 'List of rule item groups that defines this rule. ' \
                        'Rule item groups are grouped together based on rule type.',
                        properties: [
                          { name: 'ruleItems', sticky: true, type: 'array', of: 'object',
                            hint: 'Rule items that will be grouped together based on rule type.',
                            properties: [
                              { name: 'name', sticky: true },
                              { name: 'numberRuleItem', sticky: true, type: 'object',
                                hint: 'An atomic rule item composed of a number operation.',
                                properties: [
                                  { name: 'operator',
                                    control_type: 'select',
                                    sticky: true,
                                    pick_list: 'user_list_number_rule_operators',
                                    toggle_hint: 'Select from options',
                                    hint: 'Number comparison operator.',
                                    toggle_field: {
                                      name: 'operator',
                                      label: 'Operator',
                                      type: 'string',
                                      optional: true,
                                      control_type: 'text',
                                      toggle_hint: 'Use custom value',
                                      hint: 'Allowed values are: GREATER_THAN, GREATER_THAN_OR_EQUAL, ' \
                                      'EQUALS, NOT_EQUALS, LESS_THAN, LESS_THAN_OR_EQUAL and OR_OF_ANDS.<br>' \
                                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                                      "customers.userLists#UserListNumberRuleItemOperator' " \
                                      "target='_blank'>here</a> for more details about the options."
                                    } },
                                  { name: 'value', sticky: true, control_type: 'number', type: 'number',
                                    hint: 'Number value to be compared with the variable.' }
                                ] },
                              { name: 'stringRuleItem', sticky: true, type: 'object',
                                hint: 'An atomic rule item composed of a string operation.',
                                properties: [
                                  { name: 'operator',
                                    control_type: 'select',
                                    sticky: true,
                                    pick_list: 'user_list_string_rule_operators',
                                    toggle_hint: 'Select from options',
                                    hint: 'String comparison operator.',
                                    toggle_field: {
                                      name: 'operator',
                                      label: 'Operator',
                                      type: 'string',
                                      optional: true,
                                      control_type: 'text',
                                      toggle_hint: 'Use custom value',
                                      hint: 'Allowed values are: CONTAINS, EQUALS, ' \
                                      'STARTS_WITH, ENDS_WITH, NOT_EQUALS, NOT_CONTAINS, ' \
                                      'NOT_STARTS_WITH and NOT_ENDS_WITH.<br>' \
                                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                                      "customers.userLists#UserListStringRuleItemOperator' " \
                                      "target='_blank'>here</a> for more details about the options."
                                    } },
                                  { name: 'value', sticky: true,
                                    hint: 'The right hand side of the string rule item. ' \
                                    'For URLs or referrer URLs, the value can not contain illegal ' \
                                    'URL characters such as newlines, quotes, tabs, or parentheses.' }
                                ] },
                              { name: 'dateRuleItem', sticky: true, type: 'object',
                                hint: 'An atomic rule item composed of a date operation.',
                                properties: [
                                  { name: 'operator',
                                    control_type: 'select',
                                    sticky: true,
                                    pick_list: 'user_list_date_rule_operators',
                                    toggle_hint: 'Select from options',
                                    hint: 'Date comparison operator.',
                                    toggle_field: {
                                      name: 'operator',
                                      label: 'Operator',
                                      type: 'string',
                                      optional: true,
                                      control_type: 'text',
                                      toggle_hint: 'Use custom value',
                                      hint: 'Allowed values are: EQUALS, NOT_EQUALS, BEFORE and AFTER.<br>' \
                                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                                      "customers.userLists#UserListDateRuleItemOperator' " \
                                      "target='_blank'>here</a> for more details about the options."
                                    } },
                                  { name: 'value', sticky: true, type: 'date', control_type: 'date',
                                    hint: 'String representing date value to be compared with the rule variable. ' \
                                    'Times are reported in the customer\'s time zone.' },
                                  { name: 'offsetInDays', sticky: true, type: 'date', control_type: 'date',
                                    hint: 'The relative date value of the right hand side ' \
                                    'denoted by number of days offset from now. ' \
                                    'The value field will override this field when both are present.' }
                                ] }
                            ] }
                        ] }
                    ] },
                  { name: 'startDate', sticky: true, type: 'date', control_type: 'date',
                    hint: 'Start date of users visit. ' \
                    'If set to 2000-01-01, then the list includes all users before end date.<br>' \
                    'Required for creating a data specific rule user list.' },
                  { name: 'endDate', sticky: true, type: 'date', control_type: 'date',
                    hint: 'Last date of users visit. ' \
                    'If set to 2037-12-30, then the list includes all users after start date.<br>' \
                    'Required for creating a data specific rule user list.' }
                ] },
              { name: 'expressionRuleUserList', sticky: true, type: 'object',
                hint: 'Visitors of a page. The page visit is defined by one boolean rule expression.',
                properties: [
                  { name: 'rule', sticky: true, type: 'object',
                    hint: 'Boolean rule that defines this user list. ' \
                    'The rule consists of a list of rule item groups and each ' \
                    'rule item group consists of a list of rule items.',
                    properties: [
                      { name: 'ruleType',
                        control_type: 'select',
                        sticky: true,
                        pick_list: 'user_list_combined_rule_types',
                        toggle_hint: 'Select from options',
                        hint: 'Rule type is used to determine how to group rule items.',
                        toggle_field: {
                          name: 'ruleType',
                          label: 'Rule type',
                          type: 'string',
                          optional: true,
                          control_type: 'text',
                          toggle_hint: 'Use custom value',
                          hint: 'Allowed values are: AND_OF_ORS and OR_OF_ANDS.<br>' \
                          "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                          "customers.userLists#UserListRuleType' " \
                          "target='_blank'>here</a> for more details about the options."
                        } },
                      { name: 'ruleItemGroups', sticky: true, type: 'array', of: 'object',
                        hint: 'List of rule item groups that defines this rule. ' \
                        'Rule item groups are grouped together based on rule type.',
                        properties: [
                          { name: 'ruleItems', sticky: true, type: 'array', of: 'object',
                            hint: 'Rule items that will be grouped together based on rule type.',
                            properties: [
                              { name: 'name', sticky: true },
                              { name: 'numberRuleItem', sticky: true, type: 'object',
                                hint: 'An atomic rule item composed of a number operation.',
                                properties: [
                                  { name: 'operator',
                                    control_type: 'select',
                                    sticky: true,
                                    pick_list: 'user_list_number_rule_operators',
                                    toggle_hint: 'Select from options',
                                    hint: 'Number comparison operator.',
                                    toggle_field: {
                                      name: 'operator',
                                      label: 'Operator',
                                      type: 'string',
                                      optional: true,
                                      control_type: 'text',
                                      toggle_hint: 'Use custom value',
                                      hint: 'Allowed values are: GREATER_THAN, GREATER_THAN_OR_EQUAL, ' \
                                      'EQUALS, NOT_EQUALS, LESS_THAN, LESS_THAN_OR_EQUAL and OR_OF_ANDS.<br>' \
                                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                                      "customers.userLists#UserListNumberRuleItemOperator' " \
                                      "target='_blank'>here</a> for more details about the options."
                                    } },
                                  { name: 'value', sticky: true, control_type: 'number', type: 'number',
                                    hint: 'Number value to be compared with the variable.' }
                                ] },
                              { name: 'stringRuleItem', sticky: true, type: 'object',
                                hint: 'An atomic rule item composed of a string operation.',
                                properties: [
                                  { name: 'operator',
                                    control_type: 'select',
                                    sticky: true,
                                    pick_list: 'user_list_string_rule_operators',
                                    toggle_hint: 'Select from options',
                                    hint: 'String comparison operator.',
                                    toggle_field: {
                                      name: 'operator',
                                      label: 'Operator',
                                      type: 'string',
                                      optional: true,
                                      control_type: 'text',
                                      toggle_hint: 'Use custom value',
                                      hint: 'Allowed values are: CONTAINS, EQUALS, ' \
                                      'STARTS_WITH, ENDS_WITH, NOT_EQUALS, NOT_CONTAINS, ' \
                                      'NOT_STARTS_WITH and NOT_ENDS_WITH.<br>' \
                                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                                      "customers.userLists#UserListStringRuleItemOperator' " \
                                      "target='_blank'>here</a> for more details about the options."
                                    } },
                                  { name: 'value', sticky: true,
                                    hint: 'The right hand side of the string rule item. ' \
                                    'For URLs or referrer URLs, the value can not contain illegal ' \
                                    'URL characters such as newlines, quotes, tabs, or parentheses.' }
                                ] },
                              { name: 'dateRuleItem', sticky: true, type: 'object',
                                hint: 'An atomic rule item composed of a date operation.',
                                properties: [
                                  { name: 'operator',
                                    control_type: 'select',
                                    sticky: true,
                                    pick_list: 'user_list_date_rule_operators',
                                    toggle_hint: 'Select from options',
                                    hint: 'Date comparison operator.',
                                    toggle_field: {
                                      name: 'operator',
                                      label: 'Operator',
                                      type: 'string',
                                      optional: true,
                                      control_type: 'text',
                                      toggle_hint: 'Use custom value',
                                      hint: 'Allowed values are: EQUALS, NOT_EQUALS, BEFORE and AFTER.<br>' \
                                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                                      "customers.userLists#UserListDateRuleItemOperator' " \
                                      "target='_blank'>here</a> for more details about the options."
                                    } },
                                  { name: 'value', sticky: true, type: 'date', control_type: 'date',
                                    hint: 'String representing date value to be compared with the rule variable. ' \
                                    'Times are reported in the customer\'s time zone.' },
                                  { name: 'offsetInDays', sticky: true, type: 'date', control_type: 'date',
                                    hint: 'The relative date value of the right hand side ' \
                                    'denoted by number of days offset from now. ' \
                                    'The value field will override this field when both are present.' }
                                ] }
                            ] }
                        ] }
                    ] }
                ] }
            ] },
          { name: 'logicalUserList', sticky: true, type: 'object',
            hint: 'User list that is a custom combination of user lists and user interests.',
            properties: [
              { name: 'rules', sticky: true, type: 'array', of: 'object',
                hint: 'Logical list rules that define this user list.',
                properties: [
                  { name: 'operator',
                    control_type: 'select',
                    sticky: true,
                    pick_list: 'user_list_logical_rule_operators',
                    toggle_hint: 'Select from options',
                    hint: 'The logical operator of the rule.',
                    toggle_field: {
                      name: 'operator',
                      label: 'Operator',
                      type: 'string',
                      optional: true,
                      control_type: 'text',
                      toggle_hint: 'Use custom value',
                      hint: 'Allowed values are: ALL, ANY and NONE.<br>' \
                      "Click <a href='https://developers.google.com/google-ads/api/rest/reference/rest/v8/" \
                      "customers.userLists#UserListLogicalRuleOperator' " \
                      "target='_blank'>here</a> for more details about the options."
                    } },
                  { name: 'ruleOperands', sticky: true, type: 'array', of: 'object',
                    hint: 'The list of operands of the rule.',
                    properties: [
                      { name: 'userList', sticky: true, hint: 'Resource name of a user list as an operand.' }
                    ] }
                ] }
            ] },
          { name: 'basicUserList', sticky: true, type: 'object',
            hint: 'User list targeting as a collection of conversion or remarketing actions.',
            properties: [
              { name: 'actions', sticky: true, type: 'array', of: 'object',
                hint: 'Actions associated with this user list.',
                properties: [
                  { name: 'conversionAction', sticky: true,
                    hint: 'A conversion action that\'s not generated from remarketing.' },
                  { name: 'remarketingAction', sticky: true,
                    hint: 'A remarketing action.' }
                ] }
            ] }
        ]
      end
    },
    ad_group: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'resourceName' },
          { name: 'status' },
          { name: 'type' },
          { name: 'adRotationMode' },
          { name: 'urlCustomParameters', type: 'array', of: 'object',
            properties: [
              { name: 'key' },
              { name: 'value' }
            ] },
          { name: 'explorerAutoOptimizerSetting', type: 'object',
            properties: [
              { name: 'optIn', type: 'boolean' }
            ] },
          { name: 'displayCustomBidDimension' },
          { name: 'targetingSetting', type: 'object',
            properties: [
              { name: 'targetRestrictions', type: 'array', of: 'object',
                properties: [
                  { name: 'targetingDimension' },
                  { name: 'bidOnly', type: 'boolean' }
                ] },
              { name: 'targetRestrictionOperations', type: 'array', of: 'object',
                properties: [
                  { name: 'operator' },
                  { name: 'value', type: 'object',
                    properties: [
                      { name: 'targetingDimension' },
                      { name: 'bidOnly', type: 'boolean' }
                    ] }
                ] }
            ] },
          { name: 'effectiveTargetCpaSource' },
          { name: 'effectiveTargetRoasSource' },
          { name: 'labels', type: 'array', of: 'string' },
          { name: 'excludedParentAssetFieldTypes', type: 'array', of: 'string' },
          { name: 'id' },
          { name: 'name' },
          { name: 'baseAdGroup' },
          { name: 'trackingUrlTemplate', label: 'Tracking URL template' },
          { name: 'campaign' },
          { name: 'cpcBidMicros', label: 'CPC bid micros' },
          { name: 'cpmBidMicros', label: 'CPM bid micros' },
          { name: 'targetCpaMicros', label: 'Target CPA micros' },
          { name: 'cpvBidMicros', label: 'CPV bid micros' },
          { name: 'targetCpmMicros', label: 'Target CPM micros' },
          { name: 'targetRoas', label: 'Target ROAS', type: 'number' },
          { name: 'percentCpcBidMicros', label: 'Percent CPC bid micros' },
          { name: 'finalUrlSuffix', label: 'Final URL Suffix' },
          { name: 'effectiveTargetCpaMicros', label: 'Effective target CPA micros' },
          { name: 'effectiveTargetRoas', label: 'Effective target ROAS' }
        ]
      end
    },
    ad_group_ad: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        policy_summary =
          [
            { name: 'policyTopicEntries', type: 'array', of: 'object',
              properties: [
                { name: 'type' },
                { name: 'topic' },
                { name: 'evidences', type: 'array', of: 'object',
                  properties: [
                    { name: 'websiteList', type: 'object',
                      properties: [
                        { name: 'websites', type: 'array', of: 'string' }
                      ] },
                    { name: 'textList', type: 'object',
                      properties: [
                        { name: 'texts', type: 'array', of: 'string' }
                      ] },
                    { name: 'destinationTextList', type: 'object',
                      properties: [
                        { name: 'destinationTexts', type: 'array', of: 'string' }
                      ] },
                    { name: 'destinationMismatch', type: 'object',
                      properties: [
                        { name: 'urlTypes', type: 'array', of: 'string' }
                      ] },
                    { name: 'destinationNotWorking', type: 'object',
                      properties: [
                        { name: 'device' },
                        { name: 'expandedUrl' },
                        { name: 'lastCheckedDateTime' },
                        { name: 'dnsErrorType' },
                        { name: 'httpErrorCode' }
                      ] },
                    { name: 'languageCode' }
                  ] },
                { name: 'constraints', type: 'array', of: 'object',
                  properties: [
                    { name: 'countryConstraintList', type: 'object',
                      properties: [
                        { name: 'countries', type: 'array', of: 'object',
                          properties: [
                            { name: 'countryCriterion' }
                          ] },
                        { name: 'totalTargetedCountries', type: 'integer' }
                      ] },
                    { name: 'resellerConstraint' },
                    { name: 'certificateMissingInCountryList', type: 'object',
                      properties: [
                        { name: 'countries', type: 'array', of: 'object',
                          properties: [
                            { name: 'countryCriterion' }
                          ] },
                        { name: 'totalTargetedCountries', type: 'integer' }
                      ] },
                    { name: 'certificateDomainMismatchInCountryList', type: 'object',
                      properties: [
                        { name: 'countries', type: 'array', of: 'object',
                          properties: [
                            { name: 'countryCriterion' }
                          ] },
                        { name: 'totalTargetedCountries', type: 'integer' }
                      ] }
                  ] }
              ] },
            { name: 'reviewStatus' },
            { name: 'approvalStatus' }
          ]
        [
          { name: 'resourceName' },
          { name: 'status' },
          { name: 'ad', type: 'object',
            properties: [
              { name: 'resourceName' },
              { name: 'finalUrls', label: 'Final URLs', type: 'array', of: 'object' },
              { name: 'finalAppUrls', label: 'Final app URLs', type: 'array', of: 'object',
                properties: [
                  { name: 'osType', label: 'OS type' },
                  { name: 'url', label: 'URL' }
                ] },
              { name: 'finalMobileUrls', label: 'Final mobile URLs', type: 'array', of: 'string' },
              { name: 'urlCustomParameters', type: 'array', of: 'object',
                properties: [
                  { name: 'key' },
                  { name: 'value' }
                ] },
              { name: 'type' },
              { name: 'devicePreference' },
              { name: 'urlCollections', label: 'URL collections', type: 'array', of: 'object',
                properties: [
                  { name: 'finalUrls', label: 'Final URLs', type: 'array', of: 'string' },
                  { name: 'finalMobileUrls', label: 'Final mobile URLs', type: 'array', of: 'string' },
                  { name: 'urlCollectionId', label: 'URL collection ID' },
                  { name: 'trackingUrlTemplate', label: 'Tracking URL template' }
                ] },
              { name: 'systemManagedResourceSource' },
              { name: 'id' },
              { name: 'trackingUrlTemplate' },
              { name: 'finalUrlSuffix' },
              { name: 'displayUrl' },
              { name: 'addedByGoogleAds', type: 'boolean' },
              { name: 'name' },
              { name: 'textAd', type: 'object',
                properties: [
                  { name: 'headline' },
                  { name: 'description1' },
                  { name: 'description2' }
                ] },
              { name: 'expandedTextAd', type: 'object',
                properties: [
                  { name: 'headlinePart1' },
                  { name: 'headlinePart2' },
                  { name: 'headlinePart3' },
                  { name: 'description1' },
                  { name: 'description2' },
                  { name: 'path1' },
                  { name: 'path2' }
                ] },
              { name: 'callAd', type: 'object',
                properties: [
                  { name: 'countryCode' },
                  { name: 'phoneNumber' },
                  { name: 'businessName' },
                  { name: 'headline1' },
                  { name: 'headline2' },
                  { name: 'description1' },
                  { name: 'description2' },
                  { name: 'callTracked', type: 'boolean' },
                  { name: 'disableCallConversion', type: 'boolean' },
                  { name: 'phoneNumberVerificationUrl', label: 'Phone number verification URL' },
                  { name: 'conversionAction' },
                  { name: 'conversionReportingState' },
                  { name: 'path1' },
                  { name: 'path2' }
                ] },
              { name: 'expandedDynamicSearchAd', type: 'object',
                properties: [
                  { name: 'description' },
                  { name: 'description2' }
                ] },
              { name: 'hotelAd' },
              { name: 'shoppingSmartAd' },
              { name: 'shoppingProductAd' },
              { name: 'gmailAd', type: 'object',
                properties: [
                  { name: 'teaser', type: 'object',
                    properties: [
                      { name: 'headline' },
                      { name: 'description' },
                      { name: 'businessName' },
                      { name: 'logoImage' }
                    ] },
                  { name: 'marketingImageDisplayCallToAction', type: 'object',
                    properties: [
                      { name: 'text' },
                      { name: 'textColor' },
                      { name: 'urlCollectionId', label: 'URL collection ID' }
                    ] },
                  { name: 'productImages', type: 'array', of: 'object',
                    properties: [
                      { name: 'displayCallToAction', type: 'object',
                        properties: [
                          { name: 'text' },
                          { name: 'textColor' },
                          { name: 'urlCollectionId', label: 'URL collection ID' }
                        ] },
                      { name: 'productImage' },
                      { name: 'description' }
                    ] },
                  { name: 'productVideos', type: 'array', of: 'object',
                    properties: [
                      { name: 'productVideo' }
                    ] },
                  { name: 'headerImage' },
                  { name: 'marketingImage' },
                  { name: 'marketingImageHeadline' },
                  { name: 'marketingImageDescription' }
                ] },
              { name: 'imageAd', type: 'object',
                properties: [
                  { name: 'mimeType' },
                  { name: 'pixelWidth' },
                  { name: 'pixelHeight' },
                  { name: 'imageUrl' },
                  { name: 'previewPixelWidth' },
                  { name: 'previewPixelHeight' },
                  { name: 'previewImageUrl' },
                  { name: 'name' },
                  { name: 'mediaFile' },
                  { name: 'data' },
                  { name: 'adIdToCopyImageFrom' }
                ] },
              { name: 'videoAd', type: 'object',
                properties: [
                  { name: 'video', type: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'inStream', type: 'object',
                    properties: [
                      { name: 'actionButtonLabel' },
                      { name: 'actionHeadline' },
                      { name: 'companionBanner', type: 'object',
                        properties: [
                          { name: 'asset' }
                        ] }
                    ] },
                  { name: 'bumper', type: 'object',
                    properties: [
                      { name: 'companionBanner', type: 'object',
                        properties: [
                          { name: 'asset' }
                        ] }
                    ] },
                  { name: 'outStream', type: 'object',
                    properties: [
                      { name: 'headline' },
                      { name: 'description' }
                    ] },
                  { name: 'nonSkippable', type: 'object',
                    properties: [
                      { name: 'actionButtonLabel' },
                      { name: 'actionHeadline' },
                      { name: 'companionBanner', type: 'object',
                        properties: [
                          { name: 'asset' }
                        ] }
                    ] },
                  { name: 'discovery', type: 'object',
                    properties: [
                      { name: 'headline' },
                      { name: 'description1' },
                      { name: 'description2' },
                      { name: 'thumbnail' }
                    ] }
                ] },
              { name: 'videoResponsiveAd', type: 'object',
                properties: [
                  { name: 'headlines', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'longHeadlines', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'descriptions', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'callToActions', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'videos', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'companionBanners', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] }
                ] },
              { name: 'videoResponsiveAd', type: 'object',
                properties: [
                  { name: 'headlines', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'descriptions', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'path1' },
                  { name: 'path2' }
                ] },
              { name: 'legacyResponsiveDisplayAd', type: 'object',
                properties: [
                  { name: 'formatSetting' },
                  { name: 'shortHeadline' },
                  { name: 'longHeadline' },
                  { name: 'description' },
                  { name: 'businessName' },
                  { name: 'allowFlexibleColor', type: 'boolean' },
                  { name: 'accentColor' },
                  { name: 'mainColor' },
                  { name: 'callToActionText' },
                  { name: 'logoImage' },
                  { name: 'squareLogoImage' },
                  { name: 'marketingImage' },
                  { name: 'squareMarketingImage' },
                  { name: 'pricePrefix' },
                  { name: 'promoText' }
                ] },
              { name: 'appAd', type: 'object',
                properties: [
                  { name: 'mandatoryAdText', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'headlines', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'descriptions', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'images', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'youtubeVideos', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'html5MediaBundles', label: 'HTML 5 media bundles', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] }
                ] },
              { name: 'legacyAppInstallAd', type: 'object',
                properties: [
                  { name: 'appStore' },
                  { name: 'appId' },
                  { name: 'headline' },
                  { name: 'description1' },
                  { name: 'description2' }
                ] },
              { name: 'responsiveDisplayAd', type: 'object',
                properties: [
                  { name: 'headlines', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'longHeadline', type: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'descriptions', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'youtubeVideos', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'marketingImages', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'squareMarketingImages', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'logoImages', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'squareLogoImages', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'formatSetting' },
                  { name: 'controlSpec', type: 'object',
                    properties: [
                      { name: 'enableAssetEnhancements', type: 'boolean' },
                      { name: 'enableAutogenVideo', type: 'boolean' }
                    ] },
                  { name: 'businessName' },
                  { name: 'mainColor' },
                  { name: 'accentColor' },
                  { name: 'allowFlexibleColor', type: 'boolean' },
                  { name: 'callToActionText' },
                  { name: 'pricePrefix' },
                  { name: 'promoText' }
                ] },
              { name: 'localAd', type: 'object',
                properties: [
                  { name: 'headlines', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'callToActions', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'descriptions', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'marketingImages', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'logoImages', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'videos', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'path1' },
                  { name: 'path2' }
                ] },
              { name: 'displayUploadAd', type: 'object',
                properties: [
                  { name: 'displayUploadProductType' },
                  { name: 'mediaBundle', type: 'object',
                    properties: [
                      { name: 'asset' }
                    ] }
                ] },
              { name: 'appEngagementAd', type: 'object',
                properties: [
                  { name: 'headlines', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'descriptions', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'images', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'videos', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] }
                ] },
              { name: 'shoppingComparisonListingAd', type: 'object',
                properties: [
                  { name: 'headline' }
                ] },
              { name: 'smartCampaignAd', type: 'object',
                properties: [
                  { name: 'headlines', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'descriptions', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] }
                ] },
              { name: 'appPreRegistrationAd', type: 'object',
                properties: [
                  { name: 'headlines', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'descriptions', type: 'array', of: 'object',
                    properties: [
                      { name: 'pinnedField' },
                      { name: 'assetPerformanceLabel' },
                      { name: 'text' },
                      { name: 'policySummaryInfo', type: 'object',
                        properties: policy_summary }
                    ] },
                  { name: 'images', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] },
                  { name: 'youtubeVideos', type: 'array', of: 'object',
                    properties: [
                      { name: 'asset' }
                    ] }
                ] }
            ] },
          { name: 'policySummary', type: 'object',
            properties: policy_summary },
          { name: 'adStrength' },
          { name: 'actionItems', type: 'array', of: 'string' },
          { name: 'labels', type: 'array', of: 'string' },
          { name: 'adGroup' }
        ]
      end
    },
    report: {
      fields: lambda do |_connection, config_fields|
        case config_fields['report_type']
        when 'customer'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'manager'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                },
                {
                  name: 'autoTaggingEnabled'
                },
                {
                  name: 'testAccount'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'contentBudgetLostImpressionShare'
                },
                {
                  name: 'contentImpressionShare'
                },
                {
                  name: 'contentRankLostImpressionShare'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'invalidClickRate'
                },
                {
                  name: 'invalidClicks'
                },
                {
                  name: 'searchBudgetLostImpressionShare'
                },
                {
                  name: 'searchExactMatchImpressionShare'
                },
                {
                  name: 'searchImpressionShare'
                },
                {
                  name: 'searchRankLostImpressionShare'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionAdjustment'
                },
                {
                  name: 'conversionOrAdjustmentLagBucket'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionLagBucket'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'hour'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'slot'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            }
          ]
        when 'ad_group_ad'
          [
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'absoluteTopImpressionPercentage'
                },
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'averagePageViews'
                },
                {
                  name: 'averageTimeOnSite'
                },
                {
                  name: 'bounceRate'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'costPerCurrentModelAttributedConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'currentModelAttributedConversionsValue'
                },
                {
                  name: 'currentModelAttributedConversions'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'gmailForwards'
                },
                {
                  name: 'gmailSaves'
                },
                {
                  name: 'gmailSecondaryClicks'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'percentNewVisitors'
                },
                {
                  name: 'topImpressionPercentage'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'valuePerCurrentModelAttributedConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'adGroupAd',
              type: 'object',
              properties: [
                {
                  name: 'ad',
                  type: 'object',
                  properties: [
                    {
                      name: 'legacyResponsiveDisplayAd',
                      type: 'object',
                      properties: [
                        {
                          name: 'accentColor'
                        },
                        {
                          name: 'allowFlexibleColor'
                        },
                        {
                          name: 'businessName'
                        },
                        {
                          name: 'callToActionText'
                        },
                        {
                          name: 'description'
                        },
                        {
                          name: 'logoImage'
                        },
                        {
                          name: 'squareLogoImage'
                        },
                        {
                          name: 'marketingImage'
                        },
                        {
                          name: 'squareMarketingImage'
                        },
                        {
                          name: 'formatSetting'
                        },
                        {
                          name: 'longHeadline'
                        },
                        {
                          name: 'mainColor'
                        },
                        {
                          name: 'pricePrefix'
                        },
                        {
                          name: 'promoText'
                        },
                        {
                          name: 'shortHeadline'
                        }
                      ]
                    },
                    {
                      name: 'callAd',
                      type: 'object',
                      properties: [
                        {
                          name: 'phoneNumber'
                        }
                      ]
                    },
                    {
                      name: 'textAd',
                      type: 'object',
                      properties: [
                        {
                          name: 'description1'
                        },
                        {
                          name: 'description2'
                        },
                        {
                          name: 'headline'
                        }
                      ]
                    },
                    {
                      name: 'expandedDynamicSearchAd',
                      type: 'object',
                      properties: [
                        {
                          name: 'description'
                        }
                      ]
                    },
                    {
                      name: 'expandedTextAd',
                      type: 'object',
                      properties: [
                        {
                          name: 'description2'
                        },
                        {
                          name: 'headlinePart3'
                        },
                        {
                          name: 'headlinePart1'
                        },
                        {
                          name: 'headlinePart2'
                        },
                        {
                          name: 'path1'
                        },
                        {
                          name: 'path2'
                        }
                      ]
                    },
                    {
                      name: 'gmailAd',
                      type: 'object',
                      properties: [
                        { name: 'teaser',
                          type: 'object',
                          properties: [
                            {
                              name: 'logoImage'
                            },
                            {
                              name: 'businessName'
                            },
                            {
                              name: 'description'
                            },
                            {
                              name: 'headline'
                            }
                          ] },
                        { name: 'marketingImageDisplayCallToAction',
                          type: 'object',
                          properties: [
                            {
                              name: 'text'
                            },
                            {
                              name: 'textColor'
                            }
                          ] },
                        {
                          name: 'headerImage'
                        },
                        {
                          name: 'marketingImage'
                        },
                        {
                          name: 'marketingImageHeadline'
                        },
                        {
                          name: 'marketingImageDescription'
                        }
                      ]
                    },
                    {
                      name: 'imageAd',
                      type: 'object',
                      properties: [
                        {
                          name: 'imageUrl'
                        },
                        {
                          name: 'pixelHeight'
                        },
                        {
                          name: 'pixelWidth'
                        },
                        {
                          name: 'mimeType'
                        },
                        {
                          name: 'name'
                        }
                      ]
                    },
                    {
                      name: 'responsiveDisplayAd',
                      type: 'object',
                      properties: [
                        {
                          name: 'accentColor'
                        },
                        {
                          name: 'allowFlexibleColor'
                        },
                        {
                          name: 'businessName'
                        },
                        {
                          name: 'callToActionText'
                        },
                        {
                          name: 'descriptions'
                        },
                        {
                          name: 'pricePrefix'
                        },
                        {
                          name: 'promoText'
                        },
                        {
                          name: 'formatSetting'
                        },
                        {
                          name: 'headlines'
                        },
                        {
                          name: 'logoImages'
                        },
                        {
                          name: 'squareLogoImages'
                        },
                        {
                          name: 'longHeadline'
                        },
                        {
                          name: 'mainColor'
                        },
                        {
                          name: 'marketingImages'
                        },
                        {
                          name: 'squareMarketingImages'
                        },
                        {
                          name: 'youtubeVideos'
                        }
                      ]
                    },
                    {
                      name: 'responsiveSearchAd',
                      type: 'object',
                      properties: [
                        {
                          name: 'descriptions'
                        },
                        {
                          name: 'headlines'
                        },
                        {
                          name: 'path1'
                        },
                        {
                          name: 'path2'
                        }
                      ]
                    },
                    {
                      name: 'appAd',
                      type: 'object',
                      properties: [
                        {
                          name: 'descriptions'
                        },
                        {
                          name: 'headlines'
                        },
                        {
                          name: 'html5MediaBundles'
                        },
                        {
                          name: 'images'
                        },
                        {
                          name: 'mandatoryAdText'
                        },
                        {
                          name: 'youtubeVideos'
                        }
                      ]
                    },
                    {
                      name: 'type'
                    },
                    {
                      name: 'addedByGoogleAds'
                    },
                    {
                      name: 'finalMobileUrls'
                    },
                    {
                      name: 'finalUrls'
                    },
                    {
                      name: 'trackingUrlTemplate'
                    },
                    {
                      name: 'urlCustomParameters'
                    },
                    {
                      name: 'devicePreference'
                    },
                    {
                      name: 'displayUrl'
                    },
                    {
                      name: 'id'
                    },
                    {
                      name: 'systemManagedResourceSource'
                    }
                  ]
                },
                {
                  name: 'policySummary',
                  type: 'object',
                  properties: [
                    {
                      name: 'approvalStatus'
                    },
                    {
                      name: 'policyTopicEntries'
                    },
                    {
                      name: 'reviewState'
                    },
                    {
                      name: 'approvalStatus'
                    }
                  ]
                },
                {
                  name: 'adStrength'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                },
                {
                  name: 'baseAdGroup'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'keyword',
                  type: 'object',
                  properties: [
                    {
                      name: 'adGroupCriterion'
                    }
                  ]
                },
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionAdjustment'
                },
                {
                  name: 'conversionOrAdjustmentLagBucket'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionLagBucket'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'slot'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'baseCampaign'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupCriterion',
              type: 'object',
              properties: [
                {
                  name: 'negative'
                }
              ]
            }
          ]
        when 'ad_group'
          [
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'absoluteTopImpressionPercentage'
                },
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'averagePageViews'
                },
                {
                  name: 'averageTimeOnSite'
                },
                {
                  name: 'bounceRate'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'contentImpressionShare'
                },
                {
                  name: 'contentRankLostImpressionShare'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'costPerCurrentModelAttributedConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'currentModelAttributedConversionsValue'
                },
                {
                  name: 'currentModelAttributedConversions'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'gmailForwards'
                },
                {
                  name: 'gmailSaves'
                },
                {
                  name: 'gmailSecondaryClicks'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'phoneImpressions'
                },
                {
                  name: 'phoneCalls'
                },
                {
                  name: 'phoneThroughRate'
                },
                {
                  name: 'percentNewVisitors'
                },
                {
                  name: 'relativeCtr'
                },
                {
                  name: 'searchAbsoluteTopImpressionShare'
                },
                {
                  name: 'searchBudgetLostAbsoluteTopImpressionShare'
                },
                {
                  name: 'searchBudgetLostTopImpressionShare'
                },
                {
                  name: 'searchExactMatchImpressionShare'
                },
                {
                  name: 'searchImpressionShare'
                },
                {
                  name: 'searchRankLostAbsoluteTopImpressionShare'
                },
                {
                  name: 'searchRankLostImpressionShare'
                },
                {
                  name: 'searchRankLostTopImpressionShare'
                },
                {
                  name: 'searchTopImpressionShare'
                },
                {
                  name: 'topImpressionPercentage'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'valuePerCurrentModelAttributedConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                },
                {
                  name: 'type'
                },
                {
                  name: 'adRotationMode'
                },
                {
                  name: 'baseAdGroup'
                },
                {
                  name: 'displayCustomBidDimension'
                },
                {
                  name: 'cpcBidMicros'
                },
                {
                  name: 'cpmBidMicros'
                },
                {
                  name: 'cpvBidMicros'
                },
                {
                  name: 'effectiveTargetRoas'
                },
                {
                  name: 'effectiveTargetRoasSource'
                },
                {
                  name: 'finalUrlSuffix'
                },
                {
                  name: 'effectiveTargetCpaMicros'
                },
                {
                  name: 'effectiveTargetCpaSource'
                },
                {
                  name: 'trackingUrlTemplate'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionAdjustment'
                },
                {
                  name: 'conversionOrAdjustmentLagBucket'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionLagBucket'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'hour'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'slot'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'baseCampaign'
                },
                {
                  name: 'biddingStrategy'
                },
                {
                  name: 'biddingStrategyType'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            }
          ]
        when 'age_range_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'gmailForwards'
                },
                {
                  name: 'gmailSaves'
                },
                {
                  name: 'gmailSecondaryClicks'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'targetingSetting',
                  type: 'object',
                  properties: [
                    {
                      name: 'targetRestrictions'
                    }
                  ]
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                },
                {
                  name: 'baseAdGroup'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'baseCampaign'
                },
                {
                  name: 'biddingStrategy'
                },
                {
                  name: 'biddingStrategyType'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupCriterion',
              type: 'object',
              properties: [
                {
                  name: 'ageRange',
                  type: 'object',
                  properties: [
                    {
                      name: 'type'
                    }
                  ]
                },
                {
                  name: 'bidModifier'
                },
                {
                  name: 'effectiveCpcBidMicros'
                },
                {
                  name: 'effectiveCpcBidSource'
                },
                {
                  name: 'effectiveCpmBidMicros'
                },
                {
                  name: 'effectiveCpmBidSource'
                },
                {
                  name: 'finalMobileUrls'
                },
                {
                  name: 'finalUrls'
                },
                {
                  name: 'criterionId'
                },
                {
                  name: 'negative'
                },
                {
                  name: 'status'
                },
                {
                  name: 'trackingUrlTemplate'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            },
            {
              name: 'biddingStrategy',
              type: 'object',
              properties: [
                {
                  name: 'name'
                }
              ]
            }
          ]
        when 'campaign_audience_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'gmailForwards'
                },
                {
                  name: 'gmailSaves'
                },
                {
                  name: 'gmailSecondaryClicks'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'targetingSetting',
                  type: 'object',
                  properties: [
                    {
                      name: 'targetRestrictions'
                    }
                  ]
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                },
                {
                  name: 'baseAdGroup'
                },
                {
                  name: 'campaign'
                },
                {
                  name: 'trackingUrlTemplate'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'slot'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'baseCampaign'
                },
                {
                  name: 'biddingStrategy'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'raw',
              type: 'object',
              properties: [
                {
                  name: 'view'
                },
                {
                  name: 'view'
                }
              ]
            },
            {
              name: 'adGroupCriterion',
              type: 'object',
              properties: [
                {
                  name: 'effectiveCpcBidSource'
                },
                {
                  name: 'effectiveCpmBidMicros'
                },
                {
                  name: 'effectiveCpmBidSource'
                },
                {
                  name: 'finalMobileUrls'
                },
                {
                  name: 'finalUrls'
                },
                {
                  name: 'criterionId'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'userList',
              type: 'object',
              properties: [
                {
                  name: 'name'
                }
              ]
            }
          ]
        when 'ad_group_audience_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'gmailForwards'
                },
                {
                  name: 'gmailSaves'
                },
                {
                  name: 'gmailSecondaryClicks'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'targetingSetting',
                  type: 'object',
                  properties: [
                    {
                      name: 'targetRestrictions'
                    }
                  ]
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                },
                {
                  name: 'baseAdGroup'
                },
                {
                  name: 'campaign'
                },
                {
                  name: 'trackingUrlTemplate'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'slot'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'baseCampaign'
                },
                {
                  name: 'biddingStrategy'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupCriterion',
              type: 'object',
              properties: [
                {
                  name: 'effectiveCpcBidSource'
                },
                {
                  name: 'effectiveCpmBidMicros'
                },
                {
                  name: 'effectiveCpmBidSource'
                },
                {
                  name: 'finalMobileUrls'
                },
                {
                  name: 'finalUrls'
                },
                {
                  name: 'criterionId'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'userList',
              type: 'object',
              properties: [
                {
                  name: 'name'
                }
              ]
            }
          ]
        when 'group_placement_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'groupPlacementView',
              type: 'object',
              properties: [
                {
                  name: 'placementType'
                },
                {
                  name: 'targetUrl', label: 'Target URL'
                }
              ]
            }
          ]
        when 'bidding_strategy'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'biddingStrategy',
              type: 'object',
              properties: [
                {
                  name: 'targetCpa',
                  type: 'object',
                  properties: [
                    {
                      name: 'targetCpaMicros'
                    },
                    {
                      name: 'cpcBidCeilingMicros'
                    },
                    {
                      name: 'cpcBidFloorMicros'
                    }
                  ]
                },
                {
                  name: 'targetRoas',
                  type: 'object',
                  properties: [
                    {
                      name: 'targetRoas'
                    },
                    {
                      name: 'cpcBidCeilingMicros'
                    },
                    {
                      name: 'cpcBidFloorMicros'
                    }
                  ]
                },
                {
                  name: 'targetSpend',
                  type: 'object',
                  properties: [
                    {
                      name: 'cpcBidCeilingMicros'
                    },
                    {
                      name: 'targetSpendMicros'
                    }
                  ]
                },
                {
                  name: 'campaignCount'
                },
                {
                  name: 'id'
                },
                {
                  name: 'nonRemovedCampaignCount'
                },
                {
                  name: 'status'
                },
                {
                  name: 'type'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'hour'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            }
          ]
        when 'campaign_budget'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'campaignBudget',
              type: 'object',
              properties: [
                {
                  name: 'amountMicros'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'referenceCount'
                },
                {
                  name: 'status'
                },
                {
                  name: 'deliveryMethod'
                },
                {
                  name: 'hasRecommendedBudget'
                },
                {
                  name: 'explicitlyShared'
                },
                {
                  name: 'period'
                },
                {
                  name: 'recommendedBudgetAmountMicros'
                },
                {
                  name: 'recommendedBudgetEstimatedChangeWeeklyClicks'
                },
                {
                  name: 'recommendedBudgetEstimatedChangeWeeklyCostMicros'
                },
                {
                  name: 'recommendedBudgetEstimatedChangeWeeklyInteractions'
                },
                {
                  name: 'recommendedBudgetEstimatedChangeWeeklyViews'
                },
                {
                  name: 'totalAmountMicros'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'budgetCampaignAssociationStatus',
                  type: 'object',
                  properties: [
                    {
                      name: 'status'
                    }
                  ]
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'externalConversionSource'
                }
              ]
            }
          ]
        when 'call_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'callView',
              type: 'object',
              properties: [
                {
                  name: 'callDurationSeconds'
                },
                {
                  name: 'endCallDateTime'
                },
                {
                  name: 'startCallDateTime'
                },
                {
                  name: 'callStatus'
                },
                {
                  name: 'callTrackingDisplayLocation'
                },
                {
                  name: 'type'
                },
                {
                  name: 'callerAreaCode'
                },
                {
                  name: 'callerCountryCode'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'hour'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            }
          ]
        when 'ad_schedule_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'campaignCriterion',
              type: 'object',
              properties: [
                {
                  name: 'bidModifier'
                },
                {
                  name: 'criterionId'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            }
          ]
        when 'campaign_criterion'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'baseCampaign'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'campaignCriterion',
              type: 'object',
              properties: [
                {
                  name: 'keyword',
                  type: 'object',
                  properties: [
                    {
                      name: 'text'
                    }
                  ]
                },
                {
                  name: 'type'
                },
                {
                  name: 'criterionId'
                },
                {
                  name: 'negative'
                }
              ]
            }
          ]
        when 'campaign'
          [
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'absoluteTopImpressionPercentage'
                },
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'averagePageViews'
                },
                {
                  name: 'averageTimeOnSite'
                },
                {
                  name: 'bounceRate'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'contentBudgetLostImpressionShare'
                },
                {
                  name: 'contentImpressionShare'
                },
                {
                  name: 'contentRankLostImpressionShare'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'costPerCurrentModelAttributedConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'currentModelAttributedConversionsValue'
                },
                {
                  name: 'currentModelAttributedConversions'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'gmailForwards'
                },
                {
                  name: 'gmailSaves'
                },
                {
                  name: 'gmailSecondaryClicks'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'invalidClickRate'
                },
                {
                  name: 'invalidClicks'
                },
                {
                  name: 'phoneImpressions'
                },
                {
                  name: 'phoneCalls'
                },
                {
                  name: 'phoneThroughRate'
                },
                {
                  name: 'percentNewVisitors'
                },
                {
                  name: 'relativeCtr'
                },
                {
                  name: 'searchAbsoluteTopImpressionShare'
                },
                {
                  name: 'searchBudgetLostAbsoluteTopImpressionShare'
                },
                {
                  name: 'searchBudgetLostImpressionShare'
                },
                {
                  name: 'searchBudgetLostTopImpressionShare'
                },
                {
                  name: 'searchClickShare'
                },
                {
                  name: 'searchExactMatchImpressionShare'
                },
                {
                  name: 'searchImpressionShare'
                },
                {
                  name: 'searchRankLostAbsoluteTopImpressionShare'
                },
                {
                  name: 'searchRankLostImpressionShare'
                },
                {
                  name: 'searchRankLostTopImpressionShare'
                },
                {
                  name: 'searchTopImpressionShare'
                },
                {
                  name: 'topImpressionPercentage'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'valuePerCurrentModelAttributedConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionAdjustment'
                },
                {
                  name: 'conversionOrAdjustmentLagBucket'
                },
                {
                  name: 'conversionAttributionEventType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionLagBucket'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'hour'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'slot'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'maximizeConversionValue',
                  type: 'object',
                  properties: [
                    {
                      name: 'targetRoas'
                    }
                  ]
                },
                {
                  name: 'advertisingChannelSubType'
                },
                {
                  name: 'advertisingChannelType'
                },
                {
                  name: 'baseCampaign'
                },
                {
                  name: 'biddingStrategy'
                },
                {
                  name: 'biddingStrategyType'
                },
                {
                  name: 'campaignBudget'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                },
                {
                  name: 'experimentType'
                },
                {
                  name: 'endDate'
                },
                {
                  name: 'finalUrlSuffix'
                },
                {
                  name: 'servingStatus'
                },
                {
                  name: 'startDate'
                },
                {
                  name: 'trackingUrlTemplate'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            },
            {
              name: 'campaignBudget',
              type: 'object',
              properties: [
                {
                  name: 'amountMicros'
                },
                {
                  name: 'hasRecommendedBudget'
                },
                {
                  name: 'explicitlyShared'
                },
                {
                  name: 'period'
                },
                {
                  name: 'recommendedBudgetAmountMicros'
                },
                {
                  name: 'totalAmountMicros'
                }
              ]
            },
            {
              name: 'biddingStrategy',
              type: 'object',
              properties: [
                {
                  name: 'name'
                }
              ]
            }
          ]
        when 'campaign_shared_set'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'sharedSet',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'type'
                }
              ]
            },
            {
              name: 'campaignSharedSet',
              type: 'object',
              properties: [
                {
                  name: 'status'
                }
              ]
            }
          ]
        when 'location_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'campaignCriterion',
              type: 'object',
              properties: [
                {
                  name: 'bidModifier'
                },
                {
                  name: 'criterionId'
                },
                {
                  name: 'negative'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            }
          ]
        when 'click_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'date'
                },
                {
                  name: 'device'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'slot'
                }
              ]
            },
            {
              name: 'clickView',
              type: 'object',
              properties: [
                {
                  name: 'areaOfInterest',
                  type: 'object',
                  properties: [
                    {
                      name: 'city'
                    },
                    {
                      name: 'country'
                    },
                    {
                      name: 'metro'
                    },
                    {
                      name: 'mostSpecific'
                    },
                    {
                      name: 'region'
                    }
                  ]
                },
                {
                  name: 'locationOfPresence',
                  type: 'object',
                  properties: [
                    {
                      name: 'city'
                    },
                    {
                      name: 'country'
                    },
                    {
                      name: 'metro'
                    },
                    {
                      name: 'mostSpecific'
                    },
                    {
                      name: 'region'
                    }
                  ]
                },
                {
                  name: 'campaignLocationTarget'
                },
                {
                  name: 'adGroupAd'
                },
                {
                  name: 'gclid'
                },
                {
                  name: 'pageNumber'
                },
                {
                  name: 'userList'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'clicks'
                }
              ]
            }
          ]
        when 'display_keyword_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'gmailForwards'
                },
                {
                  name: 'gmailSaves'
                },
                {
                  name: 'gmailSecondaryClicks'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'targetingSetting',
                  type: 'object',
                  properties: [
                    {
                      name: 'targetRestrictions'
                    }
                  ]
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                },
                {
                  name: 'baseAdGroup'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'baseCampaign'
                },
                {
                  name: 'biddingStrategy'
                },
                {
                  name: 'biddingStrategyType'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupCriterion',
              type: 'object',
              properties: [
                {
                  name: 'keyword',
                  type: 'object',
                  properties: [
                    {
                      name: 'text'
                    }
                  ]
                },
                {
                  name: 'effectiveCpcBidMicros'
                },
                {
                  name: 'effectiveCpcBidSource'
                },
                {
                  name: 'effectiveCpmBidMicros'
                },
                {
                  name: 'effectiveCpmBidSource'
                },
                {
                  name: 'effectiveCpvBidMicros'
                },
                {
                  name: 'effectiveCpvBidSource'
                },
                {
                  name: 'finalMobileUrls'
                },
                {
                  name: 'finalUrls'
                },
                {
                  name: 'criterionId'
                },
                {
                  name: 'negative'
                },
                {
                  name: 'status'
                },
                {
                  name: 'trackingUrlTemplate'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            }
          ]
        when 'topic_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'gmailForwards'
                },
                {
                  name: 'gmailSaves'
                },
                {
                  name: 'gmailSecondaryClicks'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'targetingSetting',
                  type: 'object',
                  properties: [
                    {
                      name: 'targetRestrictions'
                    }
                  ]
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                },
                {
                  name: 'baseAdGroup'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'baseCampaign'
                },
                {
                  name: 'biddingStrategy'
                },
                {
                  name: 'biddingStrategyType'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupCriterion',
              type: 'object',
              properties: [
                {
                  name: 'topic',
                  type: 'object',
                  properties: [
                    {
                      name: 'path'
                    },
                    {
                      name: 'topicConstant'
                    }
                  ]
                },
                {
                  name: 'bidModifier'
                },
                {
                  name: 'effectiveCpcBidMicros'
                },
                {
                  name: 'effectiveCpcBidSource'
                },
                {
                  name: 'effectiveCpmBidMicros'
                },
                {
                  name: 'effectiveCpmBidSource'
                },
                {
                  name: 'finalMobileUrls'
                },
                {
                  name: 'finalUrls'
                },
                {
                  name: 'criterionId'
                },
                {
                  name: 'negative'
                },
                {
                  name: 'status'
                },
                {
                  name: 'trackingUrlTemplate'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            }
          ]
        when 'gender_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'gmailForwards'
                },
                {
                  name: 'gmailSaves'
                },
                {
                  name: 'gmailSecondaryClicks'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'targetingSetting',
                  type: 'object',
                  properties: [
                    {
                      name: 'targetRestrictions'
                    }
                  ]
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                },
                {
                  name: 'baseAdGroup'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'baseCampaign'
                },
                {
                  name: 'biddingStrategy'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupCriterion',
              type: 'object',
              properties: [
                {
                  name: 'gender',
                  type: 'object',
                  properties: [
                    {
                      name: 'type'
                    }
                  ]
                },
                {
                  name: 'bidModifier'
                },
                {
                  name: 'effectiveCpcBidMicros'
                },
                {
                  name: 'effectiveCpcBidSource'
                },
                {
                  name: 'effectiveCpmBidMicros'
                },
                {
                  name: 'effectiveCpmBidSource'
                },
                {
                  name: 'finalMobileUrls'
                },
                {
                  name: 'finalUrls'
                },
                {
                  name: 'criterionId'
                },
                {
                  name: 'negative'
                },
                {
                  name: 'status'
                },
                {
                  name: 'trackingUrlTemplate'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            },
            {
              name: 'biddingStrategy',
              type: 'object',
              properties: [
                {
                  name: 'name'
                },
                {
                  name: 'type'
                }
              ]
            }
          ]
        when 'geographic_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'geoTargetCity'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'geoTargetMetro'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'geoTargetMostSpecificLocation'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'geoTargetRegion'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'geographicView',
              type: 'object',
              properties: [
                {
                  name: 'countryCriterionId'
                },
                {
                  name: 'locationType'
                }
              ]
            },
            {
              name: 'userLocationView',
              type: 'object',
              properties: [
                {
                  name: 'targetingLocation'
                }
              ]
            }
          ]
        when 'user_location_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'geoTargetCity'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'geoTargetMetro'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'geoTargetMostSpecificLocation'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'geoTargetRegion'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'userLocationView',
              type: 'object',
              properties: [
                {
                  name: 'countryCriterionId'
                },
                {
                  name: 'targetingLocation'
                }
              ]
            },
            {
              name: 'geographicView',
              type: 'object',
              properties: [
                {
                  name: 'locationType'
                }
              ]
            }
          ]
        when 'dynamic_search_ads_search_term_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'webpage'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'dynamicSearchAdsSearchTermView',
              type: 'object',
              properties: [
                {
                  name: 'headline'
                },
                {
                  name: 'searchTerm'
                },
                {
                  name: 'landingPage'
                }
              ]
            }
          ]
        when 'keyword_view'
          [
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'absoluteTopImpressionPercentage'
                },
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'averagePageViews'
                },
                {
                  name: 'averageTimeOnSite'
                },
                {
                  name: 'bounceRate'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'costPerCurrentModelAttributedConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'currentModelAttributedConversionsValue'
                },
                {
                  name: 'currentModelAttributedConversions'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'gmailForwards'
                },
                {
                  name: 'gmailSaves'
                },
                {
                  name: 'gmailSecondaryClicks'
                },
                {
                  name: 'historicalCreativeQualityScore'
                },
                {
                  name: 'historicalLandingPageQualityScore'
                },
                {
                  name: 'historicalQualityScore'
                },
                {
                  name: 'historicalSearchPredictedCtr'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'percentNewVisitors'
                },
                {
                  name: 'searchAbsoluteTopImpressionShare'
                },
                {
                  name: 'searchBudgetLostAbsoluteTopImpressionShare'
                },
                {
                  name: 'searchBudgetLostTopImpressionShare'
                },
                {
                  name: 'searchExactMatchImpressionShare'
                },
                {
                  name: 'searchImpressionShare'
                },
                {
                  name: 'searchRankLostAbsoluteTopImpressionShare'
                },
                {
                  name: 'searchRankLostImpressionShare'
                },
                {
                  name: 'searchRankLostTopImpressionShare'
                },
                {
                  name: 'searchTopImpressionShare'
                },
                {
                  name: 'topImpressionPercentage'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'valuePerCurrentModelAttributedConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                },
                {
                  name: 'baseAdGroup'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionAdjustment'
                },
                {
                  name: 'conversionOrAdjustmentLagBucket'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionLagBucket'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'slot'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'adGroupCriterion',
              type: 'object',
              properties: [
                {
                  name: 'qualityInfo',
                  type: 'object',
                  properties: [
                    {
                      name: 'creativeQualityScore'
                    },
                    {
                      name: 'postClickQualityScore'
                    },
                    {
                      name: 'qualityScore'
                    },
                    {
                      name: 'searchPredictedCtr'
                    }
                  ]
                },
                {
                  name: 'keyword',
                  type: 'object',
                  properties: [
                    {
                      name: 'text'
                    },
                    {
                      name: 'matchType'
                    }
                  ]
                },
                {
                  name: 'positionEstimates',
                  type: 'object',
                  properties: [
                    {
                      name: 'estimatedAddClicksAtFirstPositionCpc'
                    },
                    {
                      name: 'estimatedAddCostAtFirstPositionCpc'
                    },
                    {
                      name: 'firstPageCpcMicros'
                    },
                    {
                      name: 'firstPositionCpcMicros'
                    },
                    {
                      name: 'topOfPageCpcMicros'
                    }
                  ]
                },
                {
                  name: 'topic',
                  type: 'object',
                  properties: [
                    {
                      name: 'topicConstant'
                    }
                  ]
                },
                {
                  name: 'approvalStatus'
                },
                {
                  name: 'effectiveCpcBidMicros'
                },
                {
                  name: 'effectiveCpcBidSource'
                },
                {
                  name: 'effectiveCpmBidMicros'
                },
                {
                  name: 'finalMobileUrls'
                },
                {
                  name: 'finalUrlSuffix'
                },
                {
                  name: 'finalUrls'
                },
                {
                  name: 'criterionId'
                },
                {
                  name: 'negative'
                },
                {
                  name: 'status'
                },
                {
                  name: 'systemServingStatus'
                },
                {
                  name: 'trackingUrlTemplate'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'manualCpc',
                  type: 'object',
                  properties: [
                    {
                      name: 'enhancedCpcEnabled'
                    }
                  ]
                },
                {
                  name: 'baseCampaign'
                },
                {
                  name: 'biddingStrategy'
                },
                {
                  name: 'biddingStrategyType'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            }
          ]
        when 'label'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'label',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                }
              ]
            }
          ]
        when 'landing_page_view'
          [
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'mobileFriendlyClicksPercentage'
                },
                {
                  name: 'validAcceleratedMobilePagesClicksPercentage'
                },
                {
                  name: 'speedScore'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'slot'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'advertisingChannelType'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'expandedLandingPageView',
              type: 'object',
              properties: [
                {
                  name: 'expandedFinalUrl', label: 'Expanded final URL'
                }
              ]
            },
            {
              name: 'landingPageView',
              type: 'object',
              properties: [
                {
                  name: 'unexpandedFinalUrl', label: 'Unexpanded final URL'
                }
              ]
            }
          ]
        when 'expanded_landing_page_view'
          [
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'mobileFriendlyClicksPercentage'
                },
                {
                  name: 'validAcceleratedMobilePagesClicksPercentage'
                },
                {
                  name: 'speedScore'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'slot'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'advertisingChannelType'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'expandedLandingPageView',
              type: 'object',
              properties: [
                {
                  name: 'expandedFinalUrl', label: 'Expanded final URL'
                }
              ]
            },
            {
              name: 'landingPageView',
              type: 'object',
              properties: [
                {
                  name: 'unexpandedFinalUrl', label: 'Unexpanded final URL'
                }
              ]
            }
          ]
        when 'paid_organic_search_term_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'averageCpc'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'combinedClicks'
                },
                {
                  name: 'combinedClicksPerQuery'
                },
                {
                  name: 'combinedQueries'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'organicClicks'
                },
                {
                  name: 'organicClicksPerQuery'
                },
                {
                  name: 'organicImpressions'
                },
                {
                  name: 'organicImpressionsPerQuery'
                },
                {
                  name: 'organicQueries'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'keyword',
                  type: 'object',
                  properties: [
                    {
                      name: 'info',
                      type: 'object',
                      properties: [
                        {
                          name: 'text'
                        }
                      ]
                    },
                    {
                      name: 'adGroupCriterion'
                    }
                  ]
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'searchEngineResultsPageType'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'paidOrganicSearchTermView',
              type: 'object',
              properties: [
                {
                  name: 'searchTerm'
                }
              ]
            }
          ]
        when 'parental_status_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'gmailForwards'
                },
                {
                  name: 'gmailSaves'
                },
                {
                  name: 'gmailSecondaryClicks'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'targetingSetting',
                  type: 'object',
                  properties: [
                    {
                      name: 'targetRestrictions'
                    }
                  ]
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                },
                {
                  name: 'baseAdGroup'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'baseCampaign'
                },
                {
                  name: 'biddingStrategy'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupCriterion',
              type: 'object',
              properties: [
                {
                  name: 'parentalStatus',
                  type: 'object',
                  properties: [
                    {
                      name: 'type'
                    }
                  ]
                },
                {
                  name: 'effectiveCpcBidMicros'
                },
                {
                  name: 'effectiveCpcBidSource'
                },
                {
                  name: 'effectiveCpmBidMicros'
                },
                {
                  name: 'effectiveCpmBidSource'
                },
                {
                  name: 'finalMobileUrls'
                },
                {
                  name: 'finalUrls'
                },
                {
                  name: 'criterionId'
                },
                {
                  name: 'negative'
                },
                {
                  name: 'status'
                },
                {
                  name: 'trackingUrlTemplate'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            }
          ]
        when 'feed_item'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupAd',
              type: 'object',
              properties: [
                {
                  name: 'resourceName'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'interactionOnThisExtension'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'placeholderType'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'slot'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                }
              ]
            },
            {
              name: 'feedItem',
              type: 'object',
              properties: [
                {
                  name: 'attributeValues'
                },
                {
                  name: 'endDateTime'
                },
                {
                  name: 'feed'
                },
                {
                  name: 'id'
                },
                {
                  name: 'geoTargetingRestriction'
                },
                {
                  name: 'startDateTime'
                },
                {
                  name: 'status'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'feedItemTarget',
              type: 'object',
              properties: [
                {
                  name: 'keyword',
                  type: 'object',
                  properties: [
                    {
                      name: 'matchType'
                    },
                    {
                      name: 'matchType'
                    },
                    {
                      name: 'text'
                    }
                  ]
                },
                {
                  name: 'feedItemTargetId'
                },
                {
                  name: 'feedItemTargetId'
                },
                {
                  name: 'adSchedule'
                },
                {
                  name: 'adGroup'
                },
                {
                  name: 'campaign'
                }
              ]
            }
          ]
        when 'feed_item_target'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupAd',
              type: 'object',
              properties: [
                {
                  name: 'resourceName'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'interactionOnThisExtension'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'placeholderType'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'slot'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                }
              ]
            },
            {
              name: 'feedItem',
              type: 'object',
              properties: [
                {
                  name: 'attributeValues'
                },
                {
                  name: 'endDateTime'
                },
                {
                  name: 'feed'
                },
                {
                  name: 'id'
                },
                {
                  name: 'geoTargetingRestriction'
                },
                {
                  name: 'startDateTime'
                },
                {
                  name: 'status'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'feedItemTarget',
              type: 'object',
              properties: [
                {
                  name: 'keyword',
                  type: 'object',
                  properties: [
                    {
                      name: 'matchType'
                    },
                    {
                      name: 'matchType'
                    },
                    {
                      name: 'text'
                    }
                  ]
                },
                {
                  name: 'feedItemTargetId'
                },
                {
                  name: 'feedItemTargetId'
                },
                {
                  name: 'adSchedule'
                },
                {
                  name: 'adGroup'
                },
                {
                  name: 'campaign'
                }
              ]
            }
          ]
        when 'feed_placeholder_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'slot'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'raw',
              type: 'object',
              properties: [
                {
                  name: 'campaign'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupAd',
              type: 'object',
              properties: [
                {
                  name: 'resourceName'
                }
              ]
            },
            {
              name: 'feedPlaceholderView',
              type: 'object',
              properties: [
                {
                  name: 'placeholderType'
                }
              ]
            }
          ]
        when 'managed_placement_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'gmailForwards'
                },
                {
                  name: 'gmailSaves'
                },
                {
                  name: 'gmailSecondaryClicks'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'targetingSetting',
                  type: 'object',
                  properties: [
                    {
                      name: 'targetRestrictions'
                    }
                  ]
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                },
                {
                  name: 'baseAdGroup'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'baseCampaign'
                },
                {
                  name: 'biddingStrategy'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupCriterion',
              type: 'object',
              properties: [
                {
                  name: 'placement',
                  type: 'object',
                  properties: [
                    {
                      name: 'url'
                    }
                  ]
                },
                {
                  name: 'bidModifier'
                },
                {
                  name: 'effectiveCpcBidMicros'
                },
                {
                  name: 'effectiveCpcBidSource'
                },
                {
                  name: 'effectiveCpmBidMicros'
                },
                {
                  name: 'effectiveCpmBidSource'
                },
                {
                  name: 'finalMobileUrls'
                },
                {
                  name: 'finalUrls'
                },
                {
                  name: 'criterionId'
                },
                {
                  name: 'negative'
                },
                {
                  name: 'status'
                },
                {
                  name: 'trackingUrlTemplate'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            },
            {
              name: 'biddingStrategy',
              type: 'object',
              properties: [
                {
                  name: 'name'
                },
                {
                  name: 'type'
                }
              ]
            }
          ]
        when 'product_group_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'benchmarkAverageMaxCpc'
                },
                {
                  name: 'benchmarkCtr'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'searchAbsoluteTopImpressionShare'
                },
                {
                  name: 'searchClickShare'
                },
                {
                  name: 'searchImpressionShare'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'biddingStrategyType'
                },
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupCriterion',
              type: 'object',
              properties: [
                {
                  name: 'listingGroup',
                  type: 'object',
                  properties: [
                    {
                      name: 'parentAdGroupCriterion'
                    },
                    {
                      name: 'type'
                    }
                  ]
                },
                {
                  name: 'cpcBidMicros'
                },
                {
                  name: 'finalUrlSuffix', label: 'Final URL suffix'
                },
                {
                  name: 'criterionId'
                },
                {
                  name: 'negative'
                },
                {
                  name: 'trackingUrlTemplate'
                },
                {
                  name: 'urlCustomParameters'
                }
              ]
            }
          ]
        when 'search_term_view'
          [
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'absoluteTopImpressionPercentage'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'topImpressionPercentage'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'keyword',
                  type: 'object',
                  properties: [
                    {
                      name: 'info',
                      type: 'object',
                      properties: [
                        {
                          name: 'text'
                        }
                      ]
                    },
                    {
                      name: 'adGroupCriterion'
                    }
                  ]
                },
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'searchTermMatchType'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupAd',
              type: 'object',
              properties: [
                {
                  name: 'ad',
                  type: 'object',
                  properties: [
                    {
                      name: 'id'
                    },
                    {
                      name: 'finalUrls'
                    },
                    {
                      name: 'trackingUrlTemplate', label: 'Tracking URL template'
                    }
                  ]
                }
              ]
            },
            {
              name: 'searchTermView',
              type: 'object',
              properties: [
                {
                  name: 'searchTerm'
                },
                {
                  name: 'status'
                }
              ]
            }
          ]
        when 'shared_criterion'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'sharedCriterion',
              type: 'object',
              properties: [
                {
                  name: 'keyword',
                  type: 'object',
                  properties: [
                    {
                      name: 'text'
                    },
                    {
                      name: 'matchType'
                    }
                  ]
                },
                {
                  name: 'criterionId'
                }
              ]
            },
            {
              name: 'sharedSet',
              type: 'object',
              properties: [
                {
                  name: 'id'
                }
              ]
            }
          ]
        when 'shopping_performance_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'productAggregatorId'
                },
                {
                  name: 'productBrand'
                },
                {
                  name: 'productBiddingCategoryLevel1'
                },
                {
                  name: 'productBiddingCategoryLevel2'
                },
                {
                  name: 'productBiddingCategoryLevel3'
                },
                {
                  name: 'productBiddingCategoryLevel4'
                },
                {
                  name: 'productBiddingCategoryLevel5'
                },
                {
                  name: 'productChannel'
                },
                {
                  name: 'productChannelExclusivity'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'productCountry'
                },
                {
                  name: 'productCustomAttribute0'
                },
                {
                  name: 'productCustomAttribute1'
                },
                {
                  name: 'productCustomAttribute2'
                },
                {
                  name: 'productCustomAttribute3'
                },
                {
                  name: 'productCustomAttribute4'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'productLanguage'
                },
                {
                  name: 'productMerchantId'
                },
                {
                  name: 'month'
                },
                {
                  name: 'productItemId'
                },
                {
                  name: 'productCondition'
                },
                {
                  name: 'productTitle'
                },
                {
                  name: 'productTypeL1'
                },
                {
                  name: 'productTypeL2'
                },
                {
                  name: 'productTypeL3'
                },
                {
                  name: 'productTypeL4'
                },
                {
                  name: 'productTypeL5'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'productStoreId'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'searchAbsoluteTopImpressionShare'
                },
                {
                  name: 'searchClickShare'
                },
                {
                  name: 'searchImpressionShare'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            }
          ]
        when 'detail_placement_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'activeViewCpm'
                },
                {
                  name: 'activeViewCtr'
                },
                {
                  name: 'activeViewImpressions'
                },
                {
                  name: 'activeViewMeasurability'
                },
                {
                  name: 'activeViewMeasurableCostMicros'
                },
                {
                  name: 'activeViewMeasurableImpressions'
                },
                {
                  name: 'activeViewViewability'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCost'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpe'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'interactionRate'
                },
                {
                  name: 'interactionEventTypes'
                },
                {
                  name: 'interactions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'detailPlacementView',
              type: 'object',
              properties: [
                {
                  name: 'displayName'
                },
                {
                  name: 'groupPlacementTargetUrl', label: 'Group placement target URL'
                },
                {
                  name: 'targetUrl', label: 'Target URL'
                }
              ]
            }
          ]
        when 'distance_view'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCpc'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'conversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'valuePerConversion'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'distanceView',
              type: 'object',
              properties: [
                {
                  name: 'distanceBucket'
                }
              ]
            }
          ]
        when 'video'
          [
            {
              name: 'customer',
              type: 'object',
              properties: [
                {
                  name: 'currencyCode'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'timeZone'
                },
                {
                  name: 'descriptiveName'
                },
                {
                  name: 'id'
                }
              ]
            },
            {
              name: 'adGroup',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'segments',
              type: 'object',
              properties: [
                {
                  name: 'adNetworkType'
                },
                {
                  name: 'clickType'
                },
                {
                  name: 'conversionActionCategory'
                },
                {
                  name: 'conversionAction'
                },
                {
                  name: 'conversionActionName'
                },
                {
                  name: 'date'
                },
                {
                  name: 'dayOfWeek'
                },
                {
                  name: 'device'
                },
                {
                  name: 'externalConversionSource'
                },
                {
                  name: 'month'
                },
                {
                  name: 'monthOfYear'
                },
                {
                  name: 'quarter'
                },
                {
                  name: 'week'
                },
                {
                  name: 'year'
                }
              ]
            },
            {
              name: 'metrics',
              type: 'object',
              properties: [
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'allConversionsValue'
                },
                {
                  name: 'allConversions'
                },
                {
                  name: 'averageCpm'
                },
                {
                  name: 'averageCpv'
                },
                {
                  name: 'clicks'
                },
                {
                  name: 'allConversionsFromInteractionsRate'
                },
                {
                  name: 'conversionsValue'
                },
                {
                  name: 'conversions'
                },
                {
                  name: 'costMicros'
                },
                {
                  name: 'costPerAllConversions'
                },
                {
                  name: 'costPerConversion'
                },
                {
                  name: 'crossDeviceConversions'
                },
                {
                  name: 'ctr'
                },
                {
                  name: 'engagementRate'
                },
                {
                  name: 'engagements'
                },
                {
                  name: 'impressions'
                },
                {
                  name: 'valuePerAllConversions'
                },
                {
                  name: 'videoQuartileP100Rate'
                },
                {
                  name: 'videoQuartileP25Rate'
                },
                {
                  name: 'videoQuartileP50Rate'
                },
                {
                  name: 'videoQuartileP75Rate'
                },
                {
                  name: 'videoViewRate'
                },
                {
                  name: 'videoViews'
                },
                {
                  name: 'viewThroughConversions'
                }
              ]
            },
            {
              name: 'campaign',
              type: 'object',
              properties: [
                {
                  name: 'id'
                },
                {
                  name: 'name'
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'adGroupAd',
              type: 'object',
              properties: [
                {
                  name: 'ad',
                  type: 'object',
                  properties: [
                    {
                      name: 'id'
                    }
                  ]
                },
                {
                  name: 'status'
                }
              ]
            },
            {
              name: 'video',
              type: 'object',
              properties: [
                {
                  name: 'channelId'
                },
                {
                  name: 'durationMillis', label: 'Duration in milliseconds'
                },
                {
                  name: 'id'
                },
                {
                  name: 'title'
                }
              ]
            }
          ]
        else
          []
        end
      end
    }
  },

  actions: {
    search_objects: {
      title: 'Search records',
      subtitle: 'Retrieve a list of records, e.g. campaigns, that matches your search criteria.',
      description: lambda do |_input, pick_lists|
        "Search for <span class='provider'>#{pick_lists['object_name'] || 'records'}" \
        "</span> in <span class='provider'>Google Ads</span>"
      end,
      help: 'The Search records action returns results that match all your search criteria.',
      config_fields: [
        { name: 'object_name', label: 'Object', control_type: 'select',
          hint: 'Select Google Ads object, e.g. campaigns.',
          pick_list: 'search_object_list',
          optional: false }
      ],
      input_fields: lambda do |object_definitions|
        object_definitions['search_object_input']
      end,
      execute: lambda do |_connection, input, _extended_input_schema, _extended_output_schema|
        camelize_object_name = input['object_name'].split('_').
                               map { |text| text.capitalize }.smart_join('').
                               gsub(/^[A-Z]/) { |text| text.downcase }
        query = call('build_query', input)
        payload = { query: query,
                    pageToken: input['page_token'],
                    pageSize: input['page_size'] || 100,
                    returnTotalResultsCount: true }.compact
        response = post("customers/#{input['client_customer_id']}/googleAds:search").payload(payload).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end
        { results: response['results']&.pluck(camelize_object_name) }&.merge(response.except('results'))
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['search_object_output']
      end,
      sample_output: lambda do |_connection, input|
        query = "SELECT customer_client.id
                 FROM customer_client"
        customer_client_id = post('https://googleads.googleapis.com/v8/customers/7242908860/googleAds:search').
                             payload(query: query, page_size: 1).dig('results', 0, 'customerClient', 'id')
        camelize_object_name = input['object_name'].split('_').
                               map { |text| text.capitalize }.smart_join('').
                               gsub(/^[A-Z]/) { |text| text.downcase }
        payload = { query: call('build_query', input),
                    pageSize: 1 }
        response = post("customers/#{customer_client_id}/googleAds:search").payload(payload).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end
        { results: response['results']&.pluck(camelize_object_name) }
      end
    },
    create_object: {
      title: 'Create record',
      subtitle: 'Create a record, e.g. campaign, in Google Ads.',
      description: lambda do |_input, pick_lists|
        "Create <span class='provider'>#{pick_lists['object_name'] || 'record'}" \
        "</span> in <span class='provider'>Google Ads</span>"\
      end,
      help: lambda do |_input, pick_lists|
        additional_text = if pick_lists['object_name'] == 'User list'
                            'One of <b>CRM based user list</b>, <b>Rule based user list</b>, ' \
                            '<b>Logical user list</b> or <b>Basic user list</b> is required when creating a user list.'
                          elsif pick_lists['object_name'] == 'Campaign'
                            'A campaign bidding strategy is required when creating campaigns. Please use one of ' \
                            '<b>Bidding strategy</b>, <b>Commission</b>, <b>Manual CPC</b>, <b>Maximize conversions</b>, ' \
                            '<b>Maximize conversion value</b>, <b>Target CPA</b>, <b>Target impression share</b>, ' \
                            '<b>Target ROAS</b>, <b>Target spend</b> or <b>Percent CPC</b>.'
                          end
        { body: 'Create record, e.g. campaign, in Google Ads. ' \
          'Select the object to create, then provide the data for creating the record.<br>' \
          "#{additional_text}" }
      end,
      config_fields: [
        { name: 'object_name', label: 'Object', control_type: 'select',
          hint: 'Select Google Ads object, e.g. campaign.',
          pick_list: 'create_object_list',
          optional: false }
      ],
      input_fields: lambda do |object_definitions|
        object_definitions['create_object_input']
      end,
      execute: lambda do |_connection, input, _extended_input_schema, _extended_output_schema|
        payload = { operations: [{ create: input.except('object_name', 'client_customer_id') }] }
        payload.merge(responseContentType: 'RESOURCE_NAME_ONLY') if input['object_name'] == 'campaign'
        response = post(call('mutate_endpoint', input), payload).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end
        { resourceName: response.dig('results', 0, 'resourceName') }.merge(response.except('results'))
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['mutate_output']
      end,
      sample_output: lambda do |_connection, _input|
        {
          resourceName: 'customers/7242908860/customerClients/2569649435',
          partialFailureError: { code: 'sample error code', message: 'sample error message' }
        }
      end
    },
    update_object: {
      title: 'Update record',
      subtitle: 'Update a record, e.g. campaign, via its ID.',
      description: lambda do |_input, pick_lists|
        "Update <span class='provider'>#{pick_lists['object_name'] || 'record'}" \
        "</span> in <span class='provider'>Google Ads</span>"\
      end,
      help: 'Update a record, e.g. campaign, via its ID. ' \
        'First select the object, then specify the ID of the record to update.',
      config_fields: [
        { name: 'object_name', label: 'Object', control_type: 'select',
          hint: 'Select Google Ads object, e.g. campaign.',
          pick_list: 'update_object_list',
          optional: false }
      ],
      input_fields: lambda do |object_definitions|
        object_definitions['update_object_input']
      end,
      execute: lambda do |_connection, input, _extended_input_schema, _extended_output_schema|
        update_mask = call('generate_update_mask', input.except('object_name', 'client_customer_id', 'resourceName'))
        payload = { operations: [{ updateMask: update_mask, update: input.except('object_name', 'client_customer_id') }] }
        payload.merge(responseContentType: 'RESOURCE_NAME_ONLY') if input['object_name'] == 'campaign'
        response = post(call('mutate_endpoint', input), payload).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end
        { resourceName: response.dig('results', 0, 'resourceName') }.merge(response.except('results'))
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['mutate_output']
      end,
      sample_output: lambda do |_connection, _input|
        {
          resourceName: 'customers/7242908860/customerClients/2569649435',
          partialFailureError: { code: 'sample error code', message: 'sample error message' }
        }
      end
    },
    delete_object: {
      title: 'Delete record',
      subtitle: 'Delete any standard record, e.g. campaign, via its ID.',
      description: lambda do |_input, pick_lists|
        "Delete <span class='provider'>#{pick_lists['object_name'] || 'record'}" \
        "</span> in <span class='provider'>Google Ads</span>"
      end,
      help: 'Delete any standard, e.g. campaign, via its ID. First select the object, ' \
        'then specify the ID of the record to delete.',
      config_fields: [
        { name: 'object_name', label: 'Object', control_type: 'select',
          hint: 'Select any standard Google Ads, e.g. campaign.',
          pick_list: 'delete_object_list',
          optional: false }
      ],
      input_fields: lambda do |object_definitions|
        object_definitions['delete_object_input']
      end,
      execute: lambda do |_connection, input|
        payload = { operations: [{ remove: input['resourceName'] }] }
        payload.merge(responseContentType: 'RESOURCE_NAME_ONLY') if input['object_name'] == 'campaign'
        response = post(call('mutate_endpoint', input), payload).
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end
        { resourceName: response.dig('results', 0, 'resourceName') }.merge(response.except('results'))  
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['mutate_output']
      end,
      sample_output: lambda do |_connection, _input|
        {
          resourceName: 'customers/7242908860/customerClients/2569649435',
          partialFailureError: { code: 'sample error code', message: 'sample error message' }
        }
      end
    },
    get_object: {
      title: 'Get record details by ID',
      subtitle: 'Retrieve the details of a record, e.g. campaign, via its ID.',
      description: lambda do |_input, pick_lists|
        "Get details of specific <span class='provider'>#{pick_lists['object_name'] || 'record'}" \
        "</span> in <span class='provider'>Google Ads</span>"\
      end,
      help: 'Retrieve the details of a record, e.g. campaign, via its ID.',
      config_fields: [
        { name: 'object_name', label: 'Object', control_type: 'select',
          hint: 'Select Google Ads object, e.g. campaign.',
          pick_list: 'get_object_list',
          optional: false }
      ],
      input_fields: lambda do |object_definitions|
        object_definitions['get_object_input']
      end,
      execute: lambda do |_connection, input, _extended_input_schema, _extended_output_schema|
        get("customers/#{input['client_customer_id']}/#{input['object_name'].pluralize}/#{input['id']}").
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['get_object_output']
      end,
      sample_output: lambda do |_connection, input|
        query = "SELECT customer_client.id
                 FROM customer_client"
        customer_client_id = post('https://googleads.googleapis.com/v8/customers/7242908860/googleAds:search').
                             payload(query: query, page_size: 1).dig('results', 0, 'customerClient', 'id')
        camelize_object_name = input['object_name'].split('_').
                               map { |text| text.capitalize }.smart_join('').
                               gsub(/^[A-Z]/) { |text| text.downcase }
        payload = { query: call('build_query', input),
                    pageSize: 1 }
        post("customers/#{customer_client_id}/googleAds:search").payload(payload).
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end&.dig('results', 0, camelize_object_name)
      end
    },
    retrieve_advertising_report: {
      title: 'Retrieve advertising report',
      subtitle: 'Retrieve advertising report',
      description: "Retrieve <span class='provider'>advertising " \
        'report</span> from Google Ads',
      input_fields: lambda do |object_definitions|
        object_definitions['retrieve_report_input']
      end,
      execute: lambda do |_connection, input|
        query = call('build_report_query', input)
        payload = { query: query,
                    pageToken: input['page_token'],
                    pageSize: input['page_size'] || 100,
                    returnTotalResultsCount: true }.compact
        post("customers/#{input['client_customer_id']}/googleAds:search").payload(payload).
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end
      end,
      output_fields: lambda do |object_definition|
        [
          { name: 'results', label: 'Advertising reports', type: 'array', of: 'object',
            properties: object_definition['report'] },
          { name: 'nextPageToken' },
          { name: 'totalResultsCount', type: 'integer' },
          { name: 'fieldMask' }
        ]
      end,
      sample_output: lambda do |_connection, input|
        query = call('build_report_query', input)
        payload = { query: query,
                    pageSize: 1,
                    returnTotalResultsCount: true }.compact
        post("customers/#{input['client_customer_id']}/googleAds:search").payload(payload).
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end
      end
    },
    custom_action: {
      subtitle: 'Build your own Google Ads action with a HTTP request',

      description: lambda do |object_value, _object_label|
        "<span class='provider'>" \
        "#{object_value[:action_name] || 'Custom action'}</span> in " \
        "<span class='provider'>Google Ads</span>"
      end,

      help: {
        body: 'Build your own Google Ads action with a HTTP request. ' \
        'The request will be authorized with your Google Ads connection.',
        learn_more_url: 'https://developers.google.com/google-ads/api/docs/start',
        learn_more_text: 'Google Ads API documentation'
      },

      config_fields: [
        {
          name: 'action_name',
          hint: "Give this action you're building a descriptive name, e.g. " \
          'create record, get record',
          default: 'Custom action',
          optional: false,
          schema_neutral: true
        },
        {
          name: 'verb',
          label: 'Method',
          hint: 'Select HTTP method of the request',
          optional: false,
          control_type: 'select',
          pick_list: %w[get post put patch options delete].
            map { |verb| [verb.upcase, verb] }
        }
      ],

      input_fields: lambda do |object_definition|
        object_definition['custom_action_input']
      end,

      execute: lambda do |_connection, input|
        verb = input['verb']
        if %w[get post put patch options delete].exclude?(verb)
          error("#{verb.upcase} not supported")
        end
        path = input['path']
        data = input.dig('input', 'data') || {}
        if input['request_type'] == 'multipart'
          data = data.each_with_object({}) do |(key, val), hash|
            hash[key] = if val.is_a?(Hash)
                          [val[:file_content],
                           val[:content_type],
                           val[:original_filename]]
                        else
                          val
                        end
          end
        end
        request_headers = input['request_headers']&.
        each_with_object({}) do |item, hash|
          hash[item['key']] = item['value']
        end || {}
        request = case verb
                  when 'get'
                    get(path, data)
                  when 'post'
                    if input['request_type'] == 'raw'
                      post(path).request_body(data)
                    else
                      post(path, data)
                    end
                  when 'put'
                    if input['request_type'] == 'raw'
                      put(path).request_body(data)
                    else
                      put(path, data)
                    end
                  when 'patch'
                    if input['request_type'] == 'raw'
                      patch(path).request_body(data)
                    else
                      patch(path, data)
                    end
                  when 'options'
                    options(path, data)
                  when 'delete'
                    delete(path, data)
                  end.headers(request_headers)
        request = case input['request_type']
                  when 'url_encoded_form'
                    request.request_format_www_form_urlencoded
                  when 'multipart'
                    request.request_format_multipart_form
                  else
                    request
                  end
        response =
          if input['response_type'] == 'raw'
            request.response_format_raw
          else
            request
          end.
          after_error_response(/.*/) do |code, body, headers, message|
            error({ code: code, message: message, body: body, headers: headers }.
              to_json)
          end

        response.after_response do |_code, res_body, res_headers|
          {
            body: res_body ? call('format_response', res_body) : nil,
            headers: res_headers
          }
        end
      end,

      output_fields: lambda do |object_definition|
        object_definition['custom_action_output']
      end
    }
  },

  triggers: {
    new_record: {
      title: 'New record',
      subtitle: 'Triggers when selected Google Ads object, e.g. campaign, is created.',
      description: lambda do |_input, pick_lists|
        "New <span class='provider'>#{pick_lists['object_name']&.downcase || 'record'}" \
        "</span> in <span class='provider'>Google Ads</span>"
      end,
      input_fields: lambda do |object_definitions|
        object_definitions['new_object_input']
      end,

      poll: lambda do |_connection, input, closure|
        camelize_object_name = input['object_name'].split('_').
                               map { |text| text.capitalize }.smart_join('').
                               gsub(/^[A-Z]/) { |text| text.downcase }
        page_size = 100
        page_token = closure&.[]('page_token') || nil
        since = closure&.[]('since') || (input['id'] || 0)
        id = if input['object_name'] == 'ad_group_ad'
               'ad_group_ad.ad.id'
             else
               "#{input['object_name']}.id"
             end
        params = { 'object_name' => input['object_name'], 'filter' => "#{id} >= #{since}" }

        query = call('build_query', params)
        payload = { query: query,
                    pageToken: page_token,
                    pageSize: page_size }.compact
        response = post("customers/#{input['client_customer_id']}/googleAds:search").payload(payload).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end
        records = response['results']&.pluck(camelize_object_name) || []
        formatted_records = if input['object_name'] == 'ad_group_ad'
                              records.map { |record| record.merge(id: record.dig('ad', 'id')) }
                            else
                              records
                            end
        next_updated_since = formatted_records&.last&.[]('id') || since
        closure = if (more_pages = response['nextPageToken'].present?)
                    { 'page_token' =>  response['nextPageToken'], 'since' => since }
                  else
                    { 'page_token' =>  nil, 'since' => next_updated_since }
                  end
        {
          events: formatted_records,
          next_poll: closure,
          can_poll_more: more_pages
        }
      end,

      dedup: lambda do |record|
        record['id']
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['new_object_output']
      end,
      sample_output: lambda do |_connection, input|
        query = "SELECT customer_client.id
                 FROM customer_client"
        customer_client_id = post('https://googleads.googleapis.com/v8/customers/7242908860/googleAds:search').
                             payload(query: query, page_size: 1).dig('results', 0, 'customerClient', 'id')
        camelize_object_name = input['object_name'].split('_').
                               map { |text| text.capitalize }.smart_join('').
                               gsub(/^[A-Z]/) { |text| text.downcase }
        payload = { query: call('build_query', input),
                    pageSize: 1 }
        post("customers/#{customer_client_id}/googleAds:search").payload(payload).
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end&.dig('results', 0, camelize_object_name)
      end
    }
  },

  pick_lists: {
    #==================#
    # Report picklists #
    #==================#
    report_types: lambda do |_connection|
      [
        %w[ACCOUNT_PERFORMANCE_REPORT customer],
        %w[AD_PERFORMANCE_REPORT ad_group_ad],
        %w[ADGROUP_PERFORMANCE_REPORT ad_group],
        %w[AGE_RANGE_PERFORMANCE_REPORT age_range_view],
        %w[AUDIENCE_PERFORMANCE_REPORT_(campaign_audience_view) campaign_audience_view],
        %w[AUDIENCE_PERFORMANCE_REPORT_(ad_group_audience_view) ad_group_audience_view],
        %w[AUTOMATIC_PLACEMENTS_PERFORMANCE_REPORT group_placement_view],
        %w[BID_GOAL_PERFORMANCE_REPORT bidding_strategy],
        %w[BUDGET_PERFORMANCE_REPORT campaign_budget],
        %w[CALL_METRICS_CALL_DETAILS_REPORT call_view],
        %w[CAMPAIGN_AD_SCHEDULE_TARGET_REPORT ad_schedule_view],
        %w[CAMPAIGN_CRITERIA_REPORT campaign_criterion],
        %w[CAMPAIGN_PERFORMANCE_REPORT campaign],
        %w[CAMPAIGN_SHARED_SET_REPORT campaign_shared_set],
        %w[CAMPAIGN_LOCATION_TARGET_REPORT location_view],
        %w[CLICK_PERFORMANCE_REPORT click_view],
        %w[DISPLAY_KEYWORD_PERFORMANCE_REPORT display_keyword_view],
        %w[DISPLAY_TOPICS_PERFORMANCE_REPORT topic_view],
        %w[GENDER_PERFORMANCE_REPORT gender_view],
        %w[GEO_PERFORMANCE_REPORT_(geographic_view) geographic_view],
        %w[GEO_PERFORMANCE_REPORT_(user_location_view) user_location_view],
        %w[KEYWORDLESS_QUERY_REPORT dynamic_search_ads_search_term_view],
        %w[KEYWORDS_PERFORMANCE_REPORT keyword_view],
        %w[LABEL_REPORT label],
        %w[LANDING_PAGE_REPORT_(landing_page_view) landing_page_view],
        %w[LANDING_PAGE_REPORT_(expanded_landing_page_view) expanded_landing_page_view],
        %w[PAID_ORGANIC_QUERY_REPORT paid_organic_search_term_view],
        %w[PARENTAL_STATUS_PERFORMANCE_REPORT parental_status_view],
        %w[PLACEHOLDER_FEED_ITEM_REPORT_(feed_item) feed_item],
        %w[PLACEHOLDER_FEED_ITEM_REPORT_(feed_item_target) feed_item_target],
        %w[PLACEHOLDER_REPORT feed_placeholder_view],
        %w[PLACEMENT_PERFORMANCE_REPORT managed_placement_view],
        %w[PRODUCT_PARTITION_REPORT product_group_view],
        %w[SEARCH_QUERY_PERFORMANCE_REPORT search_term_view],
        %w[SHARED_SET_CRITERIA_REPORT shared_criterion],
        %w[SHOPPING_PERFORMANCE_REPORT shopping_performance_view],
        %w[URL_PERFORMANCE_REPORT detail_placement_view],
        %w[USER_AD_DISTANCE_REPORT distance_view],
        %w[VIDEO_PERFORMANCE_REPORT video]
      ].map { |item| [item.first.labelize.downcase.capitalize, item.last] }
    end,
    date_range_types: lambda do |_connection|
      [
        %w[Today TODAY],
        %w[Yesterday YESTERDAY],
        %w[Last\ 7\ days LAST_7_DAYS],
        %w[Last\ business\ week LAST_BUSINESS_WEEK],
        %w[This\ month THIS_MONTH],
        %w[Last\ month LAST_MONTH],
        %w[Custom\ date CUSTOM_DATE],
        %w[Last\ 14\ days LAST_14_DAYS],
        %w[Last\ 30\ days LAST_30_DAYS],
        %w[This\ week\ Sunday\ until\ today THIS_WEEK_SUN_TODAY],
        %w[This\ week\ Monday\ until\ today THIS_WEEK_MON_TODAY],
        %w[Last\ week\ Sunday\ to\ Saturday LAST_WEEK_SUN_SAT],
        %w[Last\ week\ Monday\ to\ Sunday LAST_WEEK_MON_SUN]
      ]
    end,

    customer_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[CanManageClients customer.manager],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ContentBudgetLostImpressionShare metrics.content_budget_lost_impression_share],
        %w[ContentImpressionShare metrics.content_impression_share],
        %w[ContentRankLostImpressionShare metrics.content_rank_lost_impression_share],
        %w[ConversionAdjustment segments.conversion_adjustment],
        %w[ConversionAdjustmentLagBucket segments.conversion_or_adjustment_lag_bucket],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionLagBucket segments.conversion_lag_bucket],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[HourOfDay segments.hour],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[InvalidClickRate metrics.invalid_click_rate],
        %w[InvalidClicks metrics.invalid_clicks],
        %w[IsAutoTaggingEnabled customer.auto_tagging_enabled],
        %w[IsTestAccount customer.test_account],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[SearchBudgetLostImpressionShare metrics.search_budget_lost_impression_share],
        %w[SearchExactMatchImpressionShare metrics.search_exact_match_impression_share],
        %w[SearchImpressionShare metrics.search_impression_share],
        %w[SearchRankLostImpressionShare metrics.search_rank_lost_impression_share],
        %w[Slot segments.slot],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    ad_group_ad_report_fields: lambda do |_connection|
      [
        %w[AbsoluteTopImpressionPercentage metrics.absolute_top_impression_percentage],
        %w[AccentColor ad_group_ad.ad.legacy_responsive_display_ad.accent_color],
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AdStrengthInfo ad_group_ad.ad_strength],
        %w[AdType ad_group_ad.ad.type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AllowFlexibleColor ad_group_ad.ad.legacy_responsive_display_ad.allow_flexible_color],
        %w[Automated ad_group_ad.ad.added_by_google_ads],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[AveragePageviews metrics.average_page_views],
        %w[AverageTimeOnSite metrics.average_time_on_site],
        %w[BaseAdGroupId ad_group.base_ad_group],
        %w[BaseCampaignId campaign.base_campaign],
        %w[BounceRate metrics.bounce_rate],
        %w[BusinessName ad_group_ad.ad.legacy_responsive_display_ad.business_name],
        %w[CallOnlyPhoneNumber ad_group_ad.ad.call_ad.phone_number],
        %w[CallToActionText ad_group_ad.ad.legacy_responsive_display_ad.call_to_action_text],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[CombinedApprovalStatus ad_group_ad.policy_summary.approval_status],
        %w[ConversionAdjustment segments.conversion_adjustment],
        %w[ConversionAdjustmentLagBucket segments.conversion_or_adjustment_lag_bucket],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionLagBucket segments.conversion_lag_bucket],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CostPerCurrentModelAttributedConversion metrics.cost_per_current_model_attributed_conversion],
        %w[CreativeFinalMobileUrls ad_group_ad.ad.final_mobile_urls],
        %w[CreativeFinalUrls ad_group_ad.ad.final_urls],
        %w[CreativeTrackingUrlTemplate ad_group_ad.ad.tracking_url_template],
        %w[CreativeUrlCustomParameters ad_group_ad.ad.url_custom_parameters],
        %w[CriterionId segments.keyword.ad_group_criterion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CurrentModelAttributedConversionValue metrics.current_model_attributed_conversions_value],
        %w[CurrentModelAttributedConversions metrics.current_model_attributed_conversions],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Description ad_group_ad.ad.legacy_responsive_display_ad.description],
        %w[Description1 ad_group_ad.ad.text_ad.description1],
        %w[Description2 ad_group_ad.ad.text_ad.description2],
        %w[Device segments.device],
        %w[DevicePreference ad_group_ad.ad.device_preference],
        %w[DisplayUrl ad_group_ad.ad.display_url],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[EnhancedDisplayCreativeLandscapeLogoImageMediaId ad_group_ad.ad.legacy_responsive_display_ad.logo_image],
        %w[EnhancedDisplayCreativeLogoImageMediaId ad_group_ad.ad.legacy_responsive_display_ad.square_logo_image],
        %w[EnhancedDisplayCreativeMarketingImageMediaId ad_group_ad.ad.legacy_responsive_display_ad.marketing_image],
        %w[EnhancedDisplayCreativeMarketingImageSquareMediaId ad_group_ad.ad.legacy_responsive_display_ad.square_marketing_image],
        %w[ExpandedDynamicSearchCreativeDescription2 ad_group_ad.ad.expanded_dynamic_search_ad.description],
        %w[ExpandedTextAdDescription2 ad_group_ad.ad.expanded_text_ad.description2],
        %w[ExpandedTextAdHeadlinePart3 ad_group_ad.ad.expanded_text_ad.headline_part3],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FormatSetting ad_group_ad.ad.legacy_responsive_display_ad.format_setting],
        %w[GmailCreativeHeaderImageMediaId ad_group_ad.ad.gmail_ad.header_image],
        %w[GmailCreativeLogoImageMediaId ad_group_ad.ad.gmail_ad.teaser.logo_image],
        %w[GmailCreativeMarketingImageMediaId ad_group_ad.ad.gmail_ad.marketing_image],
        %w[GmailForwards metrics.gmail_forwards],
        %w[GmailSaves metrics.gmail_saves],
        %w[GmailSecondaryClicks metrics.gmail_secondary_clicks],
        %w[GmailTeaserBusinessName ad_group_ad.ad.gmail_ad.teaser.business_name],
        %w[GmailTeaserDescription ad_group_ad.ad.gmail_ad.teaser.description],
        %w[GmailTeaserHeadline ad_group_ad.ad.gmail_ad.teaser.headline],
        %w[Headline ad_group_ad.ad.text_ad.headline],
        %w[HeadlinePart1 ad_group_ad.ad.expanded_text_ad.headline_part1],
        %w[HeadlinePart2 ad_group_ad.ad.expanded_text_ad.headline_part2],
        %w[Id ad_group_ad.ad.id],
        %w[ImageAdUrl ad_group_ad.ad.image_ad.image_url],
        %w[ImageCreativeImageHeight ad_group_ad.ad.image_ad.pixel_height],
        %w[ImageCreativeImageWidth ad_group_ad.ad.image_ad.pixel_width],
        %w[ImageCreativeMimeType ad_group_ad.ad.image_ad.mime_type],
        %w[ImageCreativeName ad_group_ad.ad.image_ad.name],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[LongHeadline ad_group_ad.ad.legacy_responsive_display_ad.long_headline],
        %w[MainColor ad_group_ad.ad.legacy_responsive_display_ad.main_color],
        %w[MarketingImageCallToActionText ad_group_ad.ad.gmail_ad.marketing_image_display_call_to_action.text],
        %w[MarketingImageCallToActionTextColor ad_group_ad.ad.gmail_ad.marketing_image_display_call_to_action.text_color],
        %w[MarketingImageDescription ad_group_ad.ad.gmail_ad.marketing_image_headline],
        %w[MarketingImageHeadline ad_group_ad.ad.gmail_ad.marketing_image_description],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[MultiAssetResponsiveDisplayAdAccentColor ad_group_ad.ad.responsive_display_ad.accent_color],
        %w[MultiAssetResponsiveDisplayAdAllowFlexibleColor ad_group_ad.ad.responsive_display_ad.allow_flexible_color],
        %w[MultiAssetResponsiveDisplayAdBusinessName ad_group_ad.ad.responsive_display_ad.business_name],
        %w[MultiAssetResponsiveDisplayAdCallToActionText ad_group_ad.ad.responsive_display_ad.call_to_action_text],
        %w[MultiAssetResponsiveDisplayAdDescriptions ad_group_ad.ad.responsive_display_ad.descriptions],
        %w[MultiAssetResponsiveDisplayAdDynamicSettingsPricePrefix ad_group_ad.ad.responsive_display_ad.price_prefix],
        %w[MultiAssetResponsiveDisplayAdDynamicSettingsPromoText ad_group_ad.ad.responsive_display_ad.promo_text],
        %w[MultiAssetResponsiveDisplayAdFormatSetting ad_group_ad.ad.responsive_display_ad.format_setting],
        %w[MultiAssetResponsiveDisplayAdHeadlines ad_group_ad.ad.responsive_display_ad.headlines],
        %w[MultiAssetResponsiveDisplayAdLandscapeLogoImages ad_group_ad.ad.responsive_display_ad.logo_images],
        %w[MultiAssetResponsiveDisplayAdLogoImages ad_group_ad.ad.responsive_display_ad.square_logo_images],
        %w[MultiAssetResponsiveDisplayAdLongHeadline ad_group_ad.ad.responsive_display_ad.long_headline],
        %w[MultiAssetResponsiveDisplayAdMainColor ad_group_ad.ad.responsive_display_ad.main_color],
        %w[MultiAssetResponsiveDisplayAdMarketingImages ad_group_ad.ad.responsive_display_ad.marketing_images],
        %w[MultiAssetResponsiveDisplayAdSquareMarketingImages ad_group_ad.ad.responsive_display_ad.square_marketing_images],
        %w[MultiAssetResponsiveDisplayAdYouTubeVideos ad_group_ad.ad.responsive_display_ad.youtube_videos],
        %w[Path1 ad_group_ad.ad.expanded_text_ad.path1],
        %w[Path2 ad_group_ad.ad.expanded_text_ad.path2],
        %w[PercentNewVisitors metrics.percent_new_visitors],
        %w[PolicyTopicEntries ad_group_ad.policy_summary.policy_topic_entries],
        %w[PolicyApprovalStatus ad_group_ad.policy_summary.approval_status],
        %w[PricePrefix ad_group_ad.ad.legacy_responsive_display_ad.price_prefix],
        %w[PromoText ad_group_ad.ad.legacy_responsive_display_ad.promo_text],
        %w[Quarter segments.quarter],
        %w[ResponsiveSearchAdDescriptions ad_group_ad.ad.responsive_search_ad.descriptions],
        %w[ResponsiveSearchAdHeadlines ad_group_ad.ad.responsive_search_ad.headlines],
        %w[ResponsiveSearchAdPath1 ad_group_ad.ad.responsive_search_ad.path1],
        %w[ResponsiveSearchAdPath2 ad_group_ad.ad.responsive_search_ad.path2],
        %w[ShortHeadline ad_group_ad.ad.legacy_responsive_display_ad.short_headline],
        %w[Slot segments.slot],
        %w[Status ad_group_ad.status],
        %w[SystemManagedEntitySource ad_group_ad.ad.system_managed_resource_source],
        %w[TopImpressionPercentage metrics.top_impression_percentage],
        %w[UniversalAppAdDescriptions ad_group_ad.ad.app_ad.descriptions],
        %w[UniversalAppAdHeadlines ad_group_ad.ad.app_ad.headlines],
        %w[UniversalAppAdHtml5MediaBundles ad_group_ad.ad.app_ad.html5_media_bundles],
        %w[UniversalAppAdImages ad_group_ad.ad.app_ad.images],
        %w[UniversalAppAdMandatoryAdText ad_group_ad.ad.app_ad.mandatory_ad_text],
        %w[UniversalAppAdYouTubeVideos ad_group_ad.ad.app_ad.youtube_videos],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[ValuePerCurrentModelAttributedConversion metrics.value_per_current_model_attributed_conversion],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    ad_group_report_fields: lambda do |_connection|
      [
        %w[AbsoluteTopImpressionPercentage metrics.absolute_top_impression_percentage],
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdGroupType ad_group.type],
        %w[AdNetworkType segments.ad_network_type],
        %w[AdRotationMode ad_group.ad_rotation_mode],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[AveragePageviews metrics.average_page_views],
        %w[AverageTimeOnSite metrics.average_time_on_site],
        %w[BaseAdGroupId ad_group.base_ad_group],
        %w[BaseCampaignId campaign.base_campaign],
        %w[BiddingStrategyId campaign.bidding_strategy],
        %w[BiddingStrategyType campaign.bidding_strategy_type],
        %w[BounceRate metrics.bounce_rate],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ContentBidCriterionTypeGroup ad_group.display_custom_bid_dimension],
        %w[ContentImpressionShare metrics.content_impression_share],
        %w[ContentRankLostImpressionShare metrics.content_rank_lost_impression_share],
        %w[ConversionAdjustment segments.conversion_adjustment],
        %w[ConversionAdjustmentLagBucket segments.conversion_or_adjustment_lag_bucket],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionLagBucket segments.conversion_lag_bucket],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CostPerCurrentModelAttributedConversion metrics.cost_per_current_model_attributed_conversion],
        %w[CpcBid ad_group.cpc_bid_micros],
        %w[CpmBid ad_group.cpm_bid_micros],
        %w[CpvBid ad_group.cpv_bid_micros],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CurrentModelAttributedConversionValue metrics.current_model_attributed_conversions_value],
        %w[CurrentModelAttributedConversions metrics.current_model_attributed_conversions],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EffectiveTargetRoas ad_group.effective_target_roas],
        %w[EffectiveTargetRoasSource ad_group.effective_target_roas_source],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FinalUrlSuffix ad_group.final_url_suffix],
        %w[GmailForwards metrics.gmail_forwards],
        %w[GmailSaves metrics.gmail_saves],
        %w[GmailSecondaryClicks metrics.gmail_secondary_clicks],
        %w[HourOfDay segments.hour],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[NumOfflineImpressions metrics.phone_impressions],
        %w[NumOfflineInteractions metrics.phone_calls],
        %w[OfflineInteractionRate metrics.phone_through_rate],
        %w[PercentNewVisitors metrics.percent_new_visitors],
        %w[Quarter segments.quarter],
        %w[RelativeCtr metrics.relative_ctr],
        %w[SearchAbsoluteTopImpressionShare metrics.search_absolute_top_impression_share],
        %w[SearchBudgetLostAbsoluteTopImpressionShare metrics.search_budget_lost_absolute_top_impression_share],
        %w[SearchBudgetLostTopImpressionShare metrics.search_budget_lost_top_impression_share],
        %w[SearchExactMatchImpressionShare metrics.search_exact_match_impression_share],
        %w[SearchImpressionShare metrics.search_impression_share],
        %w[SearchRankLostAbsoluteTopImpressionShare metrics.search_rank_lost_absolute_top_impression_share],
        %w[SearchRankLostImpressionShare metrics.search_rank_lost_impression_share],
        %w[SearchRankLostTopImpressionShare metrics.search_rank_lost_top_impression_share],
        %w[SearchTopImpressionShare metrics.search_top_impression_share],
        %w[Slot segments.slot],
        %w[TargetCpa ad_group.effective_target_cpa_micros],
        %w[TargetCpaBidSource ad_group.effective_target_cpa_source],
        %w[TopImpressionPercentage metrics.top_impression_percentage],
        %w[TrackingUrlTemplate ad_group.tracking_url_template],
        %w[UrlCustomParameters ad_group.url_custom_parameters],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[ValuePerCurrentModelAttributedConversion metrics.value_per_current_model_attributed_conversion],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    age_range_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[BaseAdGroupId ad_group.base_ad_group],
        %w[BaseCampaignId campaign.base_campaign],
        %w[BidModifier ad_group_criterion.bid_modifier],
        %w[BiddingStrategyId campaign.bidding_strategy],
        %w[BiddingStrategyName bidding_strategy.name],
        %w[BiddingStrategyType campaign.bidding_strategy_type],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CpcBid ad_group_criterion.effective_cpc_bid_micros],
        %w[CpcBidSource ad_group_criterion.effective_cpc_bid_source],
        %w[CpmBid ad_group_criterion.effective_cpm_bid_micros],
        %w[CpmBidSource ad_group_criterion.effective_cpm_bid_source],
        %w[Criteria ad_group_criterion.age_range.type],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FinalMobileUrls ad_group_criterion.final_mobile_urls],
        %w[FinalUrls ad_group_criterion.final_urls],
        %w[GmailForwards metrics.gmail_forwards],
        %w[GmailSaves metrics.gmail_saves],
        %w[GmailSecondaryClicks metrics.gmail_secondary_clicks],
        %w[Id ad_group_criterion.criterion_id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsNegative ad_group_criterion.negative],
        %w[IsRestrict ad_group.targeting_setting.target_restrictions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[Status ad_group_criterion.status],
        %w[TrackingUrlTemplate ad_group_criterion.tracking_url_template],
        %w[UrlCustomParameters ad_group_criterion.url_custom_parameters],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    campaign_audience_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[BaseAdGroupId ad_group.base_ad_group],
        %w[BaseCampaignId campaign.base_campaign],
        %w[BiddingStrategyId campaign.bidding_strategy],
        %w[CampaignId ad_group.campaign],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CpcBid This should be campaign/ad group criterion depending on the view.],
        %w[CpcBidSource ad_group_criterion.effective_cpc_bid_source],
        %w[CpmBid ad_group_criterion.effective_cpm_bid_micros],
        %w[CpmBidSource ad_group_criterion.effective_cpm_bid_source],
        %w[Criteria This should be campaign/ad group bid modifier depending on the view.],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FinalMobileUrls ad_group_criterion.final_mobile_urls],
        %w[FinalUrls ad_group_criterion.final_urls],
        %w[GmailForwards metrics.gmail_forwards],
        %w[GmailSaves metrics.gmail_saves],
        %w[GmailSecondaryClicks metrics.gmail_secondary_clicks],
        %w[Id ad_group_criterion.criterion_id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsRestrict ad_group.targeting_setting.target_restrictions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[Slot segments.slot],
        %w[Status ad_group_criterion.status],
        %w[TrackingUrlTemplate ad_group.tracking_url_template],
        %w[UrlCustomParameters ad_group.url_custom_parameters],
        %w[UserListName user_list.name],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    ad_group_audience_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[BaseAdGroupId ad_group.base_ad_group],
        %w[BaseCampaignId campaign.base_campaign],
        %w[BiddingStrategyId campaign.bidding_strategy],
        %w[CampaignId ad_group.campaign],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CpcBidSource ad_group_criterion.effective_cpc_bid_source],
        %w[CpmBid ad_group_criterion.effective_cpm_bid_micros],
        %w[CpmBidSource ad_group_criterion.effective_cpm_bid_source],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FinalMobileUrls ad_group_criterion.final_mobile_urls],
        %w[FinalUrls ad_group_criterion.final_urls],
        %w[GmailForwards metrics.gmail_forwards],
        %w[GmailSaves metrics.gmail_saves],
        %w[GmailSecondaryClicks metrics.gmail_secondary_clicks],
        %w[Id ad_group_criterion.criterion_id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsRestrict ad_group.targeting_setting.target_restrictions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[Slot segments.slot],
        %w[Status ad_group_criterion.status],
        %w[TrackingUrlTemplate ad_group.tracking_url_template],
        %w[UrlCustomParameters ad_group.url_custom_parameters],
        %w[UserListName user_list.name],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    group_placement_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CriteriaParameters group_placement_view.placement_type],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Domain group_placement_view.target_url],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    bidding_strategy_report_fields: lambda do |_connection|
      [
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpm metrics.average_cpm],
        %w[CampaignCount bidding_strategy.campaign_count],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[HourOfDay segments.hour],
        %w[Id bidding_strategy.id],
        %w[Impressions metrics.impressions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[NonRemovedCampaignCount bidding_strategy.non_removed_campaign_count],
        %w[Quarter segments.quarter],
        %w[Status bidding_strategy.status],
        %w[TargetCpa bidding_strategy.target_cpa.target_cpa_micros],
        %w[TargetCpaMaxCpcBidCeiling bidding_strategy.target_cpa.cpc_bid_ceiling_micros],
        %w[TargetCpaMaxCpcBidFloor bidding_strategy.target_cpa.cpc_bid_floor_micros],
        %w[TargetRoas bidding_strategy.target_roas.target_roas],
        %w[TargetRoasBidCeiling bidding_strategy.target_roas.cpc_bid_ceiling_micros],
        %w[TargetRoasBidFloor bidding_strategy.target_roas.cpc_bid_floor_micros],
        %w[TargetSpendBidCeiling bidding_strategy.target_spend.cpc_bid_ceiling_micros],
        %w[TargetSpendSpendTarget bidding_strategy.target_spend.target_spend_micros],
        %w[Type bidding_strategy.type],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    campaign_budget_report_fields: lambda do |_connection|
      [
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[Amount campaign_budget.amount_micros],
        %w[AssociatedCampaignId campaign.id],
        %w[AssociatedCampaignName campaign.name],
        %w[AssociatedCampaignStatus campaign.status],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[BudgetCampaignAssociationStatus segments.budget_campaign_association_status.status],
        %w[BudgetId campaign_budget.id],
        %w[BudgetName campaign_budget.name],
        %w[BudgetReferenceCount campaign_budget.reference_count],
        %w[BudgetStatus campaign_budget.status],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[DeliveryMethod campaign_budget.delivery_method],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[HasRecommendedBudget campaign_budget.has_recommended_budget],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsBudgetExplicitlyShared campaign_budget.explicitly_shared],
        %w[Period campaign_budget.period],
        %w[RecommendedBudgetAmount campaign_budget.recommended_budget_amount_micros],
        %w[RecommendedBudgetEstimatedChangeInWeeklyClicks campaign_budget.recommended_budget_estimated_change_weekly_clicks],
        %w[RecommendedBudgetEstimatedChangeInWeeklyCost campaign_budget.recommended_budget_estimated_change_weekly_cost_micros],
        %w[RecommendedBudgetEstimatedChangeInWeeklyInteractions campaign_budget.recommended_budget_estimated_change_weekly_interactions],
        %w[RecommendedBudgetEstimatedChangeInWeeklyViews campaign_budget.recommended_budget_estimated_change_weekly_views],
        %w[TotalAmount campaign_budget.total_amount_micros],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    call_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[CallDuration call_view.call_duration_seconds],
        %w[CallEndTime call_view.end_call_date_time],
        %w[CallStartTime call_view.start_call_date_time],
        %w[CallStatus call_view.call_status],
        %w[CallTrackingDisplayLocation call_view.call_tracking_display_location],
        %w[CallType call_view.type],
        %w[CallerCountryCallingCode call_view.caller_area_code],
        %w[CallerNationalDesignatedCode call_view.caller_country_code],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[ExternalCustomerId customer.id],
        %w[HourOfDay segments.hour],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    ad_schedule_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[BidModifier campaign_criterion.bid_modifier],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[Id campaign_criterion.criterion_id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    campaign_criterion_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[BaseCampaignId campaign.base_campaign],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[Criteria campaign_criterion.keyword.text],
        %w[CriteriaType campaign_criterion.type],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[ExternalCustomerId customer.id],
        %w[Id campaign_criterion.criterion_id],
        %w[IsNegative campaign_criterion.negative]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    campaign_report_fields: lambda do |_connection|
      [
        %w[AbsoluteTopImpressionPercentage metrics.absolute_top_impression_percentage],
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdNetworkType segments.ad_network_type],
        %w[AdvertisingChannelSubType campaign.advertising_channel_sub_type],
        %w[AdvertisingChannelType campaign.advertising_channel_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[Amount campaign_budget.amount_micros],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[AveragePageviews metrics.average_page_views],
        %w[AverageTimeOnSite metrics.average_time_on_site],
        %w[BaseCampaignId campaign.base_campaign],
        %w[BiddingStrategyId campaign.bidding_strategy],
        %w[BiddingStrategyName bidding_strategy.name],
        %w[BiddingStrategyType campaign.bidding_strategy_type],
        %w[BounceRate metrics.bounce_rate],
        %w[BudgetId campaign.campaign_budget],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[CampaignTrialType campaign.experiment_type],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ContentBudgetLostImpressionShare metrics.content_budget_lost_impression_share],
        %w[ContentImpressionShare metrics.content_impression_share],
        %w[ContentRankLostImpressionShare metrics.content_rank_lost_impression_share],
        %w[ConversionAdjustment segments.conversion_adjustment],
        %w[ConversionAdjustmentLagBucket segments.conversion_or_adjustment_lag_bucket],
        %w[ConversionAttributionEventType segments.conversion_attribution_event_type],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionLagBucket segments.conversion_lag_bucket],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CostPerCurrentModelAttributedConversion metrics.cost_per_current_model_attributed_conversion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CurrentModelAttributedConversionValue metrics.current_model_attributed_conversions_value],
        %w[CurrentModelAttributedConversions metrics.current_model_attributed_conversions],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EndDate campaign.end_date],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FinalUrlSuffix campaign.final_url_suffix],
        %w[GmailForwards metrics.gmail_forwards],
        %w[GmailSaves metrics.gmail_saves],
        %w[GmailSecondaryClicks metrics.gmail_secondary_clicks],
        %w[HasRecommendedBudget campaign_budget.has_recommended_budget],
        %w[HourOfDay segments.hour],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[InvalidClickRate metrics.invalid_click_rate],
        %w[InvalidClicks metrics.invalid_clicks],
        %w[IsBudgetExplicitlyShared campaign_budget.explicitly_shared],
        %w[MaximizeConversionValueTargetRoas campaign.maximize_conversion_value.target_roas],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[NumOfflineImpressions metrics.phone_impressions],
        %w[NumOfflineInteractions metrics.phone_calls],
        %w[OfflineInteractionRate metrics.phone_through_rate],
        %w[PercentNewVisitors metrics.percent_new_visitors],
        %w[Period campaign_budget.period],
        %w[Quarter segments.quarter],
        %w[RecommendedBudgetAmount campaign_budget.recommended_budget_amount_micros],
        %w[RelativeCtr metrics.relative_ctr],
        %w[SearchAbsoluteTopImpressionShare metrics.search_absolute_top_impression_share],
        %w[SearchBudgetLostAbsoluteTopImpressionShare metrics.search_budget_lost_absolute_top_impression_share],
        %w[SearchBudgetLostImpressionShare metrics.search_budget_lost_impression_share],
        %w[SearchBudgetLostTopImpressionShare metrics.search_budget_lost_top_impression_share],
        %w[SearchClickShare metrics.search_click_share],
        %w[SearchExactMatchImpressionShare metrics.search_exact_match_impression_share],
        %w[SearchImpressionShare metrics.search_impression_share],
        %w[SearchRankLostAbsoluteTopImpressionShare metrics.search_rank_lost_absolute_top_impression_share],
        %w[SearchRankLostImpressionShare metrics.search_rank_lost_impression_share],
        %w[SearchRankLostTopImpressionShare metrics.search_rank_lost_top_impression_share],
        %w[SearchTopImpressionShare metrics.search_top_impression_share],
        %w[ServingStatus campaign.serving_status],
        %w[Slot segments.slot],
        %w[StartDate campaign.start_date],
        %w[TopImpressionPercentage metrics.top_impression_percentage],
        %w[TotalAmount campaign_budget.total_amount_micros],
        %w[TrackingUrlTemplate campaign.tracking_url_template],
        %w[UrlCustomParameters campaign.url_custom_parameters],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[ValuePerCurrentModelAttributedConversion metrics.value_per_current_model_attributed_conversion],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    campaign_shared_set_report_fields: lambda do |_connection|
      [
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ExternalCustomerId customer.id],
        %w[SharedSetId shared_set.id],
        %w[SharedSetName shared_set.name],
        %w[SharedSetType shared_set.type],
        %w[Status campaign_shared_set.status]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    location_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[BidModifier campaign_criterion.bid_modifier],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[Id campaign_criterion.criterion_id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsNegative campaign_criterion.negative],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    click_view_report_fields: lambda do |_connection|
      [
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AoiCityCriteriaId click_view.area_of_interest.city],
        %w[AoiCountryCriteriaId click_view.area_of_interest.country],
        %w[AoiMetroCriteriaId click_view.area_of_interest.metro],
        %w[AoiMostSpecificTargetId click_view.area_of_interest.most_specific],
        %w[AoiRegionCriteriaId click_view.area_of_interest.region],
        %w[CampaignId campaign.id],
        %w[CampaignLocationTargetId click_view.campaign_location_target],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[CreativeId click_view.ad_group_ad],
        %w[Date segments.date],
        %w[Device segments.device],
        %w[ExternalCustomerId customer.id],
        %w[GclId click_view.gclid],
        %w[LopCityCriteriaId click_view.location_of_presence.city],
        %w[LopCountryCriteriaId click_view.location_of_presence.country],
        %w[LopMetroCriteriaId click_view.location_of_presence.metro],
        %w[LopMostSpecificTargetId click_view.location_of_presence.most_specific],
        %w[LopRegionCriteriaId click_view.location_of_presence.region],
        %w[MonthOfYear segments.month_of_year],
        %w[Page click_view.page_number],
        %w[Slot segments.slot],
        %w[UserListId click_view.user_list]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    display_keyword_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[BaseAdGroupId ad_group.base_ad_group],
        %w[BaseCampaignId campaign.base_campaign],
        %w[BiddingStrategyId campaign.bidding_strategy],
        %w[BiddingStrategyType campaign.bidding_strategy_type],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CpcBid ad_group_criterion.effective_cpc_bid_micros],
        %w[CpcBidSource ad_group_criterion.effective_cpc_bid_source],
        %w[CpmBid ad_group_criterion.effective_cpm_bid_micros],
        %w[CpmBidSource ad_group_criterion.effective_cpm_bid_source],
        %w[CpvBid ad_group_criterion.effective_cpv_bid_micros],
        %w[CpvBidSource ad_group_criterion.effective_cpv_bid_source],
        %w[Criteria ad_group_criterion.keyword.text],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FinalMobileUrls ad_group_criterion.final_mobile_urls],
        %w[FinalUrls ad_group_criterion.final_urls],
        %w[GmailForwards metrics.gmail_forwards],
        %w[GmailSaves metrics.gmail_saves],
        %w[GmailSecondaryClicks metrics.gmail_secondary_clicks],
        %w[Id ad_group_criterion.criterion_id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsNegative ad_group_criterion.negative],
        %w[IsRestrict ad_group.targeting_setting.target_restrictions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[Status ad_group_criterion.status],
        %w[TrackingUrlTemplate ad_group_criterion.tracking_url_template],
        %w[UrlCustomParameters ad_group_criterion.url_custom_parameters],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    topic_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[BaseAdGroupId ad_group.base_ad_group],
        %w[BaseCampaignId campaign.base_campaign],
        %w[BidModifier ad_group_criterion.bid_modifier],
        %w[BiddingStrategyId campaign.bidding_strategy],
        %w[BiddingStrategyType campaign.bidding_strategy_type],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CpcBid ad_group_criterion.effective_cpc_bid_micros],
        %w[CpcBidSource ad_group_criterion.effective_cpc_bid_source],
        %w[CpmBid ad_group_criterion.effective_cpm_bid_micros],
        %w[CpmBidSource ad_group_criterion.effective_cpm_bid_source],
        %w[Criteria ad_group_criterion.topic.path],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FinalMobileUrls ad_group_criterion.final_mobile_urls],
        %w[FinalUrls ad_group_criterion.final_urls],
        %w[GmailForwards metrics.gmail_forwards],
        %w[GmailSaves metrics.gmail_saves],
        %w[GmailSecondaryClicks metrics.gmail_secondary_clicks],
        %w[Id ad_group_criterion.criterion_id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsNegative ad_group_criterion.negative],
        %w[IsRestrict ad_group.targeting_setting.target_restrictions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[Status ad_group_criterion.status],
        %w[TrackingUrlTemplate ad_group_criterion.tracking_url_template],
        %w[UrlCustomParameters ad_group_criterion.url_custom_parameters],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VerticalId ad_group_criterion.topic.topic_constant],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    gender_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[BaseAdGroupId ad_group.base_ad_group],
        %w[BaseCampaignId campaign.base_campaign],
        %w[BidModifier ad_group_criterion.bid_modifier],
        %w[BiddingStrategyId campaign.bidding_strategy],
        %w[BiddingStrategyName bidding_strategy.name],
        %w[BiddingStrategyType bidding_strategy.type],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CpcBid ad_group_criterion.effective_cpc_bid_micros],
        %w[CpcBidSource ad_group_criterion.effective_cpc_bid_source],
        %w[CpmBid ad_group_criterion.effective_cpm_bid_micros],
        %w[CpmBidSource ad_group_criterion.effective_cpm_bid_source],
        %w[Criteria ad_group_criterion.gender.type],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FinalMobileUrls ad_group_criterion.final_mobile_urls],
        %w[FinalUrls ad_group_criterion.final_urls],
        %w[GmailForwards metrics.gmail_forwards],
        %w[GmailSaves metrics.gmail_saves],
        %w[GmailSecondaryClicks metrics.gmail_secondary_clicks],
        %w[Id ad_group_criterion.criterion_id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsNegative ad_group_criterion.negative],
        %w[IsRestrict ad_group.targeting_setting.target_restrictions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[Status ad_group_criterion.status],
        %w[TrackingUrlTemplate ad_group_criterion.tracking_url_template],
        %w[UrlCustomParameters ad_group_criterion.url_custom_parameters],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    geographic_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[CityCriteriaId segments.geo_target_city],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CountryCriteriaId geographic_view.country_criterion_id],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsTargetingLocation user_location_view.targeting_location],
        %w[LocationType geographic_view.location_type],
        %w[MetroCriteriaId segments.geo_target_metro],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[MostSpecificCriteriaId segments.geo_target_most_specific_location],
        %w[Quarter segments.quarter],
        %w[RegionCriteriaId segments.geo_target_region],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    user_location_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[CityCriteriaId segments.geo_target_city],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CountryCriteriaId user_location_view.country_criterion_id],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsTargetingLocation user_location_view.targeting_location],
        %w[LocationType geographic_view.location_type],
        %w[MetroCriteriaId segments.geo_target_metro],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[MostSpecificCriteriaId segments.geo_target_most_specific_location],
        %w[Quarter segments.quarter],
        %w[RegionCriteriaId segments.geo_target_region],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    dynamic_search_ads_search_term_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpm metrics.average_cpm],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CriterionId segments.webpage],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[Impressions metrics.impressions],
        %w[Line1 dynamic_search_ads_search_term_view.headline],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[Query dynamic_search_ads_search_term_view.search_term],
        %w[Url dynamic_search_ads_search_term_view.landing_page],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    keyword_view_report_fields: lambda do |_connection|
      [
        %w[AbsoluteTopImpressionPercentage metrics.absolute_top_impression_percentage],
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[ApprovalStatus ad_group_criterion.approval_status],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[AveragePageviews metrics.average_page_views],
        %w[AverageTimeOnSite metrics.average_time_on_site],
        %w[BaseAdGroupId ad_group.base_ad_group],
        %w[BaseCampaignId campaign.base_campaign],
        %w[BiddingStrategyId campaign.bidding_strategy],
        %w[BiddingStrategyType campaign.bidding_strategy_type],
        %w[BounceRate metrics.bounce_rate],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionAdjustment segments.conversion_adjustment],
        %w[ConversionAdjustmentLagBucket segments.conversion_or_adjustment_lag_bucket],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionLagBucket segments.conversion_lag_bucket],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CostPerCurrentModelAttributedConversion metrics.cost_per_current_model_attributed_conversion],
        %w[CpcBid ad_group_criterion.effective_cpc_bid_micros],
        %w[CpcBidSource ad_group_criterion.effective_cpc_bid_source],
        %w[CpmBid ad_group_criterion.effective_cpm_bid_micros],
        %w[CreativeQualityScore ad_group_criterion.quality_info.creative_quality_score],
        %w[Criteria ad_group_criterion.keyword.text],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CurrentModelAttributedConversionValue metrics.current_model_attributed_conversions_value],
        %w[CurrentModelAttributedConversions metrics.current_model_attributed_conversions],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[EnhancedCpcEnabled campaign.manual_cpc.enhanced_cpc_enabled],
        %w[EstimatedAddClicksAtFirstPositionCpc ad_group_criterion.position_estimates.estimated_add_clicks_at_first_position_cpc],
        %w[EstimatedAddCostAtFirstPositionCpc ad_group_criterion.position_estimates.estimated_add_cost_at_first_position_cpc],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FinalMobileUrls ad_group_criterion.final_mobile_urls],
        %w[FinalUrlSuffix ad_group_criterion.final_url_suffix],
        %w[FinalUrls ad_group_criterion.final_urls],
        %w[FirstPageCpc ad_group_criterion.position_estimates.first_page_cpc_micros],
        %w[FirstPositionCpc ad_group_criterion.position_estimates.first_position_cpc_micros],
        %w[GmailForwards metrics.gmail_forwards],
        %w[GmailSaves metrics.gmail_saves],
        %w[GmailSecondaryClicks metrics.gmail_secondary_clicks],
        %w[HistoricalCreativeQualityScore metrics.historical_creative_quality_score],
        %w[HistoricalLandingPageQualityScore metrics.historical_landing_page_quality_score],
        %w[HistoricalQualityScore metrics.historical_quality_score],
        %w[HistoricalSearchPredictedCtr metrics.historical_search_predicted_ctr],
        %w[Id ad_group_criterion.criterion_id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsNegative ad_group_criterion.negative],
        %w[KeywordMatchType ad_group_criterion.keyword.match_type],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[PercentNewVisitors metrics.percent_new_visitors],
        %w[PostClickQualityScore ad_group_criterion.quality_info.post_click_quality_score],
        %w[QualityScore ad_group_criterion.quality_info.quality_score],
        %w[Quarter segments.quarter],
        %w[SearchAbsoluteTopImpressionShare metrics.search_absolute_top_impression_share],
        %w[SearchBudgetLostAbsoluteTopImpressionShare metrics.search_budget_lost_absolute_top_impression_share],
        %w[SearchBudgetLostTopImpressionShare metrics.search_budget_lost_top_impression_share],
        %w[SearchExactMatchImpressionShare metrics.search_exact_match_impression_share],
        %w[SearchImpressionShare metrics.search_impression_share],
        %w[SearchPredictedCtr ad_group_criterion.quality_info.search_predicted_ctr],
        %w[SearchRankLostAbsoluteTopImpressionShare metrics.search_rank_lost_absolute_top_impression_share],
        %w[SearchRankLostImpressionShare metrics.search_rank_lost_impression_share],
        %w[SearchRankLostTopImpressionShare metrics.search_rank_lost_top_impression_share],
        %w[SearchTopImpressionShare metrics.search_top_impression_share],
        %w[Slot segments.slot],
        %w[Status ad_group_criterion.status],
        %w[SystemServingStatus ad_group_criterion.system_serving_status],
        %w[TopImpressionPercentage metrics.top_impression_percentage],
        %w[TopOfPageCpc ad_group_criterion.position_estimates.top_of_page_cpc_micros],
        %w[TrackingUrlTemplate ad_group_criterion.tracking_url_template],
        %w[UrlCustomParameters ad_group_criterion.url_custom_parameters],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[ValuePerCurrentModelAttributedConversion metrics.value_per_current_model_attributed_conversion],
        %w[VerticalId ad_group_criterion.topic.topic_constant],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    label_report_fields: lambda do |_connection|
      [
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[ExternalCustomerId customer.id],
        %w[LabelId label.id],
        %w[LabelName label.name]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    landing_page_view_report_fields: lambda do |_connection|
      [
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AdvertisingChannelType campaign.advertising_channel_type],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExpandedFinalUrlString expanded_landing_page_view.expanded_final_url],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[PercentageMobileFriendlyClicks metrics.mobile_friendly_clicks_percentage],
        %w[PercentageValidAcceleratedMobilePagesClicks metrics.valid_accelerated_mobile_pages_clicks_percentage],
        %w[Quarter segments.quarter],
        %w[Slot segments.slot],
        %w[SpeedScore metrics.speed_score],
        %w[UnexpandedFinalUrlString landing_page_view.unexpanded_final_url],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    expanded_landing_page_view_report_fields: lambda do |_connection|
      [
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AdvertisingChannelType campaign.advertising_channel_type],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExpandedFinalUrlString expanded_landing_page_view.expanded_final_url],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[PercentageMobileFriendlyClicks metrics.mobile_friendly_clicks_percentage],
        %w[PercentageValidAcceleratedMobilePagesClicks metrics.valid_accelerated_mobile_pages_clicks_percentage],
        %w[Quarter segments.quarter],
        %w[Slot segments.slot],
        %w[SpeedScore metrics.speed_score],
        %w[UnexpandedFinalUrlString landing_page_view.unexpanded_final_url],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    paid_organic_search_term_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AverageCpc metrics.average_cpc],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[Clicks metrics.clicks],
        %w[CombinedAdsOrganicClicks metrics.combined_clicks],
        %w[CombinedAdsOrganicClicksPerQuery metrics.combined_clicks_per_query],
        %w[CombinedAdsOrganicQueries metrics.combined_queries],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[ExternalCustomerId customer.id],
        %w[Impressions metrics.impressions],
        %w[KeywordId segments.keyword.ad_group_criterion],
        %w[KeywordTextMatchingQuery segments.keyword.info.text],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[OrganicClicks metrics.organic_clicks],
        %w[OrganicClicksPerQuery metrics.organic_clicks_per_query],
        %w[OrganicImpressions metrics.organic_impressions],
        %w[OrganicImpressionsPerQuery metrics.organic_impressions_per_query],
        %w[OrganicQueries metrics.organic_queries],
        %w[Quarter segments.quarter],
        %w[SearchQuery paid_organic_search_term_view.search_term],
        %w[SerpType segments.search_engine_results_page_type],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    parental_status_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[BaseAdGroupId ad_group.base_ad_group],
        %w[BaseCampaignId campaign.base_campaign],
        %w[BiddingStrategyId campaign.bidding_strategy],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CpcBid ad_group_criterion.effective_cpc_bid_micros],
        %w[CpcBidSource ad_group_criterion.effective_cpc_bid_source],
        %w[CpmBid ad_group_criterion.effective_cpm_bid_micros],
        %w[CpmBidSource ad_group_criterion.effective_cpm_bid_source],
        %w[Criteria ad_group_criterion.parental_status.type],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FinalMobileUrls ad_group_criterion.final_mobile_urls],
        %w[FinalUrls ad_group_criterion.final_urls],
        %w[GmailForwards metrics.gmail_forwards],
        %w[GmailSaves metrics.gmail_saves],
        %w[GmailSecondaryClicks metrics.gmail_secondary_clicks],
        %w[Id ad_group_criterion.criterion_id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsNegative ad_group_criterion.negative],
        %w[IsRestrict ad_group.targeting_setting.target_restrictions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[Status ad_group_criterion.status],
        %w[TrackingUrlTemplate ad_group_criterion.tracking_url_template],
        %w[UrlCustomParameters ad_group_criterion.url_custom_parameters],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    feed_item_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdId ad_group_ad.resource_name],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AttributeValues feed_item.attribute_values],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EndTime feed_item.end_date_time],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FeedId feed_item.feed],
        %w[FeedItemId feed_item.id],
        %w[GeoTargetingCriterionId feed_item_target.feed_item_target_id],
        %w[GeoTargetingRestriction feed_item.geo_targeting_restriction],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsSelfAction segments.interaction_on_this_extension],
        %w[KeywordMatchType feed_item_target.keyword.match_type],
        %w[KeywordTargetingId feed_item_target.feed_item_target_id],
        %w[KeywordTargetingMatchType feed_item_target.keyword.match_type],
        %w[KeywordTargetingText feed_item_target.keyword.text],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[PlaceholderType segments.placeholder_type],
        %w[Quarter segments.quarter],
        %w[Scheduling feed_item_target.ad_schedule],
        %w[Slot segments.slot],
        %w[StartTime feed_item.start_date_time],
        %w[Status feed_item.status],
        %w[TargetingAdGroupId feed_item_target.ad_group],
        %w[TargetingCampaignId feed_item_target.campaign],
        %w[UrlCustomParameters feed_item.url_custom_parameters],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    feed_item_target_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdId ad_group_ad.resource_name],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AttributeValues feed_item.attribute_values],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EndTime feed_item.end_date_time],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FeedId feed_item.feed],
        %w[FeedItemId feed_item.id],
        %w[GeoTargetingCriterionId feed_item_target.feed_item_target_id],
        %w[GeoTargetingRestriction feed_item.geo_targeting_restriction],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsSelfAction segments.interaction_on_this_extension],
        %w[KeywordMatchType feed_item_target.keyword.match_type],
        %w[KeywordTargetingId feed_item_target.feed_item_target_id],
        %w[KeywordTargetingMatchType feed_item_target.keyword.match_type],
        %w[KeywordTargetingText feed_item_target.keyword.text],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[PlaceholderType segments.placeholder_type],
        %w[Quarter segments.quarter],
        %w[Scheduling feed_item_target.ad_schedule],
        %w[Slot segments.slot],
        %w[StartTime feed_item.start_date_time],
        %w[Status feed_item.status],
        %w[TargetingAdGroupId feed_item_target.ad_group],
        %w[TargetingCampaignId feed_item_target.campaign],
        %w[UrlCustomParameters feed_item.url_custom_parameters],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    feed_placeholder_view_report_fields: lambda do |_connection|
      [
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[CampaignId campaign],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExtensionPlaceholderCreativeId ad_group_ad.resource_name],
        %w[ExtensionPlaceholderType feed_placeholder_view.placeholder_type],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[Slot segments.slot],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    managed_placement_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[BaseAdGroupId ad_group.base_ad_group],
        %w[BaseCampaignId campaign.base_campaign],
        %w[BidModifier ad_group_criterion.bid_modifier],
        %w[BiddingStrategyId campaign.bidding_strategy],
        %w[BiddingStrategyName bidding_strategy.name],
        %w[BiddingStrategyType bidding_strategy.type],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.all_conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CpcBid ad_group_criterion.effective_cpc_bid_micros],
        %w[CpcBidSource ad_group_criterion.effective_cpc_bid_source],
        %w[CpmBid ad_group_criterion.effective_cpm_bid_micros],
        %w[CpmBidSource ad_group_criterion.effective_cpm_bid_source],
        %w[Criteria ad_group_criterion.placement.url],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FinalMobileUrls ad_group_criterion.final_mobile_urls],
        %w[FinalUrls ad_group_criterion.final_urls],
        %w[GmailForwards metrics.gmail_forwards],
        %w[GmailSaves metrics.gmail_saves],
        %w[GmailSecondaryClicks metrics.gmail_secondary_clicks],
        %w[Id ad_group_criterion.criterion_id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[IsNegative ad_group_criterion.negative],
        %w[IsRestrict ad_group.targeting_setting.target_restrictions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[Status ad_group_criterion.status],
        %w[TrackingUrlTemplate ad_group_criterion.tracking_url_template],
        %w[UrlCustomParameters ad_group_criterion.url_custom_parameters],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    product_group_view_report_fields: lambda do |_connection|
      [
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpm metrics.average_cpm],
        %w[BenchmarkAverageMaxCpc metrics.benchmark_average_max_cpc],
        %w[BenchmarkCtr metrics.benchmark_ctr],
        %w[BiddingStrategyType campaign.bidding_strategy_type],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CpcBid ad_group_criterion.cpc_bid_micros],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FinalUrlSuffix ad_group_criterion.final_url_suffix],
        %w[Id ad_group_criterion.criterion_id],
        %w[Impressions metrics.impressions],
        %w[IsNegative ad_group_criterion.negative],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[ParentCriterionId ad_group_criterion.listing_group.parent_ad_group_criterion],
        %w[PartitionType ad_group_criterion.listing_group.type],
        %w[Quarter segments.quarter],
        %w[SearchAbsoluteTopImpressionShare metrics.search_absolute_top_impression_share],
        %w[SearchClickShare metrics.search_click_share],
        %w[SearchImpressionShare metrics.search_impression_share],
        %w[TrackingUrlTemplate ad_group_criterion.tracking_url_template],
        %w[UrlCustomParameters ad_group_criterion.url_custom_parameters],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    search_term_view_report_fields: lambda do |_connection|
      [
        %w[AbsoluteTopImpressionPercentage metrics.absolute_top_impression_percentage],
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CreativeId ad_group_ad.ad.id],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[FinalUrl ad_group_ad.ad.final_urls],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[KeywordId segments.keyword.ad_group_criterion],
        %w[KeywordTextMatchingQuery segments.keyword.info.text],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[Query search_term_view.search_term],
        %w[QueryMatchTypeWithVariant segments.search_term_match_type],
        %w[QueryTargetingStatus search_term_view.status],
        %w[TopImpressionPercentage metrics.top_impression_percentage],
        %w[TrackingUrlTemplate ad_group_ad.ad.tracking_url_template],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    shared_criterion_report_fields: lambda do |_connection|
      [
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[Criteria shared_criterion.keyword.text],
        %w[ExternalCustomerId customer.id],
        %w[Id shared_criterion.criterion_id],
        %w[KeywordMatchType shared_criterion.keyword.match_type],
        %w[SharedSetId shared_set.id]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    shopping_performance_view_report_fields: lambda do |_connection|
      [
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AggregatorId segments.product_aggregator_id],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCpc metrics.average_cpc],
        %w[Brand segments.product_brand],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[CategoryL1 segments.product_bidding_category_level1],
        %w[CategoryL2 segments.product_bidding_category_level2],
        %w[CategoryL3 segments.product_bidding_category_level3],
        %w[CategoryL4 segments.product_bidding_category_level4],
        %w[CategoryL5 segments.product_bidding_category_level5],
        %w[Channel segments.product_channel],
        %w[ChannelExclusivity segments.product_channel_exclusivity],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CountryCriteriaId segments.product_country],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomAttribute0 segments.product_custom_attribute0],
        %w[CustomAttribute1 segments.product_custom_attribute1],
        %w[CustomAttribute2 segments.product_custom_attribute2],
        %w[CustomAttribute3 segments.product_custom_attribute3],
        %w[CustomAttribute4 segments.product_custom_attribute4],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[Impressions metrics.impressions],
        %w[LanguageCriteriaId segments.product_language],
        %w[MerchantId segments.product_merchant_id],
        %w[Month segments.month],
        %w[OfferId segments.product_item_id],
        %w[ProductCondition segments.product_condition],
        %w[ProductTitle segments.product_title],
        %w[ProductTypeL1 segments.product_type_l1],
        %w[ProductTypeL2 segments.product_type_l2],
        %w[ProductTypeL3 segments.product_type_l3],
        %w[ProductTypeL4 segments.product_type_l4],
        %w[ProductTypeL5 segments.product_type_l5],
        %w[Quarter segments.quarter],
        %w[SearchAbsoluteTopImpressionShare metrics.search_absolute_top_impression_share],
        %w[SearchClickShare metrics.search_click_share],
        %w[SearchImpressionShare metrics.search_impression_share],
        %w[StoreId segments.product_store_id],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    detail_placement_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[ActiveViewCpm metrics.active_view_cpm],
        %w[ActiveViewCtr metrics.active_view_ctr],
        %w[ActiveViewImpressions metrics.active_view_impressions],
        %w[ActiveViewMeasurability metrics.active_view_measurability],
        %w[ActiveViewMeasurableCost metrics.active_view_measurable_cost_micros],
        %w[ActiveViewMeasurableImpressions metrics.active_view_measurable_impressions],
        %w[ActiveViewViewability metrics.active_view_viewability],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCost metrics.average_cost],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpe metrics.average_cpe],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.all_conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[DisplayName detail_placement_view.display_name],
        %w[Domain detail_placement_view.group_placement_target_url],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[Impressions metrics.impressions],
        %w[InteractionRate metrics.interaction_rate],
        %w[InteractionTypes metrics.interaction_event_types],
        %w[Interactions metrics.interactions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[Url detail_placement_view.target_url],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    distance_view_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCpc metrics.average_cpc],
        %w[AverageCpm metrics.average_cpm],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[DistanceBucket distance_view.distance_bucket],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[Impressions metrics.impressions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[ValuePerConversion metrics.value_per_conversion],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,
    video_report_fields: lambda do |_connection|
      [
        %w[AccountCurrencyCode customer.currency_code],
        %w[AccountDescriptiveName customer.descriptive_name],
        %w[AccountTimeZone customer.time_zone],
        %w[AdGroupId ad_group.id],
        %w[AdGroupName ad_group.name],
        %w[AdGroupStatus ad_group.status],
        %w[AdNetworkType segments.ad_network_type],
        %w[AllConversionRate metrics.all_conversions_from_interactions_rate],
        %w[AllConversionValue metrics.all_conversions_value],
        %w[AllConversions metrics.all_conversions],
        %w[AverageCpm metrics.average_cpm],
        %w[AverageCpv metrics.average_cpv],
        %w[CampaignId campaign.id],
        %w[CampaignName campaign.name],
        %w[CampaignStatus campaign.status],
        %w[ClickType segments.click_type],
        %w[Clicks metrics.clicks],
        %w[ConversionCategoryName segments.conversion_action_category],
        %w[ConversionRate metrics.all_conversions_from_interactions_rate],
        %w[ConversionTrackerId segments.conversion_action],
        %w[ConversionTypeName segments.conversion_action_name],
        %w[ConversionValue metrics.conversions_value],
        %w[Conversions metrics.conversions],
        %w[Cost metrics.cost_micros],
        %w[CostPerAllConversion metrics.cost_per_all_conversions],
        %w[CostPerConversion metrics.cost_per_conversion],
        %w[CreativeId ad_group_ad.ad.id],
        %w[CreativeStatus ad_group_ad.status],
        %w[CrossDeviceConversions metrics.cross_device_conversions],
        %w[Ctr metrics.ctr],
        %w[CustomerDescriptiveName customer.descriptive_name],
        %w[Date segments.date],
        %w[DayOfWeek segments.day_of_week],
        %w[Device segments.device],
        %w[EngagementRate metrics.engagement_rate],
        %w[Engagements metrics.engagements],
        %w[ExternalConversionSource segments.external_conversion_source],
        %w[ExternalCustomerId customer.id],
        %w[Impressions metrics.impressions],
        %w[Month segments.month],
        %w[MonthOfYear segments.month_of_year],
        %w[Quarter segments.quarter],
        %w[ValuePerAllConversion metrics.value_per_all_conversions],
        %w[VideoChannelId video.channel_id],
        %w[VideoDuration video.duration_millis],
        %w[VideoId video.id],
        %w[VideoQuartile100Rate metrics.video_quartile_p100_rate],
        %w[VideoQuartile25Rate metrics.video_quartile_p25_rate],
        %w[VideoQuartile50Rate metrics.video_quartile_p50_rate],
        %w[VideoQuartile75Rate metrics.video_quartile_p75_rate],
        %w[VideoTitle video.title],
        %w[VideoViewRate metrics.video_view_rate],
        %w[VideoViews metrics.video_views],
        %w[ViewThroughConversions metrics.view_through_conversions],
        %w[Week segments.week],
        %w[Year segments.year]
      ].map { |item| [item.first.labelize, item.last] }
    end,

    #==================#
    # Object picklists #
    #==================#
    search_object_list: lambda do |_connection|
      [%w[Campaigns campaign], %w[Customer\ clients customer_client], %w[User\ lists user_list]]
    end,
    get_object_list: lambda do |_connection|
      [%w[Campaign campaign]]
    end,
    create_object_list: lambda do |_connection|
      [%w[Campaign campaign], %w[User\ list user_list]]
    end,
    update_object_list: lambda do |_connection|
      [%w[Campaign campaign], %w[User\ list user_list]]
    end,
    delete_object_list: lambda do |_connection|
      [%w[Campaign campaign], %w[User\ list user_list]]
    end,
    new_object_list: lambda do |_connection|
      [%w[Campaign campaign], %w[Ad\ group ad_group], %w[Ad ad_group_ad]]
    end,
    sort_order: lambda do |_connection|
      [%w[Descending DESC], %w[Ascending ASC]]
    end,

    #===========================#
    # Campaign object picklists #
    #===========================#
    campaign_fields: lambda do |_connection|
      %w[accessible_bidding_strategy
         ad_serving_optimization_status
         advertising_channel_sub_type
         advertising_channel_type
         app_campaign_setting.app_id
         app_campaign_setting.app_store
         app_campaign_setting.bidding_strategy_goal_type
         base_campaign
         bidding_strategy
         bidding_strategy_type
         campaign_budget
         commission.commission_rate_micros
         dynamic_search_ads_setting.domain_name
         dynamic_search_ads_setting.feeds
         dynamic_search_ads_setting.language_code
         dynamic_search_ads_setting.use_supplied_urls_only
         end_date
         excluded_parent_asset_field_types
         experiment_type
         final_url_suffix
         frequency_caps
         geo_target_type_setting.negative_geo_target_type
         geo_target_type_setting.positive_geo_target_type
         hotel_setting.hotel_center_id
         id
         labels
         local_campaign_setting.location_source_type
         manual_cpc.enhanced_cpc_enabled
         manual_cpm
         manual_cpv
         maximize_conversion_value.target_roas
         maximize_conversions.target_cpa
         name
         network_settings.target_content_network
         network_settings.target_google_search
         network_settings.target_partner_search_network
         network_settings.target_search_network
         optimization_goal_setting.optimization_goal_types
         optimization_score
         payment_mode
         percent_cpc.cpc_bid_ceiling_micros
         percent_cpc.enhanced_cpc_enabled
         real_time_bidding_setting.opt_in
         resource_name
         selective_optimization.conversion_actions
         serving_status
         shopping_setting.campaign_priority
         shopping_setting.enable_local
         shopping_setting.merchant_id
         shopping_setting.sales_country
         start_date
         status
         target_cpa.cpc_bid_ceiling_micros
         target_cpa.cpc_bid_floor_micros
         target_cpa.target_cpa_micros
         target_cpm
         target_impression_share.cpc_bid_ceiling_micros
         target_impression_share.location
         target_impression_share.location_fraction_micros
         target_roas.cpc_bid_ceiling_micros
         target_roas.cpc_bid_floor_micros
         target_roas.target_roas
         target_spend.cpc_bid_ceiling_micros
         target_spend.target_spend_micros
         targeting_setting.target_restrictions
         tracking_setting.tracking_url
         tracking_url_template
         url_custom_parameters
         vanity_pharma.vanity_pharma_display_url_mode
         vanity_pharma.vanity_pharma_text
         video_brand_safety_suitability].map { |item| [item.split('.').last.labelize, "campaign.#{item}"] }
    end,
    campaign_statuses: lambda do |_connection|
      %w[ENABLED PAUSED REMOVED].map { |item| [item.downcase.labelize, item] }
    end,
    campaign_ad_serving_optimization_statuses: lambda do |_connection|
      %w[OPTIMIZE CONVERSION_OPTIMIZE
         ROTATE ROTATE_INDEFINITELY UNAVAILABLE].map { |item| [item.downcase.labelize, item] }
    end,
    campaign_ad_channel_types: lambda do |_connection|
      %w[SEARCH DISPLAY SHOPPING
         HOTEL VIDEO MULTI_CHANNEL LOCAL SMART].map { |item| [item.downcase.labelize, item] }
    end,
    campaign_ad_channel_sub_types: lambda do |_connection|
      %w[SEARCH_MOBILE_APP DISPLAY_MOBILE_APP
         SEARCH_EXPRESS DISPLAY_EXPRESS SHOPPING_SMART_ADS DISPLAY_GMAIL_AD
         DISPLAY_SMART_CAMPAIGN VIDEO_OUTSTREAM VIDEO_ACTION VIDEO_NON_SKIPPABLE
         APP_CAMPAIGN APP_CAMPAIGN_FOR_ENGAGEMENT LOCAL_CAMPAIGN
         SHOPPING_COMPARISON_LISTING_ADS SMART_CAMPAIGN VIDEO_SEQUENCE].
        map { |item| [item.downcase.labelize, item] }
    end,
    campaign_targeting_dimensions: lambda do |_connection|
      %w[KEYWORD AUDIENCE TOPIC
         GENDER AGE_RANGE PLACEMENT PARENTAL_STATUS
         INCOME_RANGE].map { |item| [item.downcase.labelize, item] }
    end,
    campaign_targeting_dimension_operators: lambda do |_connection|
      %w[ADD REMOVE].map { |item| [item.downcase.labelize, item] }
    end,
    campaign_positive_geo_target_types: lambda do |_connection|
      %w[PRESENCE_OR_INTEREST SEARCH_INTEREST PRESENCE].
        map { |item| [item.downcase.labelize, item] }
    end,
    campaign_negative_geo_target_types: lambda do |_connection|
      %w[PRESENCE_OR_INTEREST PRESENCE].map { |item| [item.downcase.labelize, item] }
    end,
    campaign_location_source_types: lambda do |_connection|
      %w[GOOGLE_MY_BUSINESS AFFILIATE].map { |item| [item.downcase.labelize, item] }
    end,
    campaign_bidding_strategy_goal_types: lambda do |_connection|
      %w[OPTIMIZE_INSTALLS_TARGET_INSTALL_COST
         OPTIMIZE_IN_APP_CONVERSIONS_TARGET_INSTALL_COST
         OPTIMIZE_IN_APP_CONVERSIONS_TARGET_CONVERSION_COST
         OPTIMIZE_RETURN_ON_ADVERTISING_SPEND].map { |item| [item.downcase.labelize, item] }
    end,
    campaign_app_stores: lambda do |_connection|
      %w[APPLE_APP_STORE GOOGLE_APP_STORE].map { |item| [item.downcase.labelize, item] }
    end,
    campaign_frequency_caps_levels: lambda do |_connection|
      %w[AD_GROUP_AD AD_GROUP CAMPAIGN].map { |item| [item.downcase.labelize, item] }
    end,
    campaign_frequency_caps_event_types: lambda do |_connection|
      %w[IMPRESSION VIDEO_VIEW].map { |item| [item.downcase.labelize, item] }
    end,
    campaign_frequency_caps_time_units: lambda do |_connection|
      %w[DAY WEEK MONTH].map { |item| [item.downcase.labelize, item] }
    end,
    campaign_vanity_pharma_display_url_modes: lambda do |_connection|
      %w[MANUFACTURER_WEBSITE_URL
         WEBSITE_DESCRIPTION].map { |item| [item.downcase.labelize, item] }
    end,
    campaign_vanity_pharma_texts: lambda do |_connection|
      %w[PRESCRIPTION_TREATMENT_WEBSITE_EN
         PRESCRIPTION_TREATMENT_WEBSITE_ES PRESCRIPTION_DEVICE_WEBSITE_EN
         PRESCRIPTION_DEVICE_WEBSITE_ES MEDICAL_DEVICE_WEBSITE_EN MEDICAL_DEVICE_WEBSITE_ES
         PREVENTATIVE_TREATMENT_WEBSITE_EN PREVENTATIVE_TREATMENT_WEBSITE_ES
         PRESCRIPTION_CONTRACEPTION_WEBSITE_EN PRESCRIPTION_CONTRACEPTION_WEBSITE_ES
         PRESCRIPTION_VACCINE_WEBSITE_EN PRESCRIPTION_VACCINE_WEBSITE_ES].
        map { |item| [item.downcase.labelize, item] }
    end,
    campaign_payment_modes: lambda do |_connection|
      %w[CLICKS CONVERSION_VALUE CONVERSIONS GUEST_STAY].
        map { |item| [item.downcase.labelize, item] }
    end,
    campaign_target_impression_share_locations: lambda do |_connection|
      %w[ANYWHERE_ON_PAGE TOP_OF_PAGE ABSOLUTE_TOP_OF_PAGE].
        map { |item| [item.downcase.labelize, item] }
    end,

    #===================================#
    # Customer account object picklists #
    #===================================#
    customer_client_fields: lambda do |_connection|
      %w[applied_labels
         client_customer
         currency_code
         descriptive_name
         hidden
         id
         level
         manager
         resource_name
         test_account
         time_zone].map { |item| [item.split('.').last.labelize, "customer_client.#{item}"] }
    end,

    #============================#
    # User list object picklists #
    #============================#
    user_list_fields: lambda do |_connection|
      %w[access_reason
         account_user_list_status
         type
         size_range_for_search
         size_range_for_display
         size_for_search
         size_for_display
         similar_user_list.seed_user_list
         rule_based_user_list.prepopulation_status
         rule_based_user_list.expression_rule_user_list.rule.rule_type
         rule_based_user_list.expression_rule_user_list.rule.rule_item_groups
         rule_based_user_list.date_specific_rule_user_list.start_date
         rule_based_user_list.date_specific_rule_user_list.rule.rule_type
         rule_based_user_list.date_specific_rule_user_list.rule.rule_item_groups
         rule_based_user_list.date_specific_rule_user_list.end_date
         rule_based_user_list.combined_rule_user_list.rule_operator
         rule_based_user_list.combined_rule_user_list.right_operand.rule_type
         rule_based_user_list.combined_rule_user_list.right_operand.rule_item_groups
         rule_based_user_list.combined_rule_user_list.left_operand.rule_type
         rule_based_user_list.combined_rule_user_list.left_operand.rule_item_groups
         resource_name
         read_only
         name
         membership_status
         membership_life_span
         match_rate_percentage
         logical_user_list.rules
         integration_code
         id
         eligible_for_search
         eligible_for_display
         description
         basic_user_list.actions
         closing_reason
         crm_based_user_list.app_id
         crm_based_user_list.data_source_type
         crm_based_user_list.upload_key_type].
        map { |item| [item.split('.').last(2).smart_join('_').labelize, "user_list.#{item}"] }
    end,
    user_list_membership_statuses: lambda do |_connection|
      %w[OPEN CLOSED].map { |item| [item.downcase.labelize, item] }
    end,
    user_list_closing_reasons: lambda do |_connection|
      %w[UNUSED].map { |item| [item.downcase.labelize, item] }
    end,
    user_list_statuses: lambda do |_connection|
      %w[ENABLED DISABLED].map { |item| [item.downcase.labelize, item] }
    end,
    user_list_upload_key_types: lambda do |_connection|
      %w[CONTACT_INFO CRM_ID MOBILE_ADVERTISING_ID].
        map { |item| [item.downcase.labelize, item] }
    end,
    user_list_data_source_types: lambda do |_connection|
      %w[FIRST_PARTY THIRD_PARTY_CREDIT_BUREAU
         THIRD_PARTY_VOTER_FILE].map { |item| [item.downcase.labelize, item] }
    end,
    user_list_prepopulation_statuses: lambda do |_connection|
      %w[REQUESTED FINISHED FAILED].map { |item| [item.downcase.labelize, item] }
    end,
    user_list_combined_rule_operators: lambda do |_connection|
      %w[AND AND_NOT].map { |item| [item.downcase.labelize, item] }
    end,
    user_list_combined_rule_types: lambda do |_connection|
      %w[AND_OF_ORS OR_OF_ANDS].map { |item| [item.downcase.labelize, item] }
    end,
    user_list_number_rule_operators: lambda do |_connection|
      %w[GREATER_THAN GREATER_THAN_OR_EQUAL
         EQUALS NOT_EQUALS LESS_THAN LESS_THAN_OR_EQUAL].
        map { |item| [item.downcase.labelize, item] }
    end,
    user_list_string_rule_operators: lambda do |_connection|
      %w[CONTAINS EQUALS STARTS_WITH ENDS_WITH
         NOT_EQUALS NOT_CONTAINS NOT_STARTS_WITH NOT_ENDS_WITH].
        map { |item| [item.downcase.labelize, item] }
    end,
    user_list_date_rule_operators: lambda do |_connection|
      %w[EQUALS NOT_EQUALS BEFORE AFTER].map { |item| [item.downcase.labelize, item] }
    end,
    user_list_logical_rule_operators: lambda do |_connection|
      %w[ALL ANY NONE].map { |item| [item.downcase.labelize, item] }
    end
  }
}
