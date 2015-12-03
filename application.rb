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
      cid: event[:context]['GoogleAnalytics']['clientId'],
      t: 'event',
      ec: 'All',
      ea: 'Completed Order',
      ev: event[:properties]['revenue'],
      el: event[:properties]['product_skus'].first,
      uid: event[:userId],
    }
    if event[:context]['campaign']
      body.merge! ({
        cs: event[:context]['campaign']['source'],
        cm: event[:context]['campaign']['medium'],
        cn: event[:context]['campaign']['name'],
        cc: event[:context]['campaign']['content']
      })
    end

    if event[:context]['referrer']
      body.merge! ({
        dr: event[:context]['referrer']['url']
      })
    end

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
end
