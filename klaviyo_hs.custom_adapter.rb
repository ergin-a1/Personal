{
  title: 'Klaviyo',

  connection: {
    fields: [
      {
        name: 'public_api_key', label: 'Public API Key',
        hint: 'When tracking people and events, use your public API ' \
          "key / Site ID. It's safe to expose your public API key."
      },
      {
        name: 'private_api_key', label: 'Private API Key',
        control_type: 'password',
        hint: 'Private API keys are used for reading data from Klaviyo and ' \
          'manipulating some sensitive objects such as lists. You can create ' \
          'a private API key by clicking on the company logo on the top ' \
          'right >> Account >> Settings >> API Keys.'
      }
    ],

    authorization: {
      type: 'api_key',

      apply: lambda do |connection|
        params(api_key: connection['private_api_key'])
      end
    },

    base_uri: lambda do |_connection|
      'https://a.klaviyo.com/api/'
    end
  },

  test: lambda do |_connection|
    get('identify')
  end,

  methods: {
    make_schema_builder_fields_sticky: lambda do |input|
      input.map do |field|
        if field[:properties].present?
          field[:properties] = call('make_schema_builder_fields_sticky',
            field[:properties])
        elsif field['properties'].present?
          field['properties'] = call('make_schema_builder_fields_sticky',
            field['properties'])
        end

        field[:sticky] = true
        field
      end
    end,

    ############################################################################
    ######                             Schemas                           #######
    ############################################################################
    special_identify_properties: lambda do
      [
        {
          name: 'dollar_id', label: 'Person ID', sticky: true,
          hint: 'Your unique identifier for a person.'
        },
        {
          name: 'dollar_email', label: 'Person email', sticky: true,
          control_type: 'email',
          hint: 'Email address of a person.'
        },
        {
          name: 'dollar_first_name', label: 'Person first name',
          hint: 'First name of a person.'
        },
        {
          name: 'dollar_last_name', label: 'Person last name',
          hint: 'Last name of a person.'
        },
        {
          name: 'dollar_phone_number', label: 'Person phone number',
          control_type: 'phone',
          hint: 'Phone number of a person.'
        },
        {
          name: 'dollar_title', label: 'Person title',
          hint: 'Title of a person at their business or organization.'
        },
        {
          name: 'dollar_organization', label: 'Person organization',
          hint: 'Business or organization a person belongs to.'
        },
        {
          name: 'dollar_city', label: 'Person city',
          hint: 'City a person lives in.'
        },
        {
          name: 'dollar_region', label: 'Person region',
          hint: 'Region or state a person lives in.'
        },
        {
          name: 'dollar_country', label: 'Person country',
          hint: 'Country a person lives in.'
        },
        {
          name: 'dollar_zip', label: 'Person zip code',
          hint: 'Postal code where a person lives in.'
        },
        {
          name: 'dollar_image', label: 'Person image URL',
          hint: 'URL to a photo of the person.'
        },
        {
          name: 'dollar_consent', label: 'Person consent',
          hint: 'Type(s) of marketing the person consented to receive. This ' \
            'is only necessary for GDPR compliant businesses.'
        }
      ]
    end,
    special_event_properties: lambda do
      [
        {
          name: 'dollar_event_id', label: 'Event ID', sticky: true,
          hint: 'An unique identifier for an event.'
        },
        {
          name: 'dollar_value', label: 'Value', sticky: true,
          type: 'number', render_input: 'float_conversion',
          control_type: 'number', parse_output: 'float_conversion',
          hint: 'A numeric value to associate with this event.'
        }
      ]
    end,
    server_side_sample_output: lambda do
      { 'success' => true }
    end,

    ############################################################################
    ######                          Format payload                       #######
    ############################################################################
    format_track_payload: lambda do |input|
      payload = input.slice('event')
      payload['customer_properties'] =
        input['customer_properties'].except('schema', 'data').
        map do |k, v|
          {
            k.gsub('dollar_', '$') => v
          }
        end.inject(:merge).
        merge(input&.dig('customer_properties', 'data') || {})
      if input&.dig('properties', 'data').present?
        payload['properties'] = input.dig('properties', 'data')
      end
      if input['time'].present?
        payload['time'] = input['time'].to_i
      end
      payload
    end,
    format_identify_payload: lambda do |input|
      payload = {}
      payload['properties'] =
        input['properties'].except('schema', 'data').
        map do |k, v|
          {
            k.gsub('dollar_', '$') => v
          }
        end.inject(:merge).
        merge(input&.dig('properties', 'data') || {})
      payload
    end,

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

    # Formats input/output schema to replace any special characters in name,
    # without changing other attributes (method required for custom action)
    format_schema: lambda do |input|
      input&.map do |field|
        if (props = field[:properties])
          field[:properties] = call('format_schema', props)
        elsif (props = field['properties'])
          field['properties'] = call('format_schema', props)
        end
        if (name = field[:name])
          field[:label] = field[:label].presence || name.labelize
          field[:name] = name
          .gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        elsif (name = field['name'])
          field['label'] = field['label'].presence || name.labelize
          field['name'] = name
          .gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        end

        field
      end
    end,

    # Formats payload to inject any special characters that previously removed
    format_payload: lambda do |payload|
      if payload.is_a?(Array)
        payload.map do |array_value|
          call('format_payload', array_value)
        end
      elsif payload.is_a?(Hash)
        payload.each_with_object({}) do |(key, value), hash|
          key = key.gsub(/__\w+__/) do |string|
            string.gsub(/__/, '').decode_hex.as_utf8
          end
          if value.is_a?(Array) || value.is_a?(Hash)
            value = call('format_payload', value)
          end
          hash[key] = value
        end
      end
    end,

    # Formats response to replace any special characters with valid strings
    # (method required for custom action)
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
    end

  },

  object_definitions: {
    track_input: {
      fields: lambda do |_connection, config_fields|
        custom_customer_properties = parse_json(config_fields&.
            dig('customer_properties', 'schema') || '[]')
        custom_customer_properties_input =
          if custom_customer_properties.present?
            {
              name: 'data', type: 'object',
              properties: call('make_schema_builder_fields_sticky',
                custom_customer_properties)
            }
          end
        custom_properties = parse_json(config_fields&.
            dig('properties', 'schema') || '[]')
        custom_properties_input =
          if custom_properties.present?
            {
              name: 'data', type: 'object',
              properties: call('make_schema_builder_fields_sticky',
                custom_properties)
            }
          end

        [
          {
            name: 'event', optional: false,
            hint: 'Name of the event you want to track.'
          },
          {
            name: 'customer_properties', optional: false, type: 'object',
            hint: 'Custom information about the person who did this event. ' \
              'You must identify the person by their email or a unique ' \
              'identifier.',
            properties: call('special_identify_properties').concat([
              {
                name: 'schema', sticky: true, extends_schema: true,
                schema_neutral: true, control_type: 'schema-designer',
                sample_data_type: 'json_input',
                hint: 'Include any data useful for segmenting the people in ' \
                  'your account.'
              },
              custom_customer_properties_input
            ].compact)
          },
          {
            name: 'properties', optional: true, sticky: true, type: 'object',
            hint: 'Custom information about this event. Any properties ' \
              'included here can be used for creating segments later.',
            properties: call('special_event_properties').concat([
              {
                name: 'schema', sticky: true, extends_schema: true,
                schema_neutral: true, control_type: 'schema-designer',
                sample_data_type: 'json_input'
              },
              custom_properties_input
            ].compact)
          },
          {
            name: 'time', optional: true, sticky: true,
            type: 'date_time', parse_output: 'date_time_conversion',
            control_type: 'date_time', render_input: 'date_time_conversion',
            hint: 'When this event occurred. By default, Klaviyo assumes ' \
              "events happen when a request is made. If you'd like to track " \
              'and event that happened in past, use this property.'
          }
        ]
      end
    },

    identify_input: {
      fields: lambda do |_connection, config_fields|
        custom_properties = parse_json(config_fields&.
            dig('properties', 'schema') || '[]')
        custom_properties_input =
          if custom_properties.present?
            {
              name: 'data', type: 'object',
              properties: call('make_schema_builder_fields_sticky',
                custom_properties)
            }
          end

        [
          {
            name: 'properties', optional: false, type: 'object',
            hint: 'Custom information about the person who did this event. ' \
              'You must identify the person by their email or a unique ' \
              'identifier.',
            properties: call('special_identify_properties').concat([
              {
                name: 'schema', sticky: true, extends_schema: true,
                schema_neutral: true, control_type: 'schema-designer',
                sample_data_type: 'json_input',
                hint: 'Include any data useful for segmenting the people in ' \
                  'your account.'
              },
              custom_properties_input
            ].compact)
          }
        ]
      end
    },

    server_side_output: {
      fields: lambda do
        [
          {
            name: 'success',
            type: 'boolean', parse_output: 'boolean_conversion',
            control_type: 'checkbox', render_input: 'boolean_conversion'
          }
        ]
      end
    },

    metrics_info_list: {
      fields: lambda do |_connection|
        [
          {
            "control_type": "text",
            "label": "Object",
            "type": "string",
            "name": "object",
            "details": {
              "real_name": "object"
            }
          },
          {
            "name": "data",
            "type": "array",
            "of": "object",
            "label": "Data",
            "properties": [
              {
                "control_type": "text",
                "label": "Object",
                "type": "string",
                "name": "object",
                "details": {
                  "real_name": "object"
                }
              },
              {
                "control_type": "text",
                "label": "ID",
                "type": "string",
                "name": "id",
                "details": {
                  "real_name": "id"
                }
              },
              {
                "control_type": "text",
                "label": "Name",
                "type": "string",
                "name": "name",
                "details": {
                  "real_name": "name"
                }
              },
              {
                "properties": [
                  {
                    "control_type": "text",
                    "label": "Object",
                    "type": "string",
                    "name": "object",
                    "details": {
                      "real_name": "object"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "ID",
                    "type": "string",
                    "name": "id",
                    "details": {
                      "real_name": "id"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Name",
                    "type": "string",
                    "name": "name",
                    "details": {
                      "real_name": "name"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Category",
                    "type": "string",
                    "name": "category",
                    "details": {
                      "real_name": "category"
                    }
                  }
                ],
                "label": "Integration",
                "type": "object",
                "name": "integration",
                "details": {
                  "real_name": "integration"
                }
              },
              {
                "control_type": "text",
                "label": "Created",
                "type": "string",
                "name": "created",
                "details": {
                  "real_name": "created"
                }
              },
              {
                "control_type": "text",
                "label": "Updated",
                "type": "string",
                "name": "updated",
                "details": {
                  "real_name": "updated"
                }
              }
            ],
            "details": {
              "real_name": "data"
            }
          },
          {
            "control_type": "number",
            "label": "Page",
            "parse_output": "float_conversion",
            "type": "number",
            "name": "page",
            "details": {
              "real_name": "page"
            }
          },
          {
            "control_type": "number",
            "label": "Start",
            "parse_output": "float_conversion",
            "type": "number",
            "name": "start",
            "details": {
              "real_name": "start"
            }
          },
          {
            "control_type": "number",
            "label": "End",
            "parse_output": "float_conversion",
            "type": "number",
            "name": "end",
            "details": {
              "real_name": "end"
            }
          },
          {
            "control_type": "number",
            "label": "Total",
            "parse_output": "float_conversion",
            "type": "number",
            "name": "total",
            "details": {
              "real_name": "total"
            }
          },
          {
            "control_type": "number",
            "label": "Page size",
            "parse_output": "float_conversion",
            "type": "number",
            "name": "page_size",
            "details": {
              "real_name": "page_size"
            }
          }
        ]
      end
    },
    metrics_info_events_2: {
      fields: lambda do |_connection|
        [
                        {
                "control_type": "text",
                "label": "Object",
                "type": "string",
                "name": "object",
                "details": {
                  "real_name": "object"
                }
              },
              {
                "control_type": "text",
                "label": "ID",
                "type": "string",
                "name": "id",
                "details": {
                  "real_name": "id"
                }
              },
              {
                "control_type": "text",
                "label": "Statistic Id",
                "type": "string",
                "name": "statistic_id",
                "details": {
                  "real_name": "statistic_id"
                }
              },
              {           
                "control_type": "number",
                "label": "Timestamp",
                "parse_output": "float_conversion",
                "type": "number",
                "name": "timestamp",
                "details": {
                "real_name": "timestamp"
                }
              },
              {
                "control_type": "text",
                "label": "Event name",
                "type": "string",
                "name": "event_name",
                "details": {
                  "real_name": "event_name"
                }
              },
              {
                "control_type": "text",
                "label": "Datetime",
                "render_input": "date_time_conversion",
                "parse_output": "date_time_conversion",
                "type": "date_time",
                "name": "datetime",
                "details": {
                "real_name": "datetime"
                }
              },
              {
                "control_type": "text",
                "label": "UUID",
                "type": "string",
                "name": "uuid",
                "details": {
                  "real_name": "uuid"
                }
              },
              {
                "properties": [
                  {
                    "control_type": "text",
                    "label": "Subject",
                    "type": "string",
                    "name": "Subject",
                    "details": {
                      "real_name": "Subject"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Campaign Name",
                    "type": "string",
                    "name": "Campaign Name",
                    "details": {
                      "real_name": "Campaign Name"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Message",
                    "type": "string",
                    "name": "$message",
                    "details": {
                      "real_name": "$message"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Email Domain",
                    "type": "string",
                    "name": "Email Domain",
                    "details": {
                      "real_name": "Email Domain"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Message send cohort",
                    "type": "string",
                    "name": "$_cohort$message_send_cohort",
                    "details": {
                      "real_name": "$_cohort$message_send_cohort"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Client type",
                    "type": "string",
                    "name": "Client Type",
                    "details": {
                      "real_name": "Client Type"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Client OS Family",
                    "type": "string",
                    "name": "Client OS Family",
                    "details": {
                      "real_name": "Client OS Family"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": " Client OS",
                    "type": "string",
                    "name": " Client OS",
                    "details": {
                      "real_name": " Client OS"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Client Name",
                    "type": "string",
                    "name": "Client Name",
                    "details": {
                      "real_name": "Client Name"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Message Interaction",
                    "type": "string",
                    "name": "$message_interaction",
                    "details": {
                      "real_name": "$message_interaction"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "ESP",
                    "type": "string",
                    "name": "$ESP",
                    "details": {
                      "real_name": "$ESP"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Machine Open",
                    "type": "string",
                    "name": "machine_open",
                    "details": {
                      "real_name": "machine_open"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Event Id",
                    "type": "string",
                    "name": "$event_id",
                    "details": {
                      "real_name": "$event_id"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Bounce Type",
                    "type": "string",
                    "name": "Bounce Type",
                    "details": {
                      "real_name": "Bounce Type"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "URL",
                    "type": "string",
                    "name": "URL",
                    "details": {
                      "real_name": "URL"
                    }
                  },
                ],
                "label": "Event properties",
                "type": "object",
                "name": "event_properties",
                "details": {
                  "real_name": "event_properties"
                }
              },
              { 
                "properties": [
                  {
                    "control_type": "text",
                    "label": "Object",
                    "type": "string",
                    "name": "Subject",
                    "details": {
                      "real_name": "object"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "ID",
                    "type": "string",
                    "name": "id",
                    "details": {
                      "real_name": "id"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Email",
                    "type": "string",
                    "name": "$email",
                    "details": {
                      "real_name": "$email"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Address1",
                    "type": "string",
                    "name": "$address1",
                    "details": {
                      "real_name": "$address1"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Address2",
                    "type": "string",
                    "name": "$address2",
                    "details": {
                      "real_name": "$address2"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "City",
                    "type": "string",
                    "name": "$city",
                    "details": {
                      "real_name": "$city"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Country",
                    "type": "string",
                    "name": "$country",
                    "details": {
                      "real_name": "$country"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Latitude",
                    "type": "string",
                    "name": "$latitude",
                    "details": {
                      "real_name": "$latitude"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Longitude",
                    "type": "string",
                    "name": "$longitude",
                    "details": {
                      "real_name": "$longitude"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Region",
                    "type": "string",
                    "name": "$region",
                    "details": {
                      "real_name": "$region"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Zip",
                    "type": "string",
                    "name": "$zip",
                    "details": {
                      "real_name": "$zip"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Title",
                    "type": "string",
                    "name": "$title",
                    "details": {
                      "real_name": "$title"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "First Name",
                    "type": "string",
                    "name": "$first_name",
                    "details": {
                      "real_name": "$first_name"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Last Name",
                    "type": "string",
                    "name": "$last_name",
                    "details": {
                      "real_name": "$last_name"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Organization",
                    "type": "string",
                    "name": "$organization",
                    "details": {
                      "real_name": "$organization"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Phone Number",
                    "type": "string",
                    "name": "$phone_number",
                    "details": {
                      "real_name": "$phone_number"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "timezone",
                    "type": "string",
                    "name": "$timezone",
                    "details": {
                      "real_name": "$timezone"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Created",
                    "render_input": "date_time_conversion",
                    "parse_output": "date_time_conversion",
                    "type": "date_time",
                    "name": "created",
                    "details": {
                      "real_name": "created"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Updated",
                    "render_input": "date_time_conversion",
                    "parse_output": "date_time_conversion",
                    "type": "date_time",
                    "name": "updated",
                    "details": {
                      "real_name": "updated"
                    }
                  },
                ],
                "label": "Person",
                "type": "object",
                "name": "person",
                "details": {
                  "real_name": "person"
                }
              },
        ]
      end,
    },
    metrics_info_events_1: {
      fields: lambda do |_connection|
        [
          {
            "control_type": "text",
            "label": "Object",
            "type": "string",
            "name": "object",
            "details": {
              "real_name": "object"
            }
          },
          {
            "control_type": "number",
            "label": "Count",
            "type": "number",
            "name": "count",
            "details": {
              "real_name": "count"
            }
          },
          {
            "name": "data",
            "type": "array",
            "of": "object",
            "label": "Data",
            "properties": [
              {
                "control_type": "text",
                "label": "Object",
                "type": "string",
                "name": "object",
                "details": {
                  "real_name": "object"
                }
              },
              {
                "control_type": "text",
                "label": "ID",
                "type": "string",
                "name": "id",
                "details": {
                  "real_name": "id"
                }
              },
              {
                "control_type": "text",
                "label": "Statistic Id",
                "type": "string",
                "name": "statistic_id",
                "details": {
                  "real_name": "statistic_id"
                }
              },
              {           
                "control_type": "number",
                "label": "Timestamp",
                "parse_output": "float_conversion",
                "type": "number",
                "name": "timestamp",
                "details": {
                "real_name": "timestamp"
                }
              },
              {
                "control_type": "text",
                "label": "Event name",
                "type": "string",
                "name": "event_name",
                "details": {
                  "real_name": "event_name"
                }
              },
              {
                "control_type": "text",
                "label": "Datetime",
                "render_input": "date_time_conversion",
                "parse_output": "date_time_conversion",
                "type": "date_time",
                "name": "datetime",
                "details": {
                "real_name": "datetime"
                }
              },
              {
                "control_type": "text",
                "label": "UUID",
                "type": "string",
                "name": "uuid",
                "details": {
                  "real_name": "uuid"
                }
              },
              {
                "properties": [
                  {
                    "control_type": "text",
                    "label": "Subject",
                    "type": "string",
                    "name": "Subject",
                    "details": {
                      "real_name": "Subject"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Campaign Name",
                    "type": "string",
                    "name": "Campaign Name",
                    "details": {
                      "real_name": "Campaign Name"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Message",
                    "type": "string",
                    "name": "$message",
                    "details": {
                      "real_name": "$message"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Email Domain",
                    "type": "string",
                    "name": "Email Domain",
                    "details": {
                      "real_name": "Email Domain"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Message send cohort",
                    "type": "string",
                    "name": "$_cohort$message_send_cohort",
                    "details": {
                      "real_name": "$_cohort$message_send_cohort"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Client type",
                    "type": "string",
                    "name": "Client Type",
                    "details": {
                      "real_name": "Client Type"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Client OS Family",
                    "type": "string",
                    "name": "Client OS Family",
                    "details": {
                      "real_name": "Client OS Family"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": " Client OS",
                    "type": "string",
                    "name": " Client OS",
                    "details": {
                      "real_name": " Client OS"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Client Name",
                    "type": "string",
                    "name": "Client Name",
                    "details": {
                      "real_name": "Client Name"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Message Interaction",
                    "type": "string",
                    "name": "$message_interaction",
                    "details": {
                      "real_name": "$message_interaction"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "ESP",
                    "type": "string",
                    "name": "$ESP",
                    "details": {
                      "real_name": "$ESP"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Machine Open",
                    "type": "string",
                    "name": "machine_open",
                    "details": {
                      "real_name": "machine_open"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Event Id",
                    "type": "string",
                    "name": "$event_id",
                    "details": {
                      "real_name": "$event_id"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Bounce Type",
                    "type": "string",
                    "name": "Bounce Type",
                    "details": {
                      "real_name": "Bounce Type"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "URL",
                    "type": "string",
                    "name": "URL",
                    "details": {
                      "real_name": "URL"
                    }
                  },
                ],
                "label": "Event properties",
                "type": "object",
                "name": "event_properties",
                "details": {
                  "real_name": "event_properties"
                }
              },
              { 
                "properties": [
                  {
                    "control_type": "text",
                    "label": "Object",
                    "type": "string",
                    "name": "Subject",
                    "details": {
                      "real_name": "object"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "ID",
                    "type": "string",
                    "name": "id",
                    "details": {
                      "real_name": "id"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Email",
                    "type": "string",
                    "name": "$email",
                    "details": {
                      "real_name": "$email"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Address1",
                    "type": "string",
                    "name": "$address1",
                    "details": {
                      "real_name": "$address1"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Address2",
                    "type": "string",
                    "name": "$address2",
                    "details": {
                      "real_name": "$address2"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "City",
                    "type": "string",
                    "name": "$city",
                    "details": {
                      "real_name": "$city"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Country",
                    "type": "string",
                    "name": "$country",
                    "details": {
                      "real_name": "$country"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Latitude",
                    "type": "string",
                    "name": "$latitude",
                    "details": {
                      "real_name": "$latitude"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Longitude",
                    "type": "string",
                    "name": "$longitude",
                    "details": {
                      "real_name": "$longitude"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Region",
                    "type": "string",
                    "name": "$region",
                    "details": {
                      "real_name": "$region"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Zip",
                    "type": "string",
                    "name": "$zip",
                    "details": {
                      "real_name": "$zip"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Title",
                    "type": "string",
                    "name": "$title",
                    "details": {
                      "real_name": "$title"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "First Name",
                    "type": "string",
                    "name": "$first_name",
                    "details": {
                      "real_name": "$first_name"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Last Name",
                    "type": "string",
                    "name": "$last_name",
                    "details": {
                      "real_name": "$last_name"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Organization",
                    "type": "string",
                    "name": "$organization",
                    "details": {
                      "real_name": "$organization"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Phone Number",
                    "type": "string",
                    "name": "$phone_number",
                    "details": {
                      "real_name": "$phone_number"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "timezone",
                    "type": "string",
                    "name": "$timezone",
                    "details": {
                      "real_name": "$timezone"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Created",
                    "render_input": "date_time_conversion",
                    "parse_output": "date_time_conversion",
                    "type": "date_time",
                    "name": "created",
                    "details": {
                      "real_name": "created"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Updated",
                    "render_input": "date_time_conversion",
                    "parse_output": "date_time_conversion",
                    "type": "date_time",
                    "name": "updated",
                    "details": {
                      "real_name": "updated"
                    }
                  },
                ],
                "label": "Person",
                "type": "object",
                "name": "person",
                "details": {
                  "real_name": "person"
                }
              },
            ],
            "details": {
              "real_name": "data"
            }
          },
        ]
      end,
    },
    metrics_info_events: {
      fields: lambda do |_connection|
        [
          {
            "control_type": "text",
            "label": "Object",
            "type": "string",
            "name": "object",
            "details": {
              "real_name": "object"
            }
          },
          {
            "control_type": "text",
            "label": "ID",
            "type": "string",
            "name": "id",
            "details": {
              "real_name": "id"
            }
          },
          {
            "control_type": "text",
            "label": "Statistic ID",
            "type": "string",
            "name": "statistic_id",
            "details": {
              "real_name": "statistic_id"
            }
          },
          {
            "control_type": "number",
            "label": "Timestamp",
            "parse_output": "float_conversion",
            "type": "number",
            "name": "timestamp",
            "details": {
              "real_name": "timestamp"
            }
          },
          {
            "control_type": "text",
            "label": "Event name",
            "type": "string",
            "name": "event_name",
            "details": {
              "real_name": "event_name"
            }
          },
          {
            "properties": [
              {
                "control_type": "number",
                "label": "$value",
                "parse_output": "float_conversion",
                "type": "number",
                "name": "$value",
                "details": {
                  "real_name": "$value"
                }
              },
              {
                "name": "items",
                "type": "array",
                "of": "object",
                "label": "Items",
                "properties": [
                  {
                    "control_type": "text",
                    "label": "Name",
                    "type": "string",
                    "name": "name",
                    "details": {
                      "real_name": "name"
                    }
                  },
                  {
                    "control_type": "text",
                    "label": "Sku",
                    "type": "string",
                    "name": "sku",
                    "details": {
                      "real_name": "sku"
                    }
                  },
                  {
                    "control_type": "number",
                    "label": "Price",
                    "parse_output": "float_conversion",
                    "type": "number",
                    "name": "price",
                    "details": {
                      "real_name": "price"
                    }
                  },
                  {
                    "control_type": "number",
                    "label": "Quantity",
                    "parse_output": "float_conversion",
                    "type": "number",
                    "name": "quantity",
                    "details": {
                      "real_name": "quantity"
                    }
                  }
                ],
                "details": {
                  "real_name": "items"
                }
              }
            ],
            "label": "Event properties",
            "type": "object",
            "name": "event_properties",
            "details": {
              "real_name": "event_properties"
            }
          },
          {
            "control_type": "text",
            "label": "Datetime",
            "render_input": "date_time_conversion",
            "parse_output": "date_time_conversion",
            "type": "date_time",
            "name": "datetime",
            "details": {
              "real_name": "datetime"
            }
          },
          {
            "control_type": "text",
            "label": "Uuid",
            "type": "string",
            "name": "uuid",
            "details": {
              "real_name": "uuid"
            }
          },
          {
            "properties": [
              {
                "control_type": "text",
                "label": "ID",
                "type": "string",
                "name": "id",
                "details": {
                  "real_name": "id"
                }
              },
              {
                "control_type": "text",
                "label": "Object",
                "type": "string",
                "name": "object",
                "details": {
                  "real_name": "object"
                }
              },
              {
                "control_type": "text",
                "label": "$email",
                "type": "string",
                "name": "$email",
                "details": {
                  "real_name": "$email"
                }
              }
            ],
            "label": "Person",
            "type": "object",
            "name": "person",
            "details": {
              "real_name": "person"
            }
          }
        ]
      end,
    },
    
    members_list: {
      fields: lambda do |_connection|
        [
          {
            "name": "records",
            "type": "array",
            "of": "object",
            "label": "Records",
            "properties": [
              {
                "control_type": "text",
                "label": "Id",
                "type": "string",
                "name": "id",
                "details": {
                  "real_name": "id"
                }
              },
              {
                "control_type": "text",
                "label": "Email",
                "type": "string",
                "name": "email",
                "details": {
                  "real_name": "email"
                }
              }
            ],
            "details": {
              "real_name": "records"
            }
          }
        ]
      end,
    },
    
    exclusion_list: {
      fields: lambda do |_connection|
        [
              {
                "control_type": "text",
                "label": "Object",
                "type": "string",
                "name": "object",
                "details": {
                  "real_name": "object"
                }
              },
              {
                "control_type": "text",
                "label": "Email",
                "type": "string",
                "name": "email",
                "details": {
                  "real_name": "email"
                }
              },
              {
                "control_type": "text",
                "label": "Reason",
                "type": "string",
                "name": "reason",
                "details": {
                  "real_name": "reason"
                }
              },
              {           
                "control_type": "number",
                "label": "Timestamp",
                "parse_output": "float_conversion",
                "type": "number",
                "name": "timestamp",
                "details": {
                "real_name": "timestamp"
                }
              }
        ]
      end,
    },
    
    email_search: {
      fields: lambda do |_connection|
        [
          {
            "control_type": "text",
            "label": "Id",
            "type": "string",
            "name": "id",
            "details": {
              "real_name": "id"
            }
          }
        ]
      end,
    },
   
    person_attributes: {
      fields: lambda do |_connection|
        [
          {
            "control_type": "text",
            "label": "Object",
            "type": "string",
            "name": "object",
            "details": {
              "real_name": "object"
            }
          },
          {
            "control_type": "text",
            "label": "Id",
            "type": "string",
            "name": "id",
            "details": {
              "real_name": "id"
            }
          },
          {
            "control_type": "text",
            "label": "Address1",
            "type": "string",
            "name": "$address1",
            "details": {
              "real_name": "$address1"
            }
          },
          {
            "control_type": "text",
            "label": "Address2",
            "type": "string",
            "name": "$address2",
            "details": {
              "real_name": "$address2"
            }
          },
          {
            "control_type": "text",
            "label": "City",
            "type": "string",
            "name": "$city",
            "details": {
              "real_name": "$city"
            }
          },
          {
            "control_type": "text",
            "label": "Country",
            "type": "string",
            "name": "$country",
            "details": {
              "real_name": "$country"
            }
          },
          {
            "control_type": "text",
            "label": "Latitude",
            "type": "string",
            "name": "$latitude",
            "details": {
              "real_name": "$latitude"
            }
          },
          {
            "control_type": "text",
            "label": "Longitude",
            "type": "string",
            "name": "$longitude",
            "details": {
              "real_name": "$longitude"
            }
          },
          {
            "control_type": "text",
            "label": "Region",
            "type": "string",
            "name": "$region",
            "details": {
              "real_name": "$region"
            }
          },
          {
            "control_type": "text",
            "label": "Zip",
            "type": "string",
            "name": "$zip",
            "details": {
              "real_name": "$zip"
            }
          },         
          {
            "control_type": "text",
            "label": "First Name",
            "type": "string",
            "name": "first_name",
            "details": {
              "real_name": "first_name"
            }
          },
          {
            "control_type": "text",
            "label": "Email",
            "type": "string",
            "name": "email",
            "details": {
              "real_name": "email"
            }
          },
          {
            "control_type": "text",
            "label": "Title",
            "type": "string",
            "name": "$title",
            "details": {
              "real_name": "$title"
            }
          },


          {
            "control_type": "text",
            "label": "Organization",
            "type": "string",
            "name": "$organization",
            "details": {
              "real_name": "$organization"
            }
          },         
          {
            "control_type": "text",
            "label": "Phone Number",
            "type": "string",
            "name": "$phone_number",
            "details": {
              "real_name": "$phone_number"
            }
          },
          {
            "control_type": "text",
            "label": "Last Name",
            "type": "string",
            "name": "$last_name",
            "details": {
              "real_name": "$last_name"
            }
          },
          {
            "control_type": "text",
            "label": "Timezone",
            "type": "string",
            "name": "$timezone",
            "details": {
              "real_name": "$timezone"
            }
          },
          {
            "control_type": "text",
            "label": "Created",
            "type": "string",
            "name": "created",
            "details": {
                "real_name": "created"
            }
          },
          {
            "control_type": "text",
            "label": "Updated",
            "type": "string",
            "name": "updated",
            "details": {
                "real_name": "updated"
            }
          }
        ]
      end,
    },
    
    campaigns_list: {
      fields: lambda do |_connection|
        [
            {
                "control_type": "text",
                "label": "Object",
                "type": "string",
                "name": "object",
                "details": {
                "real_name": "object"
                }
            },
            {
                "control_type": "text",
                "label": "Id",
                "type": "string",
                "name": "id",
                "details": {
                "real_name": "id"
                }
            },
            {
                "control_type": "text",
                "label": "Name",
                "type": "string",
                "name": "name",
                "details": {
                "real_name": "name"
                }
            },
            {
                "control_type": "text",
                "label": "Subject",
                "type": "string",
                "name": "subject",
                "details": {
                "real_name": "subject"
                }
            },
            {
                "control_type": "text",
                "label": "From Email",
                "type": "string",
                "name": "from_email",
                "details": {
                "real_name": "from_email"
                }
            },
            {
                "control_type": "text",
                "label": "From Name",
                "type": "string",
                "name": "from_name",
                "details": {
                "real_name": "from_name"
                }
            },
            {
                "control_type": "text",
                "label": "Status",
                "type": "string",
                "name": "status",
                "details": {
                "real_name": "status"
                }
            },
            {
                "control_type": "text",
                "label": "Status Id",
                "type": "string",
                "name": "status_id",
                "details": {
                "real_name": "status_id"
                }
            },
            {
                "control_type": "text",
                "label": "Status Label",
                "type": "string",
                "name": "status_label",
                "details": {
                "real_name": "status_label"
                }
            },
            {
                "control_type": "text",
                "label": "Sent At",
                "render_input": "date_time_conversion",
                "parse_output": "date_time_conversion",
                "type": "date_time",
                "name": "sent_at",
                "details": {
                "real_name": "sent_at"
                }
            },
            {
                "control_type": "text",
                "label": "Send Time",
                "render_input": "date_time_conversion",
                "parse_output": "date_time_conversion",
                "type": "date_time",
                "name": "send_time",
                "details": {
                "real_name": "send_time"
                }
            },
            {
                "control_type": "text",
                "label": "Created",
                "render_input": "date_time_conversion",
                "parse_output": "date_time_conversion",
                "type": "date_time",
                "name": "created",
                "details": {
                "real_name": "created"
                }
            },
            {
                "control_type": "text",
                "label": "Updated",
                "render_input": "date_time_conversion",
                "parse_output": "date_time_conversion",
                "type": "date_time",
                "name": "updated",
                "details": {
                "real_name": "updated"
                }
            },
            {
                "control_type": "text",
                "label": "Number of recipients",
                "type": "string",
                "name": "num_recipients",
                "details": {
                "real_name": "num_recipients"
                }
            },
            {
                "control_type": "text",
                "label": "Campaign Type",
                "type": "string",
                "name": "campaign_type",
                "details": {
                "real_name": "campaign_type"
                }
            },
            {
                "control_type": "text",
                "label": "Is segmented",
                "type": "string",
                "name": "is_segmented",
                "details": {
                "real_name": "is_segmented"
                }
            },
            {
                "control_type": "text",
                "label": "Message Type",
                "type": "string",
                "name": "message_type",
                "details": {
                "real_name": "message_type"
                }
            },
            {
                "control_type": "text",
                "label": "Template Id",
                "type": "string",
                "name": "template_id",
                "details": {
                "real_name": "template_id"
                }
            },
        ]
      end,   
    },


    campaigns_list_1: {
      fields: lambda do |_connection|
        [
          {
            "control_type": "text",
            "label": "Object",
            "type": "string",
            "name": "object",
            "details": {
              "real_name": "object"
            }
        },
        {
            "name": "data",
            "type": "array",
            "of": "object",
            "label": "Data",
            "properties": [
                {
                    "control_type": "text",
                    "label": "Object",
                    "type": "string",
                    "name": "object",
                    "details": {
                    "real_name": "object"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Id",
                    "type": "string",
                    "name": "id",
                    "details": {
                    "real_name": "id"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Name",
                    "type": "string",
                    "name": "name",
                    "details": {
                    "real_name": "name"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Subject",
                    "type": "string",
                    "name": "subject",
                    "details": {
                    "real_name": "subject"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Subject",
                    "type": "string",
                    "name": "subject",
                    "details": {
                    "real_name": "subject"
                    }
                },
                {
                    "control_type": "text",
                    "label": "From Email",
                    "type": "string",
                    "name": "from_email",
                    "details": {
                    "real_name": "from_email"
                    }
                },
                {
                    "control_type": "text",
                    "label": "From Name",
                    "type": "string",
                    "name": "from_name",
                    "details": {
                    "real_name": "from_name"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Status",
                    "type": "string",
                    "name": "status",
                    "details": {
                    "real_name": "status"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Status Id",
                    "type": "string",
                    "name": "status_id",
                    "details": {
                    "real_name": "status_id"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Status Label",
                    "type": "string",
                    "name": "status_label",
                    "details": {
                    "real_name": "status_label"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Sent At",
                    "render_input": "date_time_conversion",
                    "parse_output": "date_time_conversion",
                    "type": "date_time",
                    "name": "sent_at",
                    "details": {
                    "real_name": "sent_at"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Send Time",
                    "render_input": "date_time_conversion",
                    "parse_output": "date_time_conversion",
                    "type": "date_time",
                    "name": "send_time",
                    "details": {
                    "real_name": "send_time"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Created",
                    "render_input": "date_time_conversion",
                    "parse_output": "date_time_conversion",
                    "type": "date_time",
                    "name": "created",
                    "details": {
                    "real_name": "created"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Updated",
                    "render_input": "date_time_conversion",
                    "parse_output": "date_time_conversion",
                    "type": "date_time",
                    "name": "updated",
                    "details": {
                    "real_name": "updated"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Number of recipients",
                    "type": "string",
                    "name": "num_recipients",
                    "details": {
                    "real_name": "num_recipients"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Campaign Type",
                    "type": "string",
                    "name": "campaign_type",
                    "details": {
                    "real_name": "campaign_type"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Is segmented",
                    "type": "string",
                    "name": "is_segmented",
                    "details": {
                    "real_name": "is_segmented"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Message Type",
                    "type": "string",
                    "name": "message_type",
                    "details": {
                    "real_name": "message_type"
                    }
                },
                {
                    "control_type": "text",
                    "label": "Template Id",
                    "type": "string",
                    "name": "template_id",
                    "details": {
                    "real_name": "template_id"
                    }
                },
            ],
            "details": {
              "real_name": "data"
            }
          }
        ]
      end,   
    },

    templates_list: {
      fields: lambda do |_connection|
        [
          {
            "control_type": "text",
            "label": "Object",
            "type": "string",
            "name": "object",
            "details": {
              "real_name": "object"
            }
          },
          {
            "name": "data",
            "type": "array",
            "of": "object",
            "label": "Data",
            "properties": [
              {
                "control_type": "text",
                "label": "Object",
                "type": "string",
                "name": "object",
                "details": {
                  "real_name": "object"
                }
              },
              {
                "control_type": "text",
                "label": "ID",
                "type": "string",
                "name": "id",
                "details": {
                  "real_name": "id"
                }
              },
              {
                "control_type": "text",
                "label": "Name",
                "type": "string",
                "name": "name",
                "details": {
                  "real_name": "name"
                }
              },
              {
                "control_type": "text",
                "label": "Html",
                "type": "string",
                "name": "html",
                "details": {
                  "real_name": "html"
                }
              },
              {
                "control_type": "text",
                "label": "Is writeable",
                "render_input": {},
                "parse_output": {},
                "toggle_hint": "Select from option list",
                "toggle_field": {
                  "label": "Is writeable",
                  "control_type": "text",
                  "toggle_hint": "Use custom value",
                  "type": "boolean",
                  "name": "is_writeable"
                },
                "type": "boolean",
                "name": "is_writeable",
                "details": {
                  "real_name": "is_writeable"
                }
              },
              {
                "control_type": "text",
                "label": "Created",
                "type": "string",
                "name": "created",
                "details": {
                  "real_name": "created"
                }
              },
              {
                "control_type": "text",
                "label": "Updated",
                "type": "string",
                "name": "updated",
                "details": {
                  "real_name": "updated"
                }
              }
            ],
            "details": {
              "real_name": "data"
            }
          },
          {
            "control_type": "number",
            "label": "Page",
            "parse_output": "float_conversion",
            "type": "number",
            "name": "page",
            "details": {
              "real_name": "page"
            }
          },
          {
            "control_type": "number",
            "label": "Start",
            "parse_output": "float_conversion",
            "type": "number",
            "name": "start",
            "details": {
              "real_name": "start"
            }
          },
          {
            "control_type": "number",
            "label": "End",
            "parse_output": "float_conversion",
            "type": "number",
            "name": "end",
            "details": {
              "real_name": "end"
            }
          },
          {
            "control_type": "number",
            "label": "Total",
            "parse_output": "float_conversion",
            "type": "number",
            "name": "total",
            "details": {
              "real_name": "total"
            }
          },
          {
            "control_type": "number",
            "label": "Page size",
            "parse_output": "float_conversion",
            "type": "number",
            "name": "page_size",
            "details": {
              "real_name": "page_size"
            }
          }
        ]
      end,
    },

    custom_action_input: {
      fields: lambda do |_connection, config_fields|
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
              'https://a.klaviyo.com/api/' \
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
    }
  },

  actions: {
    track: {
      title: 'Track event',
      subtitle: "<span class='provider'>Track</span> an event in " \
        "<span class='provider'>Klaviyo</span>",
      help: 'This API is used for tracking the events or actions a person ' \
        'does. For instance, tracking when someone is active on your ' \
        'website, when a purchase is made or when someone watches a video.',
      input_fields: lambda do |object_definitions|
        object_definitions['track_input']
      end,
      execute: lambda do |connection, input|
        payload = call('format_track_payload', input)
        payload = payload.merge({ 'token' => connection['public_api_key'] })

        response =
          get('track').params(data: payload.to_json.encode_base64).
          response_format_raw.
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end.
          after_response do |_code, body, _headers|
            body == '1'
          end

        {
          success: response
        }
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['server_side_output']
      end,
      sample_output: lambda do
        call('server_side_sample_output')
      end
    },

    identify: {
      title: 'Identify person',
      subtitle: "<span class='provider'>Identify</span> a person in " \
        "<span class='provider'>Klaviyo</span>",
      help: 'This API is used for tracking properties of a person without ' \
        'tracking an associated event',
      input_fields: lambda do |object_definitions|
        object_definitions['identify_input']
      end,
      execute: lambda do |connection, input|
        payload = call('format_identify_payload', input)
        payload = payload.merge({ 'token' => connection['public_api_key'] })

        response =
          get('identify').params(data: payload.to_json.encode_base64).
          response_format_raw.
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end.
          after_response do |_code, body, _headers|
            body == '1'
          end

        {
          success: response
        }
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['server_side_output']
      end,
      sample_output: lambda do
        call('server_side_sample_output')
      end
    },

    get_metrics_info: {
      title: "Get Metrics Info",
      help: "Returns a list of all the metrics in your account",

      execute: lambda do |connection|
        get("https://a.klaviyo.com/api/v1/metrics").params(api_key: connection['private_api_key'])
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['metrics_info_list']
      end
    },
    
#    get_events_all_metrics: {
#       title: "Get Events for all metrics",
#       help: "Returns a batched timeline of all events in your account",


#       input_fields: lambda do |object_definitions|
#         [ 
#           { name: "from_timestamp", label: "From", hint: "Epoch time from when events need to be fetched", type:"number", optional: false},
#           { name: "to_timestamp", label: "To", hint: "Epoch time till when events need to be fetched", type:"number", optional: false}
#         ]
#       end,

#       execute: lambda do |connection, input|
#         metrics = []
#         limitReached = false
#         next_cursor = nil
#         sort = "asc"
#         count = 100
#         #response = get("https://a.klaviyo.com/api/v1/metrics/timeline").params(api_key: connection['private_api_key'], count: input['count'], since: input['since'], sort: input['sort'])
#         response = workato.parse_json(get("https://a.klaviyo.com/api/v1/metrics/timeline").params(api_key: connection['private_api_key'], count: count, since: input['from_timestamp'], sort: sort).response_format_raw.gsub('Infinity', '"Infinity"'))
#         response['data'].each { |item|
#           if item['timestamp'].to_i <= input['to_timestamp'].to_i
#              metrics = metrics.push(item)
#           else
#              limitReached = true
#           end
#         }
# #         metrics = metrics + response['data']
#         if limitReached == false
#           next_cursor = response['next']
#         end
#         while next_cursor != nil
#           #response =get("https://a.klaviyo.com/api/v1/metrics/timeline").params(api_key: connection['private_api_key'], count: input['count'], since: next_cursor, sort: input['sort']).to_json
#           response = workato.parse_json(get("https://a.klaviyo.com/api/v1/metrics/timeline").params(api_key: connection['private_api_key'], count: count, since: next_cursor, sort: sort).response_format_raw.gsub('Infinity', '"Infinity"'))
#           response['data'].each { |item|
#             if item['timestamp'].to_i <= input['to_timestamp'].to_i && limitReached == false
#                metrics = metrics.push(item)
#             else
#              limitReached = true
#               next_cursor = nil
#             end
#           }
# #           metrics = metrics + response['data']
#           if limitReached == false
#             next_cursor = response['next']
#           end
#         end
#         { metrics: metrics }
#       end,

#       output_fields: lambda do |object_definitions|
#         [ 
#           name: "metrics", type: "array", of: "object", properties: object_definitions['metrics_info_events_2']
#         ]
#       end
#     },
  
    
     get_events_specific_metric: {
      title: "Get Events for a Specific Metric",
      help: "Returns a batched timeline for one specific metric",


      input_fields: lambda do |object_definitions|
        [ 
          { name: "metric_id", label: "Metric ID", optional: false },
          { name: "from_timestamp", label: "From", hint: "Epoch time from when events need to be fetched", type:"number", optional: false},
          { name: "to_timestamp", label: "To", hint: "Epoch time till when events need to be fetched", type:"number", optional: false}
        ]
      end,

      execute: lambda do |connection, input|
        metrics = []
        limitReached = false
        next_cursor = nil
        sort = "asc"
        count = 100
        response = workato.parse_json(get("https://a.klaviyo.com/api/v1/metric/#{input['metric_id']}/timeline").params(api_key: connection['private_api_key'], count: count, since: input['from_timestamp'], sort: sort).response_format_raw.gsub('Infinity', '"Infinity"'))
        puts response['data'].length()
        response['data'].each { |item|
          puts item['timestamp'].to_i
          puts input['to_timestamp'].to_i
          if item['timestamp'].to_i <= input['to_timestamp'].to_i
             metrics = metrics.push(item)
          else
             limitReached = true
          end
        }
#         metrics = metrics + response['data']
        if limitReached == false
          next_cursor = response['next']
        end
        while next_cursor != nil
          #response =get("https://a.klaviyo.com/api/v1/metrics/timeline").params(api_key: connection['private_api_key'], count: input['count'], since: next_cursor, sort: input['sort']).to_json
          response = workato.parse_json(get("https://a.klaviyo.com/api/v1/metric/#{input['metric_id']}/timeline").params(api_key: connection['private_api_key'], count: count, since: next_cursor, sort: sort).response_format_raw.gsub('Infinity', '"Infinity"'))
          puts response['data'].length()
          response['data'].each { |item|
            if item['timestamp'].to_i <= input['to_timestamp'].to_i && limitReached == false
               metrics = metrics.push(item)
            else
             limitReached = true
              next_cursor = nil
            end
          }
#           metrics = metrics + response['data']
          if limitReached == false
            next_cursor = response['next']
          end
        end
        { metrics: metrics }
      end,

      output_fields: lambda do |object_definitions|
        [ 
          name: "metrics", type: "array", of: "object", properties: object_definitions['metrics_info_events_2']
        ]
      end
    },

#     get_events_specific_metric: {
#       title: "Get Events for a Specific Metric",
#       help: "Returns a batched timeline for one specific metric",

#       input_fields: lambda do |object_definitions|
#         [
#           { name: "metric_id", label: "Metric ID", optional: false },
#           { name: "since", label: "Since", hint: "Either a 10-digit Unix timestamp (UTC) to use as starting datetime, OR a pagination token obtained from the next attribute of a prior API call. For backwards compatibility, UUIDs will continue to be supported for a limited time. Defaults to current time" },
#           { name: "count", label: "Count", hint: "Number of events to return in a batch. Max = 100"},
#           { name: "sort", label: "Sort", hint: "Sort order to apply to timeline, either descending or ascending. Valid values are desc or asc. Defaults to desc. Always descending when since is not sent, as since defaults to current time."},
#         ]
#       end,

#       execute: lambda do |connection, input|
#         get("https://a.klaviyo.com/api/v1/metric/#{input['metric_id']}/timeline").params(api_key: connection['private_api_key'], since: input['since'], count: input['count'], sort: input['sort'])
#       end,

#       output_fields: lambda do |object_definitions|
#         object_definitions['metrics_info_events_1']
#       end
#     },
    
    
  
   get_events_all_metrics: {
      title: "Get Events for all metrics",
      help: "Returns a batched timeline of all events in your account",


      input_fields: lambda do |object_definitions|
        [ 
          { name: "from_timestamp", label: "From", hint: "Epoch time from when events need to be fetched", type:"number", optional: false},
          { name: "to_timestamp", label: "To", hint: "Epoch time till when events need to be fetched", type:"number", optional: false}
        ]
      end,

      execute: lambda do |connection, input|
        metrics = []
        limitReached = false
        next_cursor = nil
        sort = "asc"
        count = 100
        #response = get("https://a.klaviyo.com/api/v1/metrics/timeline").params(api_key: connection['private_api_key'], count: input['count'], since: input['since'], sort: input['sort'])
        response = workato.parse_json(get("https://a.klaviyo.com/api/v1/metrics/timeline").params(api_key: connection['private_api_key'], count: count, since: input['from_timestamp'], sort: sort).response_format_raw.gsub('Infinity', '"Infinity"'))
        response['data'].each { |item|
          if item['timestamp'].to_i <= input['to_timestamp'].to_i
             metrics = metrics.push(item)
          else
             limitReached = true
          end
        }
#         metrics = metrics + response['data']
        if limitReached == false
          next_cursor = response['next']
        end
        while next_cursor != nil
          #response =get("https://a.klaviyo.com/api/v1/metrics/timeline").params(api_key: connection['private_api_key'], count: input['count'], since: next_cursor, sort: input['sort']).to_json
          response = workato.parse_json(get("https://a.klaviyo.com/api/v1/metrics/timeline").params(api_key: connection['private_api_key'], count: count, since: next_cursor, sort: sort).response_format_raw.gsub('Infinity', '"Infinity"'))
          response['data'].each { |item|
            if item['timestamp'].to_i <= input['to_timestamp'].to_i && limitReached == false
               metrics = metrics.push(item)
            else
             limitReached = true
              next_cursor = nil
            end
          }
#           metrics = metrics + response['data']
          if limitReached == false
            next_cursor = response['next']
          end
        end
        { metrics: metrics }
      end,

      output_fields: lambda do |object_definitions|
        [ 
          name: "metrics", type: "array", of: "object", properties: object_definitions['metrics_info_events_2']
        ]
      end
    },
    
   get_list_segment_members: {
      title: "Get List and Segment Members",
      help: "Gets all of the emails, phone numbers, and push tokens for profiles in a given list or segment",

      input_fields: lambda do |object_definitions|
        [
          { name: "list_or_segment_id", label: "List or Segment Id", hint: "List or segment id",  optional: false},
        ]
      end,

      execute: lambda do |connection, input|
        get("https://a.klaviyo.com/api/v2/group/#{input['list_or_segment_id']}/members/all").params(api_key: connection['private_api_key'])
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['members_list']
      end
    },
    
   get_list_segment_members_with_marker: {
      title: "Get List and Segment Members with Marker",
      help: "Gets all of the emails, phone numbers, and push tokens for profiles in a given list or segment",

      input_fields: lambda do |object_definitions|
        [
          { name: "list_or_segment_id", label: "List or Segment Id", hint: "List or segment id",  optional: false},
        ]
      end,

      execute: lambda do |connection, input|
        records = []
        response = workato.parse_json(get("https://a.klaviyo.com/api/v2/group/#{input['list_or_segment_id']}/members/all").params(api_key: connection['private_api_key']).response_format_raw.gsub('Infinity', '"Infinity"'))
        records = records + response['records']
        marker = response['marker']
        while marker.present?
          response = workato.parse_json(get("https://a.klaviyo.com/api/v2/group/#{input['list_or_segment_id']}/members/all").params(api_key: connection['private_api_key'], marker: marker).response_format_raw.gsub('Infinity', '"Infinity"'))
          records = records + response['records']
          marker = response['marker']
        end
        { records: records }
      end,
     
      output_fields: lambda do |object_definitions|
        object_definitions['members_list']
      end
    },
    
    get_profile: {
      title: "Get profile",
      help: "Retrieves all the data attributes for a person, based on the Klaviyo Person ID",

      input_fields: lambda do |object_definitions|
        [
          { name: "person_id", label: "Person Id",  optional: false},
        ]
      end,

      execute: lambda do |connection, input|
        get("https://a.klaviyo.com/api/v1/person/#{input['person_id']}").params(api_key: connection['private_api_key'])
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['person_attributes']
      end
    },
    
    search_email: {
      title: "Search email",
      help: "Retrieves profile id from the mail id.",

      input_fields: lambda do |object_definitions|
        [
          { name: "email_id", label: "Email Id",  optional: false},
        ]
      end,

      execute: lambda do |connection, input|
        sleep(2)
        get("https://a.klaviyo.com/api/v2/people/search").params(api_key: connection['private_api_key'], email: input['email_id'])
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['email_search']
      end
    },
    
    get_unsubscribe_information: {
      title: "Get Global Exclusions & Unsubscribes",
      help: "Returns global exclusions/unsubscribes.",

      input_fields: lambda do |object_definitions|
        [
          { name: "from_timestamp", label: "From", hint: "Epoch time from when events need to be fetched", type:"number", optional: false},
          { name: "to_timestamp", label: "To", hint: "Epoch time till when events need to be fetched", type:"number", optional: false}
        ]
      end,

      execute: lambda do |connection, input|
        data = []
        limitReached = false
        pageNumber = 0
        count = 100
        sort = "desc"
        
        
        response = workato.parse_json(get("https://a.klaviyo.com/api/v1/people/exclusions").params(api_key: connection['private_api_key'], count: count, sort: sort, page: pageNumber).response_format_raw.gsub('Infinity', '"Infinity"'))
        puts response['data'].length()
        response['data'].each { |item|  
          
          puts "item['timestamp'].to_time.to_i = "+item['timestamp'].to_time.to_i
          puts item['timestamp'].to_time.to_i >= input['from_timestamp'].to_i && item['timestamp'].to_time.to_i < input['to_timestamp'].to_i
        
          
          if item['timestamp'].to_time.to_i >= input['from_timestamp'].to_i && item['timestamp'].to_time.to_i < input['to_timestamp'].to_i
             data = data.push(item)
          end
          if item['timestamp'].to_time.to_i < input['from_timestamp'].to_i
            limitReached = true
          end
        }
      
       while limitReached == false
          pageNumber = pageNumber + 1
           response = workato.parse_json(get("https://a.klaviyo.com/api/v1/people/exclusions").params(api_key: connection['private_api_key'], count: count, sort: sort, page: pageNumber).response_format_raw.gsub('Infinity', '"Infinity"'))
          if response['data'].length() == 0
            limitReached = true
          end
          
          response['data'].each { |item|       
          if item['timestamp'].to_time.to_i >= input['from_timestamp'].to_i && item['timestamp'].to_time.to_i < input['to_timestamp'].to_i
             data = data.push(item)
          end
          if item['timestamp'].to_time.to_i < input['from_timestamp'].to_i
            limitReached = true
          end
          }
          
        end
        { data: data }
      end,

      output_fields: lambda do |object_definitions|
        [ 
          name: "data", type: "array", of: "object", properties: object_definitions['exclusion_list']
        ]
      end
      
#       output_fields: lambda do |object_definitions|
#         object_definitions['exclusion_list']
#       end
   },

    get_campaigns: {
      title: "Get Campaigns",
      help: "Returns a list of all the campaigns you've created. The campaigns are returned in reverse sorted order by the time they were created",

      input_fields: lambda do |object_definitions|
        [
          { name: "from_timestamp", label: "From timestamp", hint: "Epoch time from when campaigns need to be fetched",  optional: false},
          { name: "to_timestamp", label: "To timestamp", hint: "Epoch time till when campaigns need to be fetched",  optional: false}
        ]
      end,

      execute: lambda do |connection, input|
        data = []
        limitReached = false
        pageNumber = 0
        count = 100
        response = workato.parse_json(get("https://a.klaviyo.com/api/v1/campaigns").params(api_key: connection['private_api_key'], count: count, page: pageNumber).response_format_raw.gsub('Infinity', '"Infinity"'))
        
        response['data'].each { |item|
          puts item['created'].to_time.to_i
          puts input['to_timestamp'].to_i
          if item['created'].to_time.to_i >= input['from_timestamp'].to_i && item['created'].to_time.to_i < input['to_timestamp'].to_i && item['status'] == "draft"
             data = data.push(item)        
          end
          if item['created'].to_time.to_i < input['from_timestamp'].to_i
            limitReached = true
          end
        }
        
        while limitReached == false
          pageNumber = pageNumber + 1
          response = workato.parse_json(get("https://a.klaviyo.com/api/v1/campaigns").params(api_key: connection['private_api_key'], count: count, page: pageNumber).response_format_raw.gsub('Infinity', '"Infinity"'))
          if response['data'].length() == 0
            limitReached = true
          end
          
          response['data'].each { |item|
            if item['created'].to_time.to_i >= input['from_timestamp'].to_i && item['created'].to_time.to_i < input['to_timestamp'].to_i && item['status'] == "draft"
               data = data.push(item)
            end
            if item['created'].to_time.to_i < input['from_timestamp'].to_i
              limitReached = true
            end
          }
          
        end
        
        { data: data }
      end,

      output_fields: lambda do |object_definitions|
        [ 
          name: "data", type: "array", of: "object", properties: object_definitions['campaigns_list']
        ]
      end
    },
    


    get_templates: {
      title: "Get All Templates",
      help: "Returns a list of all the email templates you've created. The templates are returned in sorted order by name",

      execute: lambda do |connection|
        get("https://a.klaviyo.com/api/v1/email-templates").params(api_key: connection['private_api_key'])
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['templates_list']
      end

    },
    custom_action: {
      subtitle: 'Build your own Klaviyo action with a HTTP request',

      description: lambda do |object_value, _object_label|
        "<span class='provider'>" \
          "#{object_value[:action_name] || 'Custom action'}</span> in " \
          "<span class='provider'>Klaviyo</span>"
      end,

      help: {
        body: 'Build your own Klaviyo action with a HTTP request. ' \
          'The request will be authorized with your Klaviyo connection.',
        learn_more_url: 'https://a.klaviyo.com/api/',
        learn_more_text: 'Klaviyo API documentation'
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
          pick_list: %w[get post put patch options delete]
          .map { |verb| [verb.upcase, verb] }
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
      request_headers = input['request_headers']
      &.each_with_object({}) do |item, hash|
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
        end
      .after_error_response(/.*/) do |code, body, headers, message|
        error({ code: code, message: message, body: body, headers: headers }
          .to_json)
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
  new_events: {
    title: "New Events",
    subtitle: "Triggers when a events are created or updated in Klaviyo",

    input_fields: lambda do
      [
        {
          name: 'since', optional: true, hint: 'Either a 10-digit Unix timestamp (UTC) to use as starting datetime, OR a pagination token obtained from the next attribute of a prior API call. For backwards compatibility, UUIDs will continue to be supported for a limited time. Defaults to current time.'
        }
      ]
    end,

    poll: lambda do |connection, input, closure|
      closure = {} unless closure.present?
      limit = 100
      updated_since = (closure['cursor'] || input['since'])
      response = workato.parse_json(get("https://a.klaviyo.com/api/v1/metrics/timeline").params(api_key: connection['private_api_key'], count: input['count'], since: updated_since, sort: input['sort'])
        .response_format_raw
        .gsub('Infinity', '"Infinity"'))
      closure['cursor'] = response['next'] unless response.blank?
      #puts response

      {
        events: response,
        next_poll: closure,
        can_poll_more: response['next'].present?
      }
    end,

    dedup: lambda do |event|
      event['id']
    end,

  },

},

pick_lists: {

  metrics: lambda do |_connection|
    get('https://a.klaviyo.com/api/v1/metrics')["data"]&.
      pluck('name', 'id')
  end,
},
}