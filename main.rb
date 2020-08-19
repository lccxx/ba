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

sign_req = lambda { |api, params|
  query = URI.encode_www_form params
  signature = OpenSSL::HMAC.hexdigest("SHA256", SECRET_KEY, query)
  req = Net::HTTP::Get.new("/api/v3/#{api}?#{query}&signature=#{signature}")
  req['X-MBX-APIKEY'] = API_KEY
  return req
}

get_btc_price = lambda {
  req = Net::HTTP::Get.new('/api/v3/ticker/price?symbol=BTCUSDT')
  res = Net::HTTP.start(API_HOST, 443, use_ssl: true) { |http| http.request(req) }
  return JSON.parse(res.body)['price'].to_i
}

get_btc_orders = lambda {
  req = sign_req.call('allOrders', { symbol: 'BTCUSDT', limit: 9, timestamp: (Time.now.to_f * 1000).to_i })
  res = Net::HTTP.start(API_HOST, 443, use_ssl: true) { |http| http.request(req) }
  return JSON.parse res.body
}

get_my_balances = lambda {
  req = sign_req.call('account', { timestamp: (Time.now.to_f * 1000).to_i })
  res = Net::HTTP.start(API_HOST, 443, use_ssl: true) { |http| http.request(req) }
  return JSON.parse(res.body)['balances']
}

puts "BTC lastest price: #{get_btc_price.call}"
print 'My BTC balance: '
get_my_balances.call.each { |balance|
  asset = balance['asset']
  free = BigDecimal(balance['free'])
  locked = BigDecimal(balance['locked'])
  puts "#{free.to_s('8F')} + #{locked.to_s('8F')}" if asset === 'BTC'
}

btc_last_buy_price = btc_last_sell_price = 11900

get_btc_orders.call.each { |order|
  side = order['side']
  status = order['status']
  price = order['price'].to_i

  btc_last_buy_price = price if status === 'FILLED' && side === 'BUY'
  btc_last_sell_price = price if status === 'FILLED' && side === 'SELL'
}

puts "My BTC last buy price: #{btc_last_buy_price}"
puts "My BTC last sell price: #{btc_last_sell_price}"

# TODO: loop check & order
