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
      # begin
      #   @db.exec("INSERT INTO events (                  \
      #                           event_name,             \
      #                           occurred_at,            \
      #                           user_id,                \
      #                           details                 \
      #             ) VALUES (                            \
      #                 '#{params[:event]}',              \
      #                 '#{params[:timestamp]}',          \
      #                 '#{params[:userId]}',             \
      #                 '#{params[:properties].to_json}'  \
      #             )")
      # rescue PG::Error => err
      #   logger.error "Problem with (#{params[:event]}) @#{params[:timestamp]}"
      #   logger.error err.message
      # end
      puts "here's everything"
      puts params.inspect

      if params[:event] == 'Completed Order'
        post_to_ga(params)
      end
    end
  end

  def post_to_ga(event)
    params = {
      v: 1,
      tid: ENV['GA_TRACKING_ID'],
      cid: '555',
      t: 'event',
      ec: 'All',
      ea: 'Completed Order'
    }

    begin
      HTTParty.get(GA_ENDPOINT, params)
      puts "Sent an event to GA"
      puts event.inspect
    rescue Exception => e
      puts "Problem notifying GA"
    end
  end
end
