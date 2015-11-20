require 'rubygems'
require 'bundler'
require 'pg'
require 'rack'
require 'rack/contrib'
require 'json'
require 'httparty'

Bundler.require :default, (ENV['RACK_ENV'] || 'development').to_sym

# Basic Sinatra app that takes posts to /segment and inserts them in a PG DB
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
    if params[:type] == 'track'
      # ONLY dumping completed orders into the DB so we can see them later
      if params[:event] == 'Completed Order'
        begin
          # NOTE: currently erroring out when there is a quote in the name
          puts "everything!"
          puts params.inspect
          @db.exec("INSERT INTO events (                  \
                                  event_name,             \
                                  occurred_at,            \
                                  user_id,                \
                                  details                 \
                    ) VALUES (                            \
                        '#{params[:event]}',              \
                        '#{params[:timestamp]}',          \
                        '#{params[:userId]}',             \
                        '#{params[:properties].to_json}'  \
                    )")
        rescue PG::Error => err
          logger.error "Problem with (#{params[:event]}) @#{params[:timestamp]}"
          logger.error err.message
        end

        post_to_ga(params)
      end
    end
  end

  def post_to_ga(event)
    body = {
      v: 1,
      tid: ENV['GA_TRACKING_ID'],
      cid: '555',
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

    begin
      response = HTTParty.post(GA_ENDPOINT, body: body)

      # SHITTY DEBUG LOGGING
      puts "Sent an event to GA"
      puts "response:"
      puts response.inspect.to_json
      puts "body:"
      puts body.inspect.to_json
      puts "event:"
      puts event.inspect.to_json
    rescue Exception => e
      puts "Problem notifying GA"
    end
  end
end
