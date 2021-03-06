Kiwi.trace       = !!(ENV['RACK_ENV'] =~ /^dev/i)
Kiwi.route_delim = "/"

Kiwi.input_types = {
  String  => :to_s,
  Integer => :to_i,
  Float   => :to_f,
  Boolean => lambda{|val| !(val =~ /^(0|false|F|N|no|nil|null|undefined|)$/i) }
}

Kiwi.serializers = {
  # TODO: placeholder. allow for other serializers and parsers.
  :json => lambda{|data| require 'json'; data.to_json }
}

Kiwi.default_http_verb = :post
