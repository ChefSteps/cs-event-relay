require 'rubygems'
require 'bundler'
require 'pg'
require 'rack'
require 'rack/contrib'
require 'json'
require 'httparty'

Bundler.require :default, (ENV['RACK_ENV'] || 'development').to_sym

# Basic Sinatra app that takes segment webhook posts and inserts them in a PG DB
class Application < Sinatra::Base
  GA_ENDPOINT = 'http://www.google-analytics.com/collect'

  configure :production, :development do
    enable :logging
  end

  def initialize
    unless ENV['DATABASE_URL']
      puts "DATABASE_URL not specified - exiting"
      exit
    end
    uri = URI.parse(ENV['DATABASE_URL'])
    
    begin
      @db = PG.connect(uri.hostname, uri.port, nil, nil, uri.path[1..-1], uri.user, uri.password)
    rescue
      puts 'Problem connecting to Postgres. Exiting.'
      exit
    end

    super
  end

  post '/' do
    logger.info params.inspect
    if params[:type] == 'track'
      begin
        query_params = [
                          params[:event], 
                          params[:timestamp], 
                          params[:userId], 
                          params[:properties].to_json
                        ]

        @db.exec("INSERT INTO events (                  \
                                event_name,             \
                                occurred_at,            \
                                user_id,                \
                                details                 \
                  ) VALUES ($1, $2, $3, $4)", 
                  query_params)
        logger.info "Inserting an event into the database: #{query_params.inspect}"
      rescue PG::Error => err
        logger.error "Problem with (#{params[:event]}) @#{params[:timestamp]}"
        logger.error err.message
      end

      if params[:event] == 'Completed Order'
        post_to_ga(params)
      end

    end
  end

  def post_to_ga(event)
    body = {
      v: 1,
      tid: ENV['GA_TRACKING_ID'],
      t: 'event',
      ec: 'All',
      ea: 'Completed Order',
      ev: event[:properties]['revenue'],
      el: event[:properties]['product_skus'].first,
      uid: event[:userId],
    }
    body.merge! ({ cid: event[:context]['GoogleAnalytics']['clientId'] }) if event[:context]['GoogleAnalytics']

    if event[:context]['campaign']
      utm_source = event[:context]['campaign']['source']
      utm_medium = event[:context]['campaign']['medium']

      body.merge! ({
        cn: event[:context]['campaign']['name'],
        cc: event[:context]['campaign']['content']
      })
    end

    if event[:context]['referrer']
      begin
        referring_domain = URI.parse(event[:context]['referrer']['url'])
      rescue URI::InvalidURIError => e
        referring_domain = nil
      end
      body.merge! ({ dr: referring_domain.to_s }) 
    end

    source, medium = forge_source_medium(utm_source, utm_medium, referring_domain)
    body.merge! ({
      cs: source,
      cm: medium
    })

    begin
      response = HTTParty.post(GA_ENDPOINT, body: body)
      if response.code != 200
        logger.error "Problem notifying GA for #{body.inspect}"
      else
        logger.info "Inserted an event into GA: #{body.inspect}"
      end
    rescue Exception => e
      logger.error "Problem notifying GA: #{e.message}"
    end
  end

  def forge_source_medium(utm_source, utm_medium, referring_domain)
    # working off of: https://support.google.com/analytics/answer/3297892?hl=en
    # organic: <source> / organic
    # referrer: <referring domain> / referral
    # direct: nil / (none)
    # UTM params take priority over the domain they came from
    if utm_source
      source = utm_source
    elsif referring_domain && match = /bing|google/.match(referring_domain.hostname)
      source = match[0]
    elsif referring_domain
      source = referring_domain.hostname
    else
      source = nil
    end

    if utm_medium
      medium = utm_medium
    elsif referring_domain && match = /bing|google/.match(referring_domain.hostname)
      medium = 'organic'
    elsif referring_domain
      medium = 'referral'
    else
      medium = '(none)'
    end

    return source, medium
  end

end
