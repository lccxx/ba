#!/usr/bin/env ruby

require 'uri'
require 'openssl'
require 'net/http'
require 'json'
require 'bigdecimal'

dot_env_file = File.join(File.dirname(__FILE__), '.env')

File.foreach(dot_env_file) { |line|
  k, v = line.split('=').map { |str| str.strip }
  ENV[k] = v
} if File.exist?(dot_env_file)

API_KEY = ENV['BA_API_KEY']
SECRET_KEY = ENV['BA_SECRET_KEY']

abort "error: need Binance API keys" if !API_KEY || !SECRET_KEY

API_HOST = 'api.binance.com'
API_PREFIX = '/api/v3/'

sign_req = lambda { |api, params={}|
  params[:timestamp] = (Time.now.to_f * 1000).to_i
  query = URI.encode_www_form params
  signature = OpenSSL::HMAC.hexdigest("SHA256", SECRET_KEY, query)
  query += "&signature=#{signature}"
  req = Net::HTTP::Get.new("#{API_PREFIX}#{api}?#{query}")
  if [ 'order' ].include?(api)
    req = Net::HTTP::Post.new("#{API_PREFIX}#{api}")
    req.body = query
  end
  req['X-MBX-APIKEY'] = API_KEY
  return Net::HTTP.start(API_HOST, 443, use_ssl: true) { |http| http.request(req) }
}

get_btc_price = lambda {
  res_body = Net::HTTP.get URI "https://#{API_HOST}#{API_PREFIX}ticker/price?symbol=BTCUSDT"
  return JSON.parse(res_body)['price'].to_i
}

get_btc_orders = lambda {
  res = sign_req.call('allOrders', { symbol: 'BTCUSDT', limit: 9 })
  return JSON.parse res.body
}

get_balances = lambda {
  res = sign_req.call('account')
  return JSON.parse(res.body)['balances']
}

order = lambda { |side, price, quantity|
  puts "#{side} #{price} #{quantity}"
  res = sign_req.call('order', { symbol: 'BTCUSDT', timeInForce: 'GTC',
                                 side: side, type: 'LIMIT', price: price, quantity: quantity })
  return JSON.parse res.body
}

btc_last_prices = lambda {
  result = [ get_btc_price.call, 0, 0 ]
  get_btc_orders.call.each { |order|
    side = order['side']
    status = order['status']
    price = order['price'].to_i

    result[1] = price if status === 'FILLED' && side === 'SELL'
    result[2] = price if status === 'FILLED' && side === 'BUY'
  }
  return result
}

going = true

Signal.trap('SIGINT') { puts "SIGINT"; going = false }
Signal.trap('TERM') { puts "TERM"; going = false }

btc_free = 0
usdt_free = 0
btc_current_price, btc_last_sell_price, btc_last_buy_price = btc_last_prices.call

puts "BTC current price: #{btc_current_price}, Last sell: #{btc_last_sell_price}, Last buy: #{btc_last_buy_price}"
puts 'Recent orders: '
get_btc_orders.call.reverse.each { |order|
  puts "  #{order['status']} #{order['side']} #{order['price'].to_i} #{order['origQty']}"
}

loop {
  get_balances.call.each { |balance|
    asset = balance['asset']
    free = BigDecimal(balance['free'])

    btc_free = free if asset === 'BTC'
    usdt_free = free if asset === 'USDT'
  }
  puts "#{Time.now}, Balances: #{btc_free.to_s('8F')}, #{usdt_free}"

  btc_current_price, btc_last_sell_price, btc_last_buy_price = btc_last_prices.call if btc_free > 1 || usdt_free > 1

  if btc_free > 1
    btc_sell_price = btc_last_buy_price + 500
    btc_sell_price = btc_current_price + 100 if btc_sell_price < btc_current_price
    order.call('SELL', btc_sell_price, btc_free.to_s('8F'))
  end

  if usdt_free > 1
    btc_buy_price = btc_last_sell_price - 500
    btc_buy_price = btc_current_price - 100 if btc_buy_price > btc_current_price
    order.call('BUY', btc_buy_price, (usdt_free / btc_buy_price).to_s('8F'))
  end

  (9 + rand * 39).to_i.times { sleep 0.1 if going }
  break if not going
}
