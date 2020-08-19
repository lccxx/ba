#!/usr/bin/env ruby

require 'uri'
require 'openssl'
require 'net/http'
require 'json'
require 'bigdecimal'

File.foreach('.env') { |line|
  k, v = line.split('=').map { |str| str.strip }
  ENV[k] = v
} if File.exist?('.env')

API_KEY = ENV['BA_API_KEY']
SECRET_KEY = ENV['BA_SECRET_KEY']

abort "error: need Binance API keys" if !API_KEY || !SECRET_KEY

API_HOST = 'api.binance.com'
API_PREFIX = '/api/v3/'

sign_req = lambda { |api, params|
  query = URI.encode_www_form params
  signature = OpenSSL::HMAC.hexdigest("SHA256", SECRET_KEY, query)
  req = Net::HTTP::Get.new("#{API_PREFIX}#{api}?#{query}&signature=#{signature}")
  req['X-MBX-APIKEY'] = API_KEY
  return Net::HTTP.start(API_HOST, 443, use_ssl: true) { |http| http.request(req) }
}

get_btc_price = lambda {
  res_body = Net::HTTP.get URI "https://#{API_HOST}#{API_PREFIX}ticker/price?symbol=BTCUSDT"
  return JSON.parse(res_body)['price'].to_i
}

get_btc_orders = lambda {
  res = sign_req.call('allOrders', { symbol: 'BTCUSDT', limit: 9, timestamp: (Time.now.to_f * 1000).to_i })
  return JSON.parse res.body
}

get_balances = lambda {
  res = sign_req.call('account', { timestamp: (Time.now.to_f * 1000).to_i })
  return JSON.parse(res.body)['balances']
}

loop { 
  get_balances.call.each { |balance|
    asset = balance['asset']
    next if not [ 'BTC', 'USDT' ].include?(asset)
    free = BigDecimal(balance['free'])
    locked = BigDecimal(balance['locked'])
    puts "My #{asset} balance: #{free.to_s('8F')} + #{locked.to_s('8F')}"
    if free > 1
      btc_last_buy_price = btc_last_sell_price = 11900

      get_btc_orders.call.each { |order|
        side = order['side']
        status = order['status']
        price = order['price'].to_i

        btc_last_buy_price = price if status === 'FILLED' && side === 'BUY'
        btc_last_sell_price = price if status === 'FILLED' && side === 'SELL'
      }

      puts "BTC lastest price: #{get_btc_price.call}"
      puts "My BTC last buy price: #{btc_last_buy_price}"
      puts "My BTC last sell price: #{btc_last_sell_price}"
      # TODO: order
    end
  }

  sleep (1 + rand * 9).to_i
}
